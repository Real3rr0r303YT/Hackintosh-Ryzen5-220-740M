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
    # Gpu = Hardware + RadeArc PhxBringup.kext (read-only "Test A", no -phxp2) -> build\EFI-GPU
    [ValidateSet('Hardware', 'VM', 'Gpu')] [string]$Target = 'Hardware',
    [switch]$NewSmbios,      # generate smbios.local.json if it doesn't exist yet
    [switch]$SkipFetch,      # reuse build\EFI from a previous fetch
    [int]$Cores = 6,         # physical cores of the Ryzen 5 220
    [int]$AlcLayout = 11,    # AppleALC layout-id for ALC897 (try 12, 13, 21, 23, 66 … if no sound)
    [switch]$DebugOpenCore,  # DEBUG OpenCore with on-screen log (always on for -Target VM)
    [switch]$NoWireless,     # disable AirportRTW + Bluetooth kexts (troubleshooting / install over LAN)
    [switch]$NoBluetooth,    # disable only the Bluetooth kexts (WLAN stays on)
    [string]$AirportRtwPath, # use this AirportRTW.kext (e.g. a local Debug build) instead of the pinned release
    [string]$OutName,        # write to build\<OutName> instead of build\EFI (test variants side by side)
    [string]$ExtraBootArgs,  # appended to boot-args (e.g. '-rtwpoll')
    [switch]$WifiAspmOff,    # DeviceProperties pci-aspm-default=0 on the Wi-Fi card + its root port
    [string[]]$DisableKexts, # extra kexts to load disabled, e.g. NVMeFix
    [switch]$NvmeAspmOff,    # DeviceProperties pci-aspm-default=0 on the NVMe SSD + its root port
    [switch]$DropIvrs,       # ACPI/Delete the IVRS table (hide the AMD IOMMU when the BIOS can't disable it)
    # SIP off for runtime kext loading (scripts/recovery-debug.sh): csr-active-config 0xFEF
    # (incl. 0x1 untrusted + 0x200 unapproved kexts) and AMFI relaxed (amfi=0x80). Debug only.
    [switch]$SipOff,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$tools = Join-Path $Root 'build\tools'

