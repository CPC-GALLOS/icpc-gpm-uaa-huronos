#!/usr/bin/env bash
# =============================================================================
# 02-inject-custom-layer.sh — CPC GALLOS / UAA
# Injects custom wallpaper, Xorg/Mesa graphics fallbacks, Noto Color Emoji / DejaVu / Inter fonts,
# Telegram Desktop, and VS Code extensions (CPH, Microsoft Python & Red Hat Java)
# into a huronOS system partition or directory.
#
# Usage:
#   bash 02-inject-custom-layer.sh [/dev/sdX1 | /path/to/mounted/HURONOS] [wallpaper.png] [directives.hdf]
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET="${1}"
WALLPAPER_SRC="${2}"
HDF_SRC="${3}"

if [ -n "$HDF_SRC" ] && [ ! -f "$HDF_SRC" ]; then
    echo "⚠️ Warning: Specified directives file '$HDF_SRC' not found."
    HDF_SRC=""
fi
if [ -z "$HDF_SRC" ]; then
    FOUND_TEST_HDF=$(find "$SCRIPT_DIR" -maxdepth 1 -name "icpc-test-*.hdf" 2>/dev/null | sort -r | head -n 1 || true)
    if [ -n "$FOUND_TEST_HDF" ] && [ -f "$FOUND_TEST_HDF" ]; then
        HDF_SRC="$FOUND_TEST_HDF"
    elif [ -f "$SCRIPT_DIR/icpc-gpm-2026-3rd-date.hdf" ]; then
        HDF_SRC="$SCRIPT_DIR/icpc-gpm-2026-3rd-date.hdf"
    fi
fi

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
SPICE_VDAGENT_DEB_URL="https://deb.debian.org/debian/pool/main/s/spice-vdagent/spice-vdagent_0.20.0-2_amd64.deb"
SPICE_VDAGENT_DEB_SHA256="19800ed07b2b4d1fe65eb1b20affdc14132fc712da0b9577560482a7a9c48aa8"

NOTO_EMOJI_DEB_URL="https://deb.debian.org/debian/pool/main/f/fonts-noto-color-emoji/fonts-noto-color-emoji_2.051-1_all.deb"
NOTO_EMOJI_DEB_SHA256="fd24bbdf01db0e146682eea6d9f10448260fa77da579a6cc0aa336912f143638"
DEJAVU_CORE_DEB_URL="https://deb.debian.org/debian/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-8_all.deb"
DEJAVU_CORE_DEB_SHA256="86635b3d25b3655fc11cb3ecc3af59f0bf19643b02b94f2de48bd10253cdba12"
INTER_DEB_URL="https://deb.debian.org/debian/pool/main/f/fonts-inter/fonts-inter_4.0~beta7+ds-1_all.deb"
INTER_DEB_SHA256="6afd9014550e04b58bccf64b94f92ae1dbfd8018489b92de835408970234c24c"

TELEGRAM_TAR_URL="https://telegram.org/dl/desktop/linux"
TELEGRAM_FALLBACK_URL="https://github.com/telegramdesktop/tdesktop/releases/download/v5.1.7/tsetup.5.1.7.tar.xz"
TELEGRAM_ICON_URL="https://raw.githubusercontent.com/telegramdesktop/tdesktop/dev/Telegram/Resources/art/icon512.png"

# Extension definitions: MODULE_ID | DEFAULT_NAME | FALLBACK_URL | LOCAL_CANDIDATE_PATTERNS
EXT_CONFIGS=(
    "vsc-cph|competitive-programming-helper|https://github.com/agrawal-d/cph/releases/download/latest-vsix/competitive-programming-helper-2077.0.0.vsix|competitive-programming-helper-2077.0.0.vsix cph.vsix"
    "vsc-python|python|https://open-vsx.org/api/ms-python/python/2023.14.0/file/ms-python.python-2023.14.0.vsix|ms-python.python-2023.14.0.vsix ms-python.vsix python.vsix"
    "vsc-java|java|https://open-vsx.org/api/redhat/java/1.40.0/file/redhat.java-1.40.0.vsix|redhat.java-1.40.0.vsix redhat-java.vsix java.vsix"
)

echo "✓ Wallpaper source: $WALLPAPER_SRC"
echo "  Type:   $FILE_INFO"
echo "  SHA256: $WALLPAPER_SHA"
if [ -n "$HDF_SRC" ] && [ -f "$HDF_SRC" ]; then
    echo "✓ Directives source: $HDF_SRC"
fi
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
SOFTWARE_INTERNET_DIR="$TARGET_DIR/huronOS/software/internet"
DATA_BACKUPS_DIR="$TARGET_DIR/huronOS/data/backups"
CHECKSUMS_FILE="$TARGET_DIR/checksums"

if [ ! -d "$BASE_DIR" ] && [ -d "$TARGET_DIR/base" ]; then
    BASE_DIR="$TARGET_DIR/base"
