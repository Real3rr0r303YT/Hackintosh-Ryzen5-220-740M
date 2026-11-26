#!/bin/sh
# Kernel-log recorder for macOS Recovery (Tahoe 26) + optional runtime load of AirportRTW.kext.
# Usage in Recovery -> Terminal:   sh /Volumes/MACPKG/recovery-debug.sh
#        only record, no kext:     sh /Volumes/MACPKG/recovery-debug.sh nokext
#
# Why: the PC hard-freezes (no panic), so nothing is written anywhere. This script keeps the
# kernel log on the exFAT partition MACPKG (D: in Windows) and runs `sync` every 2 s, so the
# last seconds before a freeze survive:
#   debug-<time>.log         kernel log stream (log stream, process == "kernel", level debug)
#   debug-<time>-dmesg.log   kernel ring buffer (dmesg), rewritten every 2 s (backup if the
#                            stream above is buffered and loses its last lines)
#   debug-<time>-info.log    SIP/NVRAM/kext status and the output of the load attempts
#
# Wi-Fi test: boot Recovery with an EFI where AirportRTW is DISABLED (Build-EFI.ps1 -NoWireless
# -SipOff), copy AirportRTW.kext to MACPKG, run this script. It then loads the kext at runtime.
#
# Runtime kext loading in Recovery - what is known (not verifiable from Windows):
#  * macOS 11+ replaced kextload/kextutil with kmutil; the old names are wrappers (if present).
#  * Third-party kexts normally go into the Auxiliary Kernel Collection and need user approval
#    + reboot. With SIP off (csr-active-config bit 0x1 CSR_ALLOW_UNTRUSTED_KEXTS and 0x200
#    CSR_ALLOW_UNAPPROVED_KEXTS) signature and approval checks are skipped. On Intel/x86 Macs
#    `kmutil load -p` can then load a kext into the running kernel without reboot; the reboot
#    requirement in Apple's docs is about Apple Silicon.
#  * Recovery has no AuxKC and may not run kernelmanagerd, so loading MAY still fail there.
#    The script then says so and keeps recording; the fallback is the normal boot with
#    AirportRTW enabled in OpenCore while this recorder runs (start it as early as possible).
#  * AirportRTW is ad-hoc signed: AMFI must be relaxed (boot-args amfi=0x80), otherwise the
#    code-signature check rejects it even with SIP off.
#  * The kext must be owned by root:wheel and not group/world-writable -> copied to /tmp,
#    because exFAT cannot store owners/permissions.

MACPKG="/Volumes/MACPKG"
KEXT_SRC="$MACPKG/AirportRTW.kext"
KEXT="/tmp/AirportRTW.kext"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$MACPKG/debug-$TS.log"
DMESG_OUT="$MACPKG/debug-$TS-dmesg.log"
INFO="$MACPKG/debug-$TS-info.log"
PIDS=""

[ -d "$MACPKG" ] || { echo "FEHLER: $MACPKG nicht gefunden (Partition MACPKG gemountet?)."; exit 1; }

say() { echo "$*"; echo "[$(date +%H:%M:%S)] $*" >> "$INFO" 2>/dev/null; sync; }
run() {   # run a command, log command + output to INFO
    echo "" >> "$INFO"; echo "\$ $*" >> "$INFO"
    "$@" >> "$INFO" 2>&1; rc=$?
    echo "(exit $rc)" >> "$INFO"; sync
    return $rc
}
mark() {  # write a marker into the kernel stream file too, so the timeline is clear
    echo "===== MARK $(date +%H:%M:%S): $* =====" >> "$OUT" 2>/dev/null; sync
}

# ---------------------------------------------------------------- recorder
start_recorder() {
    : > "$OUT"
    if command -v log >/dev/null 2>&1; then
        # `script -F` puts log stream on a pty and flushes after every write, so a freeze does
        # not eat a stdio buffer. Without `script` (or if it fails) fall back to a plain redirect.
        if command -v script >/dev/null 2>&1; then
            script -a -q -F "$OUT" log stream --style compact --level debug \
                --predicate 'process == "kernel"' < /dev/null > /dev/null 2>&1 &
            PIDS="$PIDS $!"
            sleep 3
        fi
        if [ ! -s "$OUT" ]; then
            log stream --style compact --level debug --predicate 'process == "kernel"' \
                >> "$OUT" 2>&1 < /dev/null &
            PIDS="$PIDS $!"
        fi
    else
        echo "log-Befehl fehlt, nur dmesg wird aufgezeichnet." >> "$OUT"
    fi
    # sync loop (data must be on the disk before a freeze) + dmesg snapshots
    (
        while true; do
            if command -v dmesg >/dev/null 2>&1; then
                dmesg > "$DMESG_OUT.tmp" 2>&1 && mv -f "$DMESG_OUT.tmp" "$DMESG_OUT"
            fi
            sync
            sleep 2
        done
    ) < /dev/null > /dev/null 2>&1 &
    PIDS="$PIDS $!"
}
stop_recorder() {
    for p in $PIDS; do kill "$p" 2>/dev/null; done
    # the log stream child of `script` survives its parent being killed
    command -v pkill >/dev/null 2>&1 && pkill -f 'log stream --style compact' 2>/dev/null
    sync
}
cleanup() {
    trap '' INT TERM
    mark "Ende"
    stop_recorder
    echo ""
    echo "Aufzeichnung beendet. Dateien auf MACPKG (D: in Windows):"
    echo "  $(basename "$OUT")  $(basename "$DMESG_OUT")  $(basename "$INFO")"
    exit 0
}
trap cleanup INT TERM

