#!/bin/env bash
# =============================================================================
# huronOS Installation Script — CPC GALLOS / UAA
# Configures and installs huronOS onto a USB drive for ICPC contests.
# Contest-specific settings are defined in the .hdf directives file.
# =============================================================================
# Usage: Run this script in your terminal:
#   bash install-huronos.sh
# =============================================================================

set -e

ISO_PATH="/home/ravary/Desktop/website/huronOS-alpha-0.4-amd64.iso"
MOUNT_POINT="/media/iso"

echo "============================================="
echo " huronOS Installer — CPC GALLOS / UAA"
echo "============================================="
echo ""

# --- Step 1: Install dependencies ---
echo "[Step 1/7] Installing dependencies..."
sudo dnf install -y squashfs-tools parted psmisc e2fsprogs dosfstools perl
echo "✓ Dependencies installed."
echo ""

# --- Step 2: Mask automounter ---
echo "[Step 2/7] Masking udisks2 automounter..."
sudo systemctl mask udisks2
echo "✓ udisks2 masked (automount disabled)."
echo ""

# --- Step 3: Mount the ISO ---
echo "[Step 3/7] Mounting ISO..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT" 2>/dev/null || echo "(ISO already mounted, continuing...)"
echo ""

# Verify contents
echo "ISO contents:"
ls "$MOUNT_POINT"
echo ""

# --- Step 4: Directives reminder ---
echo "============================================="
echo " DIRECTIVES FILE REMINDER"
echo "============================================="
echo "Your directives file is at:"
echo "  /home/ravary/Desktop/website/icpc-gpm-2026-3rd-date.hdf"
echo ""
echo "You need to host it somewhere accessible via HTTP/HTTPS."
echo "Quickest: Use a GitHub Gist or Raw GitHub URL, and copy the Raw URL."
echo ""
echo "If you don't have a URL yet, leave the directives URL blank during"
echo "installation — you can configure it later in:"
echo "  HURONOS/data/configs/sync-server.conf"
echo "============================================="
echo ""
read -r -p "Press Enter to continue to installation..."
echo ""

# --- Step 5: Run the installer ---
echo "[Step 5/7] Running huronOS installer..."
echo ""
echo "⚠  WARNING: The installer will ask you to select a target disk."
echo "⚠  Your USB is /dev/sdb (58GB). ALL DATA WILL BE ERASED."
echo "⚠  Double-check before confirming!"
echo ""
cd "$MOUNT_POINT"
sudo ./install.sh
echo ""
echo "✓ Installer finished."
echo ""

# --- Step 6: CRITICAL — Manual sync ---
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

# --- Step 7: Cleanup ---
echo "[Step 7/7] Cleaning up..."
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
echo ""
echo "Judge:   https://boca.icpcmexico.org"
echo ""
echo "Check your .hdf directives file for contest-specific times and settings."
echo ""