# Installation (draft)

> ⚠️ Not tested yet. **Back up all your data first.**

## Requirements

- USB stick, at least 16 GB
- ~100 GB free space on the NVMe for a macOS partition, or a second NVMe in the free M.2 slot (safer)
- BIOS settings from [BIOS.md](BIOS.md)

## Steps

1. **BIOS**: apply the settings in [BIOS.md](BIOS.md).
2. **Make room**: in Windows Disk Management, shrink `C:` by ~100 GB (or install a second NVMe).
0. **Test in a VM first**: [VM-TEST.md](VM-TEST.md)
3. **Build the EFI**: `powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -NewSmbios` → `build\EFI`.
4. **Installer USB**: download macOS Tahoe with `macrecovery.py` (in OpenCorePkg) and put it on the stick along with the EFI.
5. **Install**: boot from the stick, format the partition as APFS in Disk Utility, install macOS.
6. **After install**: copy the EFI to the NVMe's EFI partition, do the USB mapping, set up Wi-Fi/Bluetooth.

Each step gets detailed later.