# ---------------------------------------------------------------- 1. fetch
$useDebug = $DebugOpenCore -or $Target -eq 'VM'
if (-not $SkipFetch) { & (Join-Path $PSScriptRoot 'Fetch-EFI.ps1') -Root $Root -DebugOpenCore:$useDebug }
$fetched = Join-Path $Root 'build\EFI'
$outEfi  = switch ($Target) { 'VM' { Join-Path $Root 'build\EFI-VM' } 'Gpu' { Join-Path $Root 'build\EFI-GPU' } default { $fetched } }
if ($OutName) {
    if ($OutName -match '[\\/:]') { throw '-OutName is a folder name under build\, not a path.' }
    $outEfi = Join-Path $Root "build\$OutName"
}
if ($outEfi -ne $fetched) {
    if (Test-Path $outEfi) { Remove-Item $outEfi -Recurse -Force }
    Copy-Item $fetched $outEfi -Recurse
}
if ($Target -eq 'Gpu') {
    # PhxBringup.kext built by GitHub Actions in the RadeArc fork (with PCI ID 1002:1901), see docs/GPU.md
    $phx = Join-Path $Root 'build\gpu\kexts\PhxBringup.kext'
    if (-not (Test-Path $phx)) { throw "Missing $phx - download the 'kexts' artifact from the RadeArc fork first (docs/GPU.md)." }
    Copy-Item $phx (Join-Path $outEfi 'OC\Kexts') -Recurse -Force
}
if ($AirportRtwPath) {
    if (-not (Test-Path (Join-Path $AirportRtwPath 'Contents\Info.plist'))) { throw "$AirportRtwPath is not a kext bundle." }
    $rtwDest = Join-Path $outEfi 'OC\Kexts\AirportRTW.kext'
    if (Test-Path $rtwDest) { Remove-Item $rtwDest -Recurse -Force }
    Copy-Item $AirportRtwPath $rtwDest -Recurse
    Write-Host "AirportRTW override: $AirportRtwPath" -ForegroundColor Yellow
}
# Realtek USB Bluetooth firmware uploader (0489:E123 = RTL8852B BT). Upstream (thegwchr) is gone;
# built by GitHub Actions in the Real3rr0r303YT/RealtekBluetoothFirmware fork, see docs/KEXTS.md.
$rtkBt = Join-Path $Root 'build\bt\RealtekBluetoothFirmware.kext'
if ($Target -ne 'VM' -and (Test-Path $rtkBt)) {
    $btDest = Join-Path $outEfi 'OC\Kexts\RealtekBluetoothFirmware.kext'
    if (Test-Path $btDest) { Remove-Item $btDest -Recurse -Force }
    Copy-Item $rtkBt $btDest -Recurse
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
if ($DropIvrs) {
    # Hide the AMD IOMMU (IVRS table) from macOS - the BIOS of this ASUS V500 can't turn IOMMU off
    Add-Item 'ACPI/Delete' ([ordered]@{
        All = $false; Comment = 'Drop IVRS (AMD IOMMU)'; Enabled = $true
        OemTableId = (HexBytes '0000000000000000'); TableLength = 0; TableSignature = (AsciiBytes 'IVRS')
    })
}

# --- Booter (Dortania AMD Zen, 2020+ firmware)
Clear-Node 'Booter/MmioWhitelist'; Clear-Node 'Booter/Patch'
$bq = [ordered]@{
    AvoidRuntimeDefrag = $true; DevirtualiseMmio = $false; EnableSafeModeSlide = $true
    EnableWriteUnprotector = $false; ProvideCustomSlide = $true; RebuildAppleMemoryMap = $true
    SetupVirtualMap = $false; SyncRuntimePermissions = $true; ResizeAppleGpuBars = -1
}
if ($Target -eq 'VM') {
    # VirtualBox ships an old EDK2 firmware: it needs the classic memory-map handling
    $bq.SetupVirtualMap = $true; $bq.EnableWriteUnprotector = $true
    $bq.RebuildAppleMemoryMap = $false; $bq.SyncRuntimePermissions = $false
} else {
    # Phoenix / Hawk Point (Ryzen 7040/8040/200) hangs at EXITBS:START with the plain
    # Dortania Zen values. Taken from a working Ryzen 7 7840HS + macOS 26 config
    # (github.com/kevin8717/TongFang-7840HS-Hackintosh).
    $bq.DevirtualiseMmio = $true; $bq.SetupVirtualMap = $true; $bq.ProvideMaxSlide = 100
}
foreach ($k in $bq.Keys) { Set-Val "Booter/Quirks/$k" $bq[$k] }

if ($Target -ne 'VM') {
    # Standard AMD platform MMIO regions that must stay mapped for the firmware at runtime
    $mmio = [ordered]@{
        0xFE0B0000 = 'AMD ERAX MMIO'; 0xFED00000 = 'HPET MMIO'; 0xFED40000 = 'fTPM MMIO'
        0xFED80000 = 'AMD FCH AcpiMmio / PMIO / SMI'; 0xFEDC0000 = 'AMD FCH UART / I2C / AOAC'
        0xFEE00000 = 'LAPIC MMIO'; 0xFF000000 = 'SPI Flash ROM (NVRAM runtime)'
    }
    # PS 5.1 parses 0xFE0B0000 as a negative Int32: reinterpret the 32 bits as unsigned before widening,
    # otherwise the plist gets e.g. -32833536 and OpenCore whitelists nothing.
    foreach ($a in $mmio.Keys) {
        $addr = [long][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$a), 0)
        Add-Item 'Booter/MmioWhitelist' ([ordered]@{ Address = $addr; Comment = $mmio[$a]; Enabled = $true })
    }
}

