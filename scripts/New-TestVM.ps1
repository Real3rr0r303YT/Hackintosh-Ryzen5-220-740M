<#
.SYNOPSIS
  Creates a VirtualBox VM that boots our OpenCore EFI (build\EFI-VM) to test
  the AMD patches and the boot chain before touching the real PC.

.DESCRIPTION
  - Builds a small FAT32 boot disk (build\vm\OpenCore.vhd) with the EFI and,
    if present, the macOS recovery from build\recovery\com.apple.recovery.boot
  - Creates the VM "Hackintosh-Test" with an empty 80 GB macOS disk

  -UpdateEfi rebuilds only the boot disk (after Build-EFI.ps1 -Target VM),
  the VM and the macOS disk stay as they are.

  Needs an ADMIN PowerShell (diskpart is used to format the boot disk).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\New-TestVM.ps1
  powershell -ExecutionPolicy Bypass -File scripts\New-TestVM.ps1 -UpdateEfi
#>
[CmdletBinding()]
param(
    [string]$VMName = 'Hackintosh-Test',
    [int]$DiskGB = 80,
    [int]$MemoryMB = 8192,
    [int]$Cpus = 4,
    [switch]$Recreate,       # delete an existing VM with the same name first
    [switch]$UpdateEfi,      # only rebuild the OpenCore boot disk of the existing VM
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path $vbox)) { throw 'VirtualBox not found.' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this script in an ADMIN PowerShell (needed for diskpart).' }

$recovery = Join-Path $Root 'build\recovery\com.apple.recovery.boot'
$vmDir    = Join-Path $Root 'build\vm'
$ocVhd    = Join-Path $vmDir 'OpenCore.vhd'
$macVdi   = Join-Path $vmDir 'macOS.vdi'
New-Item -ItemType Directory -Force $vmDir | Out-Null

if (-not (Test-Path (Join-Path $Root 'build\EFI-VM\OC\config.plist'))) { throw 'build\EFI-VM missing - run Build-EFI.ps1 -Target VM first.' }
if (-not (Test-Path $recovery)) { Write-Warning "No macOS recovery in $recovery - the VM will only reach the OpenCore picker." }

$dpLog = Join-Path $vmDir 'diskpart.log'
function Invoke-Diskpart([string]$script) {
    $dp = Join-Path $vmDir 'diskpart.txt'
    $script | Set-Content $dp -Encoding ASCII
    "---- $(Get-Date -Format s)`n$script" | Add-Content $dpLog
    diskpart /s $dp 2>&1 | Add-Content $dpLog
    Remove-Item $dp -Force
}

function Wait-DriveLetter([int]$diskNo, [int]$partNo) {
    foreach ($i in 1..30) {
        $l = (Get-Partition -DiskNumber $diskNo -PartitionNumber $partNo).DriveLetter
        if ($l -and $l -ne [char]0 -and (Test-Path "$($l):\")) { return $l }
        Start-Sleep -Milliseconds 500
    }
    throw "Partition $partNo got no drive letter (see build\vm\diskpart.log)."
}

# Creates a fresh FAT32 boot disk. Windows won't reliably give an EFI-type
# partition a drive letter, so: create a normal data partition, copy the files,
# THEN switch the partition type to EFI System Partition.
function New-BootDisk {
    if (Test-Path $ocVhd) { & $vbox closemedium disk $ocVhd 2>$null; Remove-Item $ocVhd -Force }
    $sizeMB = if (Test-Path $recovery) { 3072 } else { 512 }
    Invoke-Diskpart "create vdisk file=`"$ocVhd`" maximum=$sizeMB type=expandable`nselect vdisk file=`"$ocVhd`"`nattach vdisk"
    try {
        $disk = $null
        foreach ($i in 1..20) { $disk = Get-DiskImage -ImagePath $ocVhd | Get-Disk -ErrorAction SilentlyContinue; if ($disk) { break }; Start-Sleep -Milliseconds 500 }
        if (-not $disk) { throw "Attached boot disk not found (see build\vm\diskpart.log)." }
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction SilentlyContinue

        # Two partitions: OpenCore on its own ESP, recovery on a separate FAT32 volume.
        # If both share one partition, OpenCore finds its own \EFI\BOOT\BOOTx64.efi there
        # and never looks at com.apple.recovery.boot.
        $hasRec = Test-Path $recovery
        $efiPart = New-Partition -DiskNumber $disk.Number -Size $(if ($hasRec) { 300MB } else { 480MB }) -AssignDriveLetter
        Format-Volume -Partition $efiPart -FileSystem FAT32 -NewFileSystemLabel OPENCORE -Confirm:$false | Out-Null
        $efiLetter = Wait-DriveLetter $disk.Number $efiPart.PartitionNumber
        Copy-Item (Join-Path $Root 'build\EFI-VM') "$($efiLetter):\EFI" -Recurse -Force

        if ($hasRec) {
            $recPart = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $recPart -FileSystem FAT32 -NewFileSystemLabel RECOVERY -Confirm:$false | Out-Null
            $recLetter = Wait-DriveLetter $disk.Number $recPart.PartitionNumber
            Copy-Item $recovery "$($recLetter):\" -Recurse -Force
            Write-Host "Recovery partition ($($recLetter):): $((Get-ChildItem "$($recLetter):\com.apple.recovery.boot").Name -join ', ')" -ForegroundColor Cyan
            Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $recPart.PartitionNumber -AccessPath "$($recLetter):\" -ErrorAction SilentlyContinue
        }
        Write-Host "EFI partition ($($efiLetter):): $((Get-ChildItem "$($efiLetter):\EFI").Name -join ', ')" -ForegroundColor Cyan

        # now turn the first one into a real EFI System Partition (removes the letter too)
        Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $efiPart.PartitionNumber -AccessPath "$($efiLetter):\" -ErrorAction SilentlyContinue
        Invoke-Diskpart "select disk $($disk.Number)`nselect partition $($efiPart.PartitionNumber)`nset id=c12a7328-f81f-11d2-ba4b-00a0c93ec93b override"
    } finally {
        Invoke-Diskpart "select vdisk file=`"$ocVhd`"`ndetach vdisk"
    }
}

$exists = (& $vbox list vms) -match "^`"$([regex]::Escape($VMName))`""

# ---------------------------------------------------------------- update mode
if ($UpdateEfi) {
    if (-not $exists) { throw "VM '$VMName' doesn't exist - run without -UpdateEfi first." }
    $state = (& $vbox showvminfo $VMName --machinereadable | Select-String '^VMState=').Line
    if ($state -notmatch 'poweroff|aborted|saved') { throw "Power off the VM first ($state)." }
    & $vbox storageattach $VMName --storagectl SATA --port 0 --device 0 --medium none
    New-BootDisk
    & $vbox storageattach $VMName --storagectl SATA --port 0 --device 0 --type hdd --medium $ocVhd
    & $vbox setextradata $VMName 'VBoxInternal2/EfiGraphicsResolution' '1920x1080'
    Write-Host "`nBoot disk of '$VMName' rebuilt with the current build\EFI-VM." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------- existing VM
if ($exists) {
    if (-not $Recreate) { throw "VM '$VMName' already exists. Use -UpdateEfi to refresh the EFI, or -Recreate to rebuild everything." }
    & $vbox unregistervm $VMName --delete
}

New-BootDisk

# ---------------------------------------------------------------- VM
& $vbox createvm --name $VMName --ostype MacOS_64 --basefolder $vmDir --register | Out-Null
& $vbox modifyvm $VMName --firmware efi --memory $MemoryMB --cpus $Cpus --chipset ich9 `
    --graphicscontroller vmsvga --vram 128 --usbxhci on --mouse usbtablet --keyboard ps2 `
    --audio-enabled off --rtc-use-utc on --nic1 nat --nictype1 82545EM
& $vbox storagectl $VMName --name SATA --add sata --controller IntelAhci --portcount 2 --hostiocache on
if (-not (Test-Path $macVdi)) { & $vbox createmedium disk --filename $macVdi --size ($DiskGB * 1024) --format VDI | Out-Null }
& $vbox storageattach $VMName --storagectl SATA --port 0 --device 0 --type hdd --medium $ocVhd
& $vbox storageattach $VMName --storagectl SATA --port 1 --device 0 --type hdd --medium $macVdi
& $vbox setextradata $VMName 'VBoxInternal2/EfiGraphicsResolution' '1920x1080'

Write-Host "`nVM '$VMName' created. Start it in VirtualBox; OpenCore should show its boot picker." -ForegroundColor Green
