#!/usr/bin/env bash
# =============================================================================
# 02-inject-custom-layer.sh — CPC GALLOS / UAA
# Injects custom wallpaper, Xorg/Mesa graphics fallbacks, and VS Code
# extensions (CPH, Microsoft Python & Red Hat Java) into a huronOS system partition or directory.
#
# Usage:
#   bash 02-inject-custom-layer.sh [/dev/sdX1 | /path/to/mounted/HURONOS] [wallpaper.png]
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET="${1}"
WALLPAPER_SRC="${2}"

if [ -z "$WALLPAPER_SRC" ] || [ ! -f "$WALLPAPER_SRC" ]; then
    if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
        WALLPAPER_SRC="$SCRIPT_DIR/huronos-wallpaper.png"
    elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
        WALLPAPER_SRC="$SCRIPT_DIR/wallpaper.png"
    else
        FOUND_IMG=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
        if [ -n "$FOUND_IMG" ]; then
            WALLPAPER_SRC="$FOUND_IMG"
        else
            echo "❌ Error: No wallpaper found (looked for huronos-wallpaper.png or wallpaper.png)."
            exit 1
        fi
    fi
fi

WALLPAPER_SHA=$(sha256sum "$WALLPAPER_SRC" | awk '{print $1}')
FILE_INFO=$(file "$WALLPAPER_SRC")
FBDEV_DEB_URL="https://deb.debian.org/debian/pool/main/x/xserver-xorg-video-fbdev/xserver-xorg-video-fbdev_0.5.0-1_amd64.deb"
FBDEV_DEB_SHA256="cccf3792ff2b6c95b55269b67ca7c5213a00561711fe8d10e5436961faf5d9d9"

# Extension definitions: MODULE_ID | DEFAULT_NAME | FALLBACK_URL | LOCAL_CANDIDATE_PATTERNS
EXT_CONFIGS=(
    "vsc-cph|competitive-programming-helper|https://github.com/agrawal-d/cph/releases/download/latest-vsix/competitive-programming-helper-2077.0.0.vsix|competitive-programming-helper-2077.0.0.vsix cph.vsix"
    "vsc-python|python|https://open-vsx.org/api/ms-python/python/2023.14.0/file/ms-python.python-2023.14.0.vsix|ms-python.python-2023.14.0.vsix ms-python.vsix python.vsix"
    "vsc-java|java|https://open-vsx.org/api/redhat/java/1.40.0/file/redhat.java-1.40.0.vsix|redhat.java-1.40.0.vsix redhat-java.vsix java.vsix"
)

echo "✓ Wallpaper source: $WALLPAPER_SRC"
echo "  Type:   $FILE_INFO"
echo "  SHA256: $WALLPAPER_SHA"
echo ""

# Determine target mount point or device
MOUNTED_BY_US=false
TARGET_DIR=""

if [ -z "$TARGET" ]; then
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
            echo "Usage: bash $0 [/dev/sdX1 | /path/to/mounted/huronOS] [wallpaper.png]"
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
            TARGET_DIR="/tmp/huronos-inject-mnt-$$"
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
        rm -rf "/tmp/huronos-inject-mnt-$$" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Check for huronOS structure
if [ ! -d "$TARGET_DIR/huronOS" ] && [ ! -d "$TARGET_DIR/base" ]; then
    echo "❌ Error: '$TARGET_DIR' does not appear to be a valid huronOS system directory."
    exit 1
fi

BASE_DIR="$TARGET_DIR/huronOS/base"
SOFTWARE_PROG_DIR="$TARGET_DIR/huronOS/software/programming"
DATA_BACKUPS_DIR="$TARGET_DIR/huronOS/data/backups"
CHECKSUMS_FILE="$TARGET_DIR/checksums"

if [ ! -d "$BASE_DIR" ] && [ -d "$TARGET_DIR/base" ]; then
    BASE_DIR="$TARGET_DIR/base"
fi
if [ ! -d "$SOFTWARE_PROG_DIR" ] && [ -d "$TARGET_DIR/software/programming" ]; then
    SOFTWARE_PROG_DIR="$TARGET_DIR/software/programming"
