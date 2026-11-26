#!/bin/bash
# GPU desktop gone (white wallpaper, no Liquid Glass) after a restart that came too early?
# phxboot then sets its kill switch /Users/Shared/gpu/phxboot-off. This removes it and shows the last boot log.
#   bash /Volumes/RECOVERY/gpu/gpu-reset.sh      then restart and wait 1-2 minutes after the desktop appears.
echo "== letzte GPU-Starts"; tail -8 /var/log/phxboot.log 2>/dev/null
if [ -e /Users/Shared/gpu/phxboot-off ]; then
    sudo rm -f /Users/Shared/gpu/phxboot-off && echo "Notbremse entfernt. Jetzt neu starten."
else
    echo "Keine Notbremse gesetzt."
fi
