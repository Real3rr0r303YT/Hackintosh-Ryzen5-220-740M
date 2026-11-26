#!/bin/bash
# One double-click after a fresh macOS install (Finder -> USB stick RECOVERY -> Hackintosh-Setup.command):
#   1. checks that macOS was started with the GPU EFI from the SSD (Install-EfiToDisk.ps1 -Source build\EFI-GPU-accel)
#   2. mouse: "natural scrolling" off (wheel down = page down, like Windows)
#   3. GPU acceleration: stage 1 now, stage 2 (desktop on the GPU, Liquid Glass) installs itself after the next start.
#      If RadeArc is already installed, it is updated (stage 1+2 at once).
# Sound (SimpleHDA + AppleALC), Wi-Fi and Bluetooth come from the EFI and need nothing here.
G="$(cd "$(dirname "$0")" && pwd)/gpu"
dialog(){ osascript -e "display dialog \"$1\" with title \"Hackintosh Setup\" buttons {\"OK\"} default button 1 with icon $2" >/dev/null 2>&1; printf "%b\n" "$1"; }
clear
echo "== Hackintosh Setup (Radeon 740M) =="

[ -f "$G/install-gpu.sh" ] && [ -f "$G/pkg/radearc-package.zip" ] || {
    dialog "Der Ordner gpu mit dem GPU-Paket fehlt auf dem Stick.\n\nIn Windows den Stick neu schreiben (New-UsbInstaller.ps1 -UpdateEfi)." stop; exit 1; }

ARGS=$(nvram boot-args 2>/dev/null)
if ! echo "$ARGS" | grep -q -- "-phxp2" || ! echo "$ARGS" | grep -q "amfi_get_out_of_my_way"; then
    dialog "macOS wurde nicht mit der GPU-EFI gestartet (z.B. vom Stick).\n\n1. Windows starten, Admin-PowerShell:\n   Install-EfiToDisk.ps1 -Source build\\\\EFI-GPU-accel\n2. Ohne Stick neu starten, im Menue den Piraten-Apfel waehlen\n3. Diese Datei noch einmal doppelklicken." caution
    exit 1
fi

echo "== Maus: natuerliches Scrollen aus"
defaults write -g com.apple.swipescrolldirection -bool false

echo "== GPU-Beschleunigung"
echo "   Gleich wird dein macOS-Passwort abgefragt (Eingabe bleibt unsichtbar)."
if [ -d /Library/Extensions/PhxAccel.kext ]; then
    echo "   RadeArc ist schon installiert: Update (Stufe 1+2)."
    bash "$G/install-gpu.sh" ws
else
    bash "$G/install-gpu.sh"
fi
