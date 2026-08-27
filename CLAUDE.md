# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This file stays intentionally short.** `AGENTS.md` in this repo is the canonical, detailed technical reference (directives schema, mode precedence, install steps, hardware compatibility, Wi-Fi troubleshooting, font/Telegram integration, etc.) — read it before non-trivial work. This file exists only because `AGENTS.md` is not auto-loaded into every session's context the way `CLAUDE.md` is; treat it as a pointer plus the commands/architecture summary needed to get oriented quickly, not a duplicate.

## What this repo is

Installation, configuration, and hardware-compatibility tooling for deploying [huronOS](https://huronos.org) (an existing, unmaintained Debian 11 / Linux 6.0.15 live distro — not GallosOS) at Universidad Autónoma de Aguascalientes for the ICPC Gran Premio de México. It's a flat collection of numbered Bash scripts plus contest-specific `.hdf` directive files — there is no build system, package manager, or test suite in the conventional sense.

## Commands

**Shell script verification (mandatory before committing any `*.sh` change):**
```bash
shellcheck 01-install-huronos.sh 02-inject-custom-layer.sh 02b-inject-vscode-extensions.sh 03-configure-nvidia-boot.sh 04-update-directives-wallpaper.sh 05-test-huronos-vm.sh 06-test-huronos-usb-vm.sh 07-test-huronos-vbox.sh 08-test-huronos-usb-vbox.sh 09-clone-huronos-usb.sh
```
Must pass with zero errors and zero warnings. `bash -n <script>` for a quick syntax-only check while iterating.

**Full USB installation (Linux host):**
```bash
bash 01-install-huronos.sh --device /dev/sdX --config icpc-gpm-2026-3rd-date.hdf --password <pass> --url <hdf-raw-url> --wallpaper huronos-wallpaper.png --yes
```
Chains `02-inject-custom-layer.sh` (wallpaper, fonts, Telegram, VS Code extensions, graphics fallbacks) and `03-configure-nvidia-boot.sh` automatically. Omit flags to run interactively. `--yes` erases `--device` without a second confirmation.

**From Windows:** `00-setup-windows-wsl.ps1` (same flags, `-PascalCase`) bootstraps WSL2 + `usbipd-win`, attaches the physical USB, then runs `01-install-huronos.sh` inside WSL.

**VM testing before trusting a build:**
```bash
bash 05-test-huronos-vm.sh [directives.hdf]        # KVM/virt-manager, recommended default
bash 06-test-huronos-usb-vm.sh /dev/sdX            # boot a physical USB directly in KVM
bash 07-test-huronos-vbox.sh                       # VirtualBox alternative
bash 08-test-huronos-usb-vbox.sh /dev/sdX          # physical USB in VirtualBox
```

**Bulk-cloning a finished "golden master" USB onto identical-capacity drives:**
```bash
bash 09-clone-huronos-usb.sh /dev/sdb /dev/sdc /dev/sdd   # or omit targets to auto-detect other removable USBs
```

**Wallpaper hash update after replacing `huronos-wallpaper.png`:**
```bash
./04-update-directives-wallpaper.sh huronos-wallpaper.png icpc-gpm-2026-3rd-date.hdf
```

There is no linter/test suite beyond `shellcheck`; TOML/JSON schema tooling from the parent GallosOS project does not apply here — this repo's config format is `.hdf`, not `.toml`.

## Architecture

**Numbered script pipeline** (`01-`→`09-`, run in order; each is self-contained and safe to invoke standalone): base USB install → custom layer injection (offline `.vsix`/`.deb`/`.tar.xz` assets baked into `05-custom.hsl`) → NVIDIA/UEFI bootloader fixes → wallpaper hash sync → VM test variants (KVM/VirtualBox, disk-image or physical-USB) → bulk clone. `00-setup-windows-wsl.ps1` is a Windows-only prerequisite step ahead of `01-`.

**Directives (`.hdf`) mode hierarchy:** `[Always]` / `[Event]` / `[Contest]` sections, precedence `Contest > Event > Always`, with `[Event-Times]`/`[Contest-Times]` windows gating when each activates. Directives control `AvailableSoftware`, `Bookmarks`, `AllowUsbStorage`, `AllowedWebsites`, and wallpaper — see AGENTS.md § "Directives System" for the full key reference before editing any `*.hdf` file. Changing software/bookmark lists here and in `02-inject-custom-layer.sh`'s module registration (`/etc/hmm/any`, `/etc/hsync/all_software`) must stay in sync.

**Offline-artifact convention:** large build inputs (`.vsix` VS Code extensions, `.deb` font packages, `.tar.xz` Telegram tarball, the base `.iso`) live in the repo root but are `.gitignore`d for size. `02-inject-custom-layer.sh` looks for each one locally first, falling back to a pinned upstream URL + SHA256 only if missing. `Containerfile.build-cache` packages the gitignored `.vsix`/`.deb`/`.tar.xz` set (not the ISO) into a reusable image so a fresh checkout doesn't need to re-download them.

**Cross-document coherence:** `README.md` (user-facing) and `AGENTS.md` (agent/technical reference) describe the same directives, bookmarks, and software lists from different angles — a change to one (e.g. adding a bookmark or a software module) requires updating both, plus the actual `.hdf` file(s) and `02-inject-custom-layer.sh`'s registration logic if a new module is involved.
