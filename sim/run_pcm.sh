#!/bin/bash
# ADPCM-A sample path bench: sim/run_pcm.sh <game.rom> [slots] [load 0|1]
set -e
cd "$(dirname "$0")"
ROM="$1"; case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_mcatadv/pcm"; mkdir -p "$B"
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNDRIVEN -Wno-PROCASSINIT --public-flat-rw \
    --top-module tb_pcm_top -Mdir "$B/obj" \
    ../rtl/mcatadv_pcmrd.sv ../target/mister/mcatadv_mem.sv ../target/mister/sdram_ctrl.sv sdram_model.sv tb_pcm_top.sv tb_pcm.cpp > "$B/build.log" 2>&1 || { grep -E "%Error" "$B/build.log" | head -20; exit 1; }
cd "$B"
./obj/Vtb_pcm_top "$ROM" "${2:-20000}" "${3:-1}"
