#!/bin/bash
# GPU Test C + D in one go (needs boot-arg -phxp2 and a fresh boot). Shows the verdict in a macOS dialog.
M="$(cd "$(dirname "$0")" && pwd)"   # folder of this script (USB stick RECOVERY/gpu or MACPKG/gpu)
[ -d ~/gpu/phxctl ] || bash "$M/setup.sh"
cp "$M"/bringup5.sh "$M"/full.sh ~/gpu/
mkdir -p ~/gpu/mesa && cp "$M"/mesa/* ~/gpu/mesa/
xattr -dr com.apple.quarantine ~/gpu/mesa 2>/dev/null
echo "GPU-Test C + D laeuft (ca. 1-3 Min). Passwort eingeben, wenn gefragt."
bash ~/gpu/mesa/testd.sh
R=~/Desktop/testd.txt
cp "$R" "$M/testd.txt" 2>/dev/null
log show --last boot --predicate 'eventMessage CONTAINS "Phx"' > "$M/testd-kernel.log" 2>&1
sync

C=0; D=0
grep -q 'scratch0=0xdeadbeef' "$R" && grep -q 'testbuf=0xfeedf00d' "$R" && \
grep -q 'scratch1=0xdeadbeef' "$R" && grep -q 'testbuf=0x6f7a6f7a' "$R" && C=1
grep -q '256/256 correct' "$R" && D=1
NAME=$(grep -m1 -o 'AMD Radeon[^(]*(RADV[^)]*)' "$R")

if [ $C = 1 ] && [ $D = 1 ]; then
    MSG="GPU funktioniert einwandfrei!\n\nTest C (Rechen- und Grafik-Queue): OK\nTest D (Vulkan/RADV): OK\n$NAME\n\nNaechster Schritt: Beschleunigung installieren. Windows starten und Claude Bescheid geben."
    ICON=note
elif [ $C = 1 ]; then
    MSG="Test C OK (GPU rechnet), aber Test D (Vulkan) hat nicht geklappt.\n\nWindows starten und Claude 'fertig' schreiben."
    ICON=caution
else
    MSG="Test C hat nicht geklappt.\n\nWindows starten und Claude 'fertig' schreiben."
    ICON=stop
fi
osascript -e "display dialog \"$MSG\" with title \"Radeon 740M Test\" buttons {\"OK\"} default button 1 with icon $ICON" >/dev/null 2>&1
printf "%b\n" "$MSG"
