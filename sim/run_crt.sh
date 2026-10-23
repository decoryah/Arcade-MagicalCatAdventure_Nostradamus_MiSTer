#!/bin/bash
# CRT Adjust on this core's raster without the machine (sim/tb_crt_top.sv):
#   sim/run_crt.sh [on hsize hpos vshift ...]     one run per quadruple; with none, the standard set
# hsize -16..12, hpos -48..40, vshift -16..15, as the OSD menu counts them. NOBUILD=1 reuses the build.
set -e
cd "$(dirname "$0")"
. "$HOME/tools/oss-cad-suite/environment"
B="${BDIR:-$HOME/build_mcatadv/crt}"; mkdir -p "$B"
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-4} -O2 -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
    -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE \
    -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-INITIALDLY -Wno-BLKSEQ -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    --top-module tb_crt_top --prefix Vtb_crt_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_video.sv ../rtl/mcatadv_crt.sv ../modules/crt-adjust/crt_adjust.sv tb_crt_top.sv tb_crt.cpp \
    > "$B/build.log" 2>&1 || { grep -E "%Error" "$B/build.log" | head -20; tail -5 "$B/build.log"; exit 1; }
fi
if [ $# -ge 4 ]; then
    while [ $# -ge 4 ]; do "$B/obj/Vtb_crt_top" "$1" "$2" "$3" "$4"; shift 4; done
else
    run() { "$B/obj/Vtb_crt_top" "$@"; }
    run 0 0 0 0            # off: the raster's own picture
    run 1 0 0 0            # on, all amounts 0: must be the same
    run 1 3 0 0            # wider, the most that fits at H-Position 0
    run 1 12 -48 0         # as wide as the line allows, moved left to fit
    run 1 -8 0 0           # narrower
    run 1 -16 0 0          # as narrow as the menu goes
    run 1 0 20 0           # moved right
    run 1 0 -20 0          # moved left
    run 1 0 0 3            # picture down 3 lines
    run 1 0 0 -3           # picture up 3 lines
    run 1 0 0 15
    run 1 0 0 -16
fi
