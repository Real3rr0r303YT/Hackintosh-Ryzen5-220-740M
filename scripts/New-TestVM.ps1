<#
.SYNOPSIS
  Creates a VirtualBox VM that boots our OpenCore EFI (build\EFI-VM) to test
  the AMD patches and the boot chain before touching the real PC.

.DESCRIPTION
  - Builds a small FAT32 boot disk (build\vm\OpenCore.vhd) with the EFI and,
    if present, the macOS recovery from build\recovery\com.apple.recovery.boot
  - Creates the VM "Hackintosh-Test" with an empty 80 GB macOS disk

  Needs an ADMIN PowerShell (diskpart is used to format the boot disk).
  Run Build-EFI.ps1 -Target VM first.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\New-TestVM.ps1
#>
[CmdletBinding()]
param(
    [string]$VMName = 'Hackintosh-Test',
    [int]$DiskGB = 80,
    [int]$MemoryMB = 8192,
    [int]$Cpus = 4,
    [switch]$Recreate,       # delete an existing VM with the same name first
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

# ---------------------------------------------------------------- existing VM
$exists = (& $vbox list vms) -match "^`"$([regex]::Escape($VMName))`""
if ($exists) {
    if (-not $Recreate) { throw "VM '$VMName' already exists. Use -Recreate to delete and rebuild it." }
    & $vbox unregistervm $VMName --delete
}
if (Test-Path $ocVhd) { & $vbox closemedium disk $ocVhd 2>$null; Remove-Item $ocVhd -Force }

# ---------------------------------------------------------------- boot disk
$letter = [char[]](68..90) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -Last 1
$sizeMB = if (Test-Path $recovery) { 3072 } else { 512 }
$dp = Join-Path $vmDir 'diskpart.txt'
@"
create vdisk file="$ocVhd" maximum=$sizeMB type=expandable
select vdisk file="$ocVhd"
attach vdisk
convert gpt
create partition efi
format fs=fat32 quick label=OPENCORE
assign letter=$letter
"@ | Set-Content $dp -Encoding ASCII
diskpart /s $dp | Out-Null
try {
    Copy-Item (Join-Path $Root 'build\EFI-VM') "$($letter):\EFI" -Recurse -Force
    if (Test-Path $recovery) { Copy-Item $recovery "$($letter):\" -Recurse -Force }
    Write-Host "Boot disk contents:" -ForegroundColor Cyan
    Get-ChildItem "$($letter):\" | ForEach-Object { "  $($_.Name)" }
} finally {
    "select vdisk file=`"$ocVhd`"`ndetach vdisk" | Set-Content $dp -Encoding ASCII
    diskpart /s $dp | Out-Null
    Remove-Item $dp -Force
}

# ---------------------------------------------------------------- VM
& $vbox createvm --name $VMName --ostype MacOS_64 --basefolder $vmDir --register | Out-Null
& $vbox modifyvm $VMName --firmware efi --memory $MemoryMB --cpus $Cpus --chipset ich9 `
    --graphicscontroller vmsvga --vram 128 --usbxhci on --mouse usbtablet --keyboard usb `
    --audio-enabled off --rtc-use-utc on --nic1 nat --nictype1 82545EM
& $vbox storagectl $VMName --name SATA --add sata --controller IntelAhci --portcount 2 --hostiocache on
if (-not (Test-Path $macVdi)) { & $vbox createmedium disk --filename $macVdi --size ($DiskGB * 1024) --format VDI | Out-Null }
& $vbox storageattach $VMName --storagectl SATA --port 0 --device 0 --type hdd --medium $ocVhd
& $vbox storageattach $VMName --storagectl SATA --port 1 --device 0 --type hdd --medium $macVdi

Write-Host "`nVM '$VMName' created. Start it in VirtualBox; OpenCore should show its boot picker." -ForegroundColor Green
