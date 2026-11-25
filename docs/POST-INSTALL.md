# Installation & post-install (draft)

> ⚠️ **Not tested on hardware yet.** Every step that touches disks, the EFI partition or the boot order can make Windows unbootable if done wrong. **Back up your data and save your BitLocker recovery key first** (<https://account.microsoft.com/devices/recoverykey> or `manage-bde -protectors -get C:`).
>
> Where this guide says **"check"**, the detail has not been verified on this machine yet.

Starting point: the USB stick made with `scripts\New-UsbInstaller.ps1` (partition 1 = OpenCore ESP, partition 2 = FAT32 `RECOVERY` with `com.apple.recovery.boot`) and the DEBUG EFI from `Build-EFI.ps1 -Target Hardware -DebugOpenCore`.

General reference: [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/) · [Dortania OpenCore Post-Install](https://dortania.github.io/OpenCore-Post-Install/) · [Dortania Multiboot](https://dortania.github.io/OpenCore-Multiboot/)

---

## 0. Before you start (Windows side)

- [ ] **Decide where macOS goes:**
  - **Option A (safer, recommended): second NVMe** in the free M.2 slot. macOS gets its own disk *and its own EFI partition*; the Windows disk is never written to.
  - **Option B: ~100 GB partition on the Windows NVMe.** Shrink `C:` in Disk Management (`diskmgmt.msc` → right-click `C:` → *Shrink Volume*).
- [ ] For option B, **turn the free space into a labelled partition** so it is easy to recognise in macOS. In Disk Management: right-click the *Unallocated* space → *New Simple Volume* → format **exFAT**, label **`MACOS`**, no drive letter needed. (Disk Utility will later erase *only this partition* as APFS.)
- [ ] Write down the disk layout so you can recognise it later:

  ```powershell
  Get-Disk | Format-Table Number, FriendlyName, BusType, Size, PartitionStyle
  Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, Size, Type, GptType
  ```

- [ ] **Suspend BitLocker / device encryption** before changing BIOS settings (disabling Secure Boot otherwise triggers the recovery-key prompt). Admin PowerShell:

  ```powershell
  Get-BitLockerVolume -MountPoint C:
  Suspend-BitLocker -MountPoint C: -RebootCount 0   # 0 = stays suspended until you resume it (see section 10)
  ```

- [ ] BIOS settings from [BIOS.md](BIOS.md) (Secure Boot off, CSM off, Fast Boot off).
- [ ] **Plug in the Ethernet cable.** The recovery downloads macOS from Apple; RTL8111 (RealtekRTL8111.kext) is the network that works during install. Wi-Fi is not expected to work in the recovery.

---

## 1. Install macOS from the recovery (without touching Windows)

1. Boot the USB stick (ASUS boot menu key, usually **F8** – check), pick the **RECOVERY / macOS Base System** entry in the OpenCore picker.
2. In the recovery choose **Disk Utility**.
3. **View → Show All Devices** (otherwise you only see volumes, not disks and partitions).
4. **Identify the target – do not guess:**

   | You see | What it is | Touch it? |
   |---|---|---|
   | Disk ~512 GB "Union Memory …" with `EFI`, `Microsoft Reserved`, `Basic Data` (NTFS, ~400 GB), `Windows Recovery` | **Windows NVMe** | **NO** (except the `MACOS` partition in option B) |
   | Partition **`MACOS`** (ExFAT, ~100 GB) on the Union Memory disk | your macOS partition (option B) | yes – erase *this partition only* |
   | A second NVMe (different model/size) | macOS disk (option A) | yes – erase the *whole disk* |
   | Disk with `OPENCORE` + `RECOVERY` (USB) | your installer stick | no |

   Cross-check in Terminal (recovery menu → *Utilities → Terminal*), read-only:

   ```sh
   diskutil list          # match sizes/names with what you noted in Windows
   ```

5. **Erase:**
   - **Option A (second NVMe):** select the **disk** (top level) → *Erase* → Name `Macintosh HD`, Format **APFS**, Scheme **GUID Partition Map**. This also creates a fresh EFI partition on that disk.
   - **Option B (shared NVMe):** select **only the `MACOS` partition** (not the disk above it!) → *Erase* → Name `Macintosh HD`, Format **APFS**. There is no Scheme option here – if Disk Utility offers a *Scheme* field, you have selected the whole disk: **cancel**.

   > 🛑 **Never select the Union Memory disk itself and press Erase.** That wipes Windows, its EFI partition and the recovery partition. Erasing a whole disk is only for an empty second NVMe.

   Terminal alternative for option B (replace `diskXsY` with the identifier `diskutil list` shows for `MACOS`, check twice):

   ```sh
   diskutil eraseVolume APFS "Macintosh HD" diskXsY
   ```

   If Disk Utility complains about the EFI partition being too small (many OEM Windows installs use a 100 MB ESP; macOS prefers ≥ 200 MB) – check; stop there and use option A rather than resizing Windows partitions.
6. Quit Disk Utility → **Reinstall macOS Tahoe** → select `Macintosh HD` → wait (download over Ethernet, can take 30–60 min).

Source: [Dortania – Installation process](https://dortania.github.io/OpenCore-Install-Guide/installation/installation-process.html)

---

## 2. First boots during the install (several reboots)

The installer reboots **3–4 times**. **Keep the USB stick plugged in** and boot from it every time (OpenCore on the internal disk does not exist yet).

- [ ] In the OpenCore picker choose **`macOS Installer`** after each reboot (OpenCore usually pre-selects it; with Timeout 5 it boots automatically – check that it really picked the installer and not `RECOVERY` or `Windows`).
- [ ] Once `macOS Installer` disappears and only **`Macintosh HD`** is left, boot that → Setup Assistant.
- [ ] In Setup Assistant **skip Apple ID / iCloud sign-in for now** (see section 8) and skip Migration Assistant.
- [ ] Verbose mode (`-v`) stays on: if it hangs, take a photo of the last lines; the DEBUG log is also written to `opencore-*.txt` on the stick's OpenCore partition (`scripts\read_fat_logs.py`).

---

## 3. Boot from the internal disk (EFI copy + coexistence with Windows)

Only do this once macOS boots reliably **from the USB stick**. Until then, simply keep booting from the stick.

> 🛑 **Rules for the Windows EFI partition (option B):**
> - **Never delete, rename or overwrite `\EFI\Microsoft`.**
> - **Never overwrite an existing `\EFI\BOOT\BOOTx64.efi`** – on a Windows ESP this is usually Microsoft's fallback copy of the boot manager.
> - Add **only `\EFI\OC`**, and boot it through a **firmware boot entry** (below), not through `\EFI\BOOT`.
> - Back up the ESP before changing anything.

### 3a. Option A – second NVMe (simple)

The macOS disk has its own empty ESP. Copy the **complete** `EFI` folder (`EFI\BOOT` + `EFI\OC`) from the USB stick's OpenCore partition to it. From macOS:

```sh
diskutil list                         # find the EFI partition of the macOS NVMe, e.g. disk1s1
sudo diskutil mount disk1s1           # replace with your identifier
sudo diskutil mount disk2s1           # the USB stick's OPENCORE partition (check identifier)
cp -R /Volumes/OPENCORE/EFI /Volumes/EFI/   # check both volume names in Finder first
```

Then in the BIOS boot order put the new NVMe (UEFI) entry first, or use the boot menu. Windows Boot Manager stays on the Windows disk, untouched; OpenCore lists Windows as a picker entry (ScanPolicy 0).

### 3b. Option B – shared Windows ESP

1. **Check free space and back up** the ESP (admin PowerShell):

   ```powershell
   mountvol S: /S                       # mounts the system EFI partition as S:
   Get-ChildItem S:\EFI                 # expect at least: Microsoft, (Boot)
   Get-PSDrive S                        # free space: OpenCore EFI needs roughly 10-20 MB - check actual size of build\EFI
   robocopy S:\ C:\ESP-Backup /E /COPY:DAT   # full ESP backup
   ```

2. **Copy only the OC folder** (the `EFI\BOOT` folder from build\EFI is **not** copied):

   ```powershell
   robocopy .\build\EFI\OC S:\EFI\OC /E
   Get-ChildItem S:\EFI                 # now: Microsoft, Boot (unchanged), OC
   mountvol S: /D                       # unmount again
   ```

3. **Add a firmware boot entry for OpenCore** – two ways:

   **(i) OpenCore `LauncherOption` (preferred by Dortania)** – OpenCore creates and maintains its own UEFI boot entry pointing at `\EFI\OC\OpenCore.efi`. Needs `Misc/Boot/LauncherOption = Full` and `UEFI/Quirks/RequestBootVarRouting = true` in `config.plist`. `Build-EFI.ps1` currently does **not** set `LauncherOption` (check the generated config; Sample.plist default is `Disabled`), so for now edit `config.plist` on the ESP with ProperTree / a plist editor, or add it to the script later. The first boot into OpenCore still has to happen once from the USB stick (or a manual entry) so OpenCore can create the entry. Removing it later is **not** done with a plain NVRAM reset – see section 10. Source: [Dortania – LauncherOption](https://dortania.github.io/OpenCore-Post-Install/multiboot/bootstrap.html)

   **(ii) Manual entry with `bcdedit`** (admin PowerShell; check every step's output):

   ```powershell
   bcdedit /enum firmware                                   # look first: note existing entries
   bcdedit /copy "{bootmgr}" /d "OpenCore"                  # prints a new {GUID}
   bcdedit /set "{GUID}" path \EFI\OC\OpenCore.efi          # use the GUID from the line above
   bcdedit /set "{fwbootmgr}" displayorder "{GUID}" /addlast   # add at the END, Windows stays first
   bcdedit /enum firmware                                   # verify: device = the ESP partition, path = \EFI\OC\OpenCore.efi
   ```

   The copy inherits the device (the ESP) from `{bootmgr}`; only the path changes. Keep **Windows Boot Manager first** until OpenCore is proven, and select OpenCore via the boot menu (F8 – check). Move it to the top later in the BIOS boot order or with `bcdedit /set "{fwbootmgr}" displayorder "{GUID}" /addfirst`.

4. **Booting Windows:** OpenCore shows a `Windows` entry. Booting Windows *through* OpenCore also gives Windows the OpenCore ACPI tables and the Mac SMBIOS (`UpdateSMBIOSMode Create`), which can change how Windows sees the hardware (activation, drivers – check). Safer: boot Windows via **Windows Boot Manager from the BIOS boot menu**, or later switch to `UpdateSMBIOSMode Custom` + `CustomSMBIOSGuid` so the SMBIOS is only applied to macOS. See [Dortania – BootCamp / multiboot notes](https://dortania.github.io/OpenCore-Post-Install/multiboot/bootcamp.html).

> Windows updates or BIOS updates can reset the boot order or remove non-Microsoft entries. If OpenCore disappears, boot from the USB stick and re-add the entry.

---

## 4. DEBUG → RELEASE and boot-arg cleanup

Only when macOS boots reliably and you no longer need on-screen logs.

1. Rebuild with RELEASE OpenCore (default for `-Target Hardware` without `-DebugOpenCore`):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware
   ```

2. **The script still sets debug options for both flavours** – these have to be changed by hand in the new `build\EFI\OC\config.plist` (or in the script later):

   | Key | Current (script) | Clean |
   |---|---|---|
   | `NVRAM/Add/7C436110-…/boot-args` | `-v keepsyms=1 debug=0x100 alcid=11 ipc_control_port_options=0` | `alcid=11 ipc_control_port_options=0` (keep alcid; `ipc_control_port_options=0` came from the working 7840HS config – keep unless tested without) |
   | `Misc/Debug/Target` | `67` (screen + file log) | `3` or `0` |
   | `Misc/Debug/AppleDebug` | `true` | `false` |
   | `Misc/Debug/ApplePanic` | `true` | `false` |
   | `Misc/Boot/HideAuxiliary` | `false` | `true` (recovery & tools hidden; press **Space** in the picker to show them) |
   | `Misc/Boot/ShowPicker` | `true` | keep `true` (dual boot) |

3. Run `build\tools\ocvalidate.exe build\EFI\OC\config.plist`.
4. **Test on the USB stick first** (`scripts\New-UsbInstaller.ps1 -DiskNumber N -UpdateEfi` only replaces partition 1), then copy to the internal ESP as in section 3. On a shared Windows ESP replace only `\EFI\OC` (keep a copy of the old one, e.g. `\EFI\OC.bak` – check free space).
5. Delete old `opencore-*.txt` log files from the ESP.

Source: [Dortania – Fixing resolution and verbose / cosmetic](https://dortania.github.io/OpenCore-Post-Install/cosmetic/verbose.html), [Dortania – Debugging](https://dortania.github.io/OpenCore-Install-Guide/troubleshooting/debug.html)

---

## 5. USB port mapping (USBToolBox, on Windows)

macOS allows **max. 15 ports per USB controller**. This PC has **4 AMD xHCI controllers** (`1022:15BB`, `15BD`, `15C2`, `15C3`); the limit applies to each controller separately. `XhciPortLimit` stays **false** (already set by `Build-EFI.ps1`) – it is broken on newer macOS and risks data corruption.

1. Download `Windows.exe` from [USBToolBox/tool releases](https://github.com/USBToolBox/tool/releases) and run it in Windows.
2. **Discover Ports** → plug a **USB 2 stick** and a **USB 3 stick** into **every** port (front, back, both orientations of USB-C). With USB 3 ports, Windows usually binds the companion port automatically.
3. **Select Ports**: keep only physically used ports, **max. 15 per controller**. Set port types (USB 2, USB 3, Type-C with/without switch). Mark the **internal Bluetooth port** (Realtek BT, `0489:E123`) as **Internal** – do not drop it, or Bluetooth disappears.
4. **Build kext (K)** → `UTBMap.kext`. Also get **USBToolBox.kext** from [USBToolBox/kext releases](https://github.com/USBToolBox/kext/releases) (the map depends on it).
5. Add both to the EFI. `Fetch-EFI.ps1` wipes `build\EFI` on every run, so for now:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware   # normal build
   Copy-Item -Recurse <path>\USBToolBox.kext, <path>\UTBMap.kext build\EFI\OC\Kexts\
   powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -SkipFetch   # regenerates Kernel/Add incl. both kexts
   ```

   `USBToolBox.kext` sorts before `UTBMap.kext`, which is the required order. Keep `UTBMap.kext` somewhere outside `build\` (it is machine-specific; it may be committed, it contains no serials – check).
6. Verify in macOS: *System Information → USB* – every port works at the right speed, sleep/wake and Bluetooth still work.

Source: [Dortania – USB mapping](https://dortania.github.io/OpenCore-Post-Install/usb/), [USBToolBox/tool README](https://github.com/USBToolBox/tool)

---

## 6. Wi-Fi & Bluetooth (RTL8852BE)

### Wi-Fi – AirportRTW V2.3.3 (Tahoe build)

What the [AirportRTW README](https://github.com/souissiak1-maker/AirportRTW) and [releases](https://github.com/souissiak1-maker/AirportRTW/releases) say (as of V2.3.3):

- RTL8852BE (RTW89) is listed as supported. Sequoia 15.2+ / **Tahoe 26.x use an "experimental native Wi-Fi frontend"** (x86_64 only).
- V2.2.0 notes: native Sequoia/Tahoe frontend, **"no Wi-Fi root patches required"** → no OCLP root patch / IO80211FamilyLegacy needed for this frontend (per the release notes; check on this machine).
- README install steps: load order **Lilu → AMFIPass → AirportRTW**, and **`Misc/Security/SecureBootModel = Disabled`** (already set by `Build-EFI.ps1`).
- **Open point – AMFIPass:** it is in the README's load order but not explained, and it is **not** in `components.json` yet. Check whether the Tahoe build needs it on this machine (AMFIPass is distributed with OpenCore Legacy Patcher – check source/version). If added: it must load **before** AirportRTW, but `Build-EFI.ps1` sorts unknown kexts alphabetically (`AirportRTW` < `AMFIPass`), so the order would need fixing in the script.
- AWDL/AirDrop: experimental on RTW89 (V2.3.0 notes); Wi-Fi/BT coexistence is automatic since V2.3.1.
- Expect no Wi-Fi in the recovery; use Ethernet.

### Bluetooth – Realtek (USB `0489:E123`)

- `BlueToolFixup.kext` alone is **not** enough: Realtek BT chips need their firmware uploaded at every boot.
- Candidate: [RealtekBluetoothFirmware](https://github.com/thegwchr/RealtekBluetoothFirmware) ([docs](https://thegwchr.pages.dev/bluetooth/)) – needs Lilu + BlueToolFixup (macOS 12+); its supported-devices list includes **RTL8852B** (`rtl8852bu_fw.bin`). Whether the USB ID **`0489:E123`** (Foxconn module) is in its `Info.plist` is **not confirmed – check**; if not, the kext will not attach.
- Verify after boot:

  ```sh
  log show --last boot --predicate 'eventMessage CONTAINS "RealtekFirmware"'
  ```

- The BT port must be in the USB map (section 5) as **Internal**.
- Not added to `components.json` yet (KEXTS.md still lists the firmware kext as TBD).

---

## 7. Audio (ALC897) – trying layout-ids

Default is `alcid=11`. If there's no sound, or only some jacks work, try the ALC897 layouts from [AppleALC – Supported codecs](https://github.com/acidanthera/AppleALC/wiki/Supported-codecs): **11, 12, 13, 21, 23, 66, 69, 77, 98** (check the list for the current AppleALC version).

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Hardware -AlcLayout 12
```

Faster test without a full rebuild: edit `alcid=` in `boot-args` of the `config.plist` on the ESP/USB stick directly (the config's NVRAM values are rewritten on every boot, so `sudo nvram boot-args=…` in macOS will not stick – check).

For each layout, note in a table: rear line-out, front headphone, mic (front/rear), HDMI audio (unlikely without a GPU driver). Check *System Settings → Sound → Output/Input*. Keep the best one as default.

---

## 8. iServices (Apple ID, iMessage, FaceTime)

`Build-EFI.ps1 -NewSmbios` generates a **MacBookPro16,1** serial/MLB/UUID with `macserial` and stores it in **`smbios.local.json`** (git-ignored). ROM is set from the Realtek Ethernet MAC.

- [ ] **Keep `smbios.local.json` and the real `config.plist` private.** Never commit, upload or post screenshots of them (Serial, MLB, UUID, ROM). Back the JSON up somewhere safe – losing it means a new identity for Apple.
- [ ] **Check the serial** at <https://checkcoverage.apple.com>: you want a result saying the serial is **not valid / cannot be checked**. If it shows a real device or purchase date, it is in use → back up and delete `smbios.local.json`, rebuild with `-NewSmbios` (the script only generates a new one if the file is missing or the model differs).
- [ ] **en0 must be built-in:** `ifconfig en0` should be the Realtek Ethernet. In *System Information → Network* check it is listed and "built-in" (check how RealtekRTL8111 reports it; if not, Dortania describes adding the `built-in` property).
- [ ] NVRAM must work (`WriteFlash` is true) – check: `sudo nvram -p | head` shows values and they survive a reboot.
- [ ] Sign in to the App Store / iCloud first, iMessage last. If Apple rejects the login with a "customer code", contact Apple support rather than repeatedly generating new serials.

Source: [Dortania – Fixing iServices](https://dortania.github.io/OpenCore-Post-Install/universal/iservices.html)

---

## 9. Radeon 740M acceleration (nullarc) — experimental, later

**Not supported yet.** macOS currently runs on the unaccelerated firmware framebuffer (GOP) over HDMI: no Metal, no QE/CI, sluggish UI, no brightness/HDMI audio.

- [nullarc](https://github.com/luuumi-dev/nullarc) / [RadeArc](https://github.com/Kreytus/RadeArc) target Phoenix/Hawk Point iGPUs, but the 740M device ID **`1002:1901` is not in nullarc** yet, and **HDMI/DP output is not supported** by them yet (only internal eDP panels). On this desktop that means no picture.
- Would also need AMFIPass and further config changes (see [KEXTS.md](KEXTS.md)).
- Will be tested **only via a separate boot config** (a second USB stick / separate EFI copy), never on the working internal EFI.

---

## 10. Rollback (back to plain Windows)

1. **Remove OpenCore from the boot order:**
   - Manual `bcdedit` entry: `bcdedit /enum firmware` → `bcdedit /delete "{GUID}"` (the OpenCore GUID – **not** `{bootmgr}`).
   - `LauncherOption` entry: set `LauncherOption = Disabled` first, then reset NVRAM from the OpenCore picker (*Reset NVRAM*, needs `HideAuxiliary false` or Space). A plain NVRAM reset while LauncherOption is enabled keeps the entry. With OpenCore ≥ 0.8 the reset is done by `ResetNvramEntry.efi` – check its options before using it.
   - Or simply move **Windows Boot Manager** to the top in the BIOS boot order.
2. **Remove the files (option B):** `mountvol S: /S` → `Remove-Item -Recurse S:\EFI\OC` → `mountvol S: /D`. Never touch `S:\EFI\Microsoft` / `S:\EFI\Boot`. (Option A: just remove/erase the second NVMe.)
3. **macOS partition (option B):** in Disk Management delete the APFS partition and *Extend Volume* on `C:` (only works if the free space is directly after `C:`; otherwise leave it or use a partition tool – check).
4. **Restore Secure Boot:** BIOS → **Boot → Secure Boot → OS Type = Windows UEFI Mode**. Check with `Confirm-SecureBootUEFI` (admin PowerShell → `True`).
5. **Resume BitLocker** (admin PowerShell):

   ```powershell
   Resume-BitLocker -MountPoint C:
   Get-BitLockerVolume -MountPoint C:       # ProtectionStatus = On
   ```

6. **Re-enable Memory Integrity:** *Windows Security → Device security → Core isolation → Memory integrity = On*, reboot.
7. **Re-enable the Hyper-V hypervisor launch** (if it was switched off for VirtualBox testing):

   ```powershell
   bcdedit /set hypervisorlaunchtype auto
   ```

   Reboot afterwards.

---

## Sources

- Dortania: [Install Guide](https://dortania.github.io/OpenCore-Install-Guide/) · [Post-Install](https://dortania.github.io/OpenCore-Post-Install/) · [LauncherOption](https://dortania.github.io/OpenCore-Post-Install/multiboot/bootstrap.html) · [BootCamp/multiboot](https://dortania.github.io/OpenCore-Post-Install/multiboot/bootcamp.html) · [USB mapping](https://dortania.github.io/OpenCore-Post-Install/usb/) · [iServices](https://dortania.github.io/OpenCore-Post-Install/universal/iservices.html) · [OpenCore Multiboot](https://dortania.github.io/OpenCore-Multiboot/)
- OpenCore reference: `Docs/Configuration.pdf` in [OpenCorePkg 1.0.8](https://github.com/acidanthera/OpenCorePkg/releases)
- [USBToolBox tool](https://github.com/USBToolBox/tool) · [USBToolBox kext](https://github.com/USBToolBox/kext)
- [AirportRTW](https://github.com/souissiak1-maker/AirportRTW) · [RealtekBluetoothFirmware docs](https://thegwchr.pages.dev/bluetooth/)
- [AppleALC supported codecs](https://github.com/acidanthera/AppleALC/wiki/Supported-codecs)
- [nullarc](https://github.com/luuumi-dev/nullarc) · [RadeArc](https://github.com/Kreytus/RadeArc)