fi
if [ ! -d "$DATA_BACKUPS_DIR" ] && [ -d "$TARGET_DIR/data/backups" ]; then
    DATA_BACKUPS_DIR="$TARGET_DIR/data/backups"
fi
if [ ! -f "$CHECKSUMS_FILE" ] && [ -f "$TARGET_DIR/../checksums" ]; then
    CHECKSUMS_FILE="$TARGET_DIR/../checksums"
fi

echo "Target base directory: $BASE_DIR"

# Unsquash and rebuild 05-custom.hsl with wallpaper, graphics fix, and VS Code extensions
TMP_LAB="/tmp/huronos-layer-lab-$$"
mkdir -p "$TMP_LAB/squashfs-root"

CUSTOM_HSL="$BASE_DIR/05-custom.hsl"
if [ -f "$CUSTOM_HSL" ]; then
    echo "Extracting existing 05-custom.hsl layer..."
    unsquashfs -d "$TMP_LAB/squashfs-root" -f "$CUSTOM_HSL" >/dev/null 2>&1 || true
fi

echo "Injecting wallpaper as /usr/share/backgrounds/huronos-background.png..."
mkdir -p "$TMP_LAB/squashfs-root/usr/share/backgrounds"
cp -f "$WALLPAPER_SRC" "$TMP_LAB/squashfs-root/usr/share/backgrounds/huronos-background.png"

echo "Configuring Xorg display and Mesa fallback in 05-custom.hsl..."
mkdir -p "$TMP_LAB/squashfs-root/usr/share/X11/xorg.conf.d"
mkdir -p "$TMP_LAB/squashfs-root/etc/alternatives"
mkdir -p "$TMP_LAB/squashfs-root/usr/lib/xorg/modules/drivers"
mkdir -p "$TMP_LAB/squashfs-root/etc/X11/xorg.conf.d"
mkdir -p "$TMP_LAB/fbdev-package"

rm -f "$TMP_LAB/squashfs-root/etc/X11/xorg.conf.d/99-modesetting.conf"

echo "Downloading the Debian fbdev Xorg driver..."
curl -fsSL --retry 2 -o "$TMP_LAB/fbdev.deb" "$FBDEV_DEB_URL"
echo "$FBDEV_DEB_SHA256  $TMP_LAB/fbdev.deb" | sha256sum -c -
(
    cd "$TMP_LAB/fbdev-package"
    ar x "$TMP_LAB/fbdev.deb"
    tar -xJf data.tar.xz ./usr/lib/xorg/modules/drivers/fbdev_drv.so
)
install -m 0755 "$TMP_LAB/fbdev-package/usr/lib/xorg/modules/drivers/fbdev_drv.so" \
    "$TMP_LAB/squashfs-root/usr/lib/xorg/modules/drivers/fbdev_drv.so"

cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/X11/xorg.conf.d/99-display.conf"
# Linux 6.0 in huronOS alpha 0.4 has no KMS driver for Intel Arrow Lake.
# Use the EFI framebuffer exposed as /dev/fb0, not the modesetting driver.
Section "Device"
    Identifier "EFI framebuffer"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "EFI framebuffer"
EndSection
EOF

mkdir -p "$TMP_LAB/squashfs-root/etc/X11/Xsession.d"
cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/X11/Xsession.d/99-huronos-software-rendering"
# Render OpenGL clients with Mesa LLVMpipe; efifb has no 3D acceleration.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
EOF

cat << 'EOF' > "$TMP_LAB/squashfs-root/usr/share/X11/xorg.conf.d/nvidia-drm-outputclass.conf"
# Disabled for universal Intel/AMD/NVIDIA open-source compatibility
EOF

ln -sf /usr/lib/mesa-diverted "$TMP_LAB/squashfs-root/etc/alternatives/glx"
ln -sf /usr/lib/xorg/modules/extensions/libglx.so "$TMP_LAB/squashfs-root/etc/alternatives/glx--libglxserver_nvidia.so"

