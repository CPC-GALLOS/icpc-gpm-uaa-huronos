#!/usr/bin/env bash
# =============================================================================
# 07-test-huronos-vbox.sh — CPC GALLOS / UAA
# Converts the huronOS virtual disk image to VDI format and launches it
# inside Oracle VirtualBox for full graphical testing and Guest Additions.
# =============================================================================
# Usage:
#   bash 07-test-huronos-vbox.sh [disk.img]
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Storage location for VM disk (configurable via CLI arg, VM_DISK_DIR, or VM_DISK_PATH)
if [ -n "$1" ]; then
    DISK_IMG="$(readlink -f "$1")"
    VDI_IMG="${DISK_IMG%.*}.vdi"
elif [ -n "$VM_DISK_PATH" ]; then
    DISK_IMG="$VM_DISK_PATH"
    VDI_IMG="${DISK_IMG%.*}.vdi"
elif [ -n "$VM_DISK_DIR" ]; then
    mkdir -p "$VM_DISK_DIR"
    DISK_IMG="$VM_DISK_DIR/huronos-vm-disk.img"
    VDI_IMG="$VM_DISK_DIR/huronos-vm-disk.vdi"
else
    DISK_IMG="$SCRIPT_DIR/huronos-vm-disk.img"
    VDI_IMG="$SCRIPT_DIR/huronos-vm-disk.vdi"
fi

VM_NAME="huronOS-VirtualBox-VM"

echo "==========================================================="
echo " huronOS VirtualBox Test Environment (Optional Runner)"
echo "==========================================================="
echo "Note: The primary/default VM test environment is KVM (05-test-huronos-vm.sh)."
echo ""

# Check required commands
echo "[Step 1/4] Checking virtualization tools..."
MISSING_TOOLS=()
for cmd in VBoxManage qemu-img; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_TOOLS+=("$cmd")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "❌ Error: Missing tools: ${MISSING_TOOLS[*]}"
    echo "Please install VirtualBox and qemu-img (e.g. sudo dnf install -y VirtualBox qemu-img)"
    exit 1
fi
echo "✓ VirtualBox and qemu-img detected."
echo ""

# Check disk image
echo "[Step 2/4] Checking virtual disk image..."
if [ ! -f "$VDI_IMG" ] && [ ! -f "$DISK_IMG" ]; then
    echo "❌ Error: Base virtual disk image not found ($DISK_IMG or $VDI_IMG)."
    echo ""
    echo "ℹ️  VirtualBox is an optional/alternative test runner."
    echo "   To create the disk image and install huronOS for the first time, run:"
    echo "     bash 05-test-huronos-vm.sh"
    echo ""
    echo "   Once the image is created, launch it here with:"
    echo "     bash 07-test-huronos-vbox.sh"
    exit 1
fi

# Convert RAW disk image to VDI if needed
REBUILD_VDI=false
if [ ! -f "$VDI_IMG" ]; then
    REBUILD_VDI=true
elif [ -f "$DISK_IMG" ] && [ "$DISK_IMG" -nt "$VDI_IMG" ]; then
    echo "Detected that $DISK_IMG is newer than $VDI_IMG."
    REBUILD_VDI=true
fi

if [ "$REBUILD_VDI" = "true" ]; then
    echo "Converting $DISK_IMG to VirtualBox VDI format ($VDI_IMG)..."
    
    # If the VM exists and holds a lock on the old medium, detach it first
    if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
        VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
        VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
    fi
    VBoxManage closemedium disk "$VDI_IMG" --delete 2>/dev/null || rm -f "$VDI_IMG"
    
    qemu-img convert -U -f raw -O vdi "$DISK_IMG" "$VDI_IMG"
    echo "✓ VDI image generated: $VDI_IMG"
else
    echo "✓ Using existing VDI image: $VDI_IMG"
fi
echo ""

# Create or reconfigure VirtualBox VM
echo "[Step 3/4] Configuring VirtualBox VM ($VM_NAME)..."

if ! VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    echo "Creating new VirtualBox machine: $VM_NAME..."
    VBoxManage createvm --name "$VM_NAME" --ostype "Debian_64" --register
fi

# Configure VM properties
VBoxManage modifyvm "$VM_NAME" \
    --cpus 2 \
    --memory 3072 \
    --vram 128 \
    --graphicscontroller vmsvga \
    --firmware bios \
    --boot1 disk \
    --boot2 none \
    --boot3 none \
    --boot4 none \
    --nic1 nat \
    --mouse usbtablet \
    --clipboard-mode bidirectional \
    --draganddrop bidirectional \
    --rtcuseutc on

# Remove old IDE controller if present
if VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q 'storagecontrollername.*="IDE"'; then
    VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
    VBoxManage storagectl "$VM_NAME" --name "IDE" --remove 2>/dev/null || true
fi

# Setup SATA storage controller
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q 'storagecontrollername.*="SATA"'; then
    VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --bootable on
fi

# Attach VDI disk
VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$VDI_IMG"

echo "✓ VM configuration complete."
echo ""

# Launch VirtualBox VM
echo "[Step 4/4] Launching VirtualBox VM ($VM_NAME)..."
VBoxManage startvm "$VM_NAME" --type gui

echo ""
echo "============================================="
echo " ✓ huronOS successfully booted in VirtualBox!"
echo "============================================="
echo "VM Name: $VM_NAME"
echo ""
echo "Tips:"
echo "  - huronOS kernel contains native vboxguest, vboxvideo, and vboxsf drivers."
echo "  - To toggle Full Screen in VirtualBox: Host Key (Right Ctrl) + F"
echo "  - To toggle Seamless Mode: Host Key (Right Ctrl) + L"
echo "  - To stop the VM: VBoxManage controlvm \"$VM_NAME\" acpipowerbutton"
echo "============================================="
