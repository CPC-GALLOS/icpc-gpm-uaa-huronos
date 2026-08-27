# Windows / WSL2 / usbipd-win Installation Path — Design

## Context

`icpc-gpm-uaa-huronos`'s installation pipeline (`01-install-huronos.sh` and the
scripts it chains) is pure Bash and depends on Linux-only tooling
(`squashfs-tools`, `parted`, `mkfs.vfat`/`mkfs.ext4`, raw `/dev/sdX` block
device access). It only runs on a Linux host today.

The goal: someone on Windows should be able to download this repo, tell
Claude (running as an agent) to install huronOS onto a physical USB drive,
and have it actually happen — without the human needing to already know
WSL2, `usbipd-win`, or the Bash pipeline's internals.

Windows has no native raw block-device Bash environment. The bridge is
WSL2 + `usbipd-win` (installed via `winget`): `usbipd-win` attaches a
physical USB controller to the WSL2 Linux kernel so it appears as a real
`/dev/sdX` node inside WSL, at which point the existing, unmodified Bash
pipeline just works.

Three deployment paths were discussed; WSL2 + `usbipd-win` was chosen as the
**only** path built out now:

- **WSL2 + usbipd-win (native)** — chosen primary path. Reuses the existing
  Bash pipeline unmodified; the only new code is a Windows-side bootstrap/
  orchestrator.
- **Docker Desktop (WSL2 backend) + usbipd-win** — already works today with
  zero new code (Docker Desktop on Windows already runs on a WSL2 VM; a
  privileged container with the `usbipd`-attached device passed via
  `--device` can run the same Bash scripts). Decision: document this in 2-3
  paragraphs only — no new Containerfile/image, to avoid duplicate
  maintenance of a secondary path that WSL2-native already covers.
- **"WSL alone" (no usbipd-win)** — covered implicitly: everything except
  the final physical-USB write (building layers, running the VM test
  scripts) already works in a plain WSL2 distro with no Windows-side
  changes at all, since it's just Linux. No new code needed for this either.

## Non-Goals

- No new Docker image/Containerfile for the pipeline itself (see above).
- No changes to the existing numbered Bash scripts (`01-install-huronos.sh`
  through `09-clone-huronos-usb.sh`) or to `02-inject-custom-layer.sh` —
  they already work as-is once a `/dev/sdX` node exists inside WSL.
- No attempt to automate the one required human action: approving the
  Windows UAC elevation prompt for `usbipd bind`. Claude cannot click a UAC
  dialog; the design surfaces this as an explicit pause point instead of
  hiding or working around it.
- Not tested end-to-end on real Windows hardware in this session (the
  authoring environment is Linux-only) — see Verification.

## Components

### 1. `00-setup-windows-wsl.ps1` (new, repo root)

A PowerShell script, run from a native Windows PowerShell prompt, that
bootstraps prerequisites and then hands off to the existing Bash pipeline
inside WSL. Numbered `00-` since it's a prerequisite *before* `01-install-huronos.sh` in the existing numbered-script convention.

**Parameters** (mirror `01-install-huronos.sh`'s flags 1:1, plus
Windows-specific ones):

| Param | Maps to | Default |
| --- | --- | --- |
| `-BusId <id>` | *(Windows-only)* which USB to bind/attach | none — lists via `usbipd.exe list` and prompts interactively |
| `-Device <name>` | `--device` (device name expected inside WSL, no `/dev/` prefix) | auto-detected after attach (diffs `lsblk` before/after) |
| `-Config <file>` | `--config` | `01-install-huronos.sh`'s own default |
| `-Password <pass>` | `--password` | `01-install-huronos.sh`'s own default (`toor`) |
| `-Url <url>` | `--url` | `01-install-huronos.sh`'s own default |
| `-Wallpaper <img>` | `--wallpaper` | `01-install-huronos.sh`'s own default |
| `-Distro <name>` | which WSL distro to run in | the default distro from `wsl -l -q` |
| `-Yes` | `--yes` | off |

**Steps:**

