<#
.SYNOPSIS
  Writes the OpenCore EFI (build\EFI) and the macOS recovery to a USB stick.

.DESCRIPTION
  !!! ERASES THE WHOLE USB STICK !!!
  Layout (same as the tested VM boot disk):
    1. OPENCORE  300 MB  EFI System Partition  -> EFI\BOOT, EFI\OC
    2. RECOVERY  rest    FAT32                 -> com.apple.recovery.boot
  OpenCore and the recovery must be on separate partitions, otherwise OpenCore
  only finds its own BOOTx64.efi and never lists the recovery.

  Only accepts disks with BusType USB. Needs an ADMIN PowerShell.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int]$DiskNumber,
    [switch]$UpdateEfi,   # only replace EFI on partition 1 of an already prepared stick (keeps the recovery)
    [string]$Source,      # EFI folder to write (default build\EFI), e.g. build\EFI-wifi-poll
    [switch]$LogsOnly,    # with -UpdateEfi: only copy opencore-*.txt / panic-*.txt to build\usb-logs, change nothing
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this script in an ADMIN PowerShell.' }

$efi      = if ($Source) { if ([IO.Path]::IsPathRooted($Source)) { $Source } else { Join-Path $Root $Source } } else { Join-Path $Root 'build\EFI' }
Write-Host "EFI source: $efi" -ForegroundColor DarkGray
$recovery = Join-Path $Root 'build\recovery\com.apple.recovery.boot'
if (-not (Test-Path "$efi\OC\config.plist")) { throw "$efi missing - run Build-EFI.ps1 first." }
if (-not (Test-Path "$recovery\BaseSystem.dmg")) { throw 'Recovery missing - see docs/VM-TEST.md step 2 (macrecovery).' }

$disk = Get-Disk -Number $DiskNumber
if ($disk.BusType -ne 'USB') { throw "Disk $DiskNumber is '$($disk.FriendlyName)' on $($disk.BusType) - NOT a USB stick. Aborting." }
if ($disk.Size -lt 3GB) { throw 'USB stick too small (need at least 4 GB).' }

$espGuid  = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$dataGuid = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

# GPU folder for macOS (RECOVERY\gpu): RadeArc install scripts + package, run from macOS with
#   bash /Volumes/RECOVERY/gpu/install-gpu.sh
function Copy-GpuBundle([string]$letter) {
    $zip = Join-Path $Root 'build\gpu\usb\pkg\radearc-package.zip'
    if (-not (Test-Path $zip)) { Write-Host '  GPU folder skipped (no build\gpu\usb\pkg\radearc-package.zip, see docs\GPU.md)' -ForegroundColor DarkGray; return }
    $dst = "$($letter):\gpu"
    New-Item -ItemType Directory -Force "$dst\pkg" | Out-Null
    foreach ($f in 'install-gpu.sh', 'stage2.sh', 'local.radearc.stage2.plist', 'gpu-reset.sh', 'LIESMICH.txt') { Copy-Item (Join-Path $PSScriptRoot "gpu\$f") $dst -Force }
    Copy-Item $zip "$dst\pkg\" -Force
    # one double-click after a fresh install: Finder -> RECOVERY -> Hackintosh-Setup.command
    Copy-Item (Join-Path $PSScriptRoot 'gpu\Hackintosh-Setup.command') "$($letter):\" -Force
    Write-Host "  GPU folder written: $dst (install-gpu.sh, gpu-reset.sh, RadeArc package)" -ForegroundColor Cyan
}

