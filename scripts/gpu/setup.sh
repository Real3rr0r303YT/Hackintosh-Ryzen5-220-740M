#!/bin/bash
# GPU Test A extras: copy RadeArc tools + firmware from MACPKG to ~/gpu, then run the read-only checks.
M="$(cd "$(dirname "$0")" && pwd)"   # folder of this script (USB stick RECOVERY/gpu or MACPKG/gpu)
mkdir -p ~/gpu/phxctl ~/gpu/fw
cp "$M"/phxctl/* ~/gpu/phxctl/
rm -f ~/gpu/phxctl/testl*          # display experiments - never run them
chmod +x ~/gpu/phxctl/*
xattr -dr com.apple.quarantine ~/gpu/phxctl 2>/dev/null
cp "$M"/fw/* ~/gpu/fw/
cp "$M"/bringup5.sh "$M"/full.sh ~/gpu/
{
  echo "== phx properties"; ioreg -rc PhxBringup | grep -E '"phx-(build|chip|gc-version|fb-size|fb-phys|stage)"'
  echo "== phxfw"; ~/gpu/phxctl/phxfw ~/gpu/fw
  echo "== psp status (expect kr 0xe00002c7 while read-only)"; sudo ~/gpu/phxctl/phxctl psp status
  echo "== kernel log"; log show --last boot --predicate 'eventMessage CONTAINS "PhxBringup:"' | tail -20
} 2>&1 | tee "$M/test-a.log"
echo; echo "Fertig. Ergebnis liegt neben dem Script: test-a.log"
