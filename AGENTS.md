# AGENTS.md — huronOS Context for AI Assistants

This file provides context about huronOS and this repository for AI assistants helping with setup, configuration, or troubleshooting.

---

## Repository Purpose

This repo contains the installation script and directives configuration to deploy **huronOS alpha 0.4** for the **ICPC Gran Premio de México 2026 – Tercera Fecha** at **Universidad Autónoma de Aguascalientes**.

- Contest date: August 29, 2026, 11:00–16:00 CST (UTC-6, America/Mexico_City)
- Judge system: MOJ (<https://moj.naquadah.com.br> & <https://ensaio-times-2026.moj.naquadah.com.br/>)
- ISO: `huronOS-alpha-0.4-amd64.iso` (not tracked in git — MD5: `9ad2afe4980965c8b6b92fa00b8813d5`, SHA256: `b9d530bc7e5b862de9e20c6ce1690ab90f993c6bfa7b44655234708f4e06b2e9`)

---

## What is huronOS?

huronOS is a Debian-based live Linux distribution specifically designed for **competitive programming contests**. It provides:

- A controlled, reproducible environment for all contestants
- A firewall that restricts internet access to only the contest judge during contest mode
- Software modules (compilers, IDEs, editors) activated via a remote directives file
- Three execution modes: **Default**, **Event**, and **Contest**, switching automatically based on time windows

**Key constraint:** huronOS **cannot** be installed by simply burning the ISO to USB. It requires running `install.sh` from the mounted ISO, which partitions and formats the USB with a custom layout using `extlinux` as the bootloader.

---

## Known Bug: extlinux sync issue

The `extlinux` bootloader in huronOS alpha 0.4 has a **critical sync bug** (commit `cb89c2fa`):

- `sync()` was replaced with `syncfs(dir_fd)` but `dir_fd` is closed before `syncfs()` is called
- `syncfs()` silently fails with `EBADF`
- Result: bootloader files may stay in RAM cache if USB is unplugged immediately after installation

**Workaround (already in `install-huronos.sh`):** run `sync && sleep 5 && sync` after `install.sh` finishes, then wait 10 seconds before unplugging.

---

## Directives System

huronOS is controlled by a **directives file** — a plain-text INI-like file hosted on an HTTP/HTTPS server. The system polls this file to configure itself.

### File structure

```ini
[Global]
TimeZone=<IANA timezone>
ConfigExpirationTime=<ISO8601 datetime or "never">
AvailableKeyboardLayouts=<layout1|layout2|>
DefaultKeyboardLayout=<layout>
EventConfig=<true|false>
ContestConfig=<true|false>

[Always]        # Default mode — no time restriction
[Event]         # Event mode — requires [Event-Times]
[Contest]       # Contest mode — requires [Contest-Times]

# Each mode section supports:
AllowedWebsites=<domain1|domain2| or "all">
AllowUsbStorage=<true|false>
AvailableSoftware=<category/pkg|...>
Bookmarks={Label^https://url}|{Label2^https://url2}|
Wallpaper=<default|https://url>
WallpaperSha256=<sha256 of wallpaper image>

[Event-Times]
<ISO8601_start> <ISO8601_end>

[Contest-Times]
<ISO8601_start> <ISO8601_end>
```

### Mode priorities: Contest > Event > Default (Always)

### Available software packages

| ID | Software |
| ---- | ---------- |
| `internet/chromium` | Chromium browser |
| `internet/firefox` | Firefox browser |
| `internet/crow` | Crow Dictionary App |
| `internet/telegram` | Telegram Desktop application & protocol handler |
| `langs/g++` | GNU C++ compiler |
| `langs/gcc` | GNU C compiler |
| `langs/javac` | OpenJDK Java |
| `langs/kotlinc` | Kotlin compiler |
| `langs/pypy3` | PyPy 3 |
| `langs/python3` | Python 3 |
| `langs/dotnet` | C# dotnet |
| `langs/mono` | C# mono |
| `langs/ruby` | Ruby |
| `tools/konsole` | KDE terminal |
| `tools/make` | GNU Make |
| `tools/byobu` | Byobu |
| `tools/midnight-commander` | Midnight Commander |
| `programming/vscode` | VSCode (Codium) |
| `programming/vim` | Vim |
| `programming/gvim` | gVim |
| `programming/emacs` | Emacs |
| `programming/atom` | Atom |
| `programming/sublime` | Sublime Text |
| `programming/geany` | Geany |
| `programming/gedit` | gedit |
| `programming/kate` | Kate |
| `programming/intellij` | IntelliJ IDEA |
| `programming/eclipse` | Eclipse |
| `programming/pycharm` | PyCharm |
| `programming/kdevelop` | KDevelop |
| `programming/codeblocks` | Code::Blocks |
| `programming/rider` | Rider |
| `programming/joe` | Joe editor |
| `programming/vsc-clangd` | VSCode ClangD extension |
| `programming/vsc-cpptools` | VSCode C++ Tools extension |
| `programming/vsc-cph` | VSCode Competitive Programming Helper (cph) extension |
| `programming/vsc-python` | VSCode Microsoft Python extension |
| `programming/vsc-java` | VSCode Red Hat Java extension |
| `programming/vsc-cpp-compile-run` | VSCode CPP Compile/Run |
| `programming/vsc-vscodevim` | VSCode Vim extension |
| `programming/vsc-makefile-tools` | VSCode Makefile Tools |
| `programming/vsc-intellij-idea-keybindings` | VSCode IntelliJ keybindings |

### Firewall notes

- `AllowedWebsites=all` allows everything
- Domain-based: resolves IP at sync time, allows that IP
- Sites using CDNs / dynamic IPs may need multiple domains whitelisted
- For BOCA: `boca.icpcmexico.org|score.icpcmexico.org|icpcmexico.org|`

### Directives hosting options

- **GitHub Gist or Raw GitHub** (raw URL) — easiest, no infrastructure needed
- **Public web server** — best for production contests
- **Local LAN server** — use `http://192.168.x.x/file.hdf` (HTTP recommended, not HTTPS, for local servers)

---

## Installation Process

### Dependencies (Fedora)

```bash
sudo dnf install -y squashfs-tools parted psmisc e2fsprogs dosfstools perl
```

### Steps

1. Mask automounter: `sudo systemctl mask udisks2`
2. Mount ISO: `sudo mount -o loop,ro huronOS-alpha-0.4-amd64.iso /media/iso`
3. Run installer: `sudo /media/iso/install.sh`
4. Select target USB disk carefully (all data will be erased)
5. Provide: directives URL, root password, network config (blank = DHCP)
6. After install: `sync && sleep 5 && sync` (critical — see bug above)
7. Wait 10 seconds before unplugging USB
8. Cleanup: `sudo umount /media/iso && sudo systemctl unmask udisks2`

### Boot requirements

- Secure Boot must be **disabled** on UEFI systems
- Windows Fast Startup must be disabled if dual-boot machine
- huronOS auto-boots to contestant desktop after 7 seconds

### Post-install directives config (if skipped during install)

Edit on the USB: `HURONOS/data/configs/sync-server.conf`

---

## This repo's directives file

**File:** `icpc-gpm-2026-3rd-date.hdf`  
**Hosted at:** `https://raw.githubusercontent.com/CPC-GALLOS/icpc-gpm-uaa-huronos/main/icpc-gpm-2026-3rd-date.hdf` (Raw GitHub) or Gist raw URL

Key settings:

- Contest window: `2026-08-29T10:57:00` → `2026-08-29T16:20:00` (starts 3 min early for the ~2 min event->contest mode transition; ends 20 min late to allow contestants time to save/backup code)
- Config expires: `2026-08-30T23:59:59`
- Default keyboard: `latam`
- Contest firewall: `all` (sin firewall / sin drop para compatibilidad con MOJ)
- Contest USB storage: disabled
- Bookmarks in all modes:
  - `MOJ Contest`: `https://moj.naquadah.com.br`
  - `MOJ Ensaio`: `https://ensaio-times-2026.moj.naquadah.com.br/`
  - `Guia MOJ`: `https://moj.naquadah.com.br/contest/ajuda/competidor.html?lang=en`
  - `MOJ Bot (Telegram)`: `https://t.me/mojinho_bot?start=978147e0-b481-45a5-979c-076f13cf5369`
  - `BOCA Juez (Fallback)`: `https://boca.icpcmexico.org`
  - `BOCA Score (Fallback)`: `https://score.icpcmexico.org/`
  - `ICPC Mexico`: `https://icpcmexico.org`
- Available software:
  - `[Always]` & `[Event]`: includes `internet/telegram`, `internet/chromium`, `langs/*`, `tools/*`, `programming/*` (CPH, Python, Java)
  - `[Contest]`: includes compilers, IDEs, VS Code extensions; omits `internet/telegram` to maintain contest integrity

---

## Telegram Desktop, Noto Color Emoji / Unicode Fonts & Inter UI Font Integration

1. **Telegram Desktop (`internet/telegram`)**:
   - Packaged as a standalone Linux binary in `/opt/telegram/Telegram` and standalone module `huronOS/software/internet/telegram.hsm`.
   - Desktop entry `/usr/share/applications/org.telegram.desktop.desktop` registered with `x-scheme-handler/tg` MIME association.
   - Allows contestants to click the `@mojinho_bot` start URL (`https://t.me/mojinho_bot?start=...`) directly from Chromium or bookmarks to create their MOJ accounts.
   - Available in `[Always]` and `[Event]` modes before the contest.

2. **Full Emoji & Unicode Symbol Support**:
   - `fonts-noto-color-emoji` (`NotoColorEmoji.ttf`) and `fonts-dejavu-core` (`DejaVuSans.ttf`, incl. `DejaVuSansMono.ttf`) injected into `05-custom.hsl`.
   - Fontconfig fallback aliases configured in `/etc/fonts/conf.d/56-fonts-noto-color-emoji.conf` so Chromium and all X11/GTK apps render all Unicode emojis (`📖`, `👥`, `👤`, `👔`, `🎩`, `🎪`, `⚖️`, `👑`, etc.) in full color instead of missing hollow square boxes (`[]`).

3. **Inter UI Font (matches MOJ's design)**:
   - `fonts-inter` (`Inter-*.otf` static weights, `InterDisplay-*` excluded as unused) injected into `/usr/share/fonts/opentype/inter/`.
   - MOJ's stylesheet (`ui.css`) declares `font-family:"Inter",system-ui,...,sans-serif` with no `@font-face`/CDN of its own — without this package Chromium/Firefox silently fell back to `Segoe UI`/`Roboto`. No fontconfig alias is needed: the OTF's internal family name is already `Inter`, so fontconfig matches it directly once the files are present.


---

## Testing with KVM / virt-manager
 
 huronOS can be tested locally inside KVM without burning a physical USB:
 
 - **Automated setup script (Virtual Disk Image):** `05-test-huronos-vm.sh`
   - **Method:** Creates a 16 GiB raw disk image (`huronos-vm-disk.img`), attaches it as a loop device (`/dev/loopN`), runs `install.sh` from the ISO onto the loop device, and launches `virt-install`.
 - **Physical USB passthrough script (KVM):** `06-test-huronos-usb-vm.sh` (e.g. `bash 06-test-huronos-usb-vm.sh /dev/sdb`).
 - **Boot mode:** SeaBIOS (BIOS/MBR legacy boot) — DO NOT use OVMF/UEFI as huronOS uses extlinux.
 - **Physical USB passthrough:** A physical USB created with `01-install-huronos.sh` can also be passed through as a USB Host Device in `virt-manager` or directly via `06-test-huronos-usb-vm.sh` / `08-test-huronos-usb-vbox.sh`.
 - **Graphical Console & Full Screen (KVM):**
   - Command: `virt-viewer -c qemu:///system --full-screen huronOS-Test-VM &`
   - Toggle Full Screen: `F11` (release cursor: `Shift + F12`).
   - Resolution setting inside huronOS: *Settings -> Displays -> 1920x1080* or `xrandr -s 1920x1080`.
 - **VirtualBox Testing Scripts:**
   - **Virtual Disk Image:** `07-test-huronos-vbox.sh` converts `huronos-vm-disk.img` to `.vdi` using `qemu-img convert -U -f raw -O vdi` and launches `huronOS-VirtualBox-VM` using native `vboxguest`, `vboxvideo`, and `vboxsf` kernel modules.
   - **Physical USB Drive:** `08-test-huronos-usb-vbox.sh` (e.g. `bash 08-test-huronos-usb-vbox.sh /dev/sdb`) creates a raw disk VMDK descriptor directly mapped to the physical USB and boots `huronOS-USB-VirtualBox-VM`.
 - **Custom Disk Storage (`VM_DISK_DIR` / `VM_DISK_PATH`):**
   - Both `05-test-huronos-vm.sh` and `07-test-huronos-vbox.sh` support `export VM_DISK_DIR="/path/to/secondary/disk"` to store `.img` and `.vdi` files on alternative drives/partitions.

---

## Bulk-Cloning USBs from a Golden Master

- **Script:** `09-clone-huronos-usb.sh /dev/sdX [/dev/sdY ...]` (source device first, then one or more targets; omit targets to auto-detect every other removable USB).
- **Purpose:** After fully installing and customizing one USB via `01-install-huronos.sh` (Steps 1–3), clone it onto additional **identical-capacity** USBs far faster than re-running the interactive installer on each one.
- **Method:** Only the ~6 GiB system partition (label `HURONOS`) is cloned byte-for-byte (staged in RAM under `/dev/shm` when there's room) — it holds 100% of the real content (base/software squashfs layers, the custom layer, NVIDIA boot tweaks). The two ext4 persistence partitions (`event-data`, `contest-data`) start empty on every install anyway, so they're freshly `mkfs.ext4`'d per target instead of being copied, giving each clone unique filesystem UUIDs there. Those new UUIDs are rebaked into `boot/huronos.cfg` (`event.uuid=`/`contest.uuid=` lines) the same way the ISO's own `install.sh` bakes UUIDs at its "[11/13]" step, and the `checksums` line for `boot/huronos.cfg` is recomputed the same way `03-configure-nvidia-boot.sh` does after its own edits. All targets in a run are cloned in parallel as background jobs.
- **Note:** The FAT32 system partition's own volume UUID is preserved identical across all clones (it travels with the byte-cloned partition), which is safe as long as clones aren't mounted on the same host simultaneously — only the two persistence-partition UUIDs are guaranteed unique per clone.
- **Verification:** Always boot-test a freshly cloned target with `08-test-huronos-usb-vbox.sh /dev/sdX` (or `06-test-huronos-usb-vm.sh`) before using it on real contest hardware.

---

## Custom Wallpaper Integration

- **Working template:** `huronos-wallpaper.png` (1920×1080 PNG).
- **Injection mechanics:**
  - `05-custom.hsl`: Layer overlay containing `/usr/share/backgrounds/huronos-background.png` (replaces default fallback system-wide).
  - `huronOS/data/backups/`: Pre-seeded `{Always,Event,Contest}-mode-wallpaper.*`.
  - Directives `.hdf`: `Wallpaper=` and `WallpaperSha256=`.
- **Scripts:**
  - `04-update-directives-wallpaper.sh`: Computes SHA256 of `huronos-wallpaper.png` and updates `.hdf`.
  - `02-inject-custom-layer.sh`: Injects custom wallpaper into a huronOS USB partition, VM image, or mounted filesystem.
  - `01-install-huronos.sh` & `05-test-huronos-vm.sh`: Both automatically call `02-inject-custom-layer.sh` after base installation.

---

## VS Code Extensions Integration (C/C++, CPH, Python & Red Hat Java via Offline VSIX)

huronOS alpha 0.4 ships with **VSCodium 1.81.1** (August 2023). In contest environments with strict firewalls and older VS Code runtimes, downloading extensions directly from the GUI marketplace fails with download errors. Therefore, all extensions are packaged as **100% offline `.vsix` packages** and pre-injected into the system:

1. **`ms-vscode.cpptools` (C/C++ Tools)**:
   - Pre-packaged in base ISO as `huronOS/software/programming/vsc-cpptools.hsm` (v1.16.3) and pre-extracted into `05-custom.hsl`.
2. **`DivyanshuAgrawal.competitive-programming-helper` (CPH)**:
   - Package: `competitive-programming-helper-2077.0.0.vsix`.
   - Directory: `/opt/codium/contestant/extensions/divyanshuagrawal.competitive-programming-helper-2077.0.0/`.
   - Manifest: `/opt/codium/contestant/extensions/ids/vsc-cph.json`.
3. **`ms-python.python` (Microsoft Python)**:
   - Package: `ms-python.python-2023.14.0.vsix` (includes offline bundled `jedi-language-server`).
   - Directory: `/opt/codium/contestant/extensions/ms-python.python-2023.14.0/`.
   - Manifest: `/opt/codium/contestant/extensions/ids/vsc-python.json`.
4. **`redhat.java` (Language Support for Java by Red Hat)**:
   - Package: `redhat.java-1.40.0.vsix` (includes offline JDT Language Server for OpenJDK 17).
   - Directory: `/opt/codium/contestant/extensions/redhat.java-1.40.0/`.
   - Manifest: `/opt/codium/contestant/extensions/ids/vsc-java.json`.
5. **Offline Storage & Manual VSIX Install**:
   - Copies of all `.vsix` packages are stored in `/opt/codium/vsix/` and `/home/contestant/vsix/`.
   - Contestants can install via GUI: *Extensions -> ... -> Install from VSIX...*
   - Admin/CLI helper: `/usr/local/bin/install-vsix-extensions` installs/refreshes all VSIX packages automatically.
6. **huronOS Module Integration**:
   - Registered in `/etc/hmm/any` and `/etc/hsync/all_software` (`programming/vsc-cph`, `programming/vsc-python`, `programming/vsc-java`).
   - Pre-compiled `/opt/codium/contestant/extensions/extensions.json` with permissions `777`.
7. **Scripts**:
   - `02b-inject-vscode-extensions.sh`: Standalone injection script for USB, VM, or mounted HURONOS directory.
   - `02-inject-custom-layer.sh`, `01-install-huronos.sh`, `05-test-huronos-vm.sh`: Automatically perform full extension and wallpaper injection.

---

## Build-Cache Container (`Containerfile.build-cache`)

All the offline `.vsix`/`.deb`/`.tar.xz` inputs above (VS Code extensions, and the fonts & Telegram Desktop tarball from § "Telegram Desktop, Noto Color Emoji / Unicode Fonts & Inter UI Font Integration") live in the repo root but are `.gitignore`d due to size. `Containerfile.build-cache` (`FROM scratch`) packages them into one reusable image so `01-install-huronos.sh`/`02-inject-custom-layer.sh` find them locally on a fresh checkout instead of re-downloading from Debian/GitHub/Telegram mirrors:

```bash
podman build -f Containerfile.build-cache -t icpc-gpm-uaa-huronos/build-cache:latest .
podman create --name gpm-cache-tmp icpc-gpm-uaa-huronos/build-cache:latest
podman cp gpm-cache-tmp:/cache/. .
podman rm gpm-cache-tmp
```

Deliberately excludes `huronOS-alpha-0.4-amd64.iso` (separate `.gitignore` category, 5.3GB) and `huronos-vm-disk.img` (ephemeral VM test output, not a build input). See README.md § "Build-Cache Container" for the full usage walkthrough (export/import as tarball, consuming it as a `COPY --from=` stage).

---

## UAA Lab Hardware & NVIDIA Graphics Compatibility

On systems in the **Universidad Autónoma de Aguascalientes (UAA)** contest laboratories (e.g. Dell machines with Intel Arrow Lake / dedicated NVIDIA GPUs) where the kernel (Linux 6.0 in huronOS alpha 0.4) lacks KMS drivers:

- **EFI Framebuffer fallback (`fbdev`)**: huronOS boots with `modprobe.blacklist=i915,nouveau fbcon=nodefer` (without `nomodeset`) and uses Debian's `xserver-xorg-video-fbdev` driver injected into `05-custom.hsl` targeting `/dev/fb0`.
- **Software rendering**: OpenGL clients use Mesa LLVMpipe (`LIBGL_ALWAYS_SOFTWARE=1`).
- **Native 64-bit EFI menu**: (`/EFI/Boot/menu.c32` in `/EFI/Boot/syslinux.cfg`) to ensure UEFI boots without crashing Syslinux EFI.
- **Removal of `vga=normal`**: from kernel parameters.

**Automated script:** `03-configure-nvidia-boot.sh` automatically updates both `/boot/huronos.cfg` (Legacy BIOS) and `/EFI/Boot/syslinux.cfg` (UEFI) and refreshes checksums.

---

## Network Management & IEEE 802.1X / Enterprise Wi-Fi (ConnMan)

huronOS uses **ConnMan** (`cmst`) for networking.
- **WPA-Enterprise limitation:** ConnMan's simple tray GUI cannot prompt interactively for EAP (PEAP/MSCHAPv2) authentication credentials when selecting 802.1X networks such as `RIUAA` (UAA campus Wi-Fi) or `eduroam`. It produces the error:
  `"Failed to toggle connection state. IEEE8021x secured services have to be manually configured."`
- **Official Contest Recommendation:** Use wired Ethernet (`eth0` / `enp*`), which connects automatically via DHCP without authentication prompt issues.
- **Manual Wi-Fi Provisioning:** Configured by placing `.config` files under `/var/lib/connman/` (e.g. `/var/lib/connman/riuaa.config`) specifying `Type=wifi`, `Name=RIUAA`, `EAP=peap`, `Phase2=MSCHAPV2`, `Identity=...`, and `Passphrase=...`, then running `sudo systemctl restart connman`.

---

## Development Guidelines: Shell Script Quality & ShellCheck

> [!IMPORTANT]
> **Mandatory verification:** Any modified or newly created shell script (`*.sh`) in this repository **must always be verified with `shellcheck`**:
>
> ```bash
> shellcheck 01-install-huronos.sh 02-inject-custom-layer.sh 02b-inject-vscode-extensions.sh 03-configure-nvidia-boot.sh 04-update-directives-wallpaper.sh 05-test-huronos-vm.sh 06-test-huronos-usb-vm.sh 07-test-huronos-vbox.sh 08-test-huronos-usb-vbox.sh 09-clone-huronos-usb.sh
> ```
>
> All scripts in this repo must pass `shellcheck` with zero errors and zero warnings before committing.

---

## References

- [huronOS official website](https://huronos.org)
- [huronOS installation guide](https://huronos.org/docs/usage/how-to-install)
- [Directives introduction](https://huronos.org/docs/usage/directives/introduction-to-directives)
- [Directives file syntax](https://huronos.org/docs/usage/directives/directives-file-syntax)
- [Software modules](https://huronos.org/docs/usage/directives/configurations/software-modules)
- [Boot options](https://huronos.org/docs/usage/boot-options)
