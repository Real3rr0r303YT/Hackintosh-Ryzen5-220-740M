# Offline install (no internet in Recovery)

The Tahoe Recovery normally downloads macOS. Without working Wi-Fi/LAN we install
from Apple's full `InstallAssistant.pkg` instead.

## Windows side

1. Shrink C: and create two exFAT partitions (admin PowerShell):

   ```powershell
   Resize-Partition -DriveLetter C -Size ((Get-Partition -DriveLetter C).Size - 130GB)
   New-Partition -DiskNumber 0 -Size 30GB -AssignDriveLetter | Format-Volume -FileSystem exFAT -NewFileSystemLabel MACPKG -Confirm:$false
   New-Partition -DiskNumber 0 -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem exFAT -NewFileSystemLabel MACOS -Confirm:$false
   ```

2. Download the full installer from Apple's CDN to MACPKG
   (macOS Tahoe 26.6.2, build 25G83, 18,384,624,402 bytes; URL from Apple's software update catalog):

   ```powershell
   curl.exe -L -C - --retry 10 -o D:\InstallAssistant.pkg "https://swcdn.apple.com/content/downloads/37/33/140-93587-A_GRFFH93NOL/f944yaqo1cjhh2m0kxrl0zhcpg9yb9qphv/InstallAssistant.pkg"
   ```

3. Copy [`scripts/offline-install.sh`](../scripts/offline-install.sh) to MACPKG (LF line endings).
4. Put the no-Wi-Fi EFI on the stick: `New-UsbInstaller.ps1 -DiskNumber 1 -UpdateEfi -Source build\EFI-nowifi`.

## Recovery side

1. Boot the stick (F8), pick the Recovery, open **Utilities → Terminal**.
2. `sh /Volumes/MACPKG/offline-install.sh`
   - erases only the volume named **MACOS** as APFS "Macintosh HD" (asks for `JA` first),
   - unpacks the installer app with `installer -pkg`,
   - starts `startosinstall`.
3. At each reboot pick the stick, then "macOS Installer" / "Macintosh HD" in OpenCore.

A wrong system date makes the package signature check fail; check it with `date`.
After the install MACPKG can be deleted.
