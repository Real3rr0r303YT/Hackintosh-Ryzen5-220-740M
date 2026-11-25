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
