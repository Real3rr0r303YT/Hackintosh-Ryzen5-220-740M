# Hardware

Read from Windows 11 (PnP / WMI) on 2026-11-24.

## System

- **Model:** ASUS V500 Mini Tower, `VM501MH`
- **Board:** ASUSTeK `PM500MH`
- **BIOS:** AMI, version `PM500MH.306` (2026-02-25), UEFI boot
- **PSU:** 180 W (80+ Bronze), according to reviews of the Ryzen 5 220 configuration
- **Expansion:** 1× PCIe 4.0 x16, 2× M.2 2280 (storage), 1× M.2 (Wi-Fi), 1× SATA, 2× DDR5 SO-DIMM

## PCI devices

| Class | Device | Vendor:Device | Subsystem |
|---|---|---|---|
| Display | AMD Radeon 740M | `1002:1901` | `1043:1644` |
| Net | Realtek RTL8852BE Wi-Fi 6 | `10EC:B852` | `105B:E111` |
| Net | Realtek PCIe GbE (RTL8111/8168) | `10EC:8168` | `1043:205F` |
| NVMe | Union Memory (RPETJ512MMW1MDA) | `1CC4:6B03` | `1CC4:6B03` |
| SATA | ASMedia ASM1062 | `1B21:1062` | `1043:8840` |
| USB | AMD xHCI | `1022:15BB` | `1043:201F` |
| USB | AMD xHCI | `1022:15BD` | `1043:201F` |
| USB | AMD xHCI | `1022:15C2` | `1022:15C2` |
| USB | AMD xHCI | `1022:15C3` | `1022:15C3` |
| SMBus | AMD FCH SMBus | `1022:790B` | `1043:1644` |

## USB devices

| Device | VID:PID |
|---|---|
| Realtek Bluetooth (on RTL8852BE) | `0489:E123` |

## Audio

| Codec | ID |
|---|---|
| Realtek ALC897 | `10EC:0897`, subsystem `1043:2960` |
| AMD HDMI/DP audio | `1002:AA01` |

## Notes

- The iGPU reports device ID **`1901`**, not `15BF` (Phoenix 1) or `15C8` (Phoenix 2). RadeArc currently targets `15C8`, so support for `1901` has to be checked or added.
- The monitor is connected via **HDMI**.