fi
if [ ! -d "$SOFTWARE_PROG_DIR" ] && [ -d "$TARGET_DIR/software/programming" ]; then
    SOFTWARE_PROG_DIR="$TARGET_DIR/software/programming"
fi
if [ ! -d "$SOFTWARE_INTERNET_DIR" ] && [ -d "$TARGET_DIR/software/internet" ]; then
    SOFTWARE_INTERNET_DIR="$TARGET_DIR/software/internet"
fi
if [ ! -d "$DATA_BACKUPS_DIR" ] && [ -d "$TARGET_DIR/data/backups" ]; then
    DATA_BACKUPS_DIR="$TARGET_DIR/data/backups"
fi
if [ ! -f "$CHECKSUMS_FILE" ] && [ -f "$TARGET_DIR/../checksums" ]; then
    CHECKSUMS_FILE="$TARGET_DIR/../checksums"
fi

echo "Target base directory: $BASE_DIR"

# Unsquash and rebuild 05-custom.hsl with wallpaper, graphics fix, fonts, Telegram, and VS Code extensions
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

if [ -n "$HDF_SRC" ] && [ -f "$HDF_SRC" ]; then
    echo "Injecting directives into 05-custom.hsl (/etc/hsync/directives)..."
    mkdir -p "$TMP_LAB/squashfs-root/etc/hsync"
    cp -f "$HDF_SRC" "$TMP_LAB/squashfs-root/etc/hsync/directives"
fi

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

echo "Downloading Debian SPICE Guest Agent (spice-vdagent) for KVM/SPICE integration..."
mkdir -p "$TMP_LAB/spice-package"
if curl -fsSL --retry 2 -o "$TMP_LAB/spice-vdagent.deb" "$SPICE_VDAGENT_DEB_URL"; then
    if echo "$SPICE_VDAGENT_DEB_SHA256  $TMP_LAB/spice-vdagent.deb" | sha256sum -c - >/dev/null 2>&1; then
        (
            cd "$TMP_LAB/spice-package"
            ar x "$TMP_LAB/spice-vdagent.deb"
            tar -xJf data.tar.xz
        )
        mkdir -p "$TMP_LAB/squashfs-root/usr/bin"
        mkdir -p "$TMP_LAB/squashfs-root/usr/sbin"
        mkdir -p "$TMP_LAB/squashfs-root/usr/lib/systemd/system"
        mkdir -p "$TMP_LAB/squashfs-root/usr/lib/udev/rules.d"
        mkdir -p "$TMP_LAB/squashfs-root/etc/xdg/autostart"
        mkdir -p "$TMP_LAB/squashfs-root/etc/systemd/system/sockets.target.wants"
        mkdir -p "$TMP_LAB/squashfs-root/etc/systemd/system/multi-user.target.wants"

        install -m 0755 "$TMP_LAB/spice-package/usr/bin/spice-vdagent" "$TMP_LAB/squashfs-root/usr/bin/spice-vdagent"
        install -m 0755 "$TMP_LAB/spice-package/usr/sbin/spice-vdagentd" "$TMP_LAB/squashfs-root/usr/sbin/spice-vdagentd"
        cp -f "$TMP_LAB/spice-package/lib/systemd/system/"* "$TMP_LAB/squashfs-root/usr/lib/systemd/system/" 2>/dev/null || true
        cp -f "$TMP_LAB/spice-package/lib/udev/rules.d/"* "$TMP_LAB/squashfs-root/usr/lib/udev/rules.d/" 2>/dev/null || true
        cp -f "$TMP_LAB/spice-package/etc/xdg/autostart/"* "$TMP_LAB/squashfs-root/etc/xdg/autostart/" 2>/dev/null || true

        ln -sf /usr/lib/systemd/system/spice-vdagentd.socket "$TMP_LAB/squashfs-root/etc/systemd/system/sockets.target.wants/spice-vdagentd.socket" 2>/dev/null || true
        ln -sf /usr/lib/systemd/system/spice-vdagentd.service "$TMP_LAB/squashfs-root/etc/systemd/system/multi-user.target.wants/spice-vdagentd.service" 2>/dev/null || true
        echo "✓ Injected SPICE vdagent (auto-resolution & clipboard sharing enabled)"
    fi
fi

# Prevent AUFS merged-usr symlink masking: ensure no root-level lib/bin/sbin exists in 05-custom.hsl
rm -rf "$TMP_LAB/squashfs-root/lib" "$TMP_LAB/squashfs-root/lib64" "$TMP_LAB/squashfs-root/bin" "$TMP_LAB/squashfs-root/sbin"

# Clean up any rigid Section Device overrides to let Xorg naturally probe modesetting (KMS/QXL) first, and fbdev fallback second
rm -f "$TMP_LAB/squashfs-root/etc/X11/xorg.conf.d/99-display.conf"
rm -f "$TMP_LAB/squashfs-root/etc/X11/xorg.conf.d/99-modesetting.conf"

mkdir -p "$TMP_LAB/squashfs-root/etc/X11/Xsession.d"

cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/X11/Xsession.d/98-spice-vdagent"
# Auto-start SPICE user agent for dynamic Xrandr resolution and clipboard sharing in KVM
if [ -x /usr/bin/spice-vdagent ]; then
    /usr/bin/spice-vdagent >/dev/null 2>&1 &
fi
EOF

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

# =============================================================================
# Emoji & Unicode Font Injection (Noto Color Emoji, DejaVu Sans & Inter)
# =============================================================================
echo "Injecting Noto Color Emoji, DejaVu, and Inter fonts for full MOJ UI/Unicode support..."
mkdir -p "$TMP_LAB/squashfs-root/usr/share/fonts/truetype/noto"
mkdir -p "$TMP_LAB/squashfs-root/usr/share/fonts/truetype/dejavu"
mkdir -p "$TMP_LAB/squashfs-root/usr/share/fonts/opentype/inter"
mkdir -p "$TMP_LAB/squashfs-root/etc/fonts/conf.d"
mkdir -p "$TMP_LAB/squashfs-root/etc/fonts/conf.avail"
mkdir -p "$TMP_LAB/squashfs-root/usr/share/fontconfig/conf.avail"

LOCAL_NOTO_DEB=""
if [ -f "$SCRIPT_DIR/fonts-noto-color-emoji.deb" ]; then
    LOCAL_NOTO_DEB="$SCRIPT_DIR/fonts-noto-color-emoji.deb"