# --- DeviceProperties
Clear-Node 'DeviceProperties/Add'; Clear-Node 'DeviceProperties/Delete'
# Keep PCIe links out of ASPM L0s/L1 (pci-aspm-default=0) on a device and its AMD root port.
$aspmOff = @()
# RTL8852BE (Windows: PCIROOT(0)#PCI(0202)#PCI(0000)) froze the machine when the first scan started
if ($WifiAspmOff) { $aspmOff += 'PciRoot(0x0)/Pci(0x2,0x2)', 'PciRoot(0x0)/Pci(0x2,0x2)/Pci(0x0,0x0)' }
# NVMe 1CC4:6B03 (Windows: PCIROOT(0)#PCI(0102)#PCI(0000)) - test for the hang during the install
if ($NvmeAspmOff) { $aspmOff += 'PciRoot(0x0)/Pci(0x1,0x2)', 'PciRoot(0x0)/Pci(0x1,0x2)/Pci(0x0,0x0)' }
if ($aspmOff) {
    $dpAdd = Get-Val $top 'DeviceProperties/Add'
    foreach ($p in $aspmOff) {
        $ke = $doc.CreateElement('key'); $ke.InnerText = $p
        [void]$dpAdd.AppendChild($ke)
        [void]$dpAdd.AppendChild((New-Dict ([ordered]@{ 'pci-aspm-default' = (HexBytes '00000000') })))
    }
}

# --- Kernel/Add  (Lilu first, then VirtualSMC, then plugins that depend on them)
$disabledOnVM = 'AppleALC', 'NVMeFix', 'BlueToolFixup', 'RealtekBluetoothFirmware', 'RealtekRTL8111', 'AMDRyzenCPUPowerManagement', 'SMCAMDProcessor', 'AirportRTW', 'PhxXhciKick'
$order = 'Lilu', 'AMFIPass', 'VirtualSMC', 'AMDRyzenCPUPowerManagement', 'SMCAMDProcessor'
$kexts = Get-ChildItem (Join-Path $outEfi 'OC\Kexts') -Directory -Filter *.kext |
         Sort-Object @{ e = { $i = [array]::IndexOf($order, (KextName $_)); if ($i -lt 0) { 99 } else { $i } } }, Name
Clear-Node 'Kernel/Add'; Clear-Node 'Kernel/Block'; Clear-Node 'Kernel/Force'
foreach ($k in $kexts) {
    [xml]$info = Get-Content (Join-Path $k.FullName 'Contents\Info.plist') -Raw
    $exeKey = $info.SelectSingleNode("/plist/dict/key[.='CFBundleExecutable']")
    $exe = if ($exeKey) { $n = $exeKey.NextSibling; while ($n.NodeType -ne 'Element') { $n = $n.NextSibling }; "Contents/MacOS/$($n.InnerText)" } else { '' }
    $enabled = -not ($Target -eq 'VM' -and $disabledOnVM -contains (KextName $k))
    # Old (2021) power-management kexts: suspected to hang Zen 4 mobile on Tahoe right after
    # CoreAnalyticsHub; the working 7840HS config doesn't use them either.
    if ((KextName $k) -in 'AMDRyzenCPUPowerManagement', 'SMCAMDProcessor') { $enabled = $false }
    if ($NoWireless -and (KextName $k) -in 'AirportRTW', 'BlueToolFixup', 'RealtekBluetoothFirmware') { $enabled = $false }
    if ($NoBluetooth -and (KextName $k) -in 'BlueToolFixup', 'RealtekBluetoothFirmware') { $enabled = $false }
    if ($DisableKexts -and (KextName $k) -in $DisableKexts) { $enabled = $false }
    Add-Item 'Kernel/Add' ([ordered]@{
        Arch = 'Any'; BundlePath = $k.Name; Comment = (KextName $k); Enabled = $enabled
        ExecutablePath = $exe; MaxKernel = ''; MinKernel = $(if ((KextName $k) -eq 'PhxBringup') { '25.0.0' } else { '' }); PlistPath = 'Contents/Info.plist'
    })
}

# --- Kernel/Patch  (AMD Vanilla, core count patched in)
Clear-Node 'Kernel/Patch'
# Hardware: patch set from the working Phoenix/Tahoe config (has 26.4+ variants); VM: plain AMD Vanilla
$patchFile = if ($Target -ne 'VM' -and (Test-Path (Join-Path $tools 'config.plist'))) { 'config.plist' } else { 'patches.plist' }
Write-Host "Kernel patches from: $patchFile" -ForegroundColor DarkGray
[xml]$vanilla = Get-Content (Join-Path $tools $patchFile) -Raw
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
    LapicKernelPanic = $true   # as in the working 7840HS config (Zen 4)
}
foreach ($k in $kq.Keys) { Set-Val "Kernel/Quirks/$k" $kq[$k] }

