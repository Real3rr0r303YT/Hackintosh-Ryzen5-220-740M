# Test in VirtualBox first

Before touching the real PC, we boot the EFI in a VirtualBox VM.

## What the VM test checks, and what it doesn't

| Checked ✅ | Not checked ❌ |
|---|---|
| OpenCore boots, config is valid | Wi-Fi, Bluetooth, sound, LAN (VirtualBox has virtual hardware) |
| **AMD Vanilla patches** with your real Ryzen CPU (the VM sees the real CPU) | Radeon 740M / HDMI |
| macOS kernel starts, recovery/installer runs | USB mapping, sleep |

So the VM tests the **CPU and boot part**. Hardware drivers can only be tested on the real PC.

## Known limits on this PC

- **Hyper-V / Windows virtualization is active** (Memory Integrity, WSL or similar). VirtualBox then runs on top of Hyper-V, which is **slow**, and macOS may hang. If it doesn't boot, turn off Memory Integrity (Windows Security → Device security → Core isolation) and run `bcdedit /set hypervisorlaunchtype off`. That's your decision, it lowers Windows security a bit and breaks WSL2/Docker until you undo it (`bcdedit /set hypervisorlaunchtype auto`).
- **No graphics acceleration** in the VM, so it will be laggy.
- **Network:** macOS Tahoe may have no driver for VirtualBox's network card. Installing from recovery needs internet. If the installer finds no network, we'll add a fix.

## Steps

1. Build the VM EFI:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target VM
   ```
2. Download macOS Tahoe recovery (needs Python, ~1 GB from Apple's servers):
   ```powershell
   cd build\tools\macrecovery
   python macrecovery.py -b Mac-CFF7D910A743CAAF -m 00000000000000000 -os latest -o ..\..\recovery\com.apple.recovery.boot download
   ```
3. Create the VM (**admin PowerShell**):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\New-TestVM.ps1
   ```
4. Start **Hackintosh-Test** in VirtualBox → OpenCore picker → choose the recovery → watch the verbose text (`-v`).
5. If it gets stuck: take a photo/screenshot of the last lines and open an issue.
