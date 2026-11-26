# Wi-Fi test (RTL8852BE on Ryzen 5 220)

## Why the installer froze

Stock AirportRTW registers its RTW89 interrupt on PCI interrupt index 0, the
legacy INTx pin. On this AMD Phoenix 2 platform that line is misrouted under
macOS, so the system freezes right after the card powers on
(`loadCardCapabilities status=<0x0>` is the last Wi-Fi line on screen).

Fork: [Real3rr0r303YT/AirportRTW `fix/zen4-msi-poll`](https://github.com/Real3rr0r303YT/AirportRTW/tree/fix/zen4-msi-poll)

| Boot-arg | Effect |
|---|---|
| *(none)* | Use the first MSI interrupt index; fall back to INTx if it can't be registered |
| `-rtwpoll` | No interrupt at all: INTx is masked and the chip is serviced by a 2 ms timer |
| `-rtwintx` | Old behaviour (INTx, index 0) |
| `rtwirq=N` | Force interrupt index N |

The kext logs `AirportRTW-RTW89: interrupt index N` early in the verbose boot.

## Results on real hardware (2026-11-26)

| EFI | Result |
|---|---|
| stock AirportRTW (INTx) | freezes when the card powers on |
| `EFI-wifi-msi` (MSI) | card starts, firmware loads; hard freeze at the first `IO80211ScanManager::startScan` |
| `EFI-wifi-poll` (`-rtwpoll`) | same freeze at the first scan, so interrupts are not the only cause |
| `EFI-wifi-poll-aspm` (+ `pci-aspm-default=0` via DeviceProperties) | survives 3 scans, then freezes |
| `EFI-wifi-full` (driver clears ASPM L0s/L1, L1 PM substates and CLKREQ on the card and its root port; `-rtwaspm` keeps them) | built, not tested yet (planned after install) |

Current theory: the PCIe link power states between the AMD root port and the
RTL8852BE hang the link once the card starts scanning. `-WifiAspmOff` in
`Build-EFI.ps1` adds the DeviceProperties; the fork's driver now also clears
the registers itself.

macOS is installed offline first (see [OFFLINE-INSTALL.md](OFFLINE-INSTALL.md)); Wi-Fi is debugged afterwards in the installed system, where kernel logs can be read.

## Build the test EFIs

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -NoWireless
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -SkipFetch -NoBluetooth -OutName EFI-wifi-msi  -AirportRtwPath downloads\rtw-msi\Debug\AirportRTW.kext
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -SkipFetch -NoBluetooth -OutName EFI-wifi-poll -AirportRtwPath downloads\rtw-msi\Debug\AirportRTW.kext -ExtraBootArgs '-rtwpoll'
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -SkipFetch -NoWireless  -OutName EFI-nowifi
```

`downloads\rtw-msi\Debug\AirportRTW.kext` is the `AirportRTW-Tahoe-Debug` artifact of the fork's CI.

## Test order (admin PowerShell, stick = disk 1)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1 -UpdateEfi -Source build\EFI-wifi-msi
```

1. `EFI-wifi-msi`: boot, wait up to 5 minutes. If the installer GUI appears, click the Wi-Fi icon.
2. If it freezes: `EFI-wifi-poll`.
3. Fallback (known good, no Wi-Fi): `EFI-nowifi`.

On a freeze, photograph the last lines and look for `AirportRTW-RTW89: interrupt index`.
