#!/usr/bin/env bash
# =============================================================================
# 06-test-huronos-usb-vm.sh — CPC GALLOS / UAA
# Boots a physical huronOS USB drive directly in a KVM/QEMU virtual machine.
# =============================================================================
# Usage:
#   bash 06-test-huronos-usb-vm.sh [/dev/sdX]
# =============================================================================

set -e

VM_NAME="huronOS-USB-VM"
TARGET_DEV="${1:-/dev/sdb}"

echo "============================================="
echo " huronOS Physical USB KVM Test VM"
echo "============================================="
echo ""

# Check KVM availability
if [ ! -c /dev/kvm ]; then
    echo "❌ Error: /dev/kvm not found or virtualization is disabled in BIOS."
    echo "   Ensure hardware virtualization (VT-x / AMD-V) is enabled."
    exit 1
fi

# Check target device
if [ ! -b "$TARGET_DEV" ]; then
    echo "❌ Error: Block device '$TARGET_DEV' does not exist."
    echo "Available drives:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM
    echo ""
    echo "Usage: bash 06-test-huronos-usb-vm.sh /dev/sdX"
    exit 1
fi

echo "Target USB Drive: $TARGET_DEV"
lsblk "$TARGET_DEV" || true
echo ""

# Check for mounted partitions
MOUNTED_PARTS=$(findmnt -n -o TARGET -S "$TARGET_DEV" 2>/dev/null || true)
if [ -n "$MOUNTED_PARTS" ]; then
    echo "⚠️ Warning: Partitions on $TARGET_DEV appear to be mounted on the host:"
    echo "$MOUNTED_PARTS"
    echo "Attempting to unmount for VM safety..."
    for part in $(lsblk -nr -o NAME "$TARGET_DEV"); do
        sudo umount "/dev/$part" 2>/dev/null || true
    done
fi

# Check required commands
MISSING_TOOLS=()
for cmd in virt-install virsh virt-viewer; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_TOOLS+=("$cmd")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️ Missing tools: ${MISSING_TOOLS[*]}"
    echo "Installing virtualization dependencies..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y virt-install libvirt virt-viewer
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y virtinst libvirt-daemon-system virt-viewer
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --needed virt-install libvirt virt-viewer
    fi
fi

# Remove existing domain if present
if virsh -c qemu:///system dominfo "$VM_NAME" &>/dev/null; then
    echo "Destroying existing VM domain: $VM_NAME..."
    virsh -c qemu:///system destroy "$VM_NAME" &>/dev/null || true
    virsh -c qemu:///system undefine "$VM_NAME" &>/dev/null || true
fi

echo "Launching VM '$VM_NAME' with USB passthrough ($TARGET_DEV)..."

virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --ram 3072 \
  --vcpus 2 \
  --disk path="$TARGET_DEV",bus=usb,removable=on \
  --os-variant debian11 \
  --boot hd \
  --network network=default \
  --graphics spice,listen=127.0.0.1 \
  --video qxl \
  --noautoconsole

echo ""
echo "============================================="
echo " ✓ VM successfully started from $TARGET_DEV!"
echo "============================================="
echo "Opening graphical console..."
virt-viewer -c qemu:///system --wait "$VM_NAME" >/dev/null 2>&1 &

echo ""
echo "VM Name: $VM_NAME"
echo "To stop and remove the VM:"
echo "  virsh -c qemu:///system destroy $VM_NAME"
echo "  virsh -c qemu:///system undefine $VM_NAME"
echo "============================================="
