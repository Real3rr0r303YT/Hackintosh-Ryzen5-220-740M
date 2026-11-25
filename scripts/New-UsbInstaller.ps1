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
        Get-ChildItem "$($l):\" -Filter 'opencore-*.txt' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $logs -Force; "  saved log: build\usb-logs\$($_.Name)" }
        $before = if (Test-Path "$($l):\EFI\OC\OpenCore.efi") { 'OpenCore was present' } else { 'NO OpenCore found on the stick before the update' }
        Write-Host "  $before" -ForegroundColor Yellow
        if (Test-Path "$($l):\EFI") { Remove-Item "$($l):\EFI" -Recurse -Force }
        Copy-Item $efi "$($l):\EFI" -Recurse -Force
        Write-Host "EFI updated ($($l):): $((Get-ChildItem "$($l):\EFI" -Force).Name -join ', ')" -ForegroundColor Cyan
        Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber 1 -AccessPath "$($l):\" -ErrorAction SilentlyContinue
    } finally {
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber 1 -GptType $espGuid
    }
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

Write-Host "OPENCORE ($($efiLetter):): $((Get-ChildItem "$($efiLetter):\EFI" -Force).Name -join ', ')" -ForegroundColor Cyan
Write-Host "RECOVERY ($($recLetter):): $((Get-ChildItem "$($recLetter):\com.apple.recovery.boot").Name -join ', ')" -ForegroundColor Cyan

# make partition 1 a real EFI System Partition (drops its drive letter)
Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "$($efiLetter):\" -ErrorAction SilentlyContinue
Set-Partition -DiskNumber $DiskNumber -PartitionNumber $efiPart.PartitionNumber -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

Write-Host "`nUSB stick is ready. Boot the PC from it (ASUS boot menu: F8)." -ForegroundColor Green
