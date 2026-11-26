#!/bin/bash
# GPU Test B (needs boot-arg -phxp2): firmware load + GPU power-up. Arms a reboot watchdog itself.
M="$(cd "$(dirname "$0")" && pwd)"   # folder of this script (USB stick RECOVERY/gpu or MACPKG/gpu)
[ -d ~/gpu/phxctl ] || bash "$M/setup.sh"
cp "$M"/bringup5.sh "$M"/full.sh ~/gpu/   # always take the current (LF) scripts
cd ~/gpu || exit 1
bash ~/gpu/bringup5.sh 2>&1 | tee ~/gpu/test-b.log
cp ~/gpu/test-b.log ~/gpu/fwaddr.log "$M"/ 2>/dev/null
log show --last boot --predicate 'eventMessage CONTAINS "Phx"' > "$M/test-b-kernel.log" 2>&1
sync
echo; echo "Fertig. Ergebnis liegt neben dem Script: test-b.log"
