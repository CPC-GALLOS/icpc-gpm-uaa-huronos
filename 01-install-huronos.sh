#!/usr/bin/env bash
# =============================================================================
# 01-install-huronos.sh — CPC GALLOS / UAA
# Configures and installs huronOS onto a USB drive for ICPC contests.
# Contest-specific settings are defined in the .hdf directives file.
# =============================================================================
# Usage: Run this script in your terminal:
#   bash 01-install-huronos.sh
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ISO_NAME="huronOS-alpha-0.4-amd64.iso"
ISO_PATH="$SCRIPT_DIR/${ISO_NAME}"
MOUNT_POINT="/media/iso"
WALLPAPER_FILE="$SCRIPT_DIR/wallpaper.png"

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

# Locate directives file (generic: CLI arg, auto-discovery, or interactive menu)
HDF_INPUT="$1"
HDF_FILE=""

if [ -n "$HDF_INPUT" ] && [ -f "$HDF_INPUT" ]; then
    HDF_FILE="$(realpath "$HDF_INPUT")"
else
    HDF_LIST=()
    while IFS= read -r -d $'\0' file; do
        HDF_LIST+=("$file")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.hdf" -print0)

    if [ ${#HDF_LIST[@]} -eq 1 ]; then
        HDF_FILE="${HDF_LIST[0]}"
    elif [ ${#HDF_LIST[@]} -gt 1 ]; then
        echo "Multiple directives files found:"
        for i in "${!HDF_LIST[@]}"; do
            echo "  [$((i+1))] $(basename "${HDF_LIST[$i]}")"
        done
        read -r -p "Select directives configuration (1-${#HDF_LIST[@]}): " HDF_CHOICE
        if [[ "$HDF_CHOICE" =~ ^[0-9]+$ ]] && [ "$HDF_CHOICE" -ge 1 ] && [ "$HDF_CHOICE" -le "${#HDF_LIST[@]}" ]; then
            HDF_FILE="${HDF_LIST[$((HDF_CHOICE-1))]}"
        else
            echo "Using default: ${HDF_LIST[0]}"
            HDF_FILE="${HDF_LIST[0]}"
        fi
    fi
fi

# Custom wallpaper source (optional)
WALLPAPER_FILE="${2}"
if [ -z "$WALLPAPER_FILE" ] || [ ! -f "$WALLPAPER_FILE" ]; then
    if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/huronos-wallpaper.png"
    elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/wallpaper.png"
    else
        WALLPAPER_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
    fi
fi

echo "============================================="
echo " huronOS Installer — CPC GALLOS / UAA"
echo "============================================="
echo "ISO Image:        $ISO_PATH"
if [ -n "$HDF_FILE" ]; then
    echo "Directives File:  $HDF_FILE ($(basename "$HDF_FILE"))"
else
    echo "Directives File:  None selected (will prompt during install)"
fi
if [ -f "$WALLPAPER_FILE" ]; then
    echo "Custom Wallpaper: $WALLPAPER_FILE ($(sha256sum "$WALLPAPER_FILE" | awk '{print $1}'))"
fi
echo ""

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
sudo systemctl mask udisks2
echo "✓ udisks2 masked (automount disabled)."
echo ""

# --- Step 3: Mount the ISO ---
echo "[Step 3/9] Mounting ISO..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT" 2>/dev/null || echo "(ISO already mounted, continuing...)"
echo ""

# Verify contents
echo "ISO contents:"
ls "$MOUNT_POINT"
echo ""

# --- Step 4: Directives reminder ---
echo "============================================="
echo " DIRECTIVES & WALLPAPER CONFIGURATION"
echo "============================================="
echo "Your directives file is at:"
echo "  $HDF_FILE"
echo ""
echo "You can host it via GitHub Gist or Raw GitHub URL."
echo "If you edit '$WALLPAPER_FILE', you can run './04-update-directives-wallpaper.sh'"
echo "to calculate the SHA256 and update your directives file automatically."
echo ""
echo "If you don't have a URL yet, leave the directives URL blank during"
echo "installation — you can configure it later in:"
echo "  HURONOS/data/configs/sync-server.conf"
echo "============================================="
echo ""
read -r -p "Press Enter to continue to installation..."
echo ""

# --- Step 5: Run the installer ---
echo "[Step 5/9] Running huronOS installer..."
echo ""
echo "⚠  WARNING: The installer will ask you to select a target disk."
echo "⚠  Double-check your USB device before confirming! ALL DATA WILL BE ERASED."
echo ""
cd "$MOUNT_POINT"
sudo ./install.sh
cd "$SCRIPT_DIR"
echo ""
echo "✓ Base installer finished."
echo ""

# --- Step 6: Inject custom wallpaper, graphics fallback, and VS Code extensions ---
echo "[Step 6/9] Injecting custom wallpaper, graphics fallback, and VS Code extensions..."
sudo bash "$SCRIPT_DIR/02-inject-custom-layer.sh" "" "$WALLPAPER_FILE" "$HDF_FILE" || {
    echo "⚠️ Warning: Custom layer injection encountered an issue, continuing..."
}
echo ""

# --- Step 7: Configure NVIDIA Bootloader compatibility ---
echo "[Step 7/9] Configuring NVIDIA Safe Graphics / nomodeset boot options..."
sudo bash "$SCRIPT_DIR/03-configure-nvidia-boot.sh" || {
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
sudo systemctl unmask udisks2
sudo systemctl start udisks2
echo "✓ Cleanup complete."
echo ""

echo "============================================="
echo " ✓ huronOS INSTALLATION COMPLETE"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Wait 10 seconds, then unplug the USB"
echo "  2. Plug into competition machine"
echo "  3. Enter BIOS boot menu (F12/F2/Del)"
echo "  4. Disable Secure Boot if UEFI"
echo "  5. Boot from USB"
echo "  6. huronOS auto-boots to contestant desktop"
echo "Judge (MOJ):  https://moj.naquadah.com.br"
echo "Ensaio:       https://ensaio-times-2026.moj.naquadah.com.br/"
echo "Guía:         https://moj.naquadah.com.br/contest/ajuda/competidor.html?lang=en"
echo ""
echo "Check your .hdf directives file for contest-specific times and settings."
echo ""