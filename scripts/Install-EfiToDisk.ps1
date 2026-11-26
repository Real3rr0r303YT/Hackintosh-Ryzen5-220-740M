<#
.SYNOPSIS
  Installs OpenCore (EFI\OC from a build folder) onto the INTERNAL EFI System Partition next to Windows,
  and adds a UEFI boot entry "OpenCore" that starts first. No USB stick needed afterwards.

.DESCRIPTION
  - Touches only \EFI\OC on the ESP. \EFI\Microsoft and \EFI\Boot (Windows) stay as they are.
  - Backs up the whole ESP first to build\esp-backup-<date>.
  - Boot entry via bcdedit: {fwbootmgr} gets "OpenCore" (\EFI\OC\OpenCore.efi) first, Windows Boot Manager stays
    in the list. OpenCore's picker shows macOS and Windows.
  - Undo: powershell -File scripts\Install-EfiToDisk.ps1 -Remove   (deletes \EFI\OC and the boot entry)

  ADMIN PowerShell required.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\Install-EfiToDisk.ps1 -Source build\EFI-GPU-accel
#>
[CmdletBinding()]
param(
    [string]$Source = 'build\EFI-GPU-accel',
    [switch]$Remove,
    [string]$Root
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this script in an ADMIN PowerShell.' }

$label = 'OpenCore'
function Get-OcEntry {
    # bcdedit /enum firmware lists every UEFI boot entry; find ours by its description
    $cur = $null
    foreach ($line in (bcdedit /enum firmware)) {
        if ($line -match '^identifier\s+(\{[0-9a-fA-F-]+\})') { $cur = $Matches[1] }
        if ($line -match "^description\s+$label$" -and $cur) { return $cur }
    }
    return $null
}

# mount the ESP of the system disk on a free letter
$letter = 'S'
while (Test-Path "$($letter):\") { $letter = [char]([int][char]$letter + 1) }
mountvol "$($letter):" /s
if (-not (Test-Path "$($letter):\EFI\Microsoft")) { mountvol "$($letter):" /d; throw "ESP mounted at $($letter): has no EFI\Microsoft - not the Windows ESP, aborting." }
$esp = "$($letter):"
try {
    if ($Remove) {
        if (Test-Path "$esp\EFI\OC") { Remove-Item "$esp\EFI\OC" -Recurse -Force; "removed $esp\EFI\OC" }
        $id = Get-OcEntry
        if ($id) { bcdedit /delete $id | Out-Null; "removed boot entry $id" }
        Write-Host 'OpenCore removed from the internal disk. Windows boots as before.' -ForegroundColor Green
        return
    }

    $src = if ([IO.Path]::IsPathRooted($Source)) { $Source } else { Join-Path $Root $Source }
    if (-not (Test-Path "$src\OC\OpenCore.efi")) { throw "$src\OC\OpenCore.efi missing - build it first." }

    # space check (OC folder + 5 MB margin)
    $need = (Get-ChildItem "$src\OC" -Recurse -File | Measure-Object Length -Sum).Sum + 5MB
    $vol = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter -eq $esp }
    $old = if (Test-Path "$esp\EFI\OC") { (Get-ChildItem "$esp\EFI\OC" -Recurse -File | Measure-Object Length -Sum).Sum } else { 0 }
    if ($vol -and ($vol.FreeSpace + $old) -lt $need) { throw ("ESP too small: need {0:N0} MB, free {1:N0} MB." -f ($need/1MB), (($vol.FreeSpace + $old)/1MB)) }

    # full backup of the ESP
    $bak = Join-Path $Root ("build\esp-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $bak | Out-Null
    # the running Windows keeps \EFI\Microsoft\Boot\BCD locked: copy file by file, export the BCD store instead
    $skipped = 0
    Get-ChildItem "$esp\" -Recurse -Force -File | ForEach-Object {
        $dst = Join-Path $bak $_.FullName.Substring($esp.Length + 1)
        New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
        try { Copy-Item $_.FullName $dst -Force -ErrorAction Stop } catch { $skipped++ }
    }
    bcdedit /export (Join-Path $bak 'BCD-export') | Out-Null
    "ESP backup: $bak  (locked files skipped: $skipped, BCD exported to BCD-export)"

    if (Test-Path "$esp\EFI\OC") { Remove-Item "$esp\EFI\OC" -Recurse -Force }
    Copy-Item "$src\OC" "$esp\EFI\OC" -Recurse -Force
    "copied $src\OC -> $esp\EFI\OC"

    $id = Get-OcEntry
    if (-not $id) {
        $out = bcdedit /copy '{bootmgr}' /d $label
        if ($out -notmatch '(\{[0-9a-fA-F-]+\})') { throw "bcdedit /copy failed: $out" }
        $id = $Matches[1]
    }
    bcdedit /set $id device "partition=$esp" | Out-Null
    bcdedit /set $id path '\EFI\OC\OpenCore.efi' | Out-Null
    bcdedit /set '{fwbootmgr}' displayorder $id /addfirst | Out-Null
    "boot entry $label = $id (first in the firmware boot order)"
    Write-Host "`nDone. Restart: the PC starts OpenCore from the SSD (no stick). Pick macOS or Windows there." -ForegroundColor Green
    Write-Host "Undo: powershell -ExecutionPolicy Bypass -File scripts\Install-EfiToDisk.ps1 -Remove" -ForegroundColor DarkGray
} finally {
    mountvol $esp /d
}
