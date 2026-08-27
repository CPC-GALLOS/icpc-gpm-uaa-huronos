#!/usr/bin/env bash
# =============================================================================
# 08-test-huronos-usb-vbox.sh — CPC GALLOS / UAA
# Boots a physical huronOS USB drive directly inside Oracle VirtualBox using
# raw disk VMDK passthrough.
# =============================================================================
# Usage:
#   bash 08-test-huronos-usb-vbox.sh [/dev/sdX]
# =============================================================================

set -e

VM_NAME="huronOS-USB-VirtualBox-VM"
TARGET_INPUT=""

# Parse arguments
for arg in "$@"; do
    if [[ "$arg" =~ ^/dev/ ]]; then
        TARGET_INPUT="$arg"
    elif [ -b "$arg" ]; then
        TARGET_INPUT="$arg"
    fi
done

if [ -n "$TARGET_INPUT" ]; then
    TARGET_DEV="$TARGET_INPUT"
else
    # Auto-detect removable USB block device
    DETECTED_USB=$(lsblk -d -n -r -o NAME,RM,TRAN 2>/dev/null | grep -E "(usb|1)" | awk '{print "/dev/"$1}' | head -n 1 || true)
    if [ -n "$DETECTED_USB" ] && [ -b "$DETECTED_USB" ]; then
        TARGET_DEV="$DETECTED_USB"
    else
        TARGET_DEV="/dev/sdb"
    fi
fi

echo "==========================================================="
echo " huronOS Physical USB VirtualBox Test VM"
echo "==========================================================="
echo "Note: Boots physical USB storage directly via raw disk mapping."
echo ""

# Step 1: Check required commands
echo "[Step 1/4] Checking virtualization tools..."
if ! command -v VBoxManage &>/dev/null; then
    echo "❌ Error: VBoxManage not found. Please install Oracle VirtualBox."
    echo "   Fedora: sudo dnf install -y VirtualBox"
    echo "   Debian/Ubuntu: sudo apt install -y virtualbox"
    echo "   Arch Linux: sudo pacman -S virtualbox"
    exit 1
fi
echo "✓ VirtualBox detected: $(VBoxManage --version)"
echo ""

# Step 2: Check target device
echo "[Step 2/4] Validating target USB drive..."
if [ ! -b "$TARGET_DEV" ]; then
    echo "❌ Error: Block device '$TARGET_DEV' not found."
    echo "Detected storage drives:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM 2>/dev/null || true
    echo ""
    echo "Usage: bash 08-test-huronos-usb-vbox.sh /dev/sdX"
    exit 1
fi

echo "Target USB Drive: $TARGET_DEV"
lsblk "$TARGET_DEV" 2>/dev/null || true
echo ""

# Check for mounted partitions on host and unmount them
for part in $(lsblk -nr -o NAME "$TARGET_DEV" 2>/dev/null || true); do
    if findmnt -n "/dev/$part" &>/dev/null; then
        echo "Unmounting /dev/$part for VM safety..."
        sudo umount "/dev/$part" 2>/dev/null || true
    fi
done

# Ensure user permissions on raw block device
if [ ! -r "$TARGET_DEV" ] || [ ! -w "$TARGET_DEV" ]; then
    echo "Configuring read/write access permissions for $TARGET_DEV (requires sudo)..."
    sudo chmod 666 "$TARGET_DEV"
    for part in $(lsblk -nr -o NAME "$TARGET_DEV" 2>/dev/null || true); do
        sudo chmod 666 "/dev/$part" 2>/dev/null || true
    done
fi

if [ ! -r "$TARGET_DEV" ] || [ ! -w "$TARGET_DEV" ]; then
    echo "❌ Error: Insufficient permissions to read/write $TARGET_DEV."
    echo "   Please grant permissions manually:"
    echo "     sudo chmod 666 $TARGET_DEV"
    exit 1
fi
echo "✓ Read/write access to $TARGET_DEV confirmed."
echo ""

# Step 3: Create Raw Disk VMDK Pointer
echo "[Step 3/4] Generating VirtualBox raw disk VMDK descriptor..."
VM_DIR="$HOME/VirtualBox VMs/$VM_NAME"
mkdir -p "$VM_DIR"
VMDK_PATH="$VM_DIR/huronos-usb-raw.vmdk"

# If VM is currently running, stop it first
if VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep -q 'VMState="running"'; then
    echo "Stopping existing running VM: $VM_NAME..."
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 1
fi

# If VM exists and holds a lock on the old VMDK, detach it first
if VBoxManage list vms 2>/dev/null | grep -q "\"$VM_NAME\""; then
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
    VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
fi

# Remove medium registry if previously registered
OLD_UUID=$(VBoxManage list hdds 2>/dev/null | grep -B 1 "$VMDK_PATH" | grep -oP 'UUID:\s+\K[0-9a-f-]+' | head -n 1 || true)
if [ -n "$OLD_UUID" ]; then
    VBoxManage closemedium disk "$OLD_UUID" --delete 2>/dev/null || true
fi
VBoxManage closemedium disk "$VMDK_PATH" --delete 2>/dev/null || true
rm -f "$VMDK_PATH"

# Generate raw VMDK pointing to the physical USB
if ! VBoxManage createmedium disk --filename "$VMDK_PATH" --variant=RawDisk --format=VMDK --property RawDrive="$TARGET_DEV" 2>/dev/null; then
    VBoxManage internalcommands createrawvmdk -filename "$VMDK_PATH" -rawdisk "$TARGET_DEV"
fi
echo "✓ Raw VMDK created: $VMDK_PATH -> $TARGET_DEV"
echo ""

# Step 4: Configure & Launch VirtualBox VM
echo "[Step 4/4] Configuring VirtualBox VM ($VM_NAME)..."

if ! VBoxManage list vms 2>/dev/null | grep -q "\"$VM_NAME\""; then
    VBOX_FILE="$VM_DIR/$VM_NAME.vbox"
    if [ -f "$VBOX_FILE" ]; then
        echo "Registering existing VirtualBox machine: $VM_NAME..."
        VBoxManage registervm "$VBOX_FILE" 2>/dev/null || VBoxManage createvm --name "$VM_NAME" --ostype "Debian_64" --register
    else
        echo "Creating new VirtualBox machine: $VM_NAME..."
        VBoxManage createvm --name "$VM_NAME" --ostype "Debian_64" --register
    fi
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
if VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep -q 'storagecontrollername.*="IDE"'; then
    VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
    VBoxManage storagectl "$VM_NAME" --name "IDE" --remove 2>/dev/null || true
fi

# Setup SATA storage controller
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep -q 'storagecontrollername.*="SATA"'; then
    VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --bootable on
fi

# Attach Raw VMDK disk
VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$VMDK_PATH"

echo "✓ VM configuration complete."
echo ""

# Launch VirtualBox VM
echo "Launching VirtualBox VM from physical USB ($TARGET_DEV)..."
VBoxManage startvm "$VM_NAME" --type gui

echo ""
echo "==========================================================="
echo " ✓ huronOS USB VM successfully started in VirtualBox!"
echo "==========================================================="
echo "VM Name: $VM_NAME"
echo "Target Drive: $TARGET_DEV"
echo ""
echo "Tips:"
echo "  - huronOS kernel contains native vboxguest, vboxvideo, and vboxsf drivers."
echo "  - To toggle Full Screen in VirtualBox: Host Key (Right Ctrl) + F"
echo "  - To toggle Seamless Mode: Host Key (Right Ctrl) + L"
echo "  - To stop the VM: VBoxManage controlvm \"$VM_NAME\" acpipowerbutton"
echo "==========================================================="