if ($UpdateEfi) {
    $p1 = Get-Partition -DiskNumber $DiskNumber -PartitionNumber 1 -ErrorAction SilentlyContinue
    $p2 = Get-Partition -DiskNumber $DiskNumber -PartitionNumber 2 -ErrorAction SilentlyContinue
    if (-not $p1 -or -not $p2 -or $p1.GptType -ne $espGuid) { throw 'Stick is not in the expected layout - run without -UpdateEfi first.' }
    # an ESP can't reliably get a drive letter: switch to data type, copy, switch back
    Set-Partition -DiskNumber $DiskNumber -PartitionNumber 1 -GptType $dataGuid
    try {
        Add-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber 1 -AssignDriveLetter
        $l = $null
        foreach ($i in 1..30) { $l = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber 1).DriveLetter; if ($l -and $l -ne [char]0 -and (Test-Path "$($l):\")) { break }; Start-Sleep -Milliseconds 500 }
        if (-not (Test-Path "$($l):\")) { throw 'EFI partition got no drive letter.' }
        $logs = Join-Path $Root 'build\usb-logs'; New-Item -ItemType Directory -Force $logs | Out-Null
        foreach ($pat in 'opencore-*.txt', 'panic-*.txt') {
            Get-ChildItem "$($l):\" -Filter $pat -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $logs -Force; "  saved log: build\usb-logs\$($_.Name)" }
        }
        if ($LogsOnly) {
            Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber 1 -AccessPath "$($l):\" -ErrorAction SilentlyContinue
            Write-Host "`nLogs saved to build\usb-logs (EFI unchanged)." -ForegroundColor Green
            return
        }
        $before = if (Test-Path "$($l):\EFI\OC\OpenCore.efi") { 'OpenCore was present' } else { 'NO OpenCore found on the stick before the update' }
        Write-Host "  $before" -ForegroundColor Yellow
        if (Test-Path "$($l):\EFI") { Remove-Item "$($l):\EFI" -Recurse -Force }
        Copy-Item $efi "$($l):\EFI" -Recurse -Force
        Write-Host "EFI updated ($($l):): $((Get-ChildItem "$($l):\EFI" -Force).Name -join ', ')" -ForegroundColor Cyan
        Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber 1 -AccessPath "$($l):\" -ErrorAction SilentlyContinue
    } finally {
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber 1 -GptType $espGuid
    }
    $p2l = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber 2).DriveLetter
    if (-not $p2l -or $p2l -eq [char]0) {
        Add-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber 2 -AssignDriveLetter -ErrorAction SilentlyContinue
        foreach ($i in 1..20) { $p2l = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber 2).DriveLetter; if ($p2l -and $p2l -ne [char]0 -and (Test-Path "$($p2l):\")) { break }; Start-Sleep -Milliseconds 500 }
    }
    if ($p2l -and $p2l -ne [char]0) { Copy-GpuBundle $p2l } else { Write-Host '  RECOVERY partition has no drive letter - GPU folder skipped' -ForegroundColor Yellow }
    Write-Host "`nUSB stick EFI updated. Boot from it again (ASUS boot menu: F8)." -ForegroundColor Green
    return
}

Write-Host "`nTARGET: disk $DiskNumber  '$($disk.FriendlyName)'  $([math]::Round($disk.Size/1GB,1)) GB  (USB)" -ForegroundColor Yellow
Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue |
    ForEach-Object { "  current volume: $($_.DriveLetter): '$($_.FileSystemLabel)'" }
Write-Host 'EVERYTHING on this stick will be DELETED.' -ForegroundColor Red
$answer = Read-Host "Type the disk number ($DiskNumber) again to continue"
if ($answer -ne "$DiskNumber") { throw 'Not confirmed - nothing was changed.' }

function Wait-DriveLetter([int]$partNo) {
    foreach ($i in 1..30) {
        $l = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber $partNo).DriveLetter
        if ($l -and $l -ne [char]0 -and (Test-Path "$($l):\")) { return $l }
        Start-Sleep -Milliseconds 500
    }
    throw "Partition $partNo got no drive letter."
}

$style = (Get-Disk -Number $DiskNumber).PartitionStyle
if ($style -ne 'RAW') { Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false }
# USB sticks often stay "initialized" (MBR) after Clear-Disk, so convert instead of initializing
$style = (Get-Disk -Number $DiskNumber).PartitionStyle
if ($style -eq 'RAW') { Initialize-Disk -Number $DiskNumber -PartitionStyle GPT }
elseif ($style -ne 'GPT') { Set-Disk -Number $DiskNumber -PartitionStyle GPT }

$efiPart = New-Partition -DiskNumber $DiskNumber -Size 300MB -AssignDriveLetter
Format-Volume -Partition $efiPart -FileSystem FAT32 -NewFileSystemLabel OPENCORE -Confirm:$false | Out-Null
$efiLetter = Wait-DriveLetter $efiPart.PartitionNumber
Copy-Item $efi "$($efiLetter):\EFI" -Recurse -Force

$recPart = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $recPart -FileSystem FAT32 -NewFileSystemLabel RECOVERY -Confirm:$false | Out-Null
$recLetter = Wait-DriveLetter $recPart.PartitionNumber
Write-Host 'Copying recovery (~1 GB) ...' -ForegroundColor Cyan
Copy-Item $recovery "$($recLetter):\" -Recurse -Force
Copy-GpuBundle $recLetter

Write-Host "OPENCORE ($($efiLetter):): $((Get-ChildItem "$($efiLetter):\EFI" -Force).Name -join ', ')" -ForegroundColor Cyan
Write-Host "RECOVERY ($($recLetter):): $((Get-ChildItem "$($recLetter):\com.apple.recovery.boot").Name -join ', ')" -ForegroundColor Cyan

# make partition 1 a real EFI System Partition (drops its drive letter)
Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "$($efiLetter):\" -ErrorAction SilentlyContinue
Set-Partition -DiskNumber $DiskNumber -PartitionNumber $efiPart.PartitionNumber -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

Write-Host "`nUSB stick is ready. Boot the PC from it (ASUS boot menu: F8)." -ForegroundColor Green
