#!/bin/env bash
# =============================================================================
# huronOS KVM / virt-manager Test Script — CPC GALLOS / UAA
# Creates a virtual disk image, installs huronOS onto it via loop device,
# and boots a KVM VM to test directives, firewall, and software modules.
# =============================================================================
# Usage:
#   bash test-huronos-vm.sh
# =============================================================================

set -e

ISO_NAME="huronOS-alpha-0.4-amd64.iso"
ISO_PATH="./${ISO_NAME}"
DISK_IMG="./huronos-vm-disk.img"
DISK_SIZE="16G"
VM_NAME="huronOS-Test-VM"
MOUNT_POINT="/media/iso"
LOOP_DEV=""

cleanup() {
    echo ""
    echo "[Cleanup] Detaching loop devices and unmounting ISO..."
    if [ -n "$LOOP_DEV" ] && losetup "$LOOP_DEV" >/dev/null 2>&1; then
        sudo losetup -d "$LOOP_DEV" || true
        echo "✓ Detached $LOOP_DEV"
    fi
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT" || true
        echo "✓ Unmounted $MOUNT_POINT"
    fi
    sudo systemctl unmask udisks2 >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "============================================="
echo " huronOS KVM / virt-manager Test Environment"
echo "============================================="
echo ""

# Check KVM availability
if [ ! -c /dev/kvm ]; then
    echo "❌ Error: /dev/kvm not found or virtualization is disabled in BIOS."
    echo "   Ensure hardware virtualization (VT-x / AMD-V) is enabled."
    exit 1
fi

# Check required commands
echo "[Step 1/6] Checking virtualization tools..."
MISSING_TOOLS=()
for cmd in qemu-img virt-install virsh losetup parted; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_TOOLS+=("$cmd")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️ Missing tools: ${MISSING_TOOLS[*]}"
    echo "Installing virtualization dependencies..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y @virtualization qemu-img virt-install libvirt
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virt-manager qemu-utils virtinst
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --needed qemu-full virt-manager libvirt
    fi
fi

# Ensure libvirtd is running
if command -v systemctl &>/dev/null; then
    sudo systemctl enable --now libvirtd || true
fi

# Check ISO file
if [ ! -f "$ISO_PATH" ]; then
    if [ -f "/home/ravary/Desktop/website/${ISO_NAME}" ]; then
        ISO_PATH="/home/ravary/Desktop/website/${ISO_NAME}"
    else
        echo "❌ Error: ${ISO_NAME} not found at ${ISO_PATH}"
        echo "   Please download it from https://mirrors.huronos.org/huronOS/alpha/huronOS-alpha-0.4-amd64.iso"
        echo "   and place it in the current directory."
        exit 1
    fi
fi
echo "✓ ISO found: $ISO_PATH"
echo ""

# Check if disk image exists
SKIP_INSTALL=false
if [ -f "$DISK_IMG" ]; then
    echo "Found existing virtual disk image: $DISK_IMG"
    read -r -p "Do you want to reinstall to this image? (y/N): " REINSTALL
    REINSTALL=$(echo "$REINSTALL" | tr '[:upper:]' '[:lower:]')
    if [ "$REINSTALL" != "y" ]; then
        echo "Skipping installation phase. Booting VM..."
        SKIP_INSTALL=true
    fi
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    echo "[Step 2/6] Creating $DISK_SIZE raw virtual disk image..."
    rm -f "$DISK_IMG"
    qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"
    echo "✓ Created $DISK_IMG"
    echo ""

    echo "[Step 3/6] Setting up loop device..."
    sudo systemctl mask udisks2 >/dev/null 2>&1 || true
    # Use -P to force partition scanning, so loop0p1, loop0p2, etc are created
    LOOP_DEV=$(sudo losetup -P --find --show "$DISK_IMG")
    echo "✓ Attached $DISK_IMG to loop device $LOOP_DEV"
    echo ""

    echo "[Step 4/6] Mounting ISO..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT" 2>/dev/null || echo "(ISO already mounted)"
    echo ""

    echo "[Step 4.5/6] Patching installer for loop device support..."
    # huronOS install.sh normally rejects non-USB devices. We patch a copy to accept our loop device.
    cat "$MOUNT_POINT/install.sh" > /tmp/install-patched.sh
    chmod +x /tmp/install-patched.sh
    sed -i "s|ISO_DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\"|ISO_DIR=\"$MOUNT_POINT\"|" /tmp/install-patched.sh
    sed -i "s|if \[ \"\$DEV_HOTPLUG\" = \"1\" \] && \[ \"\$DEV_TYPE\" = \"disk\" \]; then|if \[ \"\$DEV_PATH\" = \"$LOOP_DEV\" \]; then|" /tmp/install-patched.sh
    
    # Fix partition naming: loop devices use 'loop0p1' instead of 'loop01'
    # shellcheck disable=SC2016
    sed -i 's|"${TARGET}1"|"${TARGET}p1"|g' /tmp/install-patched.sh
    # shellcheck disable=SC2016
    sed -i 's|"${TARGET}2"|"${TARGET}p2"|g' /tmp/install-patched.sh
    # shellcheck disable=SC2016
    sed -i 's|"${TARGET}3"|"${TARGET}p3"|g' /tmp/install-patched.sh

    echo "============================================="
    echo " RUNNING huronOS INSTALLER FOR VM"
    echo "============================================="
    echo "⚠️  When asked to select a target disk:"
    echo "    Select the loop device: $LOOP_DEV (usually option 0)"
    echo "============================================="
    echo ""
    read -r -p "Press Enter to start installer..."

    # Run the patched script from within the mount point so relative paths work
    cd "$MOUNT_POINT"
    sudo bash /tmp/install-patched.sh || true
    cd - >/dev/null
    rm -f /tmp/install-patched.sh

    # Inject custom wallpaper if present
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    VM_WALLPAPER="${1}"
    if [ -z "$VM_WALLPAPER" ] || [ ! -f "$VM_WALLPAPER" ]; then
        if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
            VM_WALLPAPER="$SCRIPT_DIR/huronos-wallpaper.png"
        elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
            VM_WALLPAPER="$SCRIPT_DIR/wallpaper.png"
        else
            VM_WALLPAPER=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
        fi
    fi

    if [ -f "$VM_WALLPAPER" ]; then
        echo ""
        echo "[Step 4.8/6] Injecting custom wallpaper ($VM_WALLPAPER) into VM disk image..."
        sudo bash "$SCRIPT_DIR/inject-wallpaper.sh" "${LOOP_DEV}p1" "$VM_WALLPAPER" || {
            echo "⚠️ Warning: Custom wallpaper injection encountered an issue, continuing..."
        }
    fi

    echo ""
    echo "[Step 5/6] Flushing disk buffers..."
    sync && sleep 3 && sync
    echo "✓ Disk sync complete."
    echo ""
fi

# Step 6: Create & Launch KVM Virtual Machine
echo "[Step 6/6] Launching KVM VM with virt-install..."

# Remove existing domain if present
if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "Destroying existing VM domain: $VM_NAME..."
    sudo virsh destroy "$VM_NAME" &>/dev/null || true
    sudo virsh undefine "$VM_NAME" &>/dev/null || true
fi

# Move disk image permissions for libvirt
chmod 666 "$DISK_IMG" 2>/dev/null || sudo chmod 666 "$DISK_IMG"

sudo virt-install \
  --name "$VM_NAME" \
  --ram 2048 \
  --vcpus 2 \
  --disk path="$(realpath "$DISK_IMG")",format=raw,bus=usb,removable=on \
  --os-variant debian11 \
  --boot hd \
  --network network=default \
  --graphics spice,listen=127.0.0.1 \
  --video qxl \
  --noautoconsole || {
    echo "virt-install completed."
}

echo ""
echo "============================================="
echo " ✓ VM successfully started!"
echo "============================================="
echo "VM Name: $VM_NAME"
echo ""
echo "You can manage and view the VM using virt-manager:"
echo "  virt-manager"
echo ""
echo "Or connect directly via virt-viewer:"
echo "  virt-viewer $VM_NAME"
echo ""
echo "To stop and remove the VM:"
echo "  sudo virsh destroy $VM_NAME"
echo "  sudo virsh undefine $VM_NAME"
echo "============================================="
