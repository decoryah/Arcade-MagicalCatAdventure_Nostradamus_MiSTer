#!/bin/bash
# Sound board on the real memory system: sim/run_sndsys.sh <game.rom> <seconds> <out.wav> [cmd@ms ...]   (BDIR=<build dir>, TRAFFIC=n)
set -e
cd "$(dirname "$0")"
ROM="$1"; SECS="$2"; OUT="$3"; shift 3
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="${BDIR:-$HOME/build_mcatadv/sndsys}"; mkdir -p "$B"
if [ -z "$NOBUILD" ]; then
JT=${JTDIR:-../modules/jt10}
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt10.qip | sed "s|^|$JT/|" | tr '\n' ' ')
verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" --public-flat-rw \
    -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNDRIVEN -Wno-PINCONNECTEMPTY \
    --top-module tb_sndsys_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_cen.sv ../rtl/mcatadv_pcmrd.sv ../rtl/mcatadv_zcache.sv ../rtl/mcatadv_sound.sv \
    ../target/mister/mcatadv_mem.sv ../target/mister/sdram_ctrl.sv \
    ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_mcode.v ../modules/cpu-tv80/tv80_reg.v ../modules/cpu-tv80/tv80s_cen.v \
    $JTFILES ../modules/jt49/jt49.v ../modules/jt49/jt49_cen.v ../modules/jt49/jt49_div.v ../modules/jt49/jt49_eg.v ../modules/jt49/jt49_exp.v ../modules/jt49/jt49_noise.v \
    sdram_model.sv tb_sndsys_top.sv tb_sndsys.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -30; exit 1; }
fi
cd "$B"
./obj/Vtb_sndsys_top "$ROM" "$SECS" "$OUT" "$@"
