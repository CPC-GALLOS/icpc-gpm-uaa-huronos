# icpc-gpm-uaa-huronos

Installation and configuration of [huronOS](https://huronos.org) for the **Universidad Autónoma de Aguascalientes** teams at the **Gran Premio de México** (ICPC Region Mexico).

- 🏆 **Judge:** [MOJ](https://moj.naquadah.com.br) | [Ensaio](https://ensaio-times-2026.moj.naquadah.com.br/) | [Guía del competidor](https://moj.naquadah.com.br/contest/ajuda/competidor.html?lang=en)
- 💿 **ISO:** huronOS alpha 0.4 amd64

---

## Repository contents

```text
icpc-gpm-uaa-huronos/
├── install-huronos.sh              # Installation script for USB drive (with custom wallpaper)
├── configure-nvidia-boot.sh        # Configures bootloader for NVIDIA GPU compatibility (nomodeset)
├── test-huronos-vm.sh              # Automated KVM / virt-manager test script
├── inject-wallpaper.sh             # Injects wallpaper into 05-custom.hsl & USB/VM partitions
├── update-directives-wallpaper.sh  # Calculates SHA256 of custom wallpaper & updates .hdf
├── huronos-wallpaper.png           # Custom contest wallpaper (1920×1080 PNG)
├── *.hdf                           # Directives files per contest
├── .gitignore                      # Ignores the ISO and VM images
├── AGENTS.md                       # AI context
└── README.md                       # This file
```

### Directives per contest

| File                                                         | Contest                                | Date                          | URL                                                                                                                                                                |
| ------------------------------------------------------------ | -------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`icpc-gpm-2026-3rd-date.hdf`](./icpc-gpm-2026-3rd-date.hdf) | Gran Premio de México 2026 – 3rd Date  | Aug 29 2026, 11:00–16:00 CST  | [GitHub Raw](https://raw.githubusercontent.com/CPC-GALLOS/icpc-gpm-uaa-huronos/main/icpc-gpm-2026-3rd-date.hdf)                                                    |

---

## Requirements

- GNU/Linux (Fedora, Ubuntu, Debian, Arch Linux)
- USB drive of **16 GiB or more** (it will be completely erased)
- The huronOS alpha 0.4 ISO **already downloaded** and placed at the root of this repo:

  ```text
  huronOS-alpha-0.4-amd64.iso
  ```

  Download it from [mirrors.huronos.org](https://mirrors.huronos.org/huronOS/alpha/huronOS-alpha-0.4-amd64.iso)  
  and **verify the checksums** before installing:

  | Hash   | Value                                                              |
  | ------ | ------------------------------------------------------------------ |
  | MD5    | `9ad2afe4980965c8b6b92fa00b8813d5`                                 |
  | SHA256 | `b9d530bc7e5b862de9e20c6ce1690ab90f993c6bfa7b44655234708f4e06b2e9` |

  ```bash
  md5sum huronOS-alpha-0.4-amd64.iso
  sha256sum huronOS-alpha-0.4-amd64.iso
  ```

### Dependencies

Install the required packages for your distro **before** running the installation scripts:

| Distro          | Physical USB Install Command                                                   | KVM / Virtualization Testing Command                                           |
| --------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Debian / Ubuntu | `sudo apt install squashfs-tools parted psmisc e2fsprogs dosfstools perl-base` | `sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager` |
| Fedora          | `sudo dnf install squashfs-tools parted psmisc e2fsprogs dosfstools perl`      | `sudo dnf install @virtualization qemu-img virt-install`                       |
| Arch Linux      | `sudo pacman -S squashfs-tools parted psmisc e2fsprogs dosfstools perl`        | `sudo pacman -S qemu-full virt-manager libvirt`                                |

---

## Installation

> ⚠️ **Make sure the ISO is already downloaded** and placed in this directory before running the script.

```bash
# Auto-detects directives file and wallpaper:
bash install-huronos.sh

# Or specify custom directives file and wallpaper explicitly:
bash install-huronos.sh contest-config.hdf my-wallpaper.png
```

The script automatically:

1. Auto-discovers ISO and directives files (presents an interactive menu if multiple `.hdf` files exist)
2. Installs system dependencies
3. Masks `udisks2` to prevent automounter interference
4. Mounts the ISO and runs huronOS `install.sh`
5. Automatically injects custom wallpaper into `05-custom.hsl` and `huronOS/data/backups/`
6. Runs `sync` twice to flush disk buffers safely
7. Unmounts and cleans up

### Installer prompts

| Prompt              | Value                                                   |
| ------------------- | ------------------------------------------------------- |
| Root password       | *(choose one)*                                          |
| Directives URL      | Raw URL of the contest's `.hdf` file (see table above)  |
| IP of sync server   | *(leave blank)*                                         |
| IP / Mask / Gateway | *(leave blank — DHCP)*                                  |
| Target disk         | Select your USB drive (e.g. `/dev/sdb`)                 |

> ⚠️ **The USB drive will be completely erased.** Make sure you select the correct disk.

---

## Custom Wallpaper

huronOS allows customizing the desktop background for contestants:

- **Format:** PNG (recommended) or JPEG
- **Resolution:** `1920×1080`
- **Current wallpaper:** [`huronos-wallpaper.png`](./huronos-wallpaper.png)

### 1. Editing & Updating

1. Open and edit [`huronos-wallpaper.png`](./huronos-wallpaper.png) with your preferred graphics software (GIMP, Canva, Figma, Photoshop, etc.).
2. Whenever you modify your wallpaper (or create new `.hdf` configs), run:

```bash
# Automatically computes SHA256 and updates ALL *.hdf files in repo:
./update-directives-wallpaper.sh

# Or update with a specific wallpaper / directives file:
./update-directives-wallpaper.sh my-wallpaper.png contest-2027.hdf
```

### 2. Injecting into USB / Virtual Machine

- **Automatic during USB install:** `bash install-huronos.sh [config.hdf]` automatically detects `wallpaper.png` and injects it into `05-custom.hsl` and `huronOS/data/backups/`.
- **Automatic during VM test:** `bash test-huronos-vm.sh [my-wallpaper.png]` automatically injects the wallpaper into the virtual disk.
- **Manual injection at any time:**

```bash
# Auto-detects partition labeled HURONOS:
sudo ./inject-wallpaper.sh

# Or specify partition or mount directory and image:
sudo ./inject-wallpaper.sh /dev/sdX1 custom-wallpaper.png
sudo ./inject-wallpaper.sh /media/user/HURONOS custom-wallpaper.png
```

---

## Boot

1. Plug in the USB and start the machine.
2. If your PC **only has a dedicated NVIDIA GPU** (no integrated GPU / iGPU), ensure the monitor cable is plugged into the **NVIDIA graphics card ports**, not the motherboard.
3. Enter the boot menu (F12 / F11 / F8 / F2 / Del).
4. **Disable Secure Boot** if using UEFI.
5. Select the USB to boot from.
6. huronOS automatically boots to the contestant desktop.

### UAA Lab Hardware & NVIDIA Graphics Compatibility

Computers in the **Universidad Autónoma de Aguascalientes (UAA)** contest laboratories (Dell systems with Intel CPU + dedicated NVIDIA RTX/Ada/GTX graphics) require specific boot options to avoid GPU hangs and ensure the `modesetting` Xorg display manager starts properly.

To configure your USB for UAA lab computers and NVIDIA graphics:

```bash
# Auto-detects partition labeled HURONOS and applies optimal lab configuration:
bash configure-nvidia-boot.sh

# Or specify the partition directly:
bash configure-nvidia-boot.sh /dev/sdX1
```

This configuration:
- Enables **DRM KMS modesetting** (keeping `/dev/dri/card0` active for Intel/modesetting display drivers).
- Blacklists `nouveau` (`modprobe.blacklist=nouveau`) to prevent kernel hangs on modern NVIDIA RTX/Ada architectures lacking open-source firmware in the base kernel.
- Removes legacy `vga=normal` and configures the native 64-bit EFI menu module (`/EFI/Boot/menu.c32`).
- Updates bootloader checksums automatically.

---

## Testing with KVM / virt-manager

You can test the entire huronOS environment (directives synchronization, contest mode, firewall, software modules, and browser bookmarks) directly inside a Linux virtual machine without needing a physical USB drive.

### Option 1: Automated Script (`test-huronos-vm.sh`)

Run the VM testing script:

```bash
bash test-huronos-vm.sh
```

This script will:

1. Check that hardware virtualization (`/dev/kvm`) and libvirt are active.
2. Create a 16 GiB raw disk image (`huronos-vm-disk.img`).
3. Attach the image to a loop device (`/dev/loopN`).
4. Mount the huronOS ISO and run `install.sh` targeting the loop device.
5. Create and boot a virtual machine (`huronOS-Test-VM`) in KVM via `virt-install`.

### Option 2: Managing via `virt-manager` GUI

Once the VM is created by `test-huronos-vm.sh` or manually:

1. Open **Virtual Machine Manager**:

   ```bash
   virt-manager
   ```

2. Select **`huronOS-Test-VM`** and click **Open**.
3. Observe the SeaBIOS boot screen; huronOS will boot automatically into the desktop within 7 seconds.

> 💡 **Tip:** Since the VM runs without a guest agent, the initial resolution may be squashed. To fix the aspect ratio and preview wallpapers accurately, open **xterm** from the Budgie menu and run `xrandr -s 1920x1080`.

#### Physical USB Passthrough in virt-manager

If you have already installed huronOS to a physical USB drive using `install-huronos.sh` and want to test it inside a VM without rebooting your host:

1. Insert your huronOS USB drive into your Linux host.
2. Open `virt-manager` and create a new Virtual Machine (**Import existing disk image** or blank VM).
3. Under **Add Hardware** → **USB Host Device**, select your physical USB drive.
4. Set the boot priority to boot from the USB device (ensure BIOS / Legacy mode is selected, not UEFI OVMF).

### VM Cleanup

To stop and remove the test virtual machine and delete the virtual disk image:

```bash
sudo virsh destroy huronOS-Test-VM
sudo virsh undefine huronOS-Test-VM
rm -f huronos-vm-disk.img
```
