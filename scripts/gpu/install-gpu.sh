#!/bin/bash
# RadeArc GPU acceleration for the Radeon 740M.
#   bash install-gpu.sh        stage 1 now (Metal for apps); stage 2 (desktop on the GPU) runs automatically at the
#                              next boot, but only if the GPU came up cleanly after stage 1.
#   bash install-gpu.sh ws     stage 1+2 at once (no automatic check in between)
# Needs the EFI-GPU-accel boot (amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1 -phxp2, SIP 7F080000).
M="$(cd "$(dirname "$0")" && pwd)"   # folder of this script (USB stick RECOVERY/gpu or MACPKG/gpu)
WS=""; [ "$1" = "ws" ] && WS="--windowserver"
dialog(){ osascript -e "display dialog \"$1\" with title \"Radeon 740M Installation\" buttons {\"OK\"} default button 1 with icon $2" >/dev/null 2>&1; printf "%b\n" "$1"; }

rm -rf ~/gpu/pkg && mkdir -p ~/gpu/pkg
ditto -x -k "$M/pkg/radearc-package.zip" ~/gpu/pkg || { dialog "Entpacken fehlgeschlagen." stop; exit 1; }
cd ~/gpu/pkg/radearc-package || { dialog "Paketordner fehlt." stop; exit 1; }
xattr -dr com.apple.quarantine . 2>/dev/null
echo "== csrutil / boot-args"; csrutil status; nvram boot-args
sudo rm -f /Users/Shared/gpu/phxboot-off   # old kill switch from an interrupted boot would keep the GPU off

echo "== Pruefung (aendert nichts)"
sudo bash ./install.sh --check 2>&1 | tee "$M/install-check.log"
if ! grep -q "All checks passed" "$M/install-check.log"; then
    dialog "Die Pruefung ist fehlgeschlagen, es wurde NICHTS installiert.\n\nWindows starten und Claude 'fertig' schreiben." stop
    exit 1
fi

echo "== Installation Stufe 1 $WS"
sudo bash ./install.sh $WS 2>&1 | tee "$M/install-gpu.log"
RC=${PIPESTATUS[0]}
sync
[ "$RC" = 0 ] || { dialog "Installation mit Fehler $RC beendet.\n\nWindows starten und Claude 'fertig' schreiben." caution; exit 1; }

echo "== Automatische Anmeldung einschalten (Anmeldebildschirm kann mit GPU-Desktop schwarz bleiben)"
echo "   Gib gleich dein macOS-Passwort ein (fuer die automatische Anmeldung):"
sudo sysadminctl -autologin set -userName "$(id -un)" -password - || echo "   Bitte von Hand: Systemeinstellungen > Benutzer & Gruppen > Automatische Anmeldung"

if [ -n "$WS" ]; then
    dialog "Stufe 1+2 installiert!\n\nZweimal neu starten (jeweils im OpenCore-Menue Macintosh HD): danach laeuft der Desktop auf der GPU." note
    exit 0
fi

echo "== Stufe 2 fuer den naechsten Start vormerken"
sudo mkdir -p /Users/Shared/gpu/stage2
sudo rm -rf /Users/Shared/gpu/stage2/radearc-package
sudo cp -R ~/gpu/pkg/radearc-package /Users/Shared/gpu/stage2/
sudo cp "$M/stage2.sh" /Users/Shared/gpu/stage2/stage2.sh
sudo cp "$M/local.radearc.stage2.plist" /Library/LaunchDaemons/local.radearc.stage2.plist
sudo chown root:wheel /Library/LaunchDaemons/local.radearc.stage2.plist
sudo chmod 644 /Library/LaunchDaemons/local.radearc.stage2.plist
sync
dialog "Stufe 1 installiert (GPU fuer Apps)!\n\nJetzt neu starten (im OpenCore-Menue Macintosh HD waehlen).\nNach dem Start prueft der PC 1-3 Minuten lang die GPU und installiert dann AUTOMATISCH Stufe 2.\nDu bekommst dann ein Fenster mit dem Ergebnis." note
