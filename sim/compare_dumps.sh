#!/bin/bash
# Render every RAM dump <dir>/dump_<tag>_*.hex with the RTL (sim/tb_system) and with the reference renderer
# (tools/refrender.py) and report the differing pixels:
#   sim/compare_dumps.sh <game.rom> <set> <mcatadv.zip> <dump-dir> <tag> [<tag> ...]
# The system bench is built by sim/run_system.sh first (NOBUILD=1 reuses it).
cd "$(dirname "$0")/.."
ROM="$1"; SET="$2"; ZIP="$3"; DIR="$4"; shift 4
for t in "$@"; do
    echo "=== $SET dump $t"
    NOBUILD=1 bash sim/run_system.sh "$ROM" 3 "${SET}_$t" +dump="$DIR/dump_$t" 2>&1 | grep -E "^frame 3:|overruns" | tail -1
    python3 tools/refrender.py "$ZIP" "$SET" "$DIR/dump_$t" "artifacts/${SET}_$t.ref.ppm" "artifacts/${SET}_$t.f003.ppm" | grep -E "differing|x="
done