# --- Misc
# Recovery/installer entries count as "auxiliary" - keep them visible while installing
Set-Val 'Misc/Boot/HideAuxiliary' $false
Set-Val 'Misc/Boot/PickerMode' 'Builtin'
Set-Val 'Misc/Boot/ShowPicker' $true
Set-Val 'Misc/Boot/Timeout' 5
Set-Val 'Misc/Boot/PollAppleHotKeys' $true
Set-Val 'Misc/Debug/AppleDebug' $true
Set-Val 'Misc/Debug/ApplePanic' $true
Set-Val 'Misc/Debug/DisableWatchDog' $true
Set-Val 'Misc/Debug/Target' 67          # 0x43: log on screen + to opencore-*.txt on the EFI volume
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
# ipc_control_port_options=0: from the working 7840HS config (avoids hangs/crashes on Tahoe)
$bootArgs = if ($Target -eq 'VM') { '-v keepsyms=1 debug=0x100' } else { "-v keepsyms=1 debug=0x100 alcid=$AlcLayout ipc_control_port_options=0" }
# phxdebug=1: RadeArc logging. Deliberately NO -phxp2 yet: without it PhxBringup only READS the GPU (Test A).
if ($Target -eq 'Gpu') { $bootArgs += ' phxdebug=1' }
# AirportRTW (Wi-Fi) on Tahoe: relax AMFI like the working 7840HS config, set the regulatory
# country, and turn off the experimental AWDL frontend (added in V2.3.0) in the kext's Info.plist.
if ($Target -ne 'VM' -and -not $NoWireless) {
    $bootArgs += ' -amfipassbeta amfi=0x80 itlwm_cc=DE'
    $rtwPlist = Join-Path $outEfi 'OC\Kexts\AirportRTW.kext\Contents\Info.plist'
    if (Test-Path $rtwPlist) {
        $t = [IO.File]::ReadAllText($rtwPlist)
        $t = [regex]::Replace($t, '(<key>RTWAwdl\w*Enabled</key>\s*)<true/>', '$1<false/>')
        if ($t -notmatch '<key>RTWAwdlEnabled</key>') {   # e.g. Debug artifacts ship without the key
            $t = [regex]::Replace($t, '(<key>IOResourceMatch</key>\s*<string>IOBSD</string>)', "`$1`n`t`t`t<key>RTWAwdlEnabled</key>`n`t`t`t<false/>")
        }
        [IO.File]::WriteAllText($rtwPlist, $t)
    }
}
if ($ExtraBootArgs) { $bootArgs += " $ExtraBootArgs" }
# csr-active-config is a little-endian UInt32 as Data: <EF0F0000> = 0x00000FEF (like <03080000> = 0x803).
# 0xFEF = every SIP bit up to 0x800 except 0x10 (APPLE_INTERNAL), i.e. includes
# 0x1 ALLOW_UNTRUSTED_KEXTS and 0x200 ALLOW_UNAPPROVED_KEXTS needed by `kmutil load`.
$csr = '00000000'
if ($SipOff) {
    $csr = 'EF0F0000'
    # the ad-hoc signed AirportRTW also needs AMFI relaxed (-NoWireless drops these args above)
    if ($bootArgs -notmatch 'amfi=0x80') { $bootArgs += ' -amfipassbeta amfi=0x80' }
    Write-Host "SIP off: csr-active-config = $csr (0x00000FEF)" -ForegroundColor Yellow
}
Set-Val "NVRAM/Add/$apple/boot-args" $bootArgs
Set-Val "NVRAM/Add/$apple/csr-active-config" (HexBytes $csr)
# NVRAM/Add never overwrites an existing variable: delete it first, so switching between a
# -SipOff EFI and a normal one really changes SIP (and the normal EFI turns it back on).
if (-not (Get-Val $top "NVRAM/Delete/$apple").SelectSingleNode("string[.='csr-active-config']")) {
    Add-Item "NVRAM/Delete/$apple" 'csr-active-config'
}
Set-Val "NVRAM/Add/$apple/prev-lang:kbd" (AsciiBytes 'de-DE:3')
Set-Val 'NVRAM/WriteFlash' $true

