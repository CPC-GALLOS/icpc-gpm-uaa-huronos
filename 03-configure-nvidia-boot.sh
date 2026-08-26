#!/usr/bin/env bash
# =============================================================================
# 03-configure-nvidia-boot.sh — CPC GALLOS / UAA
# Configures huronOS bootloader for compatibility with UAA computer labs
# and machines with dedicated NVIDIA GPUs (RTX / Ada / GTX) and Intel CPUs.
#
# Keeps the EFI framebuffer available for Xorg's fbdev driver and fixes EFI
# syslinux. Kernel 6.0 cannot drive Intel Arrow Lake (8086:7d67) or recent
# NVIDIA Ada hardware with i915/nouveau merely by force-probing.
#
# Usage:
#   bash 03-configure-nvidia-boot.sh [/dev/sdX1 | /path/to/mounted/HURONOS]
# =============================================================================

set -e

TARGET="${1}"

echo "============================================="
echo " huronOS UAA Lab & NVIDIA Boot Configuration"
echo "============================================="
echo ""

MOUNTED_BY_US=false
TARGET_DIR=""

if [ -z "$TARGET" ]; then
    # Check if already mounted
    ALREADY_MOUNTED=$(findmnt -n -o TARGET -S LABEL=HURONOS 2>/dev/null || true)
    if [ -n "$ALREADY_MOUNTED" ]; then
        TARGET_DIR="$ALREADY_MOUNTED"
        echo "Found mounted huronOS partition at: $TARGET_DIR"
    else
        echo "Searching for partition with label 'HURONOS'..."
        DEV_CANDIDATE=$(blkid -L HURONOS 2>/dev/null || true)
        if [ -n "$DEV_CANDIDATE" ]; then
            TARGET="$DEV_CANDIDATE"
            echo "Found huronOS partition: $TARGET"
        else
            echo "❌ Error: No target specified and no partition labeled 'HURONOS' found."
            echo "Usage: bash $0 [/dev/sdX1 | /path/to/mounted/huronOS]"
            exit 1
        fi
    fi
fi

if [ -z "$TARGET_DIR" ]; then
    if [ -b "$TARGET" ]; then
        EXISTING_MNT=$(findmnt -n -o TARGET "$TARGET" 2>/dev/null || true)
        if [ -n "$EXISTING_MNT" ]; then
            TARGET_DIR="$EXISTING_MNT"
            echo "Using existing mount point: $TARGET_DIR"
        elif command -v udisksctl &>/dev/null && UDISKS_OUT=$(udisksctl mount -b "$TARGET" 2>/dev/null); then
            TARGET_DIR=$(echo "$UDISKS_OUT" | grep -o 'at /.*' | sed 's/at //')
            echo "Mounted via udisksctl to: $TARGET_DIR"
            MOUNTED_BY_US=true
        else
            TARGET_DIR="/tmp/huronos-nvidia-mnt-$$"
            mkdir -p "$TARGET_DIR"
            echo "Mounting $TARGET to $TARGET_DIR..."
            mount "$TARGET" "$TARGET_DIR"
            MOUNTED_BY_US=true
        fi
    elif [ -d "$TARGET" ]; then
        TARGET_DIR="$TARGET"
    else
        echo "❌ Error: Target '$TARGET' is neither a block device nor a directory."
        exit 1
    fi
fi

