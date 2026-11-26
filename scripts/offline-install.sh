#!/bin/sh
# Offline install of macOS Tahoe from the macOS Recovery Terminal.
# Needs: exFAT volume "MACPKG" with InstallAssistant.pkg, target volume "MACOS" (or "Macintosh HD").
# Usage in Recovery -> Terminal:   sh /Volumes/MACPKG/offline-install.sh
#
# Safe to run again after an error: steps that are already done are skipped.
# Every run writes a log to MACPKG (offline-install.log) that can be read from Windows.
#
# Why step 2 exists: InstallAssistant.pkg only unpacks a ~50 MB stub app. Its postinstall
# script (link_shared_support.bash) then has to copy the whole 18 GB package into
# "Install macOS Tahoe.app/Contents/SharedSupport/SharedSupport.dmg". In Recovery that
# script often fails, so this script checks the result and does the copy itself.

MACPKG="/Volumes/MACPKG"
PKG="$MACPKG/InstallAssistant.pkg"
TARGET="/Volumes/Macintosh HD"
APP="$TARGET/Applications/Install macOS Tahoe.app"
SS_DIR="$APP/Contents/SharedSupport"
SS="$SS_DIR/SharedSupport.dmg"
LOG="$MACPKG/offline-install.log"

say() { echo "$*"; echo "$*" >> "$LOG" 2>/dev/null; }
save_logs() {
    {
        echo ""
        echo "===== $(date) ====="
        echo "--- diskutil list ---"; diskutil list 2>&1
        echo "--- df -h ---"; df -h 2>&1
        echo "--- ls Applications ---"; ls -la "$TARGET/Applications" 2>&1
        echo "--- ls SharedSupport ---"; ls -la "$SS_DIR" 2>&1
        echo "--- tail install.log ---"; tail -300 /var/log/install.log 2>&1
    } >> "$LOG" 2>/dev/null
}
fail() {
    say "FEHLER: $*"
    save_logs
    say ""
    say "Log gespeichert auf MACPKG: offline-install.log"
    say "Windows starten und Claude Bescheid geben, der Log wird von dort gelesen."
    exit 1
}
size_of() { stat -f %z "$1" 2>/dev/null || echo 0; }

echo "" >> "$LOG" 2>/dev/null
say "== macOS Offline-Installation =="
say "Datum: $(date)"
[ -f "$PKG" ] || fail "$PKG nicht gefunden."
PKG_SIZE=$(size_of "$PKG")
say "Installer: $PKG_SIZE Bytes"
[ "$PKG_SIZE" -gt 10000000000 ] || fail "InstallAssistant.pkg ist zu klein, Download unvollstaendig?"

# Step 0: format the MACOS partition (only on the first run, afterwards it is called "Macintosh HD")
if [ -d "/Volumes/MACOS" ]; then
    DEV=$(diskutil info /Volumes/MACOS | awk -F: '/Device Node/ {gsub(/ /, "", $2); print $2}')
    [ -n "$DEV" ] || fail "Geraet von MACOS nicht gefunden."
    echo ""
    echo "Die Partition MACOS ($DEV, ca. 100 GB) wird GELOESCHT und als APFS 'Macintosh HD' formatiert."
    echo "Windows (C:) und MACPKG werden NICHT angefasst."
    printf "Zum Fortfahren JA eintippen: "
    read answer
    [ "$answer" = "JA" ] || { say "Abgebrochen, nichts geaendert."; exit 1; }
    diskutil eraseVolume APFS "Macintosh HD" "$DEV" || fail "Formatieren fehlgeschlagen."
fi
[ -d "$TARGET" ] || fail "$TARGET fehlt (Partition nicht gefunden)."

# Step 1: unpack the installer app (skipped if it is already there from an earlier run)
if [ -x "$APP/Contents/Resources/startosinstall" ]; then
    say "1/3: Installer-App ist schon ausgepackt, ueberspringe."
else
    say ""
    say "1/3: Installer-App auspacken (1-15 Min) ..."
    installer -pkg "$PKG" -target "$TARGET" -verboseR >> "$LOG" 2>&1
    RC=$?
    if [ $RC -ne 0 ]; then
        say "Hinweis: installer meldet Fehler $RC. Meist ist das nur das Apple-Hilfsskript, wird in Schritt 2 repariert."
    fi
    [ -x "$APP/Contents/Resources/startosinstall" ] || fail "Installer-App wurde nicht ausgepackt (Datum korrekt? 'date' eintippen)."
fi

# Step 2: make sure SharedSupport.dmg is complete (this is what Apple's postinstall should have done)
SS_SIZE=$(size_of "$SS")
if [ "$SS_SIZE" = "$PKG_SIZE" ]; then
    say "2/3: SharedSupport.dmg ist vollstaendig, ueberspringe."
else
    say ""
    say "2/3: Kopiere das 18-GB-Paket in die Installer-App (5-15 Min, keine Fortschrittsanzeige, bitte warten) ..."
    rm -f "$SS"
    mkdir -p "$SS_DIR" && chmod 0755 "$SS_DIR" || fail "Ordner SharedSupport konnte nicht angelegt werden."
    cp "$PKG" "$SS.part" || { rm -f "$SS.part"; fail "Kopieren fehlgeschlagen (Platz? siehe df -h im Log)."; }
    mv "$SS.part" "$SS" || fail "Umbenennen fehlgeschlagen."
    chmod 0644 "$SS"
    chown root:wheel "$SS" 2>/dev/null
    chflags -h norestricted "$SS" 2>/dev/null
    SS_SIZE=$(size_of "$SS")
    [ "$SS_SIZE" = "$PKG_SIZE" ] || fail "Kopie ist unvollstaendig ($SS_SIZE statt $PKG_SIZE Bytes)."
    say "Kopie fertig und vollstaendig."
fi

# Step 3: start the real installation
save_logs
say ""
say "3/3: Installation starten ..."
say "Der PC startet danach mehrmals neu: jedes Mal F8, den Stick waehlen, dann im OpenCore-Menue"
say "'macOS Installer' und spaeter 'Macintosh HD' waehlen."
"$APP/Contents/Resources/startosinstall" --agreetolicense --volume "$TARGET" 2>&1 | tee -a "$LOG"

# startosinstall only returns if it did not start (it reboots on success).
say ""
say "startosinstall hat nicht neu gestartet. Oeffne stattdessen den grafischen Installer ..."
save_logs
"$APP/Contents/MacOS/InstallAssistant" >> "$LOG" 2>&1 \
    || fail "Grafischer Installer liess sich nicht starten."
