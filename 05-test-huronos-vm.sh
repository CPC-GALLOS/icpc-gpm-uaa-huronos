#!/usr/bin/env bash
# =============================================================================
# 05-test-huronos-vm.sh — CPC GALLOS / UAA
# Creates a virtual disk image, installs huronOS onto it via loop device,
# and boots a KVM VM to test directives, firewall, and software modules.
# =============================================================================
# Usage:
#   bash 05-test-huronos-vm.sh [directives.hdf] [wallpaper.png]
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ISO_NAME="huronOS-alpha-0.4-amd64.iso"
ISO_PATH="$SCRIPT_DIR/${ISO_NAME}"

# Storage location for VM disk (configurable via VM_DISK_DIR or VM_DISK_PATH)
if [ -n "$VM_DISK_PATH" ]; then
    DISK_IMG="$VM_DISK_PATH"
elif [ -n "$VM_DISK_DIR" ]; then
    mkdir -p "$VM_DISK_DIR"
    DISK_IMG="$VM_DISK_DIR/huronos-vm-disk.img"
else
    DISK_IMG="$SCRIPT_DIR/huronos-vm-disk.img"
fi

DISK_SIZE="16G"
VM_NAME="huronOS-Test-VM"
MOUNT_POINT="/media/iso"
LOOP_DEV=""
HTTP_SERVER_PID=""

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

# Locate Directives File
HDF_INPUT="${1}"
HDF_FILE=""

if [ -n "$HDF_INPUT" ] && [ -f "$HDF_INPUT" ]; then
    HDF_FILE="$(realpath "$HDF_INPUT")"
else
    HDF_LIST=()
    while IFS= read -r -d $'\0' file; do
        HDF_LIST+=("$file")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.hdf" -print0 | sort -z)

    if [ ${#HDF_LIST[@]} -eq 1 ]; then
        HDF_FILE="${HDF_LIST[0]}"
    elif [ ${#HDF_LIST[@]} -gt 1 ]; then
        echo "Multiple directives files found:"
        DEFAULT_IDX=0
        for i in "${!HDF_LIST[@]}"; do
            FNAME="$(basename "${HDF_LIST[$i]}")"
            echo "  [$((i+1))] $FNAME"
            if [ "$FNAME" = "icpc-gpm-2026-3rd-date.hdf" ]; then
                DEFAULT_IDX=$i
            fi
        done
        read -r -p "Select directives configuration (1-${#HDF_LIST[@]}, default: $((DEFAULT_IDX+1))): " HDF_CHOICE
        if [[ "$HDF_CHOICE" =~ ^[0-9]+$ ]] && [ "$HDF_CHOICE" -ge 1 ] && [ "$HDF_CHOICE" -le "${#HDF_LIST[@]}" ]; then
            HDF_FILE="${HDF_LIST[$((HDF_CHOICE-1))]}"
        else
            HDF_FILE="${HDF_LIST[$DEFAULT_IDX]}"
        fi
    fi
fi

# Locate Wallpaper
VM_WALLPAPER="${2}"
if [ -z "$VM_WALLPAPER" ] || [ ! -f "$VM_WALLPAPER" ]; then
    if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
        VM_WALLPAPER="$SCRIPT_DIR/huronos-wallpaper.png"
    elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
        VM_WALLPAPER="$SCRIPT_DIR/wallpaper.png"
    else
        VM_WALLPAPER=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
    fi
fi

# Resolve host bridge IP for sync server URL display
HOST_IP=$(ip -4 addr show virbr0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
if [ -z "$HOST_IP" ]; then
    HOST_IP="192.168.122.1"
fi

echo "Directives File:  ${HDF_FILE:-None selected}"
if [ -n "$HDF_FILE" ]; then
    echo "  Local HTTP URL: http://${HOST_IP}:8000/$(basename "$HDF_FILE")"
    echo "  Sync Server IP: ${HOST_IP}"
fi
if [ -n "$VM_WALLPAPER" ] && [ -f "$VM_WALLPAPER" ]; then
    echo "Wallpaper:        $VM_WALLPAPER"
fi
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
    ISO_CANDIDATE=$(find "$SCRIPT_DIR" "$HOME/Downloads" "$HOME/VM" -maxdepth 2 -name "huronOS*.iso" 2>/dev/null | head -n 1 || true)
    if [ -n "$ISO_CANDIDATE" ] && [ -f "$ISO_CANDIDATE" ]; then
        ISO_PATH="$ISO_CANDIDATE"
    else
        echo "❌ Error: ${ISO_NAME} not found at ${ISO_PATH}, $HOME/Downloads/, or $HOME/VM/"
        echo "   Please download it from https://mirrors.huronos.org/huronOS/alpha/huronOS-alpha-0.4-amd64.iso"
        echo "   and place it in the current directory."
        exit 1
    fi
fi
echo "✓ ISO found: $ISO_PATH"
echo ""

# Start background local HTTP server if needed
if ! ss -tulpn 2>/dev/null | grep -q ":8000 "; then
    echo "Starting local HTTP directives server on port 8000..."
    (cd "$SCRIPT_DIR" && python3 -m http.server 8000 --bind 0.0.0.0 >/dev/null 2>&1) &
    HTTP_SERVER_PID=$!
    echo "✓ Local HTTP server running (PID $HTTP_SERVER_PID)"
    echo ""
fi

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
    if [ -n "$HDF_FILE" ]; then
        echo ""
        echo "ℹ️  Directives suggestions during prompt:"
        echo "    URL: http://${HOST_IP}:8000/$(basename "$HDF_FILE")"
        echo "    IP:  ${HOST_IP}"
    fi
    echo "============================================="
    echo ""
    read -r -p "Press Enter to start installer..."

    # Run the patched script from within the mount point so relative paths work
    cd "$MOUNT_POINT"
    sudo bash /tmp/install-patched.sh || true
    cd - >/dev/null
    rm -f /tmp/install-patched.sh

    echo ""
    echo "[Step 4.8/6] Injecting custom wallpaper, directives, and VS Code extensions into VM disk image..."
    sudo bash "$SCRIPT_DIR/02-inject-custom-layer.sh" "${LOOP_DEV}p1" "$VM_WALLPAPER" "$HDF_FILE" || {
        echo "⚠️ Warning: Custom layer injection encountered an issue, continuing..."
    }

    echo ""
    echo "[Step 4.9/6] Configuring bootloader for VM graphics compatibility..."
    sudo bash "$SCRIPT_DIR/03-configure-nvidia-boot.sh" "${LOOP_DEV}p1" || {
        echo "⚠️ Warning: Bootloader configuration encountered an issue, continuing..."
    }

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
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
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
echo "  virt-viewer -c qemu:///system $VM_NAME"
echo ""
echo "To stop and remove the VM:"
echo "  sudo virsh destroy $VM_NAME"
echo "  sudo virsh undefine $VM_NAME"
echo "============================================="
