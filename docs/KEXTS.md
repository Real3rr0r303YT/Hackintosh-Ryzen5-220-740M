# Kexts, drivers & tools

Not included in the repo, download them from the official sources. Versions get pinned here once tested.

## OpenCore

| File | Source | Version |
|---|---|---|
| OpenCore (BOOTx64.efi, OpenCore.efi, OpenRuntime.efi, OpenShell.efi …) | [acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg/releases) | TBD |
| HfsPlus.efi | [acidanthera/OcBinaryData](https://github.com/acidanthera/OcBinaryData) | TBD |

## Kexts

| Kext | Purpose | Source | Version |
|---|---|---|---|
| Lilu | patching framework | [acidanthera/Lilu](https://github.com/acidanthera/Lilu/releases) | TBD |
| VirtualSMC | SMC emulation | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC/releases) | TBD |
| SMCAMDProcessor / AMDRyzenCPUPowerManagement | CPU power / sensors | [trulyspinach/SMCAMDProcessor](https://github.com/trulyspinach/SMCAMDProcessor/releases) | TBD |
| AppleALC | audio (ALC897) | [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC/releases) | TBD |
| RealtekRTL8111 | Ethernet | [Mieze/RTL8111_driver_for_OS_X](https://github.com/Mieze/RTL8111_driver_for_OS_X/releases) | TBD |
| NVMeFix | NVMe power management | [acidanthera/NVMeFix](https://github.com/acidanthera/NVMeFix/releases) | TBD |
| RestrictEvents | misc fixes | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents/releases) | TBD |
| AirPort_RTW89 | Wi-Fi RTL8852BE (experimental) | [Skensy/AirPort_RTW89](https://github.com/Skensy/AirPort_RTW89) | TBD |
| BlueToolFixup (BrcmPatchRAM) | Bluetooth stack fix | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) | TBD |
| Realtek BT firmware kext | Bluetooth firmware | TBD | TBD |
| USB map (USBToolBox) | USB ports | [USBToolBox](https://github.com/USBToolBox/tool) | generated per machine |

## Later: GPU acceleration

Only add these once HDMI/DP output is supported:

| Kext | Source |
|---|---|
| PhxBringup / PhxAccel | [luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) / [Kreytus/RadeArc](https://github.com/Kreytus/RadeArc) |
| AMFIPass | needed by nullarc (AMFI relaxation) |

## AMD CPU patches

Kernel patches from [AMD-OSX/AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla), with the core count set to **6** (`06`).
