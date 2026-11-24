<#
.SYNOPSIS
  Builds a ready-to-boot OpenCore EFI for the ASUS V500 (Ryzen 5 220 / Radeon 740M).

.DESCRIPTION
  1. Downloads all pinned components (scripts/Fetch-EFI.ps1)
  2. Generates config.plist from OpenCore's Sample.plist:
     AMD Vanilla patches (6 cores), Zen quirks, kexts, drivers, SSDTs, boot-args
  3. Fills in SMBIOS from smbios.local.json (personal, git-ignored)
  4. Validates with ocvalidate

  -Target Hardware : full EFI for the real PC        -> build\EFI
  -Target VM       : minimal EFI for a VirtualBox VM -> build\EFI-VM

  Also writes EFI\OC\config.sample.plist (placeholders only) for the repo.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -NewSmbios
#>
[CmdletBinding()]
param(
    [ValidateSet('Hardware', 'VM')] [string]$Target = 'Hardware',
    [switch]$NewSmbios,      # generate smbios.local.json if it doesn't exist yet
    [switch]$SkipFetch,      # reuse build\EFI from a previous fetch
    [int]$Cores = 6,         # physical cores of the Ryzen 5 220
    [int]$AlcLayout = 11,    # AppleALC layout-id for ALC897 (try 12, 13, 21, 23, 66 … if no sound)
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$tools = Join-Path $Root 'build\tools'

# ---------------------------------------------------------------- 1. fetch
if (-not $SkipFetch) { & (Join-Path $PSScriptRoot 'Fetch-EFI.ps1') -Root $Root }
$fetched = Join-Path $Root 'build\EFI'
$outEfi  = if ($Target -eq 'VM') { Join-Path $Root 'build\EFI-VM' } else { $fetched }
if ($outEfi -ne $fetched) {
    if (Test-Path $outEfi) { Remove-Item $outEfi -Recurse -Force }
    Copy-Item $fetched $outEfi -Recurse
}

# ---------------------------------------------------------------- plist helpers
[xml]$doc = Get-Content (Join-Path $tools 'Sample.plist') -Raw
$doc.PreserveWhitespace = $false
$top = $doc.SelectSingleNode('/plist/dict')

function Get-Val([Xml.XmlElement]$dict, [string]$path) {
    $node = $dict
    foreach ($k in $path.Split('/')) {
        $key = $node.SelectSingleNode("key[.='$k']")
        if (-not $key) { throw "plist key not found: $path (at '$k')" }
        $node = $key.NextSibling
        while ($node.NodeType -ne 'Element') { $node = $node.NextSibling }
    }
    return $node
}

function New-ValNode($value) {
    if ($value -is [bool])        { return $doc.CreateElement($(if ($value) { 'true' } else { 'false' })) }
    if ($value -is [int] -or $value -is [long]) { $e = $doc.CreateElement('integer'); $e.InnerText = "$value"; return $e }
    if ($value -is [byte[]])      { $e = $doc.CreateElement('data');    $e.InnerText = [Convert]::ToBase64String($value); return $e }
    if ($value -is [Xml.XmlNode]) { return $value }
    if ($value -is [Collections.IDictionary]) { return (New-Dict $value) }
    $e = $doc.CreateElement('string'); $e.InnerText = "$value"; return $e
}

function New-Dict([Collections.IDictionary]$h) {
    $d = $doc.CreateElement('dict')
    foreach ($k in $h.Keys) {
        $ke = $doc.CreateElement('key'); $ke.InnerText = $k
        [void]$d.AppendChild($ke); [void]$d.AppendChild((New-ValNode $h[$k]))
    }
    return $d
}

# Set a value; creates the key if missing. $path = "Kernel/Quirks/ProvideCurrentCpuInfo"
function Set-Val([string]$path, $value) {
    $parts  = $path.Split('/')
    $parent = if ($parts.Count -gt 1) { Get-Val $top ($parts[0..($parts.Count - 2)] -join '/') } else { $top }
    $leaf   = $parts[-1]
    $new    = New-ValNode $value
    $key    = $parent.SelectSingleNode("key[.='$leaf']")
    if ($key) {
        $old = $key.NextSibling; while ($old.NodeType -ne 'Element') { $old = $old.NextSibling }
        [void]$parent.ReplaceChild($new, $old)
    } else {
        $ke = $doc.CreateElement('key'); $ke.InnerText = $leaf
        [void]$parent.AppendChild($ke); [void]$parent.AppendChild($new)
    }
}

function Clear-Node([string]$path) { $n = Get-Val $top $path; $n.RemoveAll() }
function Add-Item([string]$path, $value) { [void](Get-Val $top $path).AppendChild((New-ValNode $value)) }
# leading comma: return the byte[] as ONE object (PowerShell would otherwise unroll it to object[])
function AsciiBytes([string]$s) { , [byte[]][Text.Encoding]::ASCII.GetBytes($s) }
function HexBytes([string]$s)   { , [byte[]]($s -split '(..)' -ne '' | ForEach-Object { [Convert]::ToByte($_, 16) }) }
# DirectoryInfo.BaseName keeps the extension on PS 5.1, so strip it ourselves
function KextName($dir) { $dir.Name -replace '\.kext$', '' }

# ---------------------------------------------------------------- 2. config
# --- ACPI
Clear-Node 'ACPI/Add'; Clear-Node 'ACPI/Delete'; Clear-Node 'ACPI/Patch'
foreach ($aml in Get-ChildItem (Join-Path $outEfi 'OC\ACPI') -Filter *.aml) {
    Add-Item 'ACPI/Add' ([ordered]@{ Comment = $aml.BaseName; Enabled = $true; Path = $aml.Name })
}

# --- Booter (Dortania AMD Zen, 2020+ firmware)
Clear-Node 'Booter/MmioWhitelist'; Clear-Node 'Booter/Patch'
$bq = [ordered]@{
    AvoidRuntimeDefrag = $true; DevirtualiseMmio = $false; EnableSafeModeSlide = $true
    EnableWriteUnprotector = $false; ProvideCustomSlide = $true; RebuildAppleMemoryMap = $true
    SetupVirtualMap = $false; SyncRuntimePermissions = $true; ResizeAppleGpuBars = -1
}
foreach ($k in $bq.Keys) { Set-Val "Booter/Quirks/$k" $bq[$k] }

# --- DeviceProperties
Clear-Node 'DeviceProperties/Add'; Clear-Node 'DeviceProperties/Delete'

# --- Kernel/Add  (Lilu first, then VirtualSMC, then plugins that depend on them)
$disabledOnVM = 'AppleALC', 'NVMeFix', 'BlueToolFixup', 'RealtekRTL8111', 'AMDRyzenCPUPowerManagement', 'SMCAMDProcessor', 'AirportRTW'
$order = 'Lilu', 'VirtualSMC', 'AMDRyzenCPUPowerManagement', 'SMCAMDProcessor'
$kexts = Get-ChildItem (Join-Path $outEfi 'OC\Kexts') -Directory -Filter *.kext |
         Sort-Object @{ e = { $i = [array]::IndexOf($order, (KextName $_)); if ($i -lt 0) { 99 } else { $i } } }, Name
Clear-Node 'Kernel/Add'; Clear-Node 'Kernel/Block'; Clear-Node 'Kernel/Force'
foreach ($k in $kexts) {
    [xml]$info = Get-Content (Join-Path $k.FullName 'Contents\Info.plist') -Raw
    $exeKey = $info.SelectSingleNode("/plist/dict/key[.='CFBundleExecutable']")
    $exe = if ($exeKey) { $n = $exeKey.NextSibling; while ($n.NodeType -ne 'Element') { $n = $n.NextSibling }; "Contents/MacOS/$($n.InnerText)" } else { '' }
    $enabled = -not ($Target -eq 'VM' -and $disabledOnVM -contains (KextName $k))
    Add-Item 'Kernel/Add' ([ordered]@{
        Arch = 'Any'; BundlePath = $k.Name; Comment = (KextName $k); Enabled = $enabled
        ExecutablePath = $exe; MaxKernel = ''; MinKernel = ''; PlistPath = 'Contents/Info.plist'
    })
}

# --- Kernel/Patch  (AMD Vanilla, core count patched in)
Clear-Node 'Kernel/Patch'
[xml]$vanilla = Get-Content (Join-Path $tools 'patches.plist') -Raw
$vp = $vanilla.SelectSingleNode("/plist/dict/key[.='Kernel']/following-sibling::dict[1]/key[.='Patch']/following-sibling::array[1]")
$coreHits = 0
foreach ($p in $vp.SelectNodes('dict')) {
    $imp = $doc.ImportNode($p, $true)
    $comment = $imp.SelectSingleNode("key[.='Comment']/following-sibling::string[1]").InnerText
    if ($comment -match 'cpuid_cores_per_package') {
        $rep = $imp.SelectSingleNode("key[.='Replace']/following-sibling::data[1]")
        $bytes = [Convert]::FromBase64String($rep.InnerText.Trim())
        $bytes[1] = [byte]$Cores
        $rep.InnerText = [Convert]::ToBase64String($bytes)
        $coreHits++
    }
    Add-Item 'Kernel/Patch' $imp
}
if ($coreHits -eq 0) { throw 'AMD Vanilla core-count patch not found - patches.plist format changed?' }

# --- Kernel quirks / emulate
Set-Val 'Kernel/Emulate/DummyPowerManagement' $true
$kq = [ordered]@{
    AppleCpuPmCfgLock = $false; AppleXcpmCfgLock = $false; DisableIoMapper = $false
    DisableLinkeditJettison = $true; PanicNoKextDump = $true; PowerTimeoutKernelPanic = $true
    ProvideCurrentCpuInfo = $true; XhciPortLimit = $false
}
foreach ($k in $kq.Keys) { Set-Val "Kernel/Quirks/$k" $kq[$k] }

# --- Misc
Set-Val 'Misc/Boot/HideAuxiliary' $true
Set-Val 'Misc/Boot/PickerMode' 'Builtin'
Set-Val 'Misc/Boot/ShowPicker' $true
Set-Val 'Misc/Boot/Timeout' 5
Set-Val 'Misc/Boot/PollAppleHotKeys' $true
Set-Val 'Misc/Debug/AppleDebug' $true
Set-Val 'Misc/Debug/ApplePanic' $true
Set-Val 'Misc/Debug/DisableWatchDog' $true
Set-Val 'Misc/Debug/Target' 3
Set-Val 'Misc/Security/AllowSetDefault' $true
Set-Val 'Misc/Security/BlacklistAppleUpdate' $true
Set-Val 'Misc/Security/ExposeSensitiveData' 6
Set-Val 'Misc/Security/ScanPolicy' 0
Set-Val 'Misc/Security/SecureBootModel' 'Disabled'
Set-Val 'Misc/Security/Vault' 'Optional'
Clear-Node 'Misc/BlessOverride'; Clear-Node 'Misc/Entries'; Clear-Node 'Misc/Tools'
Add-Item 'Misc/Tools' ([ordered]@{
    Arguments = ''; Auxiliary = $true; Comment = 'OpenShell'; Enabled = $true; Flavour = 'OpenShell:UEFIShell:Shell'
    FullNvramAccess = $false; Name = 'UEFI Shell'; Path = 'OpenShell.efi'; RealPath = $false; TextMode = $false
})

# --- NVRAM
$apple = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
$bootArgs = if ($Target -eq 'VM') { '-v keepsyms=1 debug=0x100' } else { "-v keepsyms=1 debug=0x100 alcid=$AlcLayout" }
Set-Val "NVRAM/Add/$apple/boot-args" $bootArgs
Set-Val "NVRAM/Add/$apple/csr-active-config" (HexBytes '00000000')
Set-Val "NVRAM/Add/$apple/prev-lang:kbd" (AsciiBytes 'de-DE:3')
Set-Val 'NVRAM/WriteFlash' $true

# --- UEFI
Clear-Node 'UEFI/Drivers'; Clear-Node 'UEFI/ReservedMemory'
foreach ($drv in 'OpenRuntime.efi', 'HfsPlus.efi', 'ResetNvramEntry.efi') {
    Add-Item 'UEFI/Drivers' ([ordered]@{ Arguments = ''; Comment = $drv; Enabled = $true; HideVerbose = $false; LoadEarly = $false; Path = $drv })
}
Set-Val 'UEFI/Quirks/ReleaseUsbOwnership' $true

# --- PlatformInfo (placeholders first, for the repo sample)
$model = 'MacPro7,1'
function Set-Smbios($s) {
    Set-Val 'PlatformInfo/Generic/SystemProductName' $model
    Set-Val 'PlatformInfo/Generic/SystemSerialNumber' $s.Serial
    Set-Val 'PlatformInfo/Generic/MLB' $s.MLB
    Set-Val 'PlatformInfo/Generic/SystemUUID' $s.UUID
    Set-Val 'PlatformInfo/Generic/ROM' (HexBytes $s.ROM)
}
Set-Val 'PlatformInfo/Automatic' $true
Set-Val 'PlatformInfo/UpdateSMBIOSMode' 'Create'
Set-Smbios @{ Serial = 'W00000000001'; MLB = 'M0000000000000001'; UUID = '00000000-0000-0000-0000-000000000000'; ROM = '112233445566' }

function Save-Plist([string]$path) {
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true; $settings.IndentChars = "`t"; $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $w = [Xml.XmlWriter]::Create($path, $settings); $doc.Save($w); $w.Close()
}

if ($Target -eq 'Hardware') {
    $sample = Join-Path $Root 'EFI\OC\config.sample.plist'
    New-Item -ItemType Directory -Force (Split-Path $sample) | Out-Null
    Save-Plist $sample
    Write-Host "Wrote repo sample: EFI\OC\config.sample.plist (placeholders)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 3. SMBIOS (personal)
$smbiosFile = Join-Path $Root 'smbios.local.json'
if (-not (Test-Path $smbiosFile) -and $NewSmbios) {
    $line = (& (Join-Path $tools 'macserial.exe') -m $model -g -n 1 | Select-Object -Last 1)
    $parts = $line.Split('|') | ForEach-Object { $_.Trim() }
    $mac = (Get-NetAdapter -Physical | Where-Object InterfaceDescription -like '*Realtek*GbE*' | Select-Object -First 1).MacAddress
    $rom = if ($mac) { $mac -replace '[-:]', '' } else { -join (1..6 | ForEach-Object { '{0:X2}' -f (Get-Random -Max 256) }) }
    [ordered]@{ Serial = $parts[1]; MLB = $parts[2]; UUID = [guid]::NewGuid().ToString().ToUpper(); ROM = $rom } |
        ConvertTo-Json | Set-Content $smbiosFile -Encoding UTF8
    Write-Host "Generated new SMBIOS -> smbios.local.json (keep it private, it's git-ignored)" -ForegroundColor Yellow
}
if (Test-Path $smbiosFile) {
    $s = Get-Content $smbiosFile -Raw | ConvertFrom-Json
    Set-Smbios @{ Serial = $s.Serial; MLB = $s.MLB; UUID = $s.UUID; ROM = $s.ROM }
} else {
    Write-Warning 'No smbios.local.json - config uses PLACEHOLDER serials. Run with -NewSmbios before installing.'
}

$cfg = Join-Path $outEfi 'OC\config.plist'
Save-Plist $cfg

# ---------------------------------------------------------------- 4. validate
Write-Host "`nocvalidate:" -ForegroundColor Cyan
& (Join-Path $tools 'ocvalidate.exe') $cfg
$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) { Write-Host "OK -> $outEfi" -ForegroundColor Green } else { Write-Host "ocvalidate reported problems (exit $code)" -ForegroundColor Red }
exit $code
