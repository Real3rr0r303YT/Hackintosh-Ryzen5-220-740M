#!/bin/sh
# Offline install of macOS Tahoe from the macOS Recovery Terminal.
# Needs: exFAT volume "MACPKG" with InstallAssistant.pkg, target volume "MACOS" (or "Macintosh HD").
# Usage in Recovery -> Terminal:   sh /Volumes/MACPKG/offline-install.sh
PKG="/Volumes/MACPKG/InstallAssistant.pkg"
TARGET="/Volumes/Macintosh HD"

echo "== macOS Offline-Installation =="
date
[ -f "$PKG" ] || { echo "FEHLER: $PKG nicht gefunden."; exit 1; }

if [ -d "/Volumes/MACOS" ]; then
    DEV=$(diskutil info /Volumes/MACOS | awk -F: '/Device Node/ {gsub(/ /, "", $2); print $2}')
    [ -n "$DEV" ] || { echo "FEHLER: Geraet von MACOS nicht gefunden."; exit 1; }
    echo ""
    echo "Die Partition MACOS ($DEV, ca. 100 GB) wird GELOESCHT und als APFS 'Macintosh HD' formatiert."
    echo "Windows (C:) und MACPKG werden NICHT angefasst."
    printf "Zum Fortfahren JA eintippen: "
    read answer
    [ "$answer" = "JA" ] || { echo "Abgebrochen, nichts geaendert."; exit 1; }
    diskutil eraseVolume APFS "Macintosh HD" "$DEV" || { echo "FEHLER beim Formatieren."; exit 1; }
fi
[ -d "$TARGET" ] || { echo "FEHLER: $TARGET fehlt."; exit 1; }

echo ""
echo "1/2: Installer-App auspacken (ca. 5-15 Min) ..."
installer -pkg "$PKG" -target "$TARGET" || { echo "FEHLER: installer -pkg. Pruefe Datum (date) - falsches Datum = Signaturfehler."; exit 1; }

APP=$(ls -d "$TARGET"/Applications/Install\ macOS*.app 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "FEHLER: Install-App nicht gefunden."; exit 1; }
echo "2/2: Installation starten mit $APP"
echo "Der PC startet danach mehrmals neu: im OpenCore-Menue jedes Mal 'macOS Installer' bzw. 'Macintosh HD' waehlen."
"$APP/Contents/Resources/startosinstall" --agreetolicense --volume "$TARGET"