else
    FOUND_NOTO=$(find "$SCRIPT_DIR" -maxdepth 1 -name "fonts-noto-color-emoji*.deb" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND_NOTO" ] && [ -f "$FOUND_NOTO" ]; then
        LOCAL_NOTO_DEB="$FOUND_NOTO"
    fi
fi
if [ -z "$LOCAL_NOTO_DEB" ] || [ ! -f "$LOCAL_NOTO_DEB" ]; then
    LOCAL_NOTO_DEB="$TMP_LAB/noto-emoji.deb"
    echo "  Downloading fonts-noto-color-emoji package..."
    curl -fsSL --retry 2 -o "$LOCAL_NOTO_DEB" "$NOTO_EMOJI_DEB_URL" || true
    if [ -n "$NOTO_EMOJI_DEB_SHA256" ]; then
        echo "$NOTO_EMOJI_DEB_SHA256  $LOCAL_NOTO_DEB" | sha256sum -c - >/dev/null 2>&1 || true
    fi
fi

if [ -f "$LOCAL_NOTO_DEB" ]; then
    mkdir -p "$TMP_LAB/noto-pkg"
    (
        cd "$TMP_LAB/noto-pkg"
        ar x "$LOCAL_NOTO_DEB" 2>/dev/null || true
        [ -f data.tar.xz ] && tar -xJf data.tar.xz 2>/dev/null || true
    )
    if [ -f "$TMP_LAB/noto-pkg/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf" ]; then
        cp -f "$TMP_LAB/noto-pkg/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf" \
            "$TMP_LAB/squashfs-root/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"
        echo "✓ Injected Noto Color Emoji font (/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf)"
    fi
fi

LOCAL_DEJAVU_DEB=""
if [ -f "$SCRIPT_DIR/fonts-dejavu-core.deb" ]; then
    LOCAL_DEJAVU_DEB="$SCRIPT_DIR/fonts-dejavu-core.deb"
else
    FOUND_DEJAVU=$(find "$SCRIPT_DIR" -maxdepth 1 -name "fonts-dejavu-core*.deb" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND_DEJAVU" ] && [ -f "$FOUND_DEJAVU" ]; then
        LOCAL_DEJAVU_DEB="$FOUND_DEJAVU"
    fi
fi
if [ -z "$LOCAL_DEJAVU_DEB" ] || [ ! -f "$LOCAL_DEJAVU_DEB" ]; then
    LOCAL_DEJAVU_DEB="$TMP_LAB/dejavu-core.deb"
    echo "  Downloading fonts-dejavu-core package..."
    curl -fsSL --retry 2 -o "$LOCAL_DEJAVU_DEB" "$DEJAVU_CORE_DEB_URL" || true
    if [ -n "$DEJAVU_CORE_DEB_SHA256" ]; then
        echo "$DEJAVU_CORE_DEB_SHA256  $LOCAL_DEJAVU_DEB" | sha256sum -c - >/dev/null 2>&1 || true
    fi
fi

if [ -f "$LOCAL_DEJAVU_DEB" ]; then
    mkdir -p "$TMP_LAB/dejavu-pkg"
    (
        cd "$TMP_LAB/dejavu-pkg"
        ar x "$LOCAL_DEJAVU_DEB" 2>/dev/null || true
        [ -f data.tar.xz ] && tar -xJf data.tar.xz 2>/dev/null || true
    )
    if [ -d "$TMP_LAB/dejavu-pkg/usr/share/fonts/truetype/dejavu" ]; then
        cp -rf "$TMP_LAB/dejavu-pkg/usr/share/fonts/truetype/dejavu/"* \
            "$TMP_LAB/squashfs-root/usr/share/fonts/truetype/dejavu/" 2>/dev/null || true
        echo "✓ Injected DejaVu Sans fonts (/usr/share/fonts/truetype/dejavu/)"
    fi
    if [ -d "$TMP_LAB/dejavu-pkg/etc/fonts/conf.avail" ]; then
        cp -rf "$TMP_LAB/dejavu-pkg/etc/fonts/conf.avail/"* \
            "$TMP_LAB/squashfs-root/etc/fonts/conf.avail/" 2>/dev/null || true
    fi
    if [ -d "$TMP_LAB/dejavu-pkg/etc/fonts/conf.d" ]; then
        cp -rf "$TMP_LAB/dejavu-pkg/etc/fonts/conf.d/"* \
            "$TMP_LAB/squashfs-root/etc/fonts/conf.d/" 2>/dev/null || true
    fi
fi

LOCAL_INTER_DEB=""
if [ -f "$SCRIPT_DIR/fonts-inter.deb" ]; then
    LOCAL_INTER_DEB="$SCRIPT_DIR/fonts-inter.deb"
else
    FOUND_INTER=$(find "$SCRIPT_DIR" -maxdepth 1 -name "fonts-inter*.deb" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND_INTER" ] && [ -f "$FOUND_INTER" ]; then
        LOCAL_INTER_DEB="$FOUND_INTER"
    fi
fi
if [ -z "$LOCAL_INTER_DEB" ] || [ ! -f "$LOCAL_INTER_DEB" ]; then
    LOCAL_INTER_DEB="$TMP_LAB/fonts-inter.deb"
    echo "  Downloading fonts-inter package..."
    curl -fsSL --retry 2 -o "$LOCAL_INTER_DEB" "$INTER_DEB_URL" || true
    if [ -n "$INTER_DEB_SHA256" ]; then
        echo "$INTER_DEB_SHA256  $LOCAL_INTER_DEB" | sha256sum -c - >/dev/null 2>&1 || true
    fi
fi

if [ -f "$LOCAL_INTER_DEB" ]; then
    mkdir -p "$TMP_LAB/inter-pkg"
    (
        cd "$TMP_LAB/inter-pkg"
        ar x "$LOCAL_INTER_DEB" 2>/dev/null || true
        [ -f data.tar.xz ] && tar -xJf data.tar.xz 2>/dev/null || true
    )
    if [ -d "$TMP_LAB/inter-pkg/usr/share/fonts/opentype/inter" ]; then
        cp -f "$TMP_LAB/inter-pkg/usr/share/fonts/opentype/inter/Inter-"*.otf \
            "$TMP_LAB/squashfs-root/usr/share/fonts/opentype/inter/" 2>/dev/null || true
        echo "✓ Injected Inter UI font (/usr/share/fonts/opentype/inter/) — matches MOJ's font-family:\"Inter\""
    fi
fi

# Fontconfig alias & fallback configuration for Emoji and Symbols
cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/fonts/conf.avail/56-fonts-noto-color-emoji.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="same"><string>Noto Color Emoji</string></edit>
  </match>
  <match target="pattern">
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="append"><string>Noto Color Emoji</string></edit>
  </match>
  <match target="pattern">
    <test name="family"><string>serif</string></test>
    <edit name="family" mode="append"><string>Noto Color Emoji</string></edit>
  </match>
  <match target="pattern">
    <test name="family"><string>monospace</string></test>
    <edit name="family" mode="append"><string>Noto Color Emoji</string></edit>
  </match>
</fontconfig>
EOF
cp -f "$TMP_LAB/squashfs-root/etc/fonts/conf.avail/56-fonts-noto-color-emoji.conf" \
    "$TMP_LAB/squashfs-root/usr/share/fontconfig/conf.avail/56-fonts-noto-color-emoji.conf"
ln -sf /etc/fonts/conf.avail/56-fonts-noto-color-emoji.conf \
    "$TMP_LAB/squashfs-root/etc/fonts/conf.d/56-fonts-noto-color-emoji.conf" 2>/dev/null || true

# =============================================================================
# Telegram Desktop Injection & Offline Integration
# =============================================================================
echo "Injecting Telegram Desktop application..."
declare -a GENERATED_HSMS=()

LOCAL_TG_TAR=""
if [ -f "$SCRIPT_DIR/tsetup.tar.xz" ]; then
    LOCAL_TG_TAR="$SCRIPT_DIR/tsetup.tar.xz"
else
    FOUND_TG=$(find "$SCRIPT_DIR" -maxdepth 1 -name "tsetup*.tar.xz" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND_TG" ] && [ -f "$FOUND_TG" ]; then
        LOCAL_TG_TAR="$FOUND_TG"
    fi
fi
if [ -z "$LOCAL_TG_TAR" ] || [ ! -f "$LOCAL_TG_TAR" ]; then
    LOCAL_TG_TAR="$TMP_LAB/tsetup.tar.xz"
    echo "  Downloading Telegram Desktop..."
    curl -fsSL --retry 2 -o "$LOCAL_TG_TAR" "$TELEGRAM_TAR_URL" || \
        curl -fsSL --retry 2 -o "$LOCAL_TG_TAR" "$TELEGRAM_FALLBACK_URL" || true
fi

LOCAL_TG_ICON=""
if [ -f "$SCRIPT_DIR/telegram-icon.png" ]; then
    LOCAL_TG_ICON="$SCRIPT_DIR/telegram-icon.png"
elif [ -f "$SCRIPT_DIR/icon512.png" ]; then
    LOCAL_TG_ICON="$SCRIPT_DIR/icon512.png"
fi
if [ -z "$LOCAL_TG_ICON" ] || [ ! -f "$LOCAL_TG_ICON" ]; then
    LOCAL_TG_ICON="$TMP_LAB/telegram-icon.png"
    curl -fsSL --retry 2 -o "$LOCAL_TG_ICON" "$TELEGRAM_ICON_URL" || true
fi

if [ -f "$LOCAL_TG_TAR" ]; then
    TG_UNPACK="$TMP_LAB/unpack_telegram"
    mkdir -p "$TG_UNPACK"
    tar -xf "$LOCAL_TG_TAR" -C "$TG_UNPACK" 2>/dev/null || true

    if [ -f "$TG_UNPACK/Telegram/Telegram" ]; then
        mkdir -p "$TMP_LAB/squashfs-root/opt/telegram"
        mkdir -p "$TMP_LAB/squashfs-root/usr/bin"
        mkdir -p "$TMP_LAB/squashfs-root/usr/local/bin"
        mkdir -p "$TMP_LAB/squashfs-root/usr/share/applications"
        mkdir -p "$TMP_LAB/squashfs-root/usr/share/pixmaps"
        mkdir -p "$TMP_LAB/squashfs-root/usr/share/icons/hicolor/512x512/apps"
        mkdir -p "$TMP_LAB/squashfs-root/etc/xdg"
        mkdir -p "$TMP_LAB/squashfs-root/home/contestant"

        install -m 0755 "$TG_UNPACK/Telegram/Telegram" "$TMP_LAB/squashfs-root/opt/telegram/Telegram"
        if [ -f "$TG_UNPACK/Telegram/Updater" ]; then
            install -m 0755 "$TG_UNPACK/Telegram/Updater" "$TMP_LAB/squashfs-root/opt/telegram/Updater"
        fi

        ln -sf /opt/telegram/Telegram "$TMP_LAB/squashfs-root/usr/bin/telegram-desktop"
        ln -sf /opt/telegram/Telegram "$TMP_LAB/squashfs-root/usr/local/bin/telegram-desktop"
        ln -sf /opt/telegram/Telegram "$TMP_LAB/squashfs-root/usr/local/bin/Telegram"

        if [ -f "$LOCAL_TG_ICON" ]; then
            cp -f "$LOCAL_TG_ICON" "$TMP_LAB/squashfs-root/usr/share/icons/hicolor/512x512/apps/telegram.png"
            cp -f "$LOCAL_TG_ICON" "$TMP_LAB/squashfs-root/usr/share/pixmaps/telegram.png"
            cp -f "$LOCAL_TG_ICON" "$TMP_LAB/squashfs-root/usr/share/pixmaps/org.telegram.desktop.png"
        fi

        cat << 'EOF' > "$TMP_LAB/squashfs-root/usr/share/applications/org.telegram.desktop.desktop"
[Desktop Entry]
Name=Telegram Desktop
Comment=Official desktop application for the Telegram messaging service
TryExec=telegram-desktop
Exec=telegram-desktop -- %u
Icon=telegram
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/tg;
Keywords=tg;chat;im;messaging;messenger;sms;tdesktop;
Actions=Quit;
EOF
        cp -f "$TMP_LAB/squashfs-root/usr/share/applications/org.telegram.desktop.desktop" \
            "$TMP_LAB/squashfs-root/usr/share/applications/telegramdesktop.desktop"

        # Register URL scheme handler for tg:// and t.me deep links
        touch "$TMP_LAB/squashfs-root/usr/share/applications/mimeinfo.cache"
        if ! grep -q "x-scheme-handler/tg=" "$TMP_LAB/squashfs-root/usr/share/applications/mimeinfo.cache"; then
            echo "x-scheme-handler/tg=org.telegram.desktop.desktop;telegramdesktop.desktop;" >> "$TMP_LAB/squashfs-root/usr/share/applications/mimeinfo.cache"
        fi

        cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/xdg/mimeapps.list"
[Default Applications]
x-scheme-handler/tg=org.telegram.desktop.desktop

[Added Associations]
x-scheme-handler/tg=org.telegram.desktop.desktop;
EOF

        # Keep offline copy in /opt/telegram and /home/contestant/
        cp -f "$LOCAL_TG_TAR" "$TMP_LAB/squashfs-root/opt/telegram/tsetup.tar.xz"
        cp -f "$LOCAL_TG_TAR" "$TMP_LAB/squashfs-root/home/contestant/tsetup.tar.xz"

        # Build standalone .hsm module for internet/telegram
        if [ -d "$SOFTWARE_INTERNET_DIR" ]; then
            TG_ROOT="$TMP_LAB/root_telegram"
            mkdir -p "$TG_ROOT/opt/telegram"
            mkdir -p "$TG_ROOT/usr/bin"
            mkdir -p "$TG_ROOT/usr/share/applications"
            mkdir -p "$TG_ROOT/usr/share/pixmaps"
            mkdir -p "$TG_ROOT/usr/share/icons/hicolor/512x512/apps"

            install -m 0755 "$TG_UNPACK/Telegram/Telegram" "$TG_ROOT/opt/telegram/Telegram"
            if [ -f "$TG_UNPACK/Telegram/Updater" ]; then
                install -m 0755 "$TG_UNPACK/Telegram/Updater" "$TG_ROOT/opt/telegram/Updater"
            fi
            ln -sf /opt/telegram/Telegram "$TG_ROOT/usr/bin/telegram-desktop"
            cp -f "$TMP_LAB/squashfs-root/usr/share/applications/org.telegram.desktop.desktop" "$TG_ROOT/usr/share/applications/"
            cp -f "$TMP_LAB/squashfs-root/usr/share/applications/telegramdesktop.desktop" "$TG_ROOT/usr/share/applications/"
            if [ -f "$LOCAL_TG_ICON" ]; then
                cp -f "$LOCAL_TG_ICON" "$TG_ROOT/usr/share/icons/hicolor/512x512/apps/telegram.png"
                cp -f "$LOCAL_TG_ICON" "$TG_ROOT/usr/share/pixmaps/telegram.png"
            fi

            TG_HSM_FILE="$SOFTWARE_INTERNET_DIR/telegram.hsm"
            echo "  Building standalone module: $TG_HSM_FILE"
            TMP_TG_HSM="$TMP_LAB/telegram.hsm"
            rm -f "$TMP_TG_HSM"
            NPROCS=$(nproc 2>/dev/null || echo 4)
            mksquashfs "$TG_ROOT" "$TMP_TG_HSM" -comp xz -b 256K -processors "$NPROCS" -always-use-fragments -noappend >/dev/null
            cp -f "$TMP_TG_HSM" "$TG_HSM_FILE"
            GENERATED_HSMS+=("internet/telegram.hsm")
        fi
        echo "✓ Injected Telegram Desktop"
    fi
fi

# =============================================================================
# VS Code Extensions Injection & Packaging
# =============================================================================
mkdir -p "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/ids"
mkdir -p "$TMP_LAB/squashfs-root/opt/codium/vsix"
mkdir -p "$TMP_LAB/squashfs-root/home/contestant/vsix"
mkdir -p "$TMP_LAB/squashfs-root/usr/local/bin"
mkdir -p "$TMP_LAB/squashfs-root/etc/hmm"
mkdir -p "$TMP_LAB/squashfs-root/etc/hsync"

# Extract base ISO vsc-cpptools if present in software directory
if [ -d "$SOFTWARE_PROG_DIR" ] && [ -f "$SOFTWARE_PROG_DIR/vsc-cpptools.hsm" ]; then
    echo "Pre-extracting base C/C++ Tools extension into 05-custom.hsl..."
    CPP_UNPACK="$TMP_LAB/unpack_base_cpptools"
    mkdir -p "$CPP_UNPACK"
    unsquashfs -d "$CPP_UNPACK" -f "$SOFTWARE_PROG_DIR/vsc-cpptools.hsm" >/dev/null 2>&1 || true
    if [ -d "$CPP_UNPACK/opt/codium/contestant/extensions" ]; then
        cp -rf "$CPP_UNPACK/opt/codium/contestant/extensions/"* "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/" 2>/dev/null || true
    fi
fi

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
        # Copy raw VSIX package for offline installation
        VSIX_BASENAME="$(basename "$LOCAL_VSIX")"
        cp -f "$LOCAL_VSIX" "$TMP_LAB/squashfs-root/opt/codium/vsix/$VSIX_BASENAME"
        cp -f "$LOCAL_VSIX" "$TMP_LAB/squashfs-root/home/contestant/vsix/$VSIX_BASENAME"

        UNPACK_DIR="$TMP_LAB/unpack_$MOD_ID"
        mkdir -p "$UNPACK_DIR"
        unzip -q "$LOCAL_VSIX" -d "$UNPACK_DIR"

        PKG_JSON="$UNPACK_DIR/extension/package.json"
        RAW_VERSION=$(grep -o '"version": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "1.0.0")
        RAW_PUBLISHER=$(grep -o '"publisher": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "custom")
        RAW_NAME=$(grep -o '"name": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "$DEFAULT_EXT_NAME")

        [ -z "$RAW_VERSION" ] && RAW_VERSION="1.0.0"
        [ -z "$RAW_PUBLISHER" ] && RAW_PUBLISHER="custom"
        [ -z "$RAW_NAME" ] && RAW_NAME="$DEFAULT_EXT_NAME"

        EXT_VERSION="$RAW_VERSION"
        EXT_PUBLISHER=$(echo "$RAW_PUBLISHER" | tr '[:upper:]' '[:lower:]')
        EXT_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]')

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

        # hsync mounts this .hsm above 05-custom.hsl.  The Codium wrapper
        # rewrites extensions.json at startup, therefore the directory inside
        # each dynamic module must also be writable by contestant (UID 1000).
        chmod -R 777 "$EXT_ROOT/opt/codium/contestant/extensions"

        # Inject into 05-custom.hsl tree
        mkdir -p "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/$EXT_DIR_NAME"
        cp -rf "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"* "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
        cp -f "$EXT_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json" "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/ids/${MOD_ID}.json"

        # Build standalone .hsm module
        if [ -d "$SOFTWARE_PROG_DIR" ]; then
            HSM_FILE="$SOFTWARE_PROG_DIR/${MOD_ID}.hsm"
            echo "  Building standalone module: $HSM_FILE"
            TMP_HSM="$TMP_LAB/${MOD_ID}.hsm"
            rm -f "$TMP_HSM"
            NPROCS=$(nproc 2>/dev/null || echo 4)
            mksquashfs "$EXT_ROOT" "$TMP_HSM" -comp xz -b 256K -processors "$NPROCS" -always-use-fragments -noappend >/dev/null
            cp -f "$TMP_HSM" "$HSM_FILE"
            GENERATED_HSMS+=("programming/${MOD_ID}.hsm")
        fi
    fi
done

# Pre-compile extensions.json in custom layer
echo "Compiling extensions.json registry for VSCodium..."
EXT_JSON_FILE="$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/extensions.json"
echo -n "[" > "$EXT_JSON_FILE"
FIRST_ENTRY=true
for id_file in "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions/ids/"*.json; do
    if [ -f "$id_file" ]; then
        if [ "$FIRST_ENTRY" = true ]; then
            FIRST_ENTRY=false
        else
            echo -n "," >> "$EXT_JSON_FILE"
        fi
        tr -d '\n' < "$id_file" >> "$EXT_JSON_FILE"
    fi
done
echo "]" >> "$EXT_JSON_FILE"

# Provide offline VSIX installation helper script
cat << 'EOF' > "$TMP_LAB/squashfs-root/usr/local/bin/install-vsix-extensions"
#!/bin/bash
# install-vsix-extensions — Install/reinstall all offline VSIX packages into Codium
set -e

EXT_DIR="/opt/codium/contestant/extensions"
mkdir -p "$EXT_DIR" 2>/dev/null || true
echo "Installing offline VSIX extensions into $EXT_DIR..."
for vsix in /opt/codium/vsix/*.vsix /home/contestant/vsix/*.vsix; do
    if [ -f "$vsix" ]; then
        echo "  -> Installing $(basename "$vsix")..."
        /usr/share/codium/bin/codium --extensions-dir "$EXT_DIR" --install-extension "$vsix"
    fi
done
echo "✓ All offline VSIX extensions processed."
EOF
chmod 755 "$TMP_LAB/squashfs-root/usr/local/bin/install-vsix-extensions"

# Register extensions and modules in huronOS module lists
if [ ! -f "$TMP_LAB/squashfs-root/etc/hmm/any" ]; then
    cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/hmm/any"
HURONDIR=/run/initramfs/memory/system/huronOS/software/
debuggers/ddd                               false
debuggers/gdb                               false
debuggers/valgrind                          false
debuggers/visualvm                          false
internet/chromium                           false
internet/crow                               false
internet/firefox                            false
internet/telegram                           false
langs/dotnet                                false
langs/g++                                   false
langs/gcc                                   false
langs/javac                                 false
langs/kotlinc                               false
langs/mono                                  false
langs/pypy3                                 false
langs/python3                               false
langs/ruby                                  false
tools/byobu                                 false
tools/konsole                               false
tools/midnight-commander                    false
programming/atom                            false
programming/clion                           false
programming/codeblocks                      false
programming/eclipse                         false
programming/emacs                           false
programming/geany                           false
programming/gedit                           false
programming/gvim                            false
programming/intellij                        false
programming/joe                             false
programming/kate                            false
programming/kdevelop                        false
programming/neovim                          false
programming/pycharm                         false
programming/rider                           false
programming/sublime                         false
programming/vim                             false
programming/vscode                          false
programming/vsc-clangd                      false
programming/vsc-cpp-compile-run             false
programming/vsc-cpptools                    false
programming/vsc-intellij-idea-keybindings   false
programming/vsc-vscodevim                   false
programming/vsc-cph                         false
programming/vsc-python                      false
programming/vsc-java                        false
EOF
else
    for mod in "internet/telegram" "programming/vsc-cph" "programming/vsc-python" "programming/vsc-java"; do
        if ! grep -q "$mod" "$TMP_LAB/squashfs-root/etc/hmm/any"; then
            printf "%-43s false\n" "$mod" >> "$TMP_LAB/squashfs-root/etc/hmm/any"
        fi
    done
fi

if [ ! -f "$TMP_LAB/squashfs-root/etc/hsync/all_software" ]; then
    cat << 'EOF' > "$TMP_LAB/squashfs-root/etc/hsync/all_software"
debuggers/ddd
debuggers/gdb
debuggers/valgrind
debuggers/visualvm
internet/chromium
internet/crow
internet/firefox
internet/telegram
langs/dotnet
langs/g++
langs/gcc
langs/javac
langs/kotlinc
langs/mono
langs/pypy3
langs/python3
langs/ruby
tools/byobu
tools/konsole
tools/midnight-commander
programming/atom
programming/clion
programming/codeblocks
programming/eclipse
programming/emacs
programming/geany
programming/gedit
programming/gvim
programming/intellij
programming/joe
programming/kate
programming/kdevelop
programming/neovim
programming/pycharm
programming/rider
programming/sublime
programming/vim
programming/vscode
programming/vsc-clangd
programming/vsc-cpp-compile-run
programming/vsc-cpptools
programming/vsc-intellij-idea-keybindings
programming/vsc-vscodevim
programming/vsc-cph
programming/vsc-python
programming/vsc-java
EOF
else
    for mod in "internet/telegram" "programming/vsc-cph" "programming/vsc-python" "programming/vsc-java"; do
        if ! grep -q "$mod" "$TMP_LAB/squashfs-root/etc/hsync/all_software"; then
            echo "$mod" >> "$TMP_LAB/squashfs-root/etc/hsync/all_software"
        fi
    done
fi

# Ensure permissive access for contestant user
chmod -R 777 "$TMP_LAB/squashfs-root/opt/codium/contestant/extensions" 2>/dev/null || true
chmod -R 755 "$TMP_LAB/squashfs-root/opt/codium/vsix" 2>/dev/null || true
chmod -R 777 "$TMP_LAB/squashfs-root/home/contestant/vsix" 2>/dev/null || true

echo "Building updated 05-custom.hsl squashfs layer..."
rm -f "$TMP_LAB/05-custom.hsl"
NPROCS=$(nproc 2>/dev/null || echo 4)
mksquashfs "$TMP_LAB/squashfs-root" "$TMP_LAB/05-custom.hsl" -comp xz -b 1024K -processors "$NPROCS" -always-use-fragments -noappend >/dev/null

cp -f "$TMP_LAB/05-custom.hsl" "$CUSTOM_HSL"
rm -rf "$TMP_LAB"
echo "✓ Updated $CUSTOM_HSL (with wallpaper, graphics fix, Noto Color Emoji/DejaVu/Inter fonts, Telegram Desktop, and full VS Code extensions suite)"

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

if [ -n "$HDF_SRC" ] && [ -f "$HDF_SRC" ]; then
    cp -f "$HDF_SRC" "$DATA_BACKUPS_DIR/directives"
    CONF_DIR="$TARGET_DIR/huronOS/data/configs"
    [ ! -d "$CONF_DIR" ] && CONF_DIR="$TARGET_DIR/data/configs"
    if [ -d "$CONF_DIR" ]; then
        if [ ! -f "$CONF_DIR/sync-server.conf" ] || ! grep -q "DIRECTIVES_FILE_URL=" "$CONF_DIR/sync-server.conf"; then
            cat <<EOF > "$CONF_DIR/sync-server.conf"
[Server]
INSTANCE_IP_ADDRESS=
INSTANCE_IP_MASK=
INSTANCE_IP_GATEWAY=
DIRECTIVES_ENDPOINT=
SERVER_ROOM=
DIRECTIVES_FILE_URL=http://192.168.122.1:8000/$(basename "$HDF_SRC")
DIRECTIVES_SERVER_IP=192.168.122.1
EOF
        fi
    fi
    echo "✓ Pre-seeded directives in huronOS/data/backups/directives"
fi

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
        HSM_BASENAME="$(basename "$hsm")"
        HSM_PATH=""
        for candidate in \
            "huronOS/software/programming/$HSM_BASENAME" \
            "software/programming/$HSM_BASENAME" \
            "huronOS/software/internet/$HSM_BASENAME" \
            "software/internet/$HSM_BASENAME" \
            "huronOS/software/$hsm" \
            "software/$hsm"; do
            if [ -f "$candidate" ]; then
                HSM_PATH="$candidate"
                break
            fi
        done
        if [ -n "$HSM_PATH" ] && [ -f "$HSM_PATH" ]; then
            NEW_HSM_CHECKSUM=$(sha256sum "$HSM_PATH")
            if grep -q "$HSM_BASENAME" "$CHECKSUMS_FILE"; then
                sed -i "s|.*$HSM_BASENAME.*|$NEW_HSM_CHECKSUM|" "$CHECKSUMS_FILE"
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
echo " Fonts: Noto Color Emoji, DejaVu Unicode & Inter UI ready"
echo " Telegram Desktop: App & Module ready"
echo " VS Code Extensions: C/C++, CPH, Python & Java ready"
echo "============================================="
