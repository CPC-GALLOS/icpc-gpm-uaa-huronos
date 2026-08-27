<#
.SYNOPSIS
  Windows bootstrap for icpc-gpm-uaa-huronos: sets up WSL2 + usbipd-win,
  attaches a physical USB drive to WSL, and runs 01-install-huronos.sh.
.DESCRIPTION
  See README.md "Installing from Windows (WSL2 + usbipd-win)" and
  docs/superpowers/specs/2026-08-27-windows-wsl-usbipd-install-design.md
  for the full design. This script does NOT reimplement dependency
  installation inside WSL -- 01-install-huronos.sh already handles that
  (squashfs-tools, parted, mkfs.vfat, mkfs.ext4, perl via apt/dnf/pacman).
.EXAMPLE
  .\00-setup-windows-wsl.ps1 -BusId 2-3 -Config icpc-gpm-2026-3rd-date.hdf -Password cpcgallos -Yes
#>
[CmdletBinding()]
param(
    [string]$BusId,
    [string]$Device,
    [string]$Config = "icpc-gpm-2026-3rd-date.hdf",
    [string]$Password,
    [string]$Url,
    [string]$Wallpaper,
    [string]$Distro,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-Wsl {
    param([Parameter(ValueFromRemainingArguments)][string[]]$WslArgs)
    if ($Distro) {
        & wsl.exe -d $Distro @WslArgs
    } else {
        & wsl.exe @WslArgs
    }
}

function Test-WslInstalled {
    & wsl.exe --status *> $null
    return $LASTEXITCODE -eq 0
}

# NOTE: "dorssel.usbipd-win" is the winget package ID for usbipd-win
# (https://github.com/dorssel/usbipd-win) as of this writing. This has not
# been verified against a real Windows machine in this session -- confirm
# with `winget search usbipd` before relying on this in production.
function Test-UsbipdInstalled {
    $listed = & winget list --id dorssel.usbipd-win -e 2>&1
    return ($listed -join "`n") -match "dorssel\.usbipd-win"
}

# Guards against the common first-run failure where a command was just
# installed (via wsl --install or winget install) but the current
# PowerShell process's PATH hasn't refreshed yet.
function Assert-CommandAvailable {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "'$Name' was not found on PATH. $Hint"
        exit 1
    }
}

Write-Host "==============================================="
Write-Host " huronOS Windows Installer Bootstrap"
Write-Host "==============================================="

if (-not (Test-WslInstalled)) {
    Write-Host "WSL is not installed. Installing (this requires a reboot/re-login)..."
    & wsl.exe --install
    Write-Host "WSL installation started. Reboot or re-login, then re-run this script."
    exit 0
}

if (-not (Test-UsbipdInstalled)) {
    Write-Host "usbipd-win not found. Installing via winget..."
    & winget install --id dorssel.usbipd-win -e --accept-package-agreements --accept-source-agreements
    Write-Host "usbipd-win installed. If the 'usbipd' command isn't found next, open a new PowerShell window and re-run this script (PATH needs to refresh)."
}

Assert-CommandAvailable -Name "usbipd" -Hint "usbipd-win was just installed or is already present, but this PowerShell session's PATH hasn't picked it up. Close this window, open a new PowerShell prompt, and re-run this script."
Assert-CommandAvailable -Name "wsl.exe" -Hint "WSL should already be installed at this point. Try 'wsl --status' manually to diagnose."

# --- USB selection -----------------------------------------------------------
function Get-UsbipdDevice {
    $raw = & usbipd list 2>&1
    $devices = @()
    $inConnected = $false
    foreach ($line in $raw) {
        if ($line -match '^Connected:') { $inConnected = $true; continue }
        if ($line -match '^Persisted:') { $inConnected = $false; continue }
        if ($inConnected -and $line -match '^(?<busid>\d+-\d+)\s+(?<vidpid>[0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s+(?<device>.{1,60}?)\s{2,}(?<state>\S.*)$') {
            $devices += [PSCustomObject]@{
                BusId  = $Matches.busid
                VidPid = $Matches.vidpid
                Device = $Matches.device.Trim()
                State  = $Matches.state.Trim()
            }
        }
    }
    return $devices
}

