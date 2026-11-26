#!/bin/bash
# Runs once at boot (LaunchDaemon local.radearc.stage2) after stage 1 was installed.
# If phxboot brought the GPU up, install stage 2 (--windowserver); tell the user in a dialog; remove itself.
D=/Users/Shared/gpu/stage2
LOG=$D/stage2.log
exec >>"$LOG" 2>&1
echo "== $(date) stage2 start"
for i in $(seq 1 72); do grep -q "done" /var/log/phxboot.log 2>/dev/null && break; sleep 5; done
OK=0; grep -q "done" /var/log/phxboot.log 2>/dev/null && OK=1
echo "== phxboot ok=$OK"; tail -30 /var/log/phxboot.log 2>/dev/null
system_profiler SPDisplaysDataType 2>/dev/null | grep -iE "Chipset|Metal|Vendor|Device ID"
for i in $(seq 1 120); do U=$(stat -f %Su /dev/console); [ -n "$U" ] && [ "$U" != root ] && break; sleep 5; done
U=$(stat -f %Su /dev/console); UIDN=$(id -u "$U" 2>/dev/null)
tell(){ [ -n "$UIDN" ] && launchctl asuser "$UIDN" sudo -u "$U" osascript -e "display dialog \"$1\" with title \"Radeon 740M\" buttons {\"OK\"} default button 1 with icon $2" >/dev/null 2>&1; }
if [ $OK = 1 ]; then
    (cd "$D/radearc-package" && bash ./install.sh --windowserver); RC=$?
    echo "== install.sh --windowserver rc=$RC"
    if [ $RC = 0 ]; then
        tell "Stufe 1 OK: die GPU laeuft.\nStufe 2 ist jetzt installiert!\n\nNoch EINMAL neu starten (im OpenCore-Menue Macintosh HD waehlen): danach laeuft der ganze Desktop auf der GPU." note
    else
        tell "Stufe 1 OK, aber Stufe 2 meldet Fehler $RC.\nWindows starten und Claude 'fertig' schreiben." caution
    fi
else
    tell "Die GPU ist nach Stufe 1 nicht sauber hochgefahren.\nStufe 2 wurde NICHT installiert (Sicherheit).\nWindows starten und Claude 'fertig' schreiben." stop
fi
rm -f /Library/LaunchDaemons/local.radearc.stage2.plist
for G in /Volumes/RECOVERY/gpu /Volumes/MACPKG/gpu; do [ -d "$G" ] && { cp "$LOG" "$G/stage2.log"; cp /var/log/phxboot.log "$G/phxboot.log" 2>/dev/null; sync; }; done
launchctl bootout system/local.radearc.stage2 2>/dev/null
