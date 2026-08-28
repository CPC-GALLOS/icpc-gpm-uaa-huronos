#!/usr/bin/env bash
# =============================================================================
# 01-install-huronos.sh — CPC GALLOS / UAA
# Configures and installs huronOS onto a USB drive for ICPC contests.
# Supports both interactive prompts and fully automated non-interactive CLI arguments.
# =============================================================================
# Usage:
#   # Non-interactive quick install (positional):
#   bash 01-install-huronos.sh /dev/sdb
#   bash 01-install-huronos.sh /dev/sdb [directives.hdf] [root_password] [directives_url] [server_ip] [wallpaper.png]
#
#   # Named flags:
#   bash 01-install-huronos.sh -d /dev/sdb -c icpc-gpm-2026-3rd-date.hdf -p <password> -u "https://..." -y
#
#   # Interactive mode:
#   bash 01-install-huronos.sh
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ISO_NAME="huronOS-alpha-0.4-amd64.iso"
ISO_PATH="$SCRIPT_DIR/${ISO_NAME}"
MOUNT_POINT="/media/iso"

# Default configuration values
TARGET_DEVICE=""
HDF_INPUT=""
ROOT_PASSWORD=""
DIRECTIVES_URL=""
SERVER_IP=""
WALLPAPER_FILE=""
NON_INTERACTIVE=false

# Print usage help
show_help() {
    cat << 'EOF'
huronOS USB Installer — CPC GALLOS / UAA

Usage:
  bash 01-install-huronos.sh [TARGET_DEV] [HDF_FILE] [PASSWORD] [DIRECTIVES_URL] [SERVER_IP] [WALLPAPER]
  bash 01-install-huronos.sh [OPTIONS]

Options:
  -d, --device <dev>        Target block device (e.g. /dev/sdb)
  -c, --config, --hdf <file> Directives .hdf file (default: icpc-gpm-2026-3rd-date.hdf)
  -p, --password <pass>     Root user password (prompted if not provided)
  -u, --url <url>           Directives download URL (default: Raw GitHub repo URL)
  -s, --server-ip <ip>      Directives sync server IP (optional)
  -w, --wallpaper <img.png> Custom wallpaper image (default: huronos-wallpaper.png)
  -y, --yes, --force        Non-interactive mode (auto-confirm device erase)
  -h, --help                Show this help message

Examples:
  bash 01-install-huronos.sh /dev/sdb
  bash 01-install-huronos.sh -d /dev/sdb -c icpc-gpm-2026-3rd-date.hdf -p <password> -y
EOF
    exit 0
}