if (-not $BusId) {
    $devices = Get-UsbipdDevice
    if ($devices.Count -eq 0) {
        Write-Error "No USB devices found via 'usbipd list'. Plug in the target USB drive and retry."
        exit 1
    }
    Write-Host ""
    Write-Host "Connected USB devices:"
    $i = 1
    foreach ($d in $devices) {
        Write-Host ("  [{0}] {1}  {2}  ({3})  [{4}]" -f $i, $d.BusId, $d.Device, $d.VidPid, $d.State)
        $i++
    }
    $selection = Read-Host "Select the target USB drive (1-$($devices.Count))"
    $idx = 0
    if (-not [int]::TryParse($selection, [ref]$idx) -or $idx -lt 1 -or $idx -gt $devices.Count) {
        Write-Error "Invalid selection: '$selection'"
        exit 1
    }
    $BusId = $devices[$idx - 1].BusId
}

Write-Host "Selected BUSID: $BusId"

# Best-effort safety check: warn if Windows doesn't see any USB-attached
# physical disk at all (mirrors the spirit of 01-install-huronos.sh's
# root-disk safety check -- this can't be as precise from the Windows side
# since the disk isn't a Windows volume yet, but it catches "no USB disk
# plugged in at all").
try {
    $usbDisks = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'USB' }
    if ($usbDisks.Count -eq 0) {
        Write-Warning "Windows doesn't currently see any USB-attached physical disk. Double-check '$BusId' is really your target USB drive before continuing."
    }
} catch {
    Write-Warning "Safety check for removable disk failed to run: $_"
}

if (-not $Yes) {
    $confirm = Read-Host "This will ERASE the drive at BUSID $BusId once attached to WSL. Continue? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Aborted."
        exit 0
    }
}

# --- Bind + attach -------------------------------------------------------
Write-Host "Binding $BusId (requires Administrator -- a UAC prompt may appear; a human must approve it)..."
if (-not (Test-Admin)) {
    $bindProc = Start-Process usbipd -ArgumentList "bind --busid $BusId" -Verb RunAs -PassThru -Wait
    if ($bindProc.ExitCode -ne 0) {
        Write-Error "usbipd bind failed or the UAC prompt was cancelled (exit code $($bindProc.ExitCode)). A human must approve the elevation prompt for this to proceed."
        exit 1
    }
} else {
    & usbipd bind --busid $BusId
}

Write-Host "Attaching $BusId to WSL..."
# NOTE: "--distribution" is the flag name usbipd-win's docs use for
# selecting a non-default WSL distro on "attach --wsl". Not verified
# against a real Windows machine in this session -- confirm with
# `usbipd attach --help` before relying on -Distro in production.
if ($Distro) {
    & usbipd attach --wsl --busid $BusId --distribution $Distro
} else {
    & usbipd attach --wsl --busid $BusId
}

Start-Sleep -Seconds 2
$stateLine = ((& usbipd list) | Select-String -Pattern ([regex]::Escape($BusId)))
if ($stateLine -notmatch 'Attached') {
    Write-Error "Device $BusId did not reach 'Attached' state after 'usbipd attach'. Current line: $stateLine"
    exit 1
}
Write-Host "Confirmed: $BusId is Attached."

# --- Confirm the device appears inside WSL --------------------------------
function Get-WslBlockDevice {
    (Invoke-Wsl bash -c "lsblk -dno NAME" | Out-String) -split "`r?`n" | Where-Object { $_ -match '\S' }
}

if (-not $Device) {
    Write-Host "Detecting the new block device inside WSL..."
    $before = Get-WslBlockDevice
    $maxAttempts = 10
    $found = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Start-Sleep -Seconds 2
        $after = Get-WslBlockDevice
        $new = $after | Where-Object { $before -notcontains $_ }
        if ($new) { $found = ($new | Select-Object -First 1); break }
    }
    if (-not $found) {
        Write-Error "Timed out after $maxAttempts attempts waiting for the attached USB to appear as a block device inside WSL. Run 'wsl lsblk' manually to check, then re-run with -Device <name>."
        exit 1
    }
    $Device = $found
}

Write-Host "Target device inside WSL: /dev/$Device"

# --- Run the installer -----------------------------------------------------
$installArgs = @("--device", "/dev/$Device", "--config", $Config)
if ($Password)  { $installArgs += @("--password", $Password) }
if ($Url)       { $installArgs += @("--url", $Url) }
if ($Wallpaper) { $installArgs += @("--wallpaper", $Wallpaper) }
if ($Yes)       { $installArgs += "--yes" }

$argString = ($installArgs | ForEach-Object { "'$_'" }) -join ' '
$wslRepoPath = ((& wsl.exe wslpath -a "$RepoRoot") | Out-String).Trim()
$cmd = "cd '$wslRepoPath' && bash 01-install-huronos.sh $argString"

Write-Host ""
Write-Host "==============================================="
Write-Host " Running installer inside WSL..."
Write-Host "==============================================="
Invoke-Wsl bash -c $cmd
exit $LASTEXITCODE
