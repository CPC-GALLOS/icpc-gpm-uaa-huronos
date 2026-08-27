# icpc-gpm-uaa-huronos

Installation, configuration, and hardware compatibility solutions for [huronOS](https://huronos.org) deployed at **Universidad Autónoma de Aguascalientes (UAA)** for the **ICPC Gran Premio de México**.

- 🏆 **Contest Judge:** [MOJ](https://moj.naquadah.com.br) | [Ensaio](https://ensaio-times-2026.moj.naquadah.com.br/) | [Contestant Guide](https://moj.naquadah.com.br/contest/ajuda/competidor.html?lang=en)
- 💿 **Base ISO:** `huronOS-alpha-0.4-amd64.iso` (Debian 11 / Linux Kernel 6.0.15)
- 🏢 **Venue:** Computer Laboratories, Universidad Autónoma de Aguascalientes

---

## Repository Structure & Numbered Scripts

Scripts are organized and numbered chronologically according to execution workflow:

```text
icpc-gpm-uaa-huronos/
├── 01-install-huronos.sh               # [Step 1] Base USB installer (automatically chains steps 2 and 3)
├── 02-inject-custom-layer.sh           # [Step 2] Injects 05-custom.hsl (Wallpaper, fbdev driver, Mesa, SPICE & extensions)
├── 02b-inject-vscode-extensions.sh     # [Helper] Standalone VS Code extension injector (CPH, C++, Python, Java)
├── 03-configure-nvidia-boot.sh         # [Step 3] Bootloader configuration for 2024 hardware and NVIDIA GPUs
├── 04-update-directives-wallpaper.sh   # [Utility] Computes wallpaper SHA256 hashes and updates .hdf files
├── 05-test-huronos-vm.sh               # [VM - DEFAULT] Creates and runs local VM in KVM / virt-manager (with SPICE vdagent)
├── 06-test-huronos-usb-vm.sh           # [VM - KVM USB] Direct physical USB boot in KVM / virt-viewer
├── 07-test-huronos-vbox.sh             # [VM - OPTIONAL] Converts disk to VDI and boots inside Oracle VirtualBox
├── competitive-programming-helper-*.vsix # Offline CPH extension package for VS Code
├── ms-python.python-*.vsix             # Offline Python extension package for VS Code
├── redhat.java-*.vsix                  # Offline Java language support package for VS Code
├── huronos-wallpaper.png               # Official custom contest wallpaper (1920×1080)
├── *.hdf                               # Contest directives configuration files
├── .gitignore                          # Ignores ISOs, VM disk images, and binary artifacts
├── AGENTS.md                           # AI assistant technical context
└── README.md                           # Comprehensive technical documentation
```

### Contest Directives

| File | Contest | Date & Schedule | Directives URL |
| --- | --- | --- | --- |
| [`icpc-gpm-2026-3rd-date.hdf`](./icpc-gpm-2026-3rd-date.hdf) | Gran Premio de México 2026 – 3rd Date | Aug 29, 2026, 11:00–16:00 CST | [GitHub Raw](https://raw.githubusercontent.com/CPC-GALLOS/icpc-gpm-uaa-huronos/main/icpc-gpm-2026-3rd-date.hdf) |

---

## Technical Chronicle: UAA 2024 Hardware vs huronOS 2022 (Kernel 6.0)

### Background & Challenge
huronOS alpha 0.4 is a live Debian 11 (Bullseye) distribution powered by Linux Kernel **6.0.15**, originally built between 2022 and 2023. Currently, the project **has no active upstream maintainers**.

For the 2024–2026 contest cycles, the computer laboratories at **Universidad Autónoma de Aguascalientes (UAA)** were upgraded with modern Dell desktop workstations equipped with **14th Gen Intel Core / Arrow Lake** processors (`8086:7d67` integrated graphics) and/or dedicated **NVIDIA GeForce RTX (Ada Lovelace)** GPUs.

### Technical Issues Encountered
1. **Missing KMS Drivers:** Linux kernel 6.0.15 lacks Kernel Mode Setting (KMS) drivers for 2024 hardware (Intel Arrow Lake and modern NVIDIA GPUs require Linux >= 6.8 or the newer `xe` driver).
2. **Black Screen on Default Boot:** When booting huronOS with standard parameters, the system attempted to load nonexistent or incompatible KMS drivers, resulting in a system freeze and black screen immediately after the bootloader menu.
3. **Xorg Failure with `nomodeset`:** Attempting the conventional `nomodeset` workaround caused huronOS's Xorg server (configured with standard `modesetting`) to crash due to missing DRM devices, preventing the Budgie Desktop from launching.

### Layered Engineering Solution
To ensure huronOS runs reliably without rebuilding the base kernel, a layered fallback architecture was implemented:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                   Budgie Desktop / Codium / Apps                         │
└──────────────────────────────────────────────────────────────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │  Mesa LLVMpipe (Software Rendering)  │ (LIBGL_ALWAYS_SOFTWARE=1)
                 └───────────────────┬───────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │       Xorg fbdev Driver (/dev/fb0)    │ (xserver-xorg-video-fbdev)
                 └───────────────────┬───────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │       EFI Firmware Framebuffer        │ (efifb / VESA BIOS)
                 └───────────────────┬───────────────────┘
                                     │
┌──────────────────────────────────────────────────────────────────────────┐
│ Kernel Parameters: modprobe.blacklist=i915,nouveau fbcon=nodefer         │
└──────────────────────────────────────────────────────────────────────────┘
```

1. **`xserver-xorg-video-fbdev` Driver in `05-custom.hsl`:**
   - Extracted official Debian `xserver-xorg-video-fbdev` driver and injected it into `/usr/lib/xorg/modules/drivers/fbdev_drv.so`.
   - Configured `/etc/X11/xorg.conf.d/99-display.conf` to target the UEFI firmware framebuffer (`/dev/fb0`).
2. **Software Rendering with Mesa LLVMpipe:**
   - Because the EFI framebuffer provides no 3D hardware acceleration, `/etc/X11/Xsession.d/99-huronos-software-rendering` exports `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe`.
   - This allows Budgie Desktop, Chromium, and VS Code to render smoothly via CPU at a steady 60 FPS.
3. **Kernel Bootloader Parameters:**
   - Replaced `nomodeset` with `modprobe.blacklist=i915,nouveau fbcon=nodefer` to preserve access to `/dev/fb0`.
   - Removed the obsolete `vga=normal` parameter.
4. **Native 64-bit Syslinux EFI Menu:**
   - Replaced 32-bit menu dependencies with native 64-bit `/EFI/Boot/menu.c32` in `/EFI/Boot/syslinux.cfg`, preventing memory allocation faults on modern UEFI firmware.

---

## Prerequisites

- Operating System: GNU/Linux (Fedora, Debian, Ubuntu, Arch Linux).
- USB Flash Drive of **16 GiB or larger** (will be completely formatted).
- The base ISO image `huronOS-alpha-0.4-amd64.iso` placed in this repository directory.

### ISO Checksum Verification

```bash
# MD5:    9ad2afe4980965c8b6b92fa00b8813d5
# SHA256: b9d530bc7e5b862de9e20c6ce1690ab90f993c6bfa7b44655234708f4e06b2e9
md5sum huronOS-alpha-0.4-amd64.iso
sha256sum huronOS-alpha-0.4-amd64.iso
```

### Dependency Installation

```bash
# Debian / Ubuntu:
sudo apt install squashfs-tools parted psmisc e2fsprogs dosfstools perl-base

# Fedora:
sudo dnf install squashfs-tools parted psmisc e2fsprogs dosfstools perl

# Arch Linux:
sudo pacman -S squashfs-tools parted psmisc e2fsprogs dosfstools perl
```

---

## Step-by-Step Installation Guide

### Option A: Fully Automated USB Installation

The `01-install-huronos.sh` script executes the base ISO installer and automatically chains Steps 2 and 3 (offline extensions, wallpaper, SPICE vdagent, and GPU compatibility fixes):

```bash
bash 01-install-huronos.sh
```

Prompts:
1. **Root Password:** *(Choose one or press Enter to default to `toor`)*
2. **Directives URL:** GitHub Raw URL of the corresponding `.hdf` file.
3. **Server IP:** *(Leave blank for DHCP)*
4. **Target Disk:** Select the correct USB block device (e.g. `/dev/sdb`).

---

### Option B: Manual Execution & Modular Customization

To apply individual steps on an existing USB drive or mounted filesystem:

#### Step 1: Base USB Installation
```bash
bash 01-install-huronos.sh
```

#### Step 2: Inject Custom Layer (Wallpaper + fbdev Driver + SPICE vdagent + VS Code Extensions)
```bash
# Auto-detects partition labeled HURONOS:
sudo bash 02-inject-custom-layer.sh

# Or specify partition and custom wallpaper:
sudo bash 02-inject-custom-layer.sh /dev/sdX1 huronos-wallpaper.png
```

#### Step 2b: Standalone VS Code Extensions Injection
```bash
sudo bash 02b-inject-vscode-extensions.sh /dev/sdX1
```

#### Step 3: Bootloader Configuration (UAA 2024 / NVIDIA Fixes)
```bash
sudo bash 03-configure-nvidia-boot.sh /dev/sdX1
```

#### Step 4: Update Wallpaper SHA-256 Hash in `.hdf` Directives
```bash
./04-update-directives-wallpaper.sh huronos-wallpaper.png icpc-gpm-2026-3rd-date.hdf
```

#### Step 5: Local Virtual Machine Testing

> [!TIP]
> **Which VM environment should you use?**
> * **KVM / QEMU (`05-test-huronos-vm.sh`) — [RECOMMENDED / DEFAULT]:** Primary test environment. Emulates a physical USB bus (`bus=usb`), utilizes Linux native hardware virtualization (`/dev/kvm`), and includes `spice-vdagent` (adaptive dynamic screen resizing and shared clipboard).
> * **VirtualBox (`07-test-huronos-vbox.sh`) — [OPTIONAL / ALTERNATIVE]:** Secondary runner for users who prefer Oracle VirtualBox. Requires the base disk image to be generated first by Step 5A.

> [!NOTE]
> **Secondary Disk / Custom Storage Path (`VM_DISK_DIR`):**
> If your primary root/home partition has limited disk space and you prefer storing VM disk images (`.img` and `.vdi`) on a secondary drive or folder:
> ```bash
> export VM_DISK_DIR="/path/to/secondary/disk"
> bash 05-test-huronos-vm.sh [directives.hdf]
> bash 07-test-huronos-vbox.sh
> ```

##### Option A (Default / Recommended): KVM / virt-manager
- **Create virtual disk image and boot in KVM:**
  ```bash
  bash 05-test-huronos-vm.sh [directives.hdf]
  ```
- **Boot directly from a connected physical USB drive (e.g. `/dev/sdb`):**
  ```bash
  bash 06-test-huronos-usb-vm.sh /dev/sdb
  ```
- **Graphical Console & Full Screen in KVM (`virt-viewer`):**
  - Connect to graphical console:
    ```bash
    virt-viewer -c qemu:///system huronOS-Test-VM &
    # Or launch directly in full screen:
    virt-viewer -c qemu:///system --full-screen huronOS-Test-VM &
    ```
  - `F11`: Toggle Full Screen mode.
  - `Shift + F12`: Release captured mouse cursor.

##### Option B (Optional / Alternative): Oracle VirtualBox
- **Convert to VDI and boot in VirtualBox:**
  ```bash
  bash 07-test-huronos-vbox.sh
  ```
  *(The script converts `huronos-vm-disk.img` into `huronos-vm-disk.vdi` and launches the VM with SATA AHCI and VMSVGA graphics controllers).*
- **VirtualBox Shortcuts:**
  - `Right Ctrl + F`: Toggle Full Screen mode.
  - `Right Ctrl + L`: Toggle Seamless mode.
- **Stop the VM:**
  ```bash
  VBoxManage controlvm "huronOS-VirtualBox-VM" acpipowerbutton
  ```

---

## Visual Studio Code Offline Extensions (C/C++, CPH, Python & Java)

Because huronOS operates in isolated contest environments with strict firewalls and **VSCodium 1.81.1**, downloading extensions directly from the online marketplace fails. Therefore, all required extensions are packaged and supplied **100% offline as verified `.vsix` packages**:

| Extension | Identifier / Module ID | VSIX Package | Capabilities |
| --- | --- | --- | --- |
| **C/C++ Tools** (`ms-vscode.cpptools`) | `programming/vsc-cpptools` | *Bundled in ISO* (v1.16.3) | IntelliSense autocompletion, code navigation, syntax highlighting, and formatting with `clang-format`. |
| **Competitive Programming Helper** (`divyanshuagrawal.competitive-programming-helper`) | `programming/vsc-cph` | `competitive-programming-helper-2077.0.0.vsix` | Test case management, instant solution execution, visual diff viewer, multi-language support (C++, Java, Python, Kotlin). |
| **Microsoft Python** (`ms-python.python`) | `programming/vsc-python` | `ms-python.python-2023.14.0.vsix` | Offline `jedi-language-server` autocompletion, linting, and Python 3 runtime integration for competitive programming. |
| **Language Support for Java™ by Red Hat** (`redhat.java`) | `programming/vsc-java` | `redhat.java-1.40.0.vsix` | Full Java language support (OpenJDK 17), offline JDT Language Server, diagnostics, and type resolution. |

### Integration & Offline Installation Architecture

1. **Pre-installed in System Layer (`05-custom.hsl`):** All extensions are pre-extracted and active in `/opt/codium/contestant/extensions/` with manifests `ids/vsc-*.json` and precompiled `extensions.json`. Permissions are set to `777` because the Codium wrapper rebuilds `extensions.json` at startup as user `contestant`.
2. **Backup VSIX Storage:** Offline copies of all `.vsix` archives are stored in `/opt/codium/vsix/` and `/home/contestant/vsix/`.
3. **Manual GUI Installation:** In Codium: *Extensions* -> Three-dot menu `...` -> **Install from VSIX...** selecting any file from `/home/contestant/vsix/`.
4. **CLI Restoration Helper:** In a terminal, contestants or admins can run:
   ```bash
   install-vsix-extensions
   ```
5. **huronOS Module Registration:** Declared in directives (`AvailableSoftware`), `/etc/hmm/any`, and `/etc/hsync/all_software` for interoperability with the `hmm` manager.

---

## Contest Machine Boot Instructions

1. Plug the USB flash drive into the contest computer.
2. If the machine features **only a dedicated NVIDIA GPU**, connect the display monitor cable directly to the GPU port (not the motherboard video port).
3. Power on the computer and press the boot menu key (**F12** on Dell, **F11** on HP, **F8/Del** on Asus).
4. **Disable Secure Boot** in UEFI settings if active.
5. Select the USB flash drive to boot.
6. huronOS will automatically boot into the contestant desktop after 7 seconds.

---

## Networking: Enterprise Wi-Fi (WPA-Enterprise / IEEE 802.1X)

### Institutional Wi-Fi Issue (`RIUAA` / `eduroam`)

When attempting to connect to enterprise wireless networks (such as UAA's **`RIUAA`** or **`eduroam`**) via huronOS's system tray network applet, the system returns:

> **"Failed to toggle connection state. IEEE8021x secured services have to be manually configured."**

### Why does this happen?
huronOS uses **ConnMan** (`cmst`) as its network daemon. Unlike NetworkManager, ConnMan's lightweight tray GUI lacks an interactive credential prompt for EAP authentication (PEAP, MSCHAPv2, TTLS) when clicking on an 802.1X SSID.

### Solutions & Recommendations

#### 1. Official Contest Recommendation: Wired Ethernet (LAN)
In the UAA contest laboratories, all workstations must connect via **Ethernet network cable**.
- huronOS automatically configures wired interfaces via DHCP.
- Eliminates wireless interference, disconnections, and authentication issues.

#### 2. Fast Wireless Alternative: Mobile Hotspot (WPA-PSK)
For testing or preparation:
- Share mobile data or a portable router using standard **WPA2-Personal (WPA-PSK)**.
- ConnMan prompts for the pre-shared password directly in the graphical interface.

#### 3. Manual ConnMan Configuration for WPA-Enterprise (`RIUAA` / `eduroam`)
If Wi-Fi connection to `RIUAA` or `eduroam` is strictly necessary, create a service provisioning file under `/var/lib/connman/`:

1. Open a terminal (`Konsole` or `Ctrl+Alt+T`) and create the configuration file with root privileges:
   ```bash
   sudo nano /var/lib/connman/riuaa.config
   ```

2. Add the corresponding configuration:

   **For `RIUAA` (UAA Campus Network):**
   ```ini
   [global]
   Description = Red Universitaria RIUAA

   [service_riuaa]
   Type = wifi
   Name = RIUAA
   EAP = peap
   Phase2 = MSCHAPV2
   Identity = YOUR_INSTITUTIONAL_ID_OR_EMAIL
   Passphrase = YOUR_INSTITUTIONAL_PASSWORD
   ```

   **For `eduroam`:**
   ```ini
   [global]
   Description = Red Academica eduroam

   [service_eduroam]
   Type = wifi
   Name = eduroam
   EAP = peap
   Phase2 = MSCHAPV2
   Identity = user@institution.edu
   Passphrase = YOUR_PASSWORD
   ```

3. Save the file (`Ctrl+O`, `Enter`) and exit (`Ctrl+X`).
4. Restart the ConnMan service to apply changes:
   ```bash
   sudo systemctl restart connman
   ```
5. Verify network connectivity:
   ```bash
   connmanctl services
   ping -c 3 moj.naquadah.com.br
   ```

---

## Quality Assurance & ShellCheck Verification

In accordance with repository guidelines, all shell scripts are verified with `shellcheck`:

```bash
shellcheck 01-install-huronos.sh 02-inject-custom-layer.sh 02b-inject-vscode-extensions.sh 03-configure-nvidia-boot.sh 04-update-directives-wallpaper.sh 05-test-huronos-vm.sh 06-test-huronos-usb-vm.sh 07-test-huronos-vbox.sh
```
*Quality guarantee: 0 errors and 0 warnings.*
