# Radeon 740M acceleration (experimental)

> ⚠️ Alpha software. Test on a **separate USB stick** with `build\EFI-GPU`; the normal EFI stays your fallback.

## Why RadeArc and not nullarc

| | nullarc (upstream) | RadeArc (740M fork) |
|---|---|---|
| Chip detection | by PCI ID, 1901 → wrong 780M profile (12 CU) | by IP discovery (GC 11.0.4 → Phoenix 2) |
| Firmware | Phoenix 1 only (`gc_11_0_1`, `psp_13_0_4`) | picked from IP versions (`gc_11_0_4`, `psp_13_0_11`) |
| HDMI on a desktop | not yet | GOP-head takeover tested on a Ryzen 5 8500G over HDMI |

`1002:1901` (Hawk Point 2) is the **same silicon as `15C8`** (Phoenix 2): GC 11.0.4, MP 13.0.11, DCN 3.1.4, VCN 4.0.2, 4 CU (measured on a 1901 in [nullarc #29](https://github.com/luuumi-dev/nullarc/issues/29)). It only lacked the PCI matches.

## Our fork

[Real3rr0r303YT/RadeArc](https://github.com/Real3rr0r303YT/RadeArc), commit `1af4069`: adds `0x19011002` to PhxBringup, PhxAccel (PhxFB + NMXAccel) and PhxProbe, plus a package check. Built by GitHub Actions on macOS runners (no Mac needed):

| Workflow | Status |
|---|---|
| Build kexts | ✅ |
| Build Mesa RADV | ✅ |
| Build install package | ⚠️ package built; release upload failed during a GitHub outage (HTTP 500), re-run later |

Get the kexts locally:

```powershell
gh run download <build-kexts run id> -R Real3rr0r303YT/RadeArc -n kexts -D build\gpu\kexts
powershell -ExecutionPolicy Bypass -File scripts\Build-EFI.ps1 -Target Gpu -DebugOpenCore
```

`build\EFI-GPU` = normal hardware EFI + `PhxBringup.kext` (MinKernel 25.0.0) + `phxdebug=1`. **No `-phxp2`**, so PhxBringup only reads the GPU.

## Test order (from RadeArc `docs/TEST_PHOENIX2.md`)

Only after macOS is **fully installed** (not from the recovery):

1. **Test A, read-only** (`build\EFI-GPU` as is): `phx-chip` must say Phoenix 2, `phx-gc-version` 720900.
2. Add `-phxp2`, run tests B/C (`full.sh`, watchdog reboot after 3–4 min), then D (RADV).
3. `install.sh` **without** `--windowserver`: Metal for apps only, desktop stays on the GOP framebuffer.
4. Last: `--windowserver` (enable auto-login first, in case the login screen stays black).

Needed for steps 3–4 (not in the EFI yet): AMFIPass + `amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta`, `csr-active-config 7F080000`. Consequence: library validation off, FairPlay (Apple TV+, Netflix in Safari) stops working.

**Never run** the `testj`/`testl*` scripts: display experiments, one of them took the whole DCN block down.

## Install (stage 1 + automatic stage 2)

From the USB stick (`New-UsbInstaller.ps1` puts the `gpu` folder on its RECOVERY partition), booted with `build\EFI-GPU-accel`:

```sh
bash /Volumes/RECOVERY/gpu/install-gpu.sh
```

`install.sh --check`, then stage 1 (Metal for apps), auto-login, and a one-shot LaunchDaemon (`local.radearc.stage2`) that runs `install.sh --windowserver` at the next boot only if `phxboot` reported `done`. Logs: `install-gpu.log`, `stage2.log`, `phxboot.log` in the stick's `gpu` folder.

**Kill switch:** if a boot is cut off while the GPU starts (restart too early), `phxboot` writes `/Users/Shared/gpu/phxboot-off` and later boots stay on the GOP framebuffer (white wallpaper, no Liquid Glass). `bash /Volumes/RECOVERY/gpu/gpu-reset.sh` removes it; then restart and wait 1-2 minutes after the desktop appears.

## Escape hatches

- Boot the USB stick (`build\EFI-usb`, no PhxBringup, SIP on)
- Boot-args `-phxoff`, `-phxfboff`, `-phxbringupoff`
- `sudo touch /Users/Shared/gpu/phxboot-off`, or RadeArc's `uninstall.sh`

## Licenses

PhxBringup/tools: MIT or GPL-2.0. PhxAccel / NM plugin: **PolyForm Noncommercial 1.0.0**. AMD firmware: `LICENSE.amdgpu` (binary only). None of it is redistributed in this repo.
