#!/bin/bash
# Whole-machine bench (sim/tb_system_top.sv):
#   sim/run_system.sh <game.rom> <frames> <name> [tb_system arguments: +dump=<prefix> +hold +fast +trace +load=rtl]
# Writes artifacts/<name>.fNNN.ppm and <name>.wav. Build directory: $HOME/build_mcatadv/system.
set -e
cd "$(dirname "$0")"
ROM="$1"; FRAMES="${2:-4}"; NAME="${3:-sys}"; shift 3 || true
[ -f "$ROM" ] || { echo "usage: $0 <game.rom> <frames> <name> [args]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="${BDIR:-$HOME/build_mcatadv/system}"; mkdir -p "$B"
JT=../modules/jt10
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt10.qip | sed "s|^|$JT/|" | tr '\n' ' ')
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" --public-flat-rw \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    $VFLAGS --top-module tb_system_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_cen.sv ../rtl/mcatadv_cache.sv ../rtl/mcatadv_main.sv \
    ../rtl/mcatadv_video.sv ../rtl/mcatadv_tmap.sv ../rtl/mcatadv_sprbuf.sv ../rtl/mcatadv_spr.sv ../rtl/mcatadv_zcache.sv ../rtl/mcatadv_pcmrd.sv ../rtl/mcatadv_sound.sv \
    ../rtl/mcatadv_core.sv ../target/mister/mcatadv_mem.sv ../target/mister/sdram_ctrl.sv \
    ../modules/cpu-fx68k/fx68kAlu.sv ../modules/cpu-fx68k/uaddrPla.sv ../modules/cpu-fx68k/fx68k.sv \
    ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_mcode.v ../modules/cpu-tv80/tv80_reg.v ../modules/cpu-tv80/tv80s_cen.v \
    $JTFILES ../modules/jt49/jt49.v ../modules/jt49/jt49_cen.v ../modules/jt49/jt49_div.v ../modules/jt49/jt49_eg.v ../modules/jt49/jt49_exp.v ../modules/jt49/jt49_noise.v \
    sdram_model.sv tb_system_top.sv tb_system.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -40; exit 1; }
fi
cp ../microrom.mem ../nanorom.mem "$B/"
mkdir -p ../artifacts
cd "$B"
./obj/Vtb_system_top "$ROM" "$FRAMES" "$OLDPWD/../artifacts/$NAME" "$@"
