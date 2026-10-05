#!/bin/bash
# CPU-side bring-up bench (sim/tb_main_top.sv):
#   sim/run_main.sh <game.rom> [frames] [trace-from-frame]
# <game.rom> is an image from tools/mra_build.py (the 68000 program is its first 1 MB).
set -e
cd "$(dirname "$0")"
ROM="$1"; FRAMES="${2:-10}"; FROM="${3:-0}"
[ -f "$ROM" ] || { echo "usage: $0 <game.rom> [frames] [trace-from]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_mcatadv/main"; mkdir -p "$B"
python3 - "$ROM" "$B/prog.hex" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()[:0x100000]
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(d), 2):
        f.write('%04x\n' % (d[i] | (d[i+1] << 8)))
PY
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT \
    --top-module tb_main_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_cache.sv ../rtl/mcatadv_main.sv \
    ../modules/cpu-fx68k/fx68kAlu.sv ../modules/cpu-fx68k/uaddrPla.sv ../modules/cpu-fx68k/fx68k.sv \
    tb_main_top.sv tb_main.cpp > "$B/build.log" 2>&1 || { tail -40 "$B/build.log"; exit 1; }
cp ../microrom.mem ../nanorom.mem "$B/"
cd "$B"
./obj/Vtb_main_top "$FRAMES" main.trace "$FROM"
echo "trace: $B/main.trace"
