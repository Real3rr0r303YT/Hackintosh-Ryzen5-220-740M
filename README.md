# Hackintosh-Ryzen5-220-740M

OpenCore EFI for the **ASUS V500 Mini Tower (VM501MH / board PM500MH)** with **AMD Ryzen 5 220** and **Radeon 740M** iGPU, running **macOS Tahoe 26**.

> ✅ **Working (as of 2026-11-26):** macOS Tahoe 26.6.2 is installed and runs on the real hardware with Wi-Fi and **Metal 3 GPU acceleration** on the Radeon 740M (RadeArc fork). OpenCore boots from the internal SSD with a graphical picker. Bluetooth, audio and LAN are not tested yet. Alpha-quality GPU driver: keep the USB stick (`build\EFI-usb`, no GPU driver) as a fallback.

## Hardware

| Component | Model | PCI / USB ID |
|---|---|---|
| CPU | AMD Ryzen 5 220 (Zen 4 Hawk Point, 6 cores / 12 threads) | – |
| iGPU | AMD Radeon 740M (Hawk Point 2 = Phoenix 2 silicon) | `1002:1901` |
| Board / BIOS | ASUS PM500MH, BIOS `PM500MH.306` (UEFI) | – |
| RAM | 16 GB DDR5 SO-DIMM | – |
| NVMe | Union Memory RPETJ512MMW1MDA 512 GB | `1CC4:6B03` |
| SATA | ASMedia ASM1062 | `1B21:1062` |
| Ethernet | Realtek RTL8111 (GbE) | `10EC:8168` |
| Wi-Fi | Realtek RTL8852BE (Wi-Fi 6) | `10EC:B852` |
| Bluetooth | Realtek (on RTL8852BE, USB) | `USB 0489:E123` |
| Audio | 🧪 | macOS Tahoe has no `AppleHDA` any more: [SimpleHDA](https://github.com/laobamac/SimpleHDA) 1.0.2 (audited, release = CI build) injects it through OpenCore, + AppleALC layout 11 (ALC897), `shda-lang=de`. No system volume change. Testing |
| USB | 4× AMD xHCI | `1022:15BB`, `15BD`, `15C2`, `15C3` |
| Display out | HDMI 2.1 / DisplayPort 1.4 (from iGPU) | – |

Full details: [docs/HARDWARE.md](docs/HARDWARE.md)

## Status (real hardware, macOS Tahoe 26.6 recovery from USB)

| Feature | Status | Notes |
|---|---|---|
| OpenCore 1.0.8 boot + recovery entry | ✅ | Recovery on its own FAT32 partition, `.contentVisibility` hides the self entry |
| AMD kernel patches (6 cores) | ✅ | Patch set incl. macOS 26.4+ variants |
| ExitBootServices (`EXITBS:START`) | ✅ | Needed `DevirtualiseMmio` + 7-entry AMD MMIO whitelist + `SetupVirtualMap` |
| CPU init after CoreAnalyticsHub | ✅ | Needed `SSDT-PLUG-ALT` (cores are ACPI0007 devices) |
| Kernel → launchd userspace | ✅ | |
| Display via HDMI (no acceleration) | ✅ | Firmware framebuffer (GOP) |
| Installer GUI (language picker, reinstall menu) | ✅ | Built with `-NoWireless`, boots to the GUI very fast. Needed `PhxXhciKick.kext` (Zen 4 xHCI interrupt fix, from [kevin8717/TongFang-7840HS-Hackintosh](https://github.com/kevin8717/TongFang-7840HS-Hackintosh), MIT) |
| USB / keyboard / mouse | ✅ | Work in the installer with `PhxXhciKick` |
| Wi-Fi | ✅ | Works (Recovery and installed macOS) with our [AirportRTW fork](https://github.com/Real3rr0r303YT/AirportRTW/tree/fix/zen4-msi-poll) (MSI + ASPM off). The freezes were caused by a bug in our MmioWhitelist (negative addresses), fixed in `Build-EFI.ps1` |
| Bluetooth | 🧪 | `RealtekBluetoothFirmware.kext` 1.0.2 (has `0489:E123`, firmware bundled), built from our audited fork [Real3rr0r303YT/RealtekBluetoothFirmware](https://github.com/Real3rr0r303YT/RealtekBluetoothFirmware), + BlueToolFixup. Off during the install, enabled afterwards |
| Ethernet (LAN) | 🔲 | RealtekRTL8111 injected; untested (no cable available) |
| Audio | 🔲 | AppleALC (layout 11) injected; untested |
| GPU acceleration (740M) | ✅ | **Metal 3** with our [RadeArc fork](https://github.com/Real3rr0r303YT/RadeArc) (PCI ID `1901`): Tests A–D passed (Phoenix 2, firmware load, MES/queues, RADV 256/256), desktop composited on the GPU (Liquid Glass, Dock animations). `build\EFI-GPU-accel`, see [docs/GPU.md](docs/GPU.md) |
| macOS installation | ✅ | macOS Tahoe 26.6.2 installed with the offline installer ([docs/OFFLINE-INSTALL.md](docs/OFFLINE-INSTALL.md)) |
| OpenCore on the internal SSD | ✅ | `Install-EfiToDisk.ps1`, graphical picker (OpenCanopy) with macOS + Windows, no stick needed |
| USB mapping / sleep | 🔲 | after install |
| VirtualBox VM test | ❌ | reaches the macOS kernel, hangs at `EXITBS:START` under Hyper-V "snail mode" |

Legend: ✅ works · 🟡 partly · 🧪 in testing · ⚗ experimental, planned after install · ❌ doesn't work · 🔲 not tested / in progress

## Build the EFI

No ready-made EFI with third-party files is stored here. A script downloads the pinned versions from the official sources and generates the config:

```powershell
# real PC (generates your personal SMBIOS once, kept in smbios.local.json)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -NewSmbios -DebugOpenCore

# installer EFI without Wi-Fi/Bluetooth (used for the offline install)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -NoWireless -OutName EFI-nowifi

# GPU test EFI = Hardware + RadeArc PhxBringup (read-only)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Gpu -DebugOpenCore

# VirtualBox test VM
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target VM
```

`Build-EFI.ps1` switches:

| Switch | Effect |
|---|---|
| `-Target Hardware\|Gpu\|VM` | real PC (default), + RadeArc PhxBringup, or VirtualBox VM |
| `-DebugOpenCore` | DEBUG OpenCore with on-screen log (always on for `VM`) |
| `-NoWireless` | leave out AirportRTW and the Bluetooth kexts (`AMFIPass` always stays) |
| `-NoBluetooth` | leave out only the Bluetooth kexts (Wi-Fi stays) |
| `-AirportRtwPath <kext>` | use this `AirportRTW.kext` (e.g. a CI debug build of the fork) instead of the pinned release |
| `-OutName <name>` | write to `build\<name>` instead of `build\EFI` (test variants side by side) |
| `-ExtraBootArgs '<args>'` | append to boot-args (e.g. `'-rtwpoll'`) |
| `-WifiAspmOff` | DeviceProperties `pci-aspm-default=0` on the Wi-Fi card and its root port |
| `-GpuAccel` | boot-args and SIP (`csr-active-config 7F080000`) for RadeArc's `install.sh` (use with `-Target Gpu`) |
| `-SkipFetch` | reuse the downloads from a previous run |
| `-NewSmbios` | generate `smbios.local.json` if it doesn't exist yet |

`AMFIPass.kext` 1.4.1 (pinned, from dortania/OpenCore-Legacy-Patcher payloads) loads right after Lilu; AirportRTW requires it on Sequoia/Tahoe.

Result: `build\EFI`, `build\EFI-GPU`, `build\EFI-VM` or `build\<OutName>`, checked with `ocvalidate`.

## USB installer

```powershell
# installer / fallback EFI: Wi-Fi fix + graphical picker, no GPU driver
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -DebugOpenCore -NoBluetooth -OutName EFI-usb

# admin PowerShell, ERASES the stick (only accepts USB disks, asks for confirmation)
powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1 -Source build\EFI-usb

# later: only replace the EFI, keep the recovery (also saves the OpenCore logs to build\usb-logs)
powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1 -UpdateEfi -Source build\EFI-usb
```

Both also write a **`gpu` folder** to the stick's RECOVERY partition (RadeArc package + `install-gpu.sh`, `gpu-reset.sh`, `LIESMICH.txt`) and **`Hackintosh-Setup.command`** next to it, if `build\gpu\usb\pkg\radearc-package.zip` exists. After a fresh install (booted from the SSD with `EFI-GPU-accel`), double-click `Hackintosh-Setup.command` in Finder: it turns off natural scrolling and installs the GPU driver (stage 2 follows by itself after the next start; an existing install is updated).

```powershell
gh release download package-latest -R Real3rr0r303YT/RadeArc -D build\gpu\usb\pkg
```

With the Wi-Fi fix the recovery has Wi-Fi, so the normal online reinstall works. The recovery comes from Apple via `macrecovery.py` (see [docs/VM-TEST.md](docs/VM-TEST.md), step 2). BIOS settings: [docs/BIOS.md](docs/BIOS.md). Offline install from the recovery: [docs/OFFLINE-INSTALL.md](docs/OFFLINE-INSTALL.md).

## OpenCore on the internal SSD (no stick)

```powershell
# admin PowerShell: backs up the EFI partition to build\esp-backup-<date>, copies EFI\OC next to Windows,
# adds a UEFI boot entry "OpenCore" and puts it first. Windows' own files are not touched.
powershell -ExecutionPolicy Bypass -File scripts\Install-EfiToDisk.ps1 -Source build\EFI-GPU-accel

# undo (Windows boots directly again)
powershell -ExecutionPolicy Bypass -File scripts\Install-EfiToDisk.ps1 -Remove
```

OpenCore then shows the graphical picker (OpenCanopy, GoldenGate icons) with macOS and Windows. Windows started from OpenCore keeps its real SMBIOS (`UpdateSMBIOSMode Custom`), so its activation is not affected.

## GPU acceleration (Radeon 740M)

Boot macOS with `build\EFI-GPU-accel` (`-Target Gpu -GpuAccel`), then in the macOS Terminal:

```sh
bash /Volumes/RECOVERY/gpu/install-gpu.sh
```

Stage 1 (Metal for apps) installs right away and turns on auto-login. After the next boot a one-shot LaunchDaemon waits for the GPU to come up cleanly, installs stage 2 (WindowServer on the GPU: Liquid Glass, blur, Dock animations) and shows the result in a dialog. One more restart and the desktop runs on the GPU.

**Wait 1–2 minutes after the desktop appears before restarting.** If a boot is cut off while the GPU starts, RadeArc's `phxboot` sets a kill switch and the next boots stay on the plain framebuffer (white wallpaper, no Liquid Glass). Fix: `bash /Volumes/RECOVERY/gpu/gpu-reset.sh` (or `sudo rm /Users/Shared/gpu/phxboot-off`), then restart. Details: [docs/GPU.md](docs/GPU.md).

## Repository layout

```
EFI/OC/config.sample.plist   generated config with placeholder serials (for reference)
scripts/
  components.json      pinned versions + download URLs
  Fetch-EFI.ps1        downloads everything into build/
  Build-EFI.ps1        generates config.plist (AMD patches, quirks, kexts) + ocvalidate
  New-UsbInstaller.ps1 writes EFI + recovery (+ gpu folder) to a USB stick
  Install-EfiToDisk.ps1 copies OpenCore to the internal EFI partition + boot entry
  gpu/                 install-gpu.sh (stage 1 + automatic stage 2), stage2.sh, gpu-reset.sh, test scripts
  New-TestVM.ps1       VirtualBox test VM
  offline-install.sh   offline macOS install from InstallAssistant.pkg (run in the recovery)
  read_fat_logs.py     reads OpenCore logs out of a FAT32 disk image
docs/
  HARDWARE.md  KEXTS.md  BIOS.md  INSTALL.md  OFFLINE-INSTALL.md  POST-INSTALL.md
  WIFI-TEST.md  GPU.md  VM-TEST.md
build/                 output (git-ignored)
```

Docs: [Hardware](docs/HARDWARE.md) · [Kexts](docs/KEXTS.md) · [BIOS](docs/BIOS.md) · [Install](docs/INSTALL.md) · [Offline install](docs/OFFLINE-INSTALL.md) · [Post-install](docs/POST-INSTALL.md) · [Wi-Fi test](docs/WIFI-TEST.md) · [GPU](docs/GPU.md) · [VM test](docs/VM-TEST.md)

## Important

- **Never commit your real `config.plist`.** It contains your SMBIOS serial numbers. `.gitignore` blocks it and `smbios.local.json`; only `config.sample.plist` with placeholders belongs here.
- Third-party kexts and drivers are **not redistributed** (each has its own license). See [docs/KEXTS.md](docs/KEXTS.md).
- macOS's license only allows installation on Apple hardware. This project is for education and research.

## Credits

[Acidanthera](https://github.com/acidanthera) (OpenCore, Lilu, VirtualSMC, AppleALC, BrcmPatchRAM/BlueToolFixup …) · [AMD-OSX](https://github.com/AMD-OSX) (AMD Vanilla patches) · [kevin8717/TongFang-7840HS-Hackintosh](https://github.com/kevin8717/TongFang-7840HS-Hackintosh) (PhxXhciKick, SSDT-PLUG-ALT, Phoenix booter quirks, 26.4+ patches) · [nullarc](https://github.com/luuumi-dev/nullarc) / [RadeArc](https://github.com/Kreytus/RadeArc) (740M acceleration) · [AirportRTW](https://github.com/souissiak1-maker/AirportRTW) by souissiak1-maker (Realtek Wi-Fi) · RealtekBluetoothFirmware by thegwchr (mirrored by [yan-ad](https://github.com/yan-ad/bt-realtek)) · [SimpleHDA](https://github.com/laobamac/SimpleHDA) by laobamac (AppleHDA on Tahoe) · [OpenCore-Legacy-Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher) by dortania (AMFIPass) · [Dortania guides](https://dortania.github.io/OpenCore-Install-Guide/)

## License

GPL-3.0, see [LICENSE](LICENSE). Applies to the configuration and docs in this repo only, not to third-party components.
