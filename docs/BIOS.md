# BIOS settings (ASUS PM500MH)

> Draft. Names in the ASUS BIOS may differ, fill in exactly once checked.

| Setting | Value | Why |
|---|---|---|
| Secure Boot | **Disabled** | OpenCore isn't signed for Microsoft's Secure Boot |
| CSM | **Disabled** | pure UEFI boot |
| Above 4G Decoding | Enabled (if available) | needed for modern GPUs |
| Resizable BAR | Disabled | can cause trouble in macOS |
| SVM (virtualization) | Disabled at first | rules out an error source |
| Fast Boot | Disabled | so USB is detected at boot |
| UMA frame buffer (iGPU memory) | 2 GB or more (if available) | more VRAM for the iGPU |
| TPM / fTPM | leave as is | Windows 11 needs it |