# --- UEFI
Clear-Node 'UEFI/Drivers'; Clear-Node 'UEFI/ReservedMemory'
foreach ($drv in 'OpenRuntime.efi', 'HfsPlus.efi', 'ResetNvramEntry.efi') {
    Add-Item 'UEFI/Drivers' ([ordered]@{ Arguments = ''; Comment = $drv; Enabled = $true; HideVerbose = $false; LoadEarly = $false; Path = $drv })
}
Set-Val 'UEFI/Quirks/ReleaseUsbOwnership' $true
if ($useDebug) {
    # show errors + warnings + info on screen (DEBUG build), so we see where it hangs
    Set-Val 'Misc/Debug/DisplayLevel' 2147483714
}
if ($Target -eq 'VM') {
    # VirtualBox firmware handles keys itself; OpenCore's own key handling swallows input there
    Set-Val 'UEFI/Input/KeySupport' $false
    # VBox otherwise picks 8K (7680x4320) - unreadable and slow
    Set-Val 'UEFI/Output/Resolution' '1920x1080'
}

# --- PlatformInfo (placeholders first, for the repo sample)
# MacBookPro16,1 like the working 7840HS config; MacPro7,1 needs extra MCE workarounds on AMD
$model = 'MacBookPro16,1'
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

if ($Target -eq 'Hardware' -and -not $SipOff) {   # the repo sample keeps SIP on
    $sample = Join-Path $Root 'EFI\OC\config.sample.plist'
    New-Item -ItemType Directory -Force (Split-Path $sample) | Out-Null
    Save-Plist $sample
    Write-Host "Wrote repo sample: EFI\OC\config.sample.plist (placeholders)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 3. SMBIOS (personal)
$smbiosFile = Join-Path $Root 'smbios.local.json'
if ((Test-Path $smbiosFile) -and ((Get-Content $smbiosFile -Raw | ConvertFrom-Json).Model -ne $model)) {
    if ($NewSmbios) { Remove-Item -LiteralPath $smbiosFile; Write-Host "SMBIOS model changed to $model - generating new serials" -ForegroundColor Yellow }
    else { Write-Warning "smbios.local.json is for another model - run with -NewSmbios to regenerate for $model." }
}
if (-not (Test-Path $smbiosFile) -and $NewSmbios) {
    $line = (& (Join-Path $tools 'macserial.exe') -m $model -g -n 1 | Select-Object -Last 1)
    $parts = $line.Split('|') | ForEach-Object { $_.Trim() }
    $mac = (Get-NetAdapter -Physical | Where-Object InterfaceDescription -like '*Realtek*GbE*' | Select-Object -First 1).MacAddress
    $rom = if ($mac) { $mac -replace '[-:]', '' } else { -join (1..6 | ForEach-Object { '{0:X2}' -f (Get-Random -Max 256) }) }
    # macserial -g prints "SERIAL | MLB"
    if ($parts.Count -lt 2 -or -not $parts[0] -or -not $parts[1]) { throw "Unexpected macserial output - SMBIOS not generated." }
    [ordered]@{ Model = $model; Serial = $parts[0]; MLB = $parts[1]; UUID = [guid]::NewGuid().ToString().ToUpper(); ROM = $rom } |
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

# Hide OpenCore's own \EFI\BOOT\BOOTx64.efi from the picker. Otherwise it shows up as
# an entry (named after the volume) that only relaunches OpenCore and halts.
Set-Content -Path (Join-Path $outEfi 'BOOT\.contentVisibility') -Value 'Disabled' -NoNewline -Encoding ASCII

# ---------------------------------------------------------------- 4. validate
Write-Host "`nocvalidate:" -ForegroundColor Cyan
& (Join-Path $tools 'ocvalidate.exe') $cfg
$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) { Write-Host "OK -> $outEfi" -ForegroundColor Green } else { Write-Host "ocvalidate reported problems (exit $code)" -ForegroundColor Red }
exit $code
