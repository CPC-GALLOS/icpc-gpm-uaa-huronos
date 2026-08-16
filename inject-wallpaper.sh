#!/usr/bin/env bash
# =============================================================================
# inject-wallpaper.sh — CPC GALLOS / UAA
# Injects a custom wallpaper into a huronOS system partition or directory.
#
# Can be called with:
#   1. A mounted directory (e.g. /media/HURONOS or /mnt/huronos)
#   2. A device/partition path (e.g. /dev/sdb1 or /dev/loop0p1)
#   3. No argument (will auto-detect partition labeled 'HURONOS')
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
echo "✓ Wallpaper source: $WALLPAPER_SRC"
echo "  Type:   $FILE_INFO"
echo "  SHA256: $WALLPAPER_SHA"
echo ""

# 2. Determine target mount point or device
MOUNTED_BY_US=false
TARGET_DIR=""

if [ -z "$TARGET" ]; then
    echo "Searching for partition with label 'HURONOS'..."
    DEV_CANDIDATE=$(blkid -L HURONOS 2>/dev/null || true)
    if [ -n "$DEV_CANDIDATE" ]; then
        TARGET="$DEV_CANDIDATE"
        echo "Found huronOS partition: $TARGET"
    else
        echo "❌ Error: No target specified and no partition labeled 'HURONOS' found."
        echo "Usage: sudo bash $0 [/dev/sdX1 | /path/to/mounted/huronOS] [wallpaper.png]"
        exit 1
    fi
fi

if [ -b "$TARGET" ]; then
    # It's a block device (e.g. /dev/sdb1)
    TARGET_DIR="/tmp/huronos-inject-mnt-$$"
    mkdir -p "$TARGET_DIR"
    echo "Mounting $TARGET to $TARGET_DIR..."
    mount "$TARGET" "$TARGET_DIR"
    MOUNTED_BY_US=true
elif [ -d "$TARGET" ]; then
    TARGET_DIR="$TARGET"
else
    echo "❌ Error: Target '$TARGET' is neither a block device nor a directory."
    exit 1
fi

cleanup() {
    if [ "$MOUNTED_BY_US" = true ] && mountpoint -q "$TARGET_DIR" 2>/dev/null; then
        echo "Unmounting $TARGET_DIR..."
        sync
        umount "$TARGET_DIR" || true
        rm -rf "$TARGET_DIR"
    fi
}
trap cleanup EXIT INT TERM

# 3. Check for huronOS structure
if [ ! -d "$TARGET_DIR/huronOS" ] && [ ! -d "$TARGET_DIR/base" ]; then
    echo "❌ Error: '$TARGET_DIR' does not appear to be a valid huronOS system directory."
    exit 1
fi

BASE_DIR="$TARGET_DIR/huronOS/base"
DATA_BACKUPS_DIR="$TARGET_DIR/huronOS/data/backups"
CHECKSUMS_FILE="$TARGET_DIR/checksums"

if [ ! -d "$BASE_DIR" ] && [ -d "$TARGET_DIR/base" ]; then
    BASE_DIR="$TARGET_DIR/base"
fi
if [ ! -d "$DATA_BACKUPS_DIR" ] && [ -d "$TARGET_DIR/data/backups" ]; then
    DATA_BACKUPS_DIR="$TARGET_DIR/data/backups"
fi
if [ ! -f "$CHECKSUMS_FILE" ] && [ -f "$TARGET_DIR/../checksums" ]; then
    CHECKSUMS_FILE="$TARGET_DIR/../checksums"
fi

echo "Target base directory: $BASE_DIR"

# 4. Unsquash and rebuild 05-custom.hsl with the new wallpaper
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

echo "Building updated 05-custom.hsl squashfs layer..."
rm -f "$TMP_LAB/05-custom.hsl"
mksquashfs "$TMP_LAB/squashfs-root" "$TMP_LAB/05-custom.hsl" -comp xz -b 1024K -always-use-fragments -noappend >/dev/null

cp -f "$TMP_LAB/05-custom.hsl" "$CUSTOM_HSL"
rm -rf "$TMP_LAB"
echo "✓ Updated $CUSTOM_HSL"

# 5. Pre-seed wallpaper in huronOS/data/backups/
mkdir -p "$DATA_BACKUPS_DIR"
WALL_BASENAME="$(basename "$WALLPAPER_SRC")"
WALL_EXT="${WALL_BASENAME##*.}"

cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Always-mode-wallpaper.${WALL_EXT}"
cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Event-mode-wallpaper.${WALL_EXT}"
cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Contest-mode-wallpaper.${WALL_EXT}"
# Also seed .png aliases if extension is not png for fallback
if [ "$WALL_EXT" != "png" ]; then
    cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Always-mode-wallpaper.png"
    cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Event-mode-wallpaper.png"
    cp -f "$WALLPAPER_SRC" "$DATA_BACKUPS_DIR/Contest-mode-wallpaper.png"
fi
echo "✓ Pre-seeded Always, Event, and Contest mode wallpapers in huronOS/data/backups/"

# 6. Update checksums file if present
if [ -f "$CHECKSUMS_FILE" ]; then
    echo "Updating $CHECKSUMS_FILE with new 05-custom.hsl checksum..."
    CURRENT_PWD="$(pwd)"
    cd "$TARGET_DIR"
    NEW_CHECKSUM=$(sha256sum huronOS/base/05-custom.hsl 2>/dev/null || sha256sum base/05-custom.hsl)
    sed -i "s|.*05-custom.hsl.*|$NEW_CHECKSUM|" "$CHECKSUMS_FILE"
    cd "$CURRENT_PWD"
    echo "✓ Checksums updated."
fi

sync
echo ""
echo "============================================="
echo " ✓ Custom wallpaper successfully injected!"
echo " Wallpaper SHA256: $WALLPAPER_SHA"
echo "============================================="