1. **Prerequisite check (idempotent):**
   - `wsl --status` → if WSL isn't installed, run `wsl --install`, print that
     a reboot/re-login is required, and **stop** (a fresh WSL install
     requires a restart before it's usable; the script does not attempt to
     work around this).
   - Check for `usbipd-win` (e.g. `winget list --id dorssel.usbipd-win`) →
     if missing, `winget install --id dorssel.usbipd-win -e`.
   - Does **not** duplicate package installation inside WSL
     (`squashfs-tools`, `parted`, etc.) — `01-install-huronos.sh` Step 1/9
     already detects and installs those itself via `apt`/`dnf`/`pacman`.

2. **USB selection:** run `usbipd.exe list`, print the table. If `-BusId`
   wasn't given, prompt interactively (same UX pattern as
   `01-install-huronos.sh` prompting when multiple `.hdf` files exist).
   Cross-check the selected device against `Get-PhysicalDisk`/`Get-Disk` and
   warn if it doesn't look removable — mirrors the existing root-disk safety
   check in `01-install-huronos.sh`.

3. **Bind + attach:** detect elevation
   (`[Security.Principal.WindowsPrincipal]::...IsInRole(Administrator)`); if
   not elevated, re-launch just the `usbipd bind --busid <id>` call via
   `Start-Process -Verb RunAs` (triggers **one** UAC prompt — a human must
   click "Yes"; this is documented, not hidden). Then
   `usbipd attach --wsl --busid <id>` (does not require elevation).

4. **Confirm attach inside WSL:** short bounded retry loop (not a long
   `sleep`) polling `wsl -d <Distro> -- lsblk -o NAME,SIZE,RM,MOUNTPOINT`
   until the new block device appears.

5. **Run the installer:** `wsl -d <Distro> -- bash -c "cd <repo-path-under-/mnt/c/...> && bash 01-install-huronos.sh --device /dev/<name> --config ... --password ... --url ... --wallpaper ... --yes"`, streaming output live to the PowerShell console. Exit code propagates.

### 2. `AGENTS.md` — new section "Windows / WSL2 Deployment (usbipd-win)"

Teaches a fresh Claude session (no memory of this conversation) how to
handle "install this on a USB" when invoked from a Windows context:

- **Environment detection:** check `$env:WSL_DISTRO_NAME` / `uname -r`
  containing `microsoft` (already inside WSL — `usbipd.exe` is reachable via
  WSL→Windows interop) vs. native PowerShell (`$PSVersionTable`).
- **Elevation gotcha, explicit:** if `00-setup-windows-wsl.ps1` needs to
  elevate for `bind`, Claude must pause and ask the human to approve the UAC
  prompt — it cannot click it. Claude must confirm success by checking
  `usbipd list` shows `Attached` state, never assume success from a
  non-error exit alone.
- **Flag reuse:** cross-reference to the README's existing "Non-Interactive
  / Scripted Installation" flags table — `00-setup-windows-wsl.ps1` reuses
  those flags 1:1, nothing new to relearn.

### 3. `README.md` — new section "Installing from Windows (WSL2 + usbipd-win)"

- Prerequisites: Windows 10 2004+ / 11, admin rights once (for the UAC
  prompt).
- The one-liner example invocation.
- Short paragraph: Docker Desktop already works unmodified (privileged
  container + `usbipd`-attached `--device`) — no new image built or
  maintained for it.
- Same `[!WARNING]` about `-Yes` wiping the target device without a second
  confirmation, matching the existing Bash-side warning already in this
  file.

## Verification

- **Cannot be run end-to-end in this session** — the authoring environment
  is Linux-only, no Windows host available. This is a known limitation of
  the design process, not swept under the rug.
- Static checks to run before considering this done:
  - `PSScriptAnalyzer` against `00-setup-windows-wsl.ps1`, if available in
    the implementation environment.
  - Manual trace of every `usbipd.exe`/`wsl.exe`/`winget` invocation against
    their documented CLI syntax (no invented flags).
  - `shellcheck` is not applicable (PowerShell, not Bash) — note this
    explicitly rather than silently skipping the repo's usual QA step.
- Before relying on this for actual lab-day USB prep, the script needs a
  real test run on a Windows machine with a spare USB drive. This should be
  called out to the user as a follow-up, not implied as already covered.
