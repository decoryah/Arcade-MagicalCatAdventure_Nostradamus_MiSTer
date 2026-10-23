#!/bin/bash
# What the framework's scandoubler (sys/arcade_video.v) does with this core's raster, without the machine:
#   sim/run_sd.sh [frames] [fx 0..4: None, HQ2x, CRT 25/50/75 %] [forced_scandoubler 0/1] [bad_blank 0/1]
# bad_blank = 1 gives the scandoubler a horizontal blank that stays high through the vertical blank (the fault that froze
# the Gaiapolis core's picture); it must stall, the real wiring (0) must not.
set -e
cd "$(dirname "$0")"
. "$HOME/tools/oss-cad-suite/environment"
S=../sys; B="${BDIR:-$HOME/build_mcatadv/sd}"; mkdir -p "$B"
python3 - $S/video_mixer.sv $B/video_mixer_sim.sv <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'generate\s+if\(GAMMA && HALF_DEPTH\) begin.*?end else begin(.*?)end\s+endgenerate', s, re.S)
assert m, 'video_mixer.sv: the R_in generate block was not found'
open(sys.argv[2], 'w').write(s[:m.start()] + m.group(1).strip() + chr(10) + s[m.end():])
PY
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-4} -O2 -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
    -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE \
    -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-INITIALDLY -Wno-BLKSEQ -Wno-PROCASSINIT \
    +1364-2005ext+v -I. --top-module tb_sd_top --prefix Vtb_sd_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_video.sv $S/arcade_video.v $B/video_mixer_sim.sv $S/scandoubler.v $S/scanlines.v $S/gamma_corr.sv $S/hq2x.sv $S/video_freezer.sv \
    sync_fix.sv tb_sd_top.sv tb_sd.cpp > "$B/build.log" 2>&1 || { grep -E "%Error" "$B/build.log" | head -20; tail -5 "$B/build.log"; exit 1; }
fi
"$B/obj/Vtb_sd_top" "${1:-6}" "${2:-0}" "${3:-0}" "${4:-0}"
