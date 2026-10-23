#!/bin/bash
# End-to-end bench of the MiSTer top level (MCatAdv.sv): hps_io and the PLLs stubbed, everything else real, an SDRAM chip
# model and an Avalon DDR3 model on the pins.
#   sim/emu/run_emu.sh <image.rom> [frames after the load, default 3] [out prefix, default emu]
# The image is a full layout-v2 image (work/v2/<set>.rom: tools/mamerom.py, or tools/mra_build.py on an MRA).
# Environment:
#   FAST=1       load the way Main_MiSTer does for the MRA's address= attribute (the image copied into the DDR3, then a
#                download without bytes) and let the core replay it; without it the image is streamed through the ioctl port.
#                The loader check (every word of the image where the memory's ports read it) applies to both
#   HOLD=0       do not hold the machine in reset after the load (the default holds it, so the overlay is a still picture)
#   OVL=0        diagnostic overlay off
#   BUSY=<pct>   the DDR3 model's share of clocks with BUSY high (default 10): a build option, so use another BDIR
#   LEN=<bytes>  load only the first part of the image (a quick test); PRE=<frames>: run the video that long before the load
#   RESTART=1    interrupt the fast load part-way with a streamed download, then fast load again
#   JOYTEST=1    the controller decoding of both games' button layouts (every joystick bit set alone, both players)
#   Scale: SCALE=0..4 (Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+), AR=0..3 (Original, Full Screen,
#          ARC1, ARC2), ORIENT=0..3 (Game default, Horizontal, Rotate CCW, Rotate CW), HW / HH (the scaler's size, default
#          1920 x 1080), DIRECT=1. The integer modes act when the picture is not turned (Magical Cat Adventure, or ORIENT=1)
#   Scandoubler: FX=0..4 (None, HQ2x, CRT 25 / 50 / 75 %), FSD=1 (MiSTer.ini's forced_scandoubler)
#   CRT Adjust: CRT=1 turns it on, HSIZE (-16..8), HPOS (-48..40), VSHIFT (-16..10) set the amounts as the OSD counts them.
#          With CRT=1 and the amounts at 0 the picture hash must equal the run without it
set -e
cd "$(dirname "$0")"
IMG="$1"; FR="${2:-3}"; PRE="${3:-emu}"
[ -f "$IMG" ] || { echo "usage: $0 <image.rom> [frames] [prefix]" >&2; exit 2; }
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
S=../../sys
B="${BDIR:-$HOME/build_mcatadv/emu}"; mkdir -p "$B"
JT=../../modules/jt10
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt10.qip | sed "s|^|$JT/|" | tr '\n' ' ')
# The framework's video_mixer.sv declares R_in/G_in/B_in inside an unnamed generate block and uses them outside it. Quartus
# accepts that; Verilator takes them for undeclared implicit wires nothing drives, and the picture comes out black. The bench
# builds a copy with the three wires declared at module level (for GAMMA=1, HALF_DEPTH=0 -- arcade_video with DW=24).
python3 - $S/video_mixer.sv $B/video_mixer_sim.sv <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'generate\s+if\(GAMMA && HALF_DEPTH\) begin.*?end else begin(.*?)end\s+endgenerate', s, re.S)
assert m, 'video_mixer.sv: the R_in generate block was not found'
open(sys.argv[2], 'w').write(s[:m.start()] + m.group(1).strip() + chr(10) + s[m.end():])
PY
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-8} -O2 --public-flat-rw -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
    -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE \
    -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-INITIALDLY -Wno-BLKSEQ -Wno-PROCASSINIT -Wno-SYNCASYNCNET -Wno-VARHIDDEN -Wno-BLKANDNBLK \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-LITENDIAN -Wno-ASCRANGE -Wno-SELRANGE --no-assert-case -Wno-fatal \
    +1364-2005ext+v -DMISTER_FB=1 -I. -I../.. ${BUSY:+-GDDR_BUSY_PCT=$BUSY} \
    --top-module tb_emu_top --prefix Vtb_emu_top -Mdir "$B/obj" \
    ../../MCatAdv.sv ../../rtl/mcatadv_*.sv ../../target/mister/mcatadv_mem.sv ../../target/mister/sdram_ctrl.sv ../../target/mister/mcatadv_fastload.sv \
    ../../modules/cpu-fx68k/fx68kAlu.sv ../../modules/cpu-fx68k/uaddrPla.sv ../../modules/cpu-fx68k/fx68k.sv \
    ../../modules/cpu-tv80/tv80_alu.v ../../modules/cpu-tv80/tv80_core.v ../../modules/cpu-tv80/tv80_mcode.v ../../modules/cpu-tv80/tv80_reg.v ../../modules/cpu-tv80/tv80s_cen.v \
    $JTFILES ../../modules/jt49/jt49.v ../../modules/jt49/jt49_cen.v ../../modules/jt49/jt49_div.v ../../modules/jt49/jt49_eg.v ../../modules/jt49/jt49_exp.v ../../modules/jt49/jt49_noise.v \
    ../../modules/crt-adjust/crt_adjust.sv \
    $S/arcade_video.v $B/video_mixer_sim.sv $S/scandoubler.v $S/scanlines.v $S/gamma_corr.sv $S/hq2x.sv $S/video_freezer.sv $S/video_freak.sv $S/math.sv \
    hps_io_stub.sv pll_stub.sv sync_fix.sv ../sdram_model.sv ../ddr_model.sv tb_emu_top.sv tb_emu.cpp \
    > "$B/build.log" 2>&1 || { grep -E "%Error" "$B/build.log" | head -30; tail -5 "$B/build.log"; exit 1; }
fi
# the machine reads its microcode tables with $readmemh relative to the project directory (as Quartus does)
cd ../..
mkdir -p artifacts
stdbuf -oL "$B/obj/Vtb_emu_top" "$IMG" "$FR" "artifacts/$PRE"