cleanup() {
    if [ "$MOUNTED_BY_US" = true ]; then
        echo "Syncing and unmounting $TARGET_DIR..."
        sync
        if [ -b "$TARGET" ] && command -v udisksctl &>/dev/null && mountpoint -q "$TARGET_DIR" 2>/dev/null; then
            udisksctl unmount -b "$TARGET" 2>/dev/null || umount "$TARGET_DIR" 2>/dev/null || true
        elif mountpoint -q "$TARGET_DIR" 2>/dev/null; then
            umount "$TARGET_DIR" || true
        fi
        rm -rf "/tmp/huronos-nvidia-mnt-$$" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

CFG_BOOT="$TARGET_DIR/boot/huronos.cfg"
CFG_EFI="$TARGET_DIR/EFI/Boot/syslinux.cfg"
CHECKSUMS_FILE="$TARGET_DIR/checksums"

if [ ! -f "$CFG_BOOT" ]; then
    echo "❌ Error: '$CFG_BOOT' not found."
    exit 1
fi

echo "1. Configuring bootloader parameters for UAA lab hardware & NVIDIA GPU..."

# Extract flags from existing huronos.cfg
HURONOS_FLAGS=$(grep -o 'huronos.flags=([^)]*)' "$CFG_BOOT" | head -n 1 || true)
if [ -z "$HURONOS_FLAGS" ]; then
    HURONOS_FLAGS="huronos.flags=(persistence=true)"
fi

# Configure boot/huronos.cfg for Legacy BIOS
cat << EOF > "$CFG_BOOT"
UI vesamenu.c32
PROMPT 0
TIMEOUT 70

MENU HSHIFT 15
MENU WIDTH 49
MENU title Boot huronOS (Legacy Mode)

MENU background /boot/huronboot.png
MENU color title	* #FFFFFFFF *
MENU color border	* #00000000 #00000000 none
MENU color sel		* #ffffffff #76a1d0ff *
MENU color hotsel	1;7;37;40 #ffffffff #76a1d0ff *
MENU color tabmsg	* #ffffffff #00000000 *
MENU color help		37;40 #ffdddd00 #00000000 none
MENU vshift 16
MENU rows 7
MENU helpmsgrow 12
MENU cmdlinerow 12
MENU tabmsgrow 13
MENU tabmsg Press [Tab] to edit options, [Enter] to boot

MENU AUTOBOOT [Esc] -> options, Booting in # second{,s}

DEFAULT persistent-fbdev
LABEL persistent-fbdev
  MENU LABEL ^1. Start contest system (EFI framebuffer / fbdev - Default)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS

LABEL persistent-intel
  MENU LABEL ^2. Start contest system (Intel DRM - supported hardware only)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=nouveau $HURONOS_FLAGS

LABEL standard
  MENU LABEL ^3. Start contest system (experimental NVIDIA DRM)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 nouveau.modeset=1 nouveau.noaccel=1 $HURONOS_FLAGS

LABEL persistent-debug
  MENU LABEL ^4. Start contest system (Verbose Debug Mode)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 debug loglevel=7 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS

LABEL persistent-nomodeset
  MENU LABEL ^5. Start contest system (console-only / nomodeset)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 nomodeset nouveau.modeset=0 modprobe.blacklist=nouveau $HURONOS_FLAGS

LABEL nosync
  MENU LABEL ^6. Start no-sync mode
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS
EOF
echo "✓ Updated $CFG_BOOT"

# Configure EFI/Boot/syslinux.cfg for UEFI Mode
if [ -f "$CFG_EFI" ]; then
cat << EOF > "$CFG_EFI"
UI /EFI/Boot/menu.c32
PROMPT 0
TIMEOUT 70

MENU TITLE huronOS (UEFI Boot Menu)
MENU COLOR title 1;36;44 #ffffffff #00000000 none
MENU COLOR sel 7;37;40 #00000000 #ffffffff none
MENU COLOR unsel 37;44 #ffffffff #00000000 none
MENU COLOR tabmsg * #ffffffff #00000000 *
MENU tabmsg Press [Tab] to edit options, [Enter] to boot

DEFAULT persistent-fbdev
LABEL persistent-fbdev
  MENU LABEL ^1. Start contest system (EFI framebuffer / fbdev - Default)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS

LABEL persistent-intel
  MENU LABEL ^2. Start contest system (Intel DRM - supported hardware only)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=nouveau $HURONOS_FLAGS

LABEL standard
  MENU LABEL ^3. Start contest system (experimental NVIDIA DRM)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 nouveau.modeset=1 nouveau.noaccel=1 $HURONOS_FLAGS

LABEL persistent-debug
  MENU LABEL ^4. Start contest system (Verbose Debug Mode)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 debug loglevel=7 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS

LABEL persistent-nomodeset
  MENU LABEL ^5. Start contest system (console-only / nomodeset)
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 nomodeset nouveau.modeset=0 modprobe.blacklist=nouveau $HURONOS_FLAGS

LABEL nosync
  MENU LABEL ^6. Start no-sync mode
  KERNEL /boot/vmlinuz-6.0.15-huronos+
  APPEND initrd=/boot/initrfs.img load_ramdisk=1 prompt_ramdisk=0 rw consoleblank=0 console=tty0 modprobe.blacklist=i915,nouveau fbcon=nodefer $HURONOS_FLAGS
EOF
echo "✓ Updated $CFG_EFI"
fi

# Update checksums if file exists
if [ -f "$CHECKSUMS_FILE" ]; then
    echo "Updating checksums in $CHECKSUMS_FILE..."
    ORIGINAL_DIR="$(pwd)"
    cd "$TARGET_DIR"
    NEW_SUM_BOOT=$(sha256sum ./boot/huronos.cfg 2>/dev/null || true)
    NEW_SUM_EFI=$(sha256sum ./EFI/Boot/syslinux.cfg 2>/dev/null || true)
    if [ -n "$NEW_SUM_BOOT" ]; then
        sed -i "s|.*./boot/huronos.cfg.*|$NEW_SUM_BOOT|" "$CHECKSUMS_FILE"
    fi
    if [ -n "$NEW_SUM_EFI" ]; then
        sed -i "s|.*./EFI/Boot/syslinux.cfg.*|$NEW_SUM_EFI|" "$CHECKSUMS_FILE"
    fi
    cd "$ORIGINAL_DIR"
    echo "✓ Checksums updated."
fi

sync
echo ""
echo "============================================="
echo " ✓ UAA Lab & NVIDIA boot configuration successfully applied!"
echo "============================================="
echo "1. Made the EFI-framebuffer/fbdev fallback the default (without nomodeset)."
echo "2. Removed unsupported i915.force_probe=* from all normal boot paths."
echo "3. Kept experimental nouveau separate, removed vga=normal, and fixed the 64-bit EFI menu module."
echo ""