# ---------------------------------------------------------------- start
{
    echo "== recovery-debug $TS =="
    echo "Datum: $(date)"
} > "$INFO"
run sw_vers
run uname -a
run csrutil status
run nvram csr-active-config
run nvram boot-args

start_recorder
mark "Aufzeichnung gestartet"
say "Kernel-Log laeuft -> $OUT"
say "dmesg alle 2 s     -> $DMESG_OUT"
sleep 2
if [ -s "$OUT" ]; then say "log stream schreibt Daten (OK)."
else say "WARNUNG: log stream hat noch nichts geschrieben, dmesg-Datei ist die Reserve."; fi

if [ "$1" = "nokext" ]; then
    say ""
    say "Nur Aufzeichnung (nokext). Jetzt das Problem ausloesen. Beenden mit Ctrl+C."
    while true; do sleep 60; done
fi

# ---------------------------------------------------------------- kext preparation
say ""
if [ ! -f "$KEXT_SRC/Contents/Info.plist" ]; then
    say "Keine AirportRTW.kext auf MACPKG gefunden ($KEXT_SRC)."
    say "Es wird nur aufgezeichnet. Beenden mit Ctrl+C."
    while true; do sleep 60; done
fi

# SIP check: csrutil status prints "disabled" / "Custom Configuration" when OpenCore's
# csr-active-config is active. Warn only; the load attempt shows the real result.
SIP=$(csrutil status 2>&1)
case "$SIP" in
    *disabled*|*Custom*) say "SIP: gelockert (OK)." ;;
    *) say "WARNUNG: SIP scheint AKTIV zu sein ($SIP)."
       say "         Laden wird wahrscheinlich scheitern. EFI mit Build-EFI.ps1 -SipOff bauen." ;;
esac
case "$(nvram boot-args 2>/dev/null)" in
    *amfi=0x80*|*amfi_get_out_of_my_way*) say "AMFI: gelockert (OK)." ;;
    *) say "WARNUNG: boot-args ohne amfi=0x80 - die ad-hoc-signierte Kext wird evtl. abgelehnt." ;;
esac

rm -rf "$KEXT"
cp -R "$KEXT_SRC" "$KEXT" || { say "FEHLER: Kopieren nach /tmp fehlgeschlagen."; cleanup; }
chown -R root:wheel "$KEXT" 2>/dev/null
chmod -R 755 "$KEXT" 2>/dev/null
find "$KEXT" -type f -exec chmod 644 {} \; 2>/dev/null
[ -f "$KEXT/Contents/MacOS/AirportRTW" ] && chmod 755 "$KEXT/Contents/MacOS/AirportRTW"
command -v xattr >/dev/null 2>&1 && xattr -cr "$KEXT" 2>/dev/null
run ls -laR "$KEXT"

say ""
say "Alles bereit. Jetzt wird AirportRTW.kext geladen."
say "Wenn der PC einfriert: 10 s warten, dann hart ausschalten, Windows starten und"
say "Claude Bescheid geben (Dateien debug-$TS*.log auf D:)."
printf "Enter druecken zum Laden (Ctrl+C = abbrechen) ... "
read dummy

# ---------------------------------------------------------------- load attempts
loaded() { kmutil showloaded 2>/dev/null | grep -qi airportrtw || kextstat 2>/dev/null | grep -qi airportrtw; }
try_load() {   # $1 = description, rest = command
    desc="$1"; shift
    command -v "$1" >/dev/null 2>&1 || { say "$desc: Befehl $1 fehlt, uebersprungen."; return 1; }
    say "Versuch: $desc"
    mark "LADE KEXT: $*"
    sleep 1
    run "$@"; rc=$?
    sleep 3
    if loaded; then mark "KEXT GELADEN ($desc)"; say "AirportRTW ist geladen ($desc)."; return 0; fi
    say "$desc: nicht geladen (exit $rc, Details in $(basename "$INFO"))."
    return 1
}

OK=0
try_load "kmutil load" kmutil load -p "$KEXT" && OK=1
[ $OK = 1 ] || { try_load "kmutil load (ohne Authentifizierung)" kmutil load --no-authentication -p "$KEXT" && OK=1; }
[ $OK = 1 ] || { try_load "kextutil" kextutil -v 6 "$KEXT" && OK=1; }
[ $OK = 1 ] || { try_load "kextload" kextload -v 6 "$KEXT" && OK=1; }

say ""
if [ $OK = 1 ]; then
    run kmutil showloaded --list-only
    say "Kext laeuft. Jetzt ggf. WLAN-Menue oben rechts oeffnen / Netzwerk waehlen."
    say "Aufzeichnung laeuft weiter (alle 30 s ifconfig ins Info-Log). Beenden mit Ctrl+C."
else
    say "Laden zur Laufzeit hat NICHT geklappt (in Recovery evtl. grundsaetzlich nicht moeglich)."
    say "Info-Log mit den Fehlermeldungen liegt auf MACPKG. Aufzeichnung laeuft weiter, Ctrl+C beendet."
fi
while true; do
    run ifconfig
    sleep 30
done
