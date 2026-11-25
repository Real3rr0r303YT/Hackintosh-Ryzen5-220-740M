# Hackintosh-Ryzen5-220-740M

OpenCore EFI for the **ASUS V500 Mini Tower (VM501MH / board PM500MH)** with **AMD Ryzen 5 220** and **Radeon 740M** iGPU, running **macOS Tahoe 26**.

> ⚠️ **Work in progress.** The macOS Tahoe 26.6 recovery boots into userspace on the real hardware; installation is the next step. Use at your own risk and back up your data first.

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
| Audio | Realtek ALC897 | `HDA 10EC:0897` |
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
| Wi-Fi | 🟡 | AirportRTW V2.3.3 loads and scans (`IO80211ScanManager`), connecting not tested |
| Bluetooth | 🟡 | BlueTool starts; firmware for `0489:E123` not confirmed |
| Ethernet / Audio | 🟡 | RealtekRTL8111 / AppleALC inject OK, not tested in macOS |
| macOS installation | 🔲 | next step, see [docs/POST-INSTALL.md](docs/POST-INSTALL.md) |
| GPU acceleration (740M) | 🧪 | [RadeArc fork](https://github.com/Real3rr0r303YT/RadeArc) with PCI ID `1901` built; test after install, see [docs/GPU.md](docs/GPU.md) |
| USB mapping / sleep | 🔲 | after install |
| VirtualBox VM test | ❌ | reaches the macOS kernel, hangs at `EXITBS:START` under Hyper-V "snail mode" |

Legend: ✅ works · 🟡 partly · 🧪 experimental · ❌ doesn't work · 🔲 not tested

## Build the EFI

No ready-made EFI with third-party files is stored here. A script downloads the pinned versions from the official sources and generates the config:

```powershell
# real PC (generates your personal SMBIOS once, kept in smbios.local.json)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -NewSmbios -DebugOpenCore

# GPU test EFI = Hardware + RadeArc PhxBringup (read-only)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Gpu -DebugOpenCore

# VirtualBox test VM
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target VM
```

Result: `build\EFI`, `build\EFI-GPU` or `build\EFI-VM`, checked with `ocvalidate`.

## USB installer

```powershell
# admin PowerShell, ERASES the stick (only accepts USB disks, asks for confirmation)
powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1

# later: only replace the EFI, keep the recovery (also saves the OpenCore logs to build\usb-logs)
powershell -ExecutionPolicy Bypass -File scripts\New-UsbInstaller.ps1 -DiskNumber 1 -UpdateEfi
```

The recovery comes from Apple via `macrecovery.py` (see [docs/VM-TEST.md](docs/VM-TEST.md), step 2). BIOS settings: [docs/BIOS.md](docs/BIOS.md).

## Repository layout

```
EFI/OC/config.sample.plist   generated config with placeholder serials (for reference)
scripts/
  components.json      pinned versions + download URLs
  Fetch-EFI.ps1        downloads everything into build/
  Build-EFI.ps1        generates config.plist (AMD patches, quirks, kexts) + ocvalidate
  New-UsbInstaller.ps1 writes EFI + recovery to a USB stick
  New-TestVM.ps1       VirtualBox test VM
  read_fat_logs.py     reads OpenCore logs out of a FAT32 disk image
docs/
  HARDWARE.md  KEXTS.md  BIOS.md  INSTALL.md  POST-INSTALL.md  GPU.md  VM-TEST.md
build/                 output (git-ignored)
```

## Important

- **Never commit your real `config.plist`.** It contains your SMBIOS serial numbers. `.gitignore` blocks it and `smbios.local.json`; only `config.sample.plist` with placeholders belongs here.
- Third-party kexts and drivers are **not redistributed** (each has its own license). See [docs/KEXTS.md](docs/KEXTS.md).
- macOS's license only allows installation on Apple hardware. This project is for education and research.

## Credits

[Acidanthera](https://github.com/acidanthera) (OpenCore, Lilu, VirtualSMC, AppleALC …) · [AMD-OSX](https://github.com/AMD-OSX) (AMD Vanilla patches) · [kevin8717/TongFang-7840HS-Hackintosh](https://github.com/kevin8717/TongFang-7840HS-Hackintosh) (Phoenix booter quirks, SSDT-PLUG-ALT, 26.4+ patches) · [nullarc](https://github.com/luuumi-dev/nullarc) / [RadeArc](https://github.com/Kreytus/RadeArc) · [AirportRTW](https://github.com/souissiak1-maker/AirportRTW) · [Dortania guides](https://dortania.github.io/OpenCore-Install-Guide/)

## License

GPL-3.0, see [LICENSE](LICENSE). Applies to the configuration and docs in this repo only, not to third-party components.