# Parse CLI arguments (flags or positional)
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -d|--device|--target)
            TARGET_DEVICE="$2"
            NON_INTERACTIVE=true
            shift 2
            ;;
        -c|--config|--hdf)
            HDF_INPUT="$2"
            shift 2
            ;;
        -p|--password)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        -u|--url)
            DIRECTIVES_URL="$2"
            shift 2
            ;;
        -s|--server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        -w|--wallpaper)
            WALLPAPER_FILE="$2"
            shift 2
            ;;
        -y|--yes|-f|--force|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        -*)
            echo "❌ Error: Unknown option '$1'"
            echo "Run 'bash $0 --help' for usage."
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Handle positional arguments if flags were not used
if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
    if [[ "${POSITIONAL_ARGS[0]}" == /dev/* ]]; then
        TARGET_DEVICE="${POSITIONAL_ARGS[0]}"
        NON_INTERACTIVE=true
        [ ${#POSITIONAL_ARGS[@]} -gt 1 ] && HDF_INPUT="${POSITIONAL_ARGS[1]}"
        [ ${#POSITIONAL_ARGS[@]} -gt 2 ] && ROOT_PASSWORD="${POSITIONAL_ARGS[2]}"
        [ ${#POSITIONAL_ARGS[@]} -gt 3 ] && DIRECTIVES_URL="${POSITIONAL_ARGS[3]}"
        [ ${#POSITIONAL_ARGS[@]} -gt 4 ] && SERVER_IP="${POSITIONAL_ARGS[4]}"
        [ ${#POSITIONAL_ARGS[@]} -gt 5 ] && WALLPAPER_FILE="${POSITIONAL_ARGS[5]}"
    elif [[ "${POSITIONAL_ARGS[0]}" == *.hdf ]]; then
        HDF_INPUT="${POSITIONAL_ARGS[0]}"
        [ ${#POSITIONAL_ARGS[@]} -gt 1 ] && WALLPAPER_FILE="${POSITIONAL_ARGS[1]}"
    fi
fi

# Locate ISO
if [ ! -f "$ISO_PATH" ]; then
    ISO_CANDIDATE=$(find "$SCRIPT_DIR" "$HOME/Downloads" "$HOME/VM" -maxdepth 2 -name "huronOS*.iso" 2>/dev/null | head -n 1 || true)
    if [ -n "$ISO_CANDIDATE" ] && [ -f "$ISO_CANDIDATE" ]; then
        ISO_PATH="$ISO_CANDIDATE"
    else
        echo "❌ Error: huronOS ISO not found in $SCRIPT_DIR, $HOME/Downloads/, or $HOME/VM/"
        exit 1
    fi
fi

# Locate directives file
HDF_FILE=""
if [ -n "$HDF_INPUT" ] && [ -f "$HDF_INPUT" ]; then
    HDF_FILE="$(realpath "$HDF_INPUT")"
elif [ -f "$SCRIPT_DIR/icpc-gpm-2026-3rd-date.hdf" ]; then
    HDF_FILE="$SCRIPT_DIR/icpc-gpm-2026-3rd-date.hdf"
else
    HDF_LIST=()
    while IFS= read -r -d $'\0' file; do
        HDF_LIST+=("$file")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.hdf" -print0 | sort -z)

    if [ ${#HDF_LIST[@]} -eq 1 ]; then
        HDF_FILE="${HDF_LIST[0]}"
    elif [ ${#HDF_LIST[@]} -gt 1 ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            HDF_FILE="${HDF_LIST[0]}"
        else
            echo "Multiple directives files found:"
            for i in "${!HDF_LIST[@]}"; do
                echo "  [$((i+1))] $(basename "${HDF_LIST[$i]}")"
            done
            read -r -p "Select directives configuration (1-${#HDF_LIST[@]}, default 1): " HDF_CHOICE
            if [[ "$HDF_CHOICE" =~ ^[0-9]+$ ]] && [ "$HDF_CHOICE" -ge 1 ] && [ "$HDF_CHOICE" -le "${#HDF_LIST[@]}" ]; then
                HDF_FILE="${HDF_LIST[$((HDF_CHOICE-1))]}"
            else
                HDF_FILE="${HDF_LIST[0]}"
            fi
        fi
    fi
fi

# Default Directives URL if unset
if [ -z "$DIRECTIVES_URL" ] && [ -n "$HDF_FILE" ]; then
    HDF_BASENAME="$(basename "$HDF_FILE")"
    DIRECTIVES_URL="https://raw.githubusercontent.com/CPC-GALLOS/icpc-gpm-uaa-huronos/main/$HDF_BASENAME"
fi

# Custom wallpaper source
if [ -z "$WALLPAPER_FILE" ] || [ ! -f "$WALLPAPER_FILE" ]; then
    if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/huronos-wallpaper.png"
    elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/wallpaper.png"
    else
        WALLPAPER_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
    fi
fi

# Resolve root password: prompt interactively if not provided via -p
if [ -z "$ROOT_PASSWORD" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        # Non-interactive fallback: use the huronOS factory default (documented in the ISO)
        ROOT_PASSWORD="toor"
        echo "⚠️  No --password provided; using the huronOS factory default."
        echo "   Run with -p <password> to set a custom root password."
    else
        read -r -s -p "Root password for huronOS (leave blank for factory default): " ROOT_PASSWORD
        echo ""
        [ -z "$ROOT_PASSWORD" ] && ROOT_PASSWORD="toor"
    fi
fi

echo "============================================="
echo " huronOS Installer — CPC GALLOS / UAA"
echo "============================================="
echo "ISO Image:        $ISO_PATH"
[ -n "$TARGET_DEVICE" ] && echo "Target USB:       $TARGET_DEVICE"
echo "Directives File:  ${HDF_FILE:-None selected} ($(basename "${HDF_FILE:-none}"))"
echo "Directives URL:   ${DIRECTIVES_URL:-None}"
echo "Root Password:    (set)"
if [ -n "$SERVER_IP" ]; then
    echo "Sync Server IP:   $SERVER_IP"
fi
if [ -n "$WALLPAPER_FILE" ] && [ -f "$WALLPAPER_FILE" ]; then
    echo "Custom Wallpaper: $WALLPAPER_FILE"
fi
echo "============================================="
echo ""

# Safety check for host operating system disks
if [ -n "$TARGET_DEVICE" ]; then
    if [ ! -b "$TARGET_DEVICE" ]; then
        echo "❌ Error: Specified target '$TARGET_DEVICE' is not a valid block device."
        exit 1
    fi
    ROOT_MNT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    ROOT_PARENT=$(lsblk -no PKNAME "$ROOT_MNT_DEV" 2>/dev/null || true)
    if [ -n "$ROOT_PARENT" ] && [ "$TARGET_DEVICE" = "/dev/$ROOT_PARENT" ]; then
        echo "❌ CRITICAL SAFETY ERROR: '$TARGET_DEVICE' contains the host OS root filesystem (/)."
        echo "   Refusing to erase system drive."
        exit 1
    fi
fi

# --- Step 1: Check & install dependencies ---
echo "[Step 1/9] Checking dependencies..."
MISSING_TOOLS=()
for cmd in mksquashfs unsquashfs parted fuser mkfs.vfat mkfs.ext4 perl wipefs; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_TOOLS+=("$cmd")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️ Missing tools: ${MISSING_TOOLS[*]}"
    echo "Installing dependencies..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y squashfs-tools parted psmisc e2fsprogs dosfstools perl
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y squashfs-tools parted psmisc e2fsprogs dosfstools perl-base
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --needed squashfs-tools parted psmisc e2fsprogs dosfstools perl
    else
        echo "❌ Error: Could not detect package manager (dnf/apt/pacman)."
        echo "   Please install the following tools manually: ${MISSING_TOOLS[*]}"
        exit 1
    fi
    echo "✓ Dependencies installed."
else
    echo "✓ All required dependencies are already installed."
fi
echo ""

# --- Step 2: Mask automounter ---
echo "[Step 2/9] Masking udisks2 automounter..."
sudo systemctl mask udisks2 >/dev/null 2>&1 || true
echo "✓ udisks2 masked (automount disabled)."
echo ""

# --- Step 3: Mount the ISO ---
echo "[Step 3/9] Mounting ISO..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT" 2>/dev/null || echo "(ISO already mounted, continuing...)"
echo ""

# --- Step 4: Prepare installer runner script ---
INSTALL_TMP="/tmp/huronos-install-run-$$.sh"
cp -f "$MOUNT_POINT/install.sh" "$INSTALL_TMP"
chmod +x "$INSTALL_TMP"

# Patch ISO_DIR to absolute mount point
sed -i "s|ISO_DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\"|ISO_DIR=\"$MOUNT_POINT\"|" "$INSTALL_TMP"

# If target device is explicitly provided, bypass interactive disk selection and prompt
if [ -n "$TARGET_DEVICE" ]; then
    # Inject exact target assignment and skip interactive prompts
    sed -i "s|if \[ \"\$DEV_HOTPLUG\" = \"1\" \] && \[ \"\$DEV_TYPE\" = \"disk\" \]; then|if [ \"\$DEV_PATH\" = \"$TARGET_DEVICE\" ]; then|" "$INSTALL_TMP"
    # Auto-confirm selection
    sed -i 's|read -r -p "Please, select the disk where you want to install huronOS on: " SELECTION|SELECTION=0|g' "$INSTALL_TMP"
    sed -i 's|read -r -p "The selected disk is.*do you want to continue? (Y/n) " CONFIRM|CONFIRM=Y|g' "$INSTALL_TMP"
fi

# In non-interactive mode, the sync server IP is genuinely optional (it's only
# used to open a firewall exception for a local directives-sync server). Its
# own [ -z "$DIRECTIVES_SERVER_IP" ] guard means there's no value we can pass
# to make it skip its prompt when left blank on purpose, so bypass the read
# outright and let it stay whatever was set via --server-ip (empty by default).
if [ "$NON_INTERACTIVE" = true ]; then
    sed -i 's|read -r -p "IP of the sync server:" DIRECTIVES_SERVER_IP|: # non-interactive: DIRECTIVES_SERVER_IP left as-is|' "$INSTALL_TMP"
fi

# Export configuration variables for the installer
export NEW_PASSWORD="$ROOT_PASSWORD"
export DIRECTIVES_FILE_URL="$DIRECTIVES_URL"
export DIRECTIVES_SERVER_IP="$SERVER_IP"

# install.sh's own arg parser unconditionally resets NEW_PASSWORD="" before
# ever looking at the environment, so the export above is silently clobbered
# and it falls back to an interactive prompt. It only honors the password
# (and directives URL/IP) via explicit CLI flags, so pass those too.
INSTALL_ARGS=(--root-password "$ROOT_PASSWORD")
[ -n "$DIRECTIVES_URL" ] && INSTALL_ARGS+=(--directives-url "$DIRECTIVES_URL")
[ -n "$SERVER_IP" ] && INSTALL_ARGS+=(--directives-server-ip "$SERVER_IP")

# --- Step 5: Run the installer ---
echo "[Step 5/9] Running huronOS installer..."
cd "$MOUNT_POINT"
sudo -E bash "$INSTALL_TMP" "${INSTALL_ARGS[@]}"
cd "$SCRIPT_DIR"
rm -f "$INSTALL_TMP"
echo ""
echo "✓ Base installer finished."
echo ""

# Determine target partition for layer injection
INJECT_TARGET=""
if [ -n "$TARGET_DEVICE" ]; then
    INJECT_TARGET="${TARGET_DEVICE}1"
fi

# --- Step 6: Inject custom wallpaper, fonts, Telegram, and VS Code extensions ---
echo "[Step 6/9] Injecting custom wallpaper, Noto Color Emoji fonts, Telegram Desktop, and VS Code extensions..."
sudo bash "$SCRIPT_DIR/02-inject-custom-layer.sh" "$INJECT_TARGET" "$WALLPAPER_FILE" "$HDF_FILE" || {
    echo "⚠️ Warning: Custom layer injection encountered an issue, continuing..."
}
echo ""

# --- Step 7: Configure NVIDIA Bootloader compatibility ---
echo "[Step 7/9] Configuring NVIDIA Safe Graphics / UEFI boot options..."
sudo bash "$SCRIPT_DIR/03-configure-nvidia-boot.sh" "$INJECT_TARGET" || {
    echo "⚠️ Warning: NVIDIA boot configuration encountered an issue, continuing..."
}
echo ""

# --- Step 8: CRITICAL — Manual sync ---
echo "============================================="
echo " ⚠  CRITICAL: Syncing disk buffers..."
echo " Due to a known extlinux bug, we MUST sync"
echo " manually before unplugging the USB."
echo "============================================="
sync
echo "First sync done. Waiting 5 seconds..."
sleep 5
sync
echo "Second sync done. Waiting 5 more seconds..."
sleep 5
echo "✓ Disk buffers flushed. Safe to unplug in a moment."
echo ""

# --- Step 9: Cleanup ---
echo "[Step 9/9] Cleaning up..."
cd /
sudo umount "$MOUNT_POINT" 2>/dev/null || true
sudo systemctl unmask udisks2 >/dev/null 2>&1 || true
sudo systemctl start udisks2 >/dev/null 2>&1 || true
echo "✓ Cleanup complete."
echo ""

echo "============================================="
echo " ✓ huronOS INSTALLATION COMPLETE"
echo "============================================="
echo "Target Device:  ${TARGET_DEVICE:-Auto-detected USB}"
echo "Directives:     ${HDF_FILE:-Default}"
echo "Directives URL: $DIRECTIVES_URL"
echo "Root Password:  (set)"
echo "Emojis/Fonts:   Noto Color Emoji & DejaVu installed"
echo "Telegram:       Installed & registered (active in Always & Event modes)"
echo "Extensions:     CPH, C++, Python & Java installed"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Wait 10 seconds, then unplug the USB"
echo "  2. Plug into competition machine"
echo "  3. Enter BIOS boot menu (F12/F2/Del)"
echo "  4. Disable Secure Boot if UEFI"
echo "  5. Boot from USB"
echo "  6. huronOS auto-boots to contestant desktop"
echo ""