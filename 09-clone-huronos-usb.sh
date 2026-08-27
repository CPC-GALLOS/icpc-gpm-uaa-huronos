#!/usr/bin/env bash
# =============================================================================
# 09-clone-huronos-usb.sh — CPC GALLOS / UAA
# Rapidly clones a fully installed, customized "golden master" huronOS USB
# onto one or more additional USB drives of the same model/capacity, instead
# of re-running the full 01-install-huronos.sh flow (interactive partition,
# format, file copy, checksum verification, and bootloader install) on every
# single drive.
#
# Only the ~6 GiB system partition (label HURONOS) is cloned byte-for-byte —
# it holds 100% of the real content (base squashfs layers, software layers,
# the custom wallpaper/VS Code layer from 02-inject-custom-layer.sh, and the
# NVIDIA boot tweaks from 03-configure-nvidia-boot.sh). The two ext4
# persistence partitions (event-data, contest-data) start empty on every
# install anyway, so they are freshly formatted per target instead of being
# copied — this avoids writing gigabytes of empty filesystem and gives each
# clone its own unique filesystem UUIDs there, which are then rebaked into
# boot/huronos.cfg exactly like the base installer's own UUID-bake step.
#
# Caveat: the system partition's own FAT32 volume UUID is NOT rebaked — it
# travels with the byte-cloned partition, so every clone shares the source's
# UUID there. Harmless as long as clones aren't mounted on the same host at
# once. Always boot-test a fresh clone (08-test-huronos-usb-vbox.sh /dev/sdX)
# before it goes anywhere near real contest hardware.
#
# Usage:
#   bash 09-clone-huronos-usb.sh /dev/sdX [/dev/sdY ...]
#   First argument = golden-master source device (already fully installed).
#   Remaining arguments = target devices. If none are given, every other
#   removable USB disk currently attached is auto-detected as a target.
# =============================================================================

set -e

SOURCE_DEV="${1:-}"
if [ -n "$SOURCE_DEV" ]; then
    shift
fi
TARGET_DEVS=("$@")

echo "==========================================================="
echo " huronOS Golden-Master USB Cloner"
echo "==========================================================="
echo ""

if [ -z "$SOURCE_DEV" ]; then
    echo "❌ Error: no source device given."
    echo "Usage: bash 09-clone-huronos-usb.sh /dev/sdX [/dev/sdY ...]"
    exit 1
fi

# --- Step 1: Validate source ---
echo "[Step 1/7] Validating golden-master source device..."
if [ ! -b "$SOURCE_DEV" ]; then
    echo "❌ Error: '$SOURCE_DEV' is not a block device."
    exit 1
fi

SOURCE_LABEL="$(blkid -o value -s LABEL "${SOURCE_DEV}1" 2>/dev/null || true)"
if [ "$SOURCE_LABEL" != "HURONOS" ]; then
    echo "❌ Error: ${SOURCE_DEV}1 is not labeled HURONOS — '$SOURCE_DEV' does not"
    echo "   look like a finished huronOS install. Run 01-install-huronos.sh on it"
    echo "   first, then use the finished drive as the source here."
    exit 1
fi
echo "✓ Source $SOURCE_DEV carries a HURONOS system partition."
echo ""

# --- Step 2: Determine targets ---
echo "[Step 2/7] Selecting target USB drives..."
if [ ${#TARGET_DEVS[@]} -eq 0 ]; then
    echo "No targets given — auto-detecting other removable USB disks..."
    while IFS= read -r DETECTED; do
        [ -n "$DETECTED" ] && [ "$DETECTED" != "$SOURCE_DEV" ] && TARGET_DEVS+=("$DETECTED")
    done < <(lsblk -d -n -r -o PATH,RM,TRAN 2>/dev/null | awk '$2=="1"{print $1}')
fi

if [ ${#TARGET_DEVS[@]} -eq 0 ]; then
    echo "❌ Error: no target USB drives found or given."
    echo "Usage: bash 09-clone-huronos-usb.sh /dev/sdX [/dev/sdY ...]"
    exit 1
fi

ROOT_DISK_PART="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_DISK=""
if [ -n "$ROOT_DISK_PART" ] && [ -b "$ROOT_DISK_PART" ]; then
    ROOT_DISK="/dev/$(lsblk -n -o PKNAME "$ROOT_DISK_PART" 2>/dev/null || true)"
fi

SOURCE_SIZE="$(blockdev --getsize64 "$SOURCE_DEV")"

VALID_TARGETS=()
for TGT in "${TARGET_DEVS[@]}"; do
    if [ ! -b "$TGT" ]; then
        echo "❌ Error: '$TGT' is not a block device. Aborting."
        exit 1
    fi
    if [ "$TGT" = "$SOURCE_DEV" ]; then
        echo "❌ Error: target '$TGT' is the same as the source device. Aborting."
        exit 1
    fi
    if [ -n "$ROOT_DISK" ] && [ "$TGT" = "$ROOT_DISK" ]; then
        echo "❌ Error: target '$TGT' is the host's own root disk. Refusing to touch it."
        exit 1
    fi
    TGT_RM="$(lsblk -d -n -r -o RM "$TGT" 2>/dev/null || echo "0")"
    if [ "$TGT_RM" != "1" ]; then
        echo "❌ Error: '$TGT' is not marked as a removable device. Refusing to touch it."
        echo "   Pass only removable USB drives as targets."
        exit 1
    fi
    TGT_SIZE="$(blockdev --getsize64 "$TGT")"
    if [ "$TGT_SIZE" -lt "$SOURCE_SIZE" ]; then
        echo "❌ Error: target '$TGT' ($TGT_SIZE bytes) is smaller than the source"
        echo "   '$SOURCE_DEV' ($SOURCE_SIZE bytes). Use identical-capacity drives."
        exit 1
    fi
    if [ "$TGT_SIZE" -gt "$SOURCE_SIZE" ]; then
        echo "⚠  Warning: target '$TGT' is larger than the source — extra capacity"
        echo "   will be left unpartitioned, matching the source's layout exactly."
    fi
    VALID_TARGETS+=("$TGT")
done
echo ""

# --- Step 3: Confirmation ---
echo "[Step 3/7] Review the operation before continuing:"
echo ""
echo "Source (golden master, read-only):"
lsblk -d -o NAME,SIZE,MODEL "$SOURCE_DEV" 2>/dev/null || true
echo ""
echo "Targets (⚠ ALL DATA WILL BE ERASED on each):"
for TGT in "${VALID_TARGETS[@]}"; do
    lsblk -d -o NAME,SIZE,MODEL "$TGT" 2>/dev/null || true
done
echo ""
read -r -p "Type 'yes' to erase and clone onto all listed targets: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted — no changes made."
    exit 1
fi
echo ""

# --- Step 4: Unmount source and targets ---
echo "[Step 4/7] Unmounting source and target partitions..."
for DEV in "$SOURCE_DEV" "${VALID_TARGETS[@]}"; do
    for PART in $(lsblk -nr -o PATH "$DEV" 2>/dev/null || true); do
        if findmnt -n "$PART" &>/dev/null; then
            echo "Unmounting $PART..."
            sudo umount "$PART" 2>/dev/null || true
        fi
    done
done
echo "✓ Devices unmounted."
echo ""

# --- Step 5: Capture source layout and stage system-partition image ---
echo "[Step 5/7] Capturing golden-master layout..."
WORKDIR="$(mktemp -d /tmp/huronos-clone.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

MBR_BIN="$WORKDIR/mbr.bin"
SFDISK_DUMP="$WORKDIR/partitions.sfdisk"
sudo dd if="$SOURCE_DEV" of="$MBR_BIN" bs=440 count=1 status=none
# WORKDIR is owned by the invoking user (mktemp), so this redirect needs no elevation.
# shellcheck disable=SC2024
sudo sfdisk -d "$SOURCE_DEV" > "$SFDISK_DUMP"

OLD_EVENT_UUID="$(blkid -o value -s UUID "${SOURCE_DEV}2" 2>/dev/null || true)"
OLD_CONTEST_UUID="$(blkid -o value -s UUID "${SOURCE_DEV}3" 2>/dev/null || true)"
if [ -z "$OLD_EVENT_UUID" ] || [ -z "$OLD_CONTEST_UUID" ]; then
    echo "❌ Error: could not read event-data/contest-data UUIDs from $SOURCE_DEV."
    exit 1
fi

SYSPART_SIZE="$(blockdev --getsize64 "${SOURCE_DEV}1")"
SYSPART_IMG="$WORKDIR/system-partition.img"

MEM_AVAILABLE_KB="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
if [ "$((MEM_AVAILABLE_KB * 1024))" -gt "$((SYSPART_SIZE + 536870912))" ]; then
    STAGE_DIR="/dev/shm"
    echo "Staging system partition image in RAM ($STAGE_DIR)..."
else
    STAGE_DIR="$WORKDIR"
    echo "Not enough free RAM to stage in tmpfs — staging on disk instead..."
fi
SYSPART_IMG="$STAGE_DIR/huronos-system-partition.img"
sudo dd if="${SOURCE_DEV}1" of="$SYSPART_IMG" bs=4M status=progress
echo "✓ System partition staged at $SYSPART_IMG ($SYSPART_SIZE bytes)."
echo ""

# --- Step 6: Clone onto every target in parallel ---
echo "[Step 6/7] Cloning onto ${#VALID_TARGETS[@]} target(s) in parallel..."
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"

clone_one_target() {
    TGT="$1"
    set -e

    for PART in $(lsblk -nr -o PATH "$TGT" 2>/dev/null || true); do
        sudo umount "$PART" 2>/dev/null || true
    done

    echo "[$TGT] Writing MBR bootstrap..."
    sudo dd if="$MBR_BIN" of="$TGT" bs=440 count=1 conv=notrunc status=none

    echo "[$TGT] Applying partition table..."
    # SFDISK_DUMP is user-readable, so this redirect needs no elevation.
    # shellcheck disable=SC2024
    sudo sfdisk "$TGT" < "$SFDISK_DUMP"
    sudo partprobe "$TGT" 2>/dev/null || true
    sudo udevadm settle

    TRIES=0
    while [ ! -b "${TGT}1" ] || [ ! -b "${TGT}2" ] || [ ! -b "${TGT}3" ]; do
        TRIES=$((TRIES + 1))
        if [ "$TRIES" -gt 20 ]; then
            echo "[$TGT] ❌ Error: partitions did not appear after partitioning."
            exit 1
        fi
        sleep 0.5
    done

    # This byte-copies the FAT32 volume UUID too, so it's identical across all
    # clones (see the caveat in the header comment) — only partitions 2/3 below
    # get their UUIDs regenerated.
    echo "[$TGT] Writing system partition image (~$((SYSPART_SIZE / 1024 / 1024)) MiB)..."
    sudo dd if="$SYSPART_IMG" of="${TGT}1" bs=4M status=progress

    echo "[$TGT] Formatting empty persistence partitions..."
    sudo mkfs.ext4 -L event-data -F "${TGT}2" -q
    sudo mkfs.ext4 -L contest-data -F "${TGT}3" -q

    NEW_EVENT_UUID="$(blkid -o value -s UUID "${TGT}2")"
    NEW_CONTEST_UUID="$(blkid -o value -s UUID "${TGT}3")"

    MNT="$WORKDIR/mnt-$(basename "$TGT")"
    mkdir -p "$MNT"
    sudo mount "${TGT}1" "$MNT"

    echo "[$TGT] Rebaking persistence-partition UUIDs into boot/huronos.cfg..."
    sudo sed -i "s|event.uuid=$OLD_EVENT_UUID|event.uuid=$NEW_EVENT_UUID|g" "$MNT/boot/huronos.cfg"
    sudo sed -i "s|contest.uuid=$OLD_CONTEST_UUID|contest.uuid=$NEW_CONTEST_UUID|g" "$MNT/boot/huronos.cfg"

    if [ -f "$MNT/checksums" ]; then
        NEW_SUM_BOOT="$(cd "$MNT" && sha256sum ./boot/huronos.cfg)"
        sudo sed -i "s|.*./boot/huronos.cfg.*|$NEW_SUM_BOOT|" "$MNT/checksums"
    fi

    sync
    sudo umount "$MNT"
    echo "[$TGT] ✓ Clone complete (event.uuid=$NEW_EVENT_UUID, contest.uuid=$NEW_CONTEST_UUID)."
}

PIDS=()
for TGT in "${VALID_TARGETS[@]}"; do
    clone_one_target "$TGT" > "$LOGDIR/$(basename "$TGT").log" 2>&1 &
    PIDS+=($!)
done

FAILED=0
for I in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$I]}"; then
        FAILED=$((FAILED + 1))
    fi
done
echo ""

for TGT in "${VALID_TARGETS[@]}"; do
    echo "--- $TGT ---"
    cat "$LOGDIR/$(basename "$TGT").log"
    echo ""
done

# --- Step 7: Summary ---
echo "[Step 7/7] Summary"
if [ "$FAILED" -eq 0 ]; then
    echo "✓ All ${#VALID_TARGETS[@]} target(s) cloned successfully."
else
    echo "❌ $FAILED of ${#VALID_TARGETS[@]} target(s) failed — see logs above."
fi
echo ""
echo "Before using a cloned USB on real contest hardware, verify it boots:"
echo "  bash 08-test-huronos-usb-vbox.sh <target-device>   (VirtualBox)"
echo "  bash 06-test-huronos-usb-vm.sh <target-device>     (KVM)"
echo ""

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