mkdir -p "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/ids"

declare -a GENERATED_HSMS=()

for ext_spec in "${EXT_CONFIGS[@]}"; do
    IFS='|' read -r MOD_ID DEFAULT_EXT_NAME EXT_URL PATTERNS <<< "$ext_spec"

    echo "Injecting extension: $MOD_ID ($DEFAULT_EXT_NAME)..."

    LOCAL_VSIX=""
    for pat in $PATTERNS; do
        if [ -f "$SCRIPT_DIR/$pat" ]; then
            LOCAL_VSIX="$SCRIPT_DIR/$pat"
            break
        fi
    done

    if [ -z "$LOCAL_VSIX" ]; then
        FOUND=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*$DEFAULT_EXT_NAME*.vsix" 2>/dev/null | head -n 1 || true)
        if [ -n "$FOUND" ] && [ -f "$FOUND" ]; then
            LOCAL_VSIX="$FOUND"
        fi
    fi

    if [ -z "$LOCAL_VSIX" ] || [ ! -f "$LOCAL_VSIX" ]; then
        echo "  Downloading $MOD_ID from $EXT_URL..."
        LOCAL_VSIX="$TMP_LAB/${MOD_ID}.vsix"
        curl -fsSL --retry 3 -o "$LOCAL_VSIX" "$EXT_URL" || true
    fi

    if [ -f "$LOCAL_VSIX" ]; then
        UNPACK_DIR="$TMP_LAB/unpack_$MOD_ID"
        mkdir -p "$UNPACK_DIR"
        unzip -q "$LOCAL_VSIX" -d "$UNPACK_DIR"

        PKG_JSON="$UNPACK_DIR/extension/package.json"
        EXT_VERSION=$(grep -o '"version": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "1.0.0")
        EXT_PUBLISHER=$(grep -o '"publisher": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "custom")
        EXT_NAME=$(grep -o '"name": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "$DEFAULT_EXT_NAME")

        [ -z "$EXT_VERSION" ] && EXT_VERSION="1.0.0"
        [ -z "$EXT_PUBLISHER" ] && EXT_PUBLISHER="custom"
        [ -z "$EXT_NAME" ] && EXT_NAME="$DEFAULT_EXT_NAME"

        FULL_EXT_ID="${EXT_PUBLISHER}.${EXT_NAME}"
        EXT_DIR_NAME="${FULL_EXT_ID}-${EXT_VERSION}"

        EXT_ROOT="$TMP_LAB/root_$MOD_ID"
        mkdir -p "$EXT_ROOT/opt/codium/contestant/extensions/ids"
        mkdir -p "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME"

        cp -rf "$UNPACK_DIR/extension/"* "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
        if [ -f "$UNPACK_DIR/extension.vsixmanifest" ]; then
            cp -f "$UNPACK_DIR/extension.vsixmanifest" "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest"
        fi

        NOW_MS=$(date +%s000)
        cat << EOF > "$EXT_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json"
{"identifier":{"id":"${FULL_EXT_ID}"},"version":"${EXT_VERSION}","location":{"\$mid":1,"fsPath":"/opt/codium/contestant/extensions/${EXT_DIR_NAME}","external":"file:///opt/codium/contestant/extensions/${EXT_DIR_NAME}","path":"/opt/codium/contestant/extensions/${EXT_DIR_NAME}","scheme":"file"},"relativeLocation":"${EXT_DIR_NAME}","metadata":{"installedTimestamp":${NOW_MS}}}
EOF

        # Inject into 05-custom.hsl tree
        mkdir -p "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/$EXT_DIR_NAME"
        cp -rf "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"* "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
        if [ -f "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest" ]; then
            cp -f "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest" "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
        fi
        cp -f "$EXT_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json" "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/ids/${MOD_ID}.json"

        # Build standalone .hsm module
        if [ -d "$SOFTWARE_PROG_DIR" ]; then
            HSM_FILE="$SOFTWARE_PROG_DIR/${MOD_ID}.hsm"
            echo "  Building standalone module: $HSM_FILE"
            TMP_HSM="$TMP_LAB/${MOD_ID}.hsm"
            rm -f "$TMP_HSM"
            mksquashfs "$EXT_ROOT" "$TMP_HSM" -comp xz -b 1024K -always-use-fragments -noappend >/dev/null
            cp -f "$TMP_HSM" "$HSM_FILE"
            GENERATED_HSMS+=("${MOD_ID}.hsm")
        fi
    fi
done

echo "Building updated 05-custom.hsl squashfs layer..."
rm -f "$TMP_LAB/05-custom.hsl"
mksquashfs "$TMP_LAB/squashfs-root" "$TMP_LAB/05-custom.hsl" -comp xz -b 1024K -always-use-fragments -noappend >/dev/null

cp -f "$TMP_LAB/05-custom.hsl" "$CUSTOM_HSL"
rm -rf "$TMP_LAB"
echo "✓ Updated $CUSTOM_HSL (with wallpaper, graphics fix, and full VS Code extensions suite)"

# Pre-seed wallpaper in huronOS/data/backups/
mkdir -p "$DATA_BACKUPS_DIR"
WALL_BASENAME="$(basename "$WALLPAPER_SRC")"
WALL_EXT="${WALL_BASENAME##*.}"

copy_wallpaper_if_needed() {
    local destination="$1"

    if [ ! -e "$destination" ] || ! cmp -s "$WALLPAPER_SRC" "$destination"; then
        cp -f "$WALLPAPER_SRC" "$destination"
    fi
}

copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Always-mode-wallpaper.${WALL_EXT}"
copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Event-mode-wallpaper.${WALL_EXT}"
copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Contest-mode-wallpaper.${WALL_EXT}"
if [ "$WALL_EXT" != "png" ]; then
    copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Always-mode-wallpaper.png"
    copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Event-mode-wallpaper.png"
    copy_wallpaper_if_needed "$DATA_BACKUPS_DIR/Contest-mode-wallpaper.png"
fi
echo "✓ Pre-seeded Always, Event, and Contest mode wallpapers in huronOS/data/backups/"

# Update checksums file if present
if [ -f "$CHECKSUMS_FILE" ]; then
    echo "Updating $CHECKSUMS_FILE with new checksums..."
    CURRENT_PWD="$(pwd)"
    cd "$TARGET_DIR"
    NEW_HSL_CHECKSUM=$(sha256sum huronOS/base/05-custom.hsl 2>/dev/null || sha256sum base/05-custom.hsl 2>/dev/null || true)
    if [ -n "$NEW_HSL_CHECKSUM" ]; then
        if grep -q "05-custom.hsl" "$CHECKSUMS_FILE"; then
            sed -i "s|.*05-custom.hsl.*|$NEW_HSL_CHECKSUM|" "$CHECKSUMS_FILE"
        else
            echo "$NEW_HSL_CHECKSUM" >> "$CHECKSUMS_FILE"
        fi
    fi

    for hsm in "${GENERATED_HSMS[@]}"; do
        HSM_PATH="huronOS/software/programming/$hsm"
        [ ! -f "$HSM_PATH" ] && HSM_PATH="software/programming/$hsm"
        if [ -f "$HSM_PATH" ]; then
            NEW_HSM_CHECKSUM=$(sha256sum "$HSM_PATH")
            if grep -q "$hsm" "$CHECKSUMS_FILE"; then
                sed -i "s|.*$hsm.*|$NEW_HSM_CHECKSUM|" "$CHECKSUMS_FILE"
            else
                echo "$NEW_HSM_CHECKSUM" >> "$CHECKSUMS_FILE"
            fi
        fi
    done

    cd "$CURRENT_PWD"
    echo "✓ Checksums updated."
fi

sync
echo ""
echo "============================================="
echo " ✓ Custom layer successfully injected!"
echo " Wallpaper SHA256: $WALLPAPER_SHA"
echo " VS Code Extensions: C/C++, CPH, Python & Java ready"
echo "============================================="
