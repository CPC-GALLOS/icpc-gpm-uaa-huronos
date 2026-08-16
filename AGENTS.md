# AGENTS.md — huronOS Context for AI Assistants

This file provides context about huronOS and this repository for AI assistants helping with setup, configuration, or troubleshooting.

---

## Repository Purpose

This repo contains the installation script and directives configuration to deploy **huronOS alpha 0.4** for the **ICPC Gran Premio de México 2026 – Tercera Fecha** at **Universidad Autónoma de Aguascalientes**.

- Contest date: August 29, 2026, 11:00–16:00 CST (UTC-6, America/Mexico_City)
- Judge system: BOCA at <https://boca.icpcmexico.org>
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

- Contest window: `2026-08-29T11:00:00` → `2026-08-29T16:00:00`
- Config expires: `2026-08-30T23:59:59`
- Default keyboard: `latam`
- Contest firewall: `boca.icpcmexico.org|score.icpcmexico.org|icpcmexico.org|`
- Contest USB storage: disabled
- Both bookmarks in all modes: `BOCA Contest` + `ICPC Mexico`

---

## Testing with KVM / virt-manager

huronOS can be tested locally inside KVM without burning a physical USB:

- **Automated setup script:** `test-huronos-vm.sh`
- **Method:** Creates a 16 GiB raw disk image (`huronos-vm-disk.img`), attaches it as a loop device (`/dev/loopN`), runs `install.sh` from the ISO onto the loop device, and launches `virt-install`.
- **Boot mode:** SeaBIOS (BIOS/MBR legacy boot) — DO NOT use OVMF/UEFI as huronOS uses extlinux.
- **Physical USB passthrough:** A physical USB created with `install-huronos.sh` can also be passed through as a USB Host Device in `virt-manager`.

---

## References

- [huronOS official website](https://huronos.org)
- [huronOS installation guide](https://huronos.org/docs/usage/how-to-install)
- [Directives introduction](https://huronos.org/docs/usage/directives/introduction-to-directives)
- [Directives file syntax](https://huronos.org/docs/usage/directives/directives-file-syntax)
- [Software modules](https://huronos.org/docs/usage/directives/configurations/software-modules)
- [Boot options](https://huronos.org/docs/usage/boot-options)
