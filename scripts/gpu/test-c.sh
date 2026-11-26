#!/bin/bash
# GPU Test C (needs boot-arg -phxp2, fresh boot): full.sh runs Test B again, then MES scheduler + compute/gfx queues.
M="$(cd "$(dirname "$0")" && pwd)"   # folder of this script (USB stick RECOVERY/gpu or MACPKG/gpu)
[ -d ~/gpu/phxctl ] || bash "$M/setup.sh"
cp "$M"/bringup5.sh "$M"/full.sh ~/gpu/
cd ~/gpu || exit 1
MC=1 CS=1 ADOPT=1 GFX=1 AG=1 bash ~/gpu/full.sh kiqsched 2>&1 | tee ~/gpu/test-c.log
cp ~/gpu/test-c.log "$M"/ 2>/dev/null
log show --last boot --predicate 'eventMessage CONTAINS "Phx"' > "$M/test-c-kernel.log" 2>&1
sync
echo; echo "Fertig. Ergebnis liegt neben dem Script: test-c.log"
