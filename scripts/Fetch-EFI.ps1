<#
.SYNOPSIS
  Downloads the pinned OpenCore files, kexts, SSDTs and helper tools from
  scripts/components.json and puts them into build/EFI and build/tools.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\Fetch-EFI.ps1
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Force,        # re-download even if the file is cached
    [switch]$DebugOpenCore # use the DEBUG build of OpenCore (verbose on-screen log)
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$manifest  = Get-Content (Join-Path $PSScriptRoot 'components.json') -Raw | ConvertFrom-Json
$dlDir     = Join-Path $Root 'downloads'
$xDir      = Join-Path $dlDir 'extracted'
$efiDir    = Join-Path $Root 'build\EFI'
$toolsDir  = Join-Path $Root 'build\tools'

# Fresh EFI tree every run, so removed components don't linger.
if (Test-Path $efiDir) { Remove-Item $efiDir -Recurse -Force }
foreach ($d in $dlDir, $xDir, $toolsDir, "$efiDir\BOOT", "$efiDir\OC\ACPI", "$efiDir\OC\Drivers", "$efiDir\OC\Kexts", "$efiDir\OC\Tools") {
    New-Item -ItemType Directory -Force $d | Out-Null
}

function Find-Item([string]$base, [string]$pick) {
    $norm = $pick -replace '/', '\'
    $all  = Get-ChildItem $base -Recurse -Force |
            Where-Object { $_.FullName -notmatch '\\(Debug|DEBUG)\\|\.dSYM(\\|$)|__MACOSX' }
    # never pick something nested inside another bundle (e.g. PlugIns of a kext)
    $all  = $all | Where-Object { (Split-Path -Parent $_.FullName.Substring($base.Length)) -notmatch '\.kext(\\|$)' }
    if ($pick -eq '*.kext') {
        return $all | Where-Object { $_.PSIsContainer -and $_.Name -like '*.kext' }
    }
    if ($norm.Contains('\')) {
        return $all | Where-Object { $_.FullName.EndsWith('\' + $norm) } | Select-Object -First 1
    }
    return $all | Where-Object { $_.Name -eq $pick } | Select-Object -First 1
}

foreach ($c in $manifest.components) {
    if ($DebugOpenCore -and $c.name -eq 'OpenCore') { $c.url = $c.url -replace '-RELEASE\.zip$', '-DEBUG.zip' }
    # one cache folder per component: several downloads share a file name (Info.plist, config.plist)
    $cDir = Join-Path $dlDir ($c.name -replace '[^\w.-]', '_')
    New-Item -ItemType Directory -Force $cDir | Out-Null
    $file = Join-Path $cDir ([IO.Path]::GetFileName(([Uri]$c.url).AbsolutePath))
    if ($Force -or -not (Test-Path $file)) {
        Write-Host "Downloading $($c.name) ..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $c.url -OutFile $file -UseBasicParsing
    } else {
        Write-Host "Cached      $($c.name)"
    }

    if ($file -like '*.zip') {
        $src = Join-Path $xDir $c.name
        if (Test-Path $src) { Remove-Item $src -Recurse -Force }
        Expand-Archive -Path $file -DestinationPath $src -Force
    } else {
        $src = Join-Path $xDir $c.name
        New-Item -ItemType Directory -Force $src | Out-Null
        Copy-Item $file $src -Force
    }

    foreach ($it in $c.items) {
        $found = @(Find-Item $src $it.pick)
        if ($found.Count -eq 0 -or -not $found[0]) { throw "$($c.name): '$($it.pick)' not found in download" }
        $dest = if ($it.to -eq 'tools') { $toolsDir } else { Join-Path $efiDir ($it.to -replace '/', '\') }
        New-Item -ItemType Directory -Force $dest | Out-Null
        foreach ($f in $found) {
            Copy-Item $f.FullName $dest -Recurse -Force
            Write-Host "   + $($f.Name) -> $($it.to)" -ForegroundColor DarkGray
        }
    }
}

Write-Host "`nDone. EFI files in $efiDir" -ForegroundColor Green
