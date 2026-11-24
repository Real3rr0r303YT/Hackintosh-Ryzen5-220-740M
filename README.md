# Hackintosh-Ryzen5-220-740M

OpenCore EFI for the **ASUS V500 Mini Tower (VM501MH / board PM500MH)** with **AMD Ryzen 5 220** and **Radeon 740M** iGPU.

> ⚠️ **Work in progress.** Nothing here is tested on hardware yet. Use at your own risk and back up your data first.

## Hardware

| Component | Model | PCI / USB ID |
|---|---|---|
| CPU | AMD Ryzen 5 220 (Zen 4, 6 cores / 12 threads) | – |
| iGPU | AMD Radeon 740M | `1002:1901` |
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

## Status

| Feature | Status | Notes |
|---|---|---|
| Boot (OpenCore + AMD Vanilla patches) | 🔲 not tested | |
| GPU acceleration (740M) | ❌ not yet | Planned via [nullarc](https://github.com/luuumi-dev/nullarc) / [RadeArc](https://github.com/Kreytus/RadeArc). HDMI/DP output not supported by them yet; device ID `1901` not confirmed. |
| Display via HDMI (no acceleration) | 🔲 not tested | Firmware framebuffer (GOP) only |
| Ethernet | 🔲 not tested | RealtekRTL8111.kext |
| Wi-Fi | 🔲 not tested | AirPort_RTW89 (experimental) |
| Bluetooth | 🔲 not tested | BlueToolFixup + Realtek firmware (experimental) |
| Audio | 🔲 not tested | AppleALC (ALC897) |
| USB | 🔲 not tested | needs USB mapping |
| Sleep / wake | 🔲 not tested | |

Legend: ✅ works · 🟡 partly · ❌ doesn't work · 🔲 not tested

## Target

- **macOS:** Tahoe 26 (required by nullarc)
- **Bootloader:** OpenCore (latest release)

## Build the EFI

No ready-made EFI with third-party files is stored here. A script downloads the pinned versions from the official sources and generates the config:

```powershell
# real PC (generates your personal SMBIOS once, kept in smbios.local.json)
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -NewSmbios

# VirtualBox test VM
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target VM
```

Result: `build\EFI` (or `build\EFI-VM`), checked with `ocvalidate`. Test in a VM first: [docs/VM-TEST.md](docs/VM-TEST.md)

## Repository layout

```
EFI/OC/config.sample.plist   generated config with placeholder serials (for reference)
scripts/
  components.json      pinned versions + download URLs
  Fetch-EFI.ps1        downloads everything into build/
  Build-EFI.ps1        generates config.plist (AMD patches, quirks, kexts) + ocvalidate
  New-TestVM.ps1       VirtualBox test VM
docs/
  HARDWARE.md  KEXTS.md  BIOS.md  INSTALL.md  VM-TEST.md
build/                 output (git-ignored)
```

## Important

- **Never commit your real `config.plist`.** It contains your SMBIOS serial numbers. `.gitignore` blocks it; only `config.sample.plist` with placeholders belongs here.
- Third-party kexts and drivers are **not redistributed** (each has its own license). See [docs/KEXTS.md](docs/KEXTS.md).
- macOS's license only allows installation on Apple hardware. This project is for education and research.

## Credits

[Acidanthera](https://github.com/acidanthera) (OpenCore, Lilu, VirtualSMC, AppleALC …) · [AMD-OSX](https://github.com/AMD-OSX) (AMD Vanilla patches) · [nullarc](https://github.com/luuumi-dev/nullarc) / [RadeArc](https://github.com/Kreytus/RadeArc) · AirPort_RTW89 contributors · [Dortania guides](https://dortania.github.io/OpenCore-Install-Guide/)

## License

GPL-3.0, see [LICENSE](LICENSE). Applies to the configuration and docs in this repo only, not to third-party components.
