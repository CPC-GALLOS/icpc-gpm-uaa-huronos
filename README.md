# icpc-gpm-uaa-huronos

Installation and configuration of [huronOS](https://huronos.org) for the **Universidad Autónoma de Aguascalientes** teams at the **Gran Premio de México** (ICPC Region Mexico).

- 🏆 **Judge:** [boca.icpcmexico.org](https://boca.icpcmexico.org)
- 💿 **ISO:** huronOS alpha 0.4 amd64

---

## Repository contents

```text
icpc-gpm-uaa-huronos/
├── install-huronos.sh          # Installation script for USB drive
├── test-huronos-vm.sh          # Automated KVM / virt-manager test script
├── *.hdf                       # Directives files per contest
├── .gitignore                  # Ignores the ISO and VM images
├── AGENTS.md                   # AI context
└── README.md                   # This file
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
| Fedora          | `sudo dnf install squashfs-tools parted psmisc e2fsprogs dosfstools perl-base` | `sudo dnf install @virtualization qemu-img virt-install`                       |
| Arch Linux      | `sudo pacman -S squashfs-tools parted psmisc e2fsprogs dosfstools perl`        | `sudo pacman -S qemu-full virt-manager libvirt`                                |

---

## Installation

> ⚠️ **Make sure the ISO is already downloaded** and placed in this directory before running the script.

```bash
bash install-huronos.sh
```

The script automatically:

1. Installs system dependencies
2. Masks `udisks2` to prevent automounter interference
3. Mounts the ISO
4. Runs huronOS's `install.sh` (interactive — select your USB drive)
5. Runs `sync` twice to guarantee complete write to disk
6. Unmounts and cleans up

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

## Directives

Each `.hdf` file configures huronOS behavior for its contest:

| Mode                               | Firewall                | USB     | Software               |
| ---------------------------------- | ----------------------- | ------- | ---------------------- |
| **Always** (outside contest hours) | Everything open         | Allowed | All languages and IDEs |
| **Contest** (time window)          | BOCA + ICPC Mexico only | Blocked | All languages and IDEs |

**Browser bookmarks:** BOCA Contest · ICPC Mexico  
**Timezone:** America/Mexico_City (UTC-6, CST)  
**Default keyboard layout:** latam

---

## Boot

1. Plug in the USB and start the machine
2. Enter the boot menu (F12 / F2 / Del)
3. **Disable Secure Boot** if using UEFI
4. Select the USB to boot from
5. huronOS automatically boots to the contestant desktop

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
