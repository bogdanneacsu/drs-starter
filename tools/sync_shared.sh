#!/usr/bin/env bash
# Copiază modulele comune din DRSStarter în DRSOrganizer (aplicațiile CSP trebuie să fie foldere autonome).
# Sursa de adevăr este DRSStarter/src. Testul tests/organizer_run.lua verifică că copiile sunt identice.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/DRSStarter"; DST="$HERE/DRSOrganizer"
SHARED="src/vec.lua src/config.lua src/start_config.lua src/calibration.lua src/car_probe.lua src/track_nodes.lua
src/alignment.lua src/style.lua src/ui_common.lua src/ui_safety_live.lua src/world_draw.lua
src/live/client.lua src/live/time_sync.lua src/live/live_model.lua"
mkdir -p "$DST/src/live" "$DST/fonts" "$DST/img"
for f in $SHARED; do cp "$SRC/$f" "$DST/$f"; done
cp "$SRC"/fonts/* "$DST/fonts/"; cp "$SRC"/img/* "$DST/img/"; cp "$SRC/icon.png" "$DST/icon.png"
echo "$SHARED" | tr ' ' '\n' | sed '/^$/d' > "$DST/src/SHARED_FILES.txt"
echo "sincronizat: $(wc -l < "$DST/src/SHARED_FILES.txt") module"
