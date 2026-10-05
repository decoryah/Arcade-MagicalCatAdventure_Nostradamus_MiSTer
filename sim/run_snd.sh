#!/bin/bash
# Sound board bench: sim/run_snd.sh <game.rom> <out.wav> <seconds> [cmd@ms ...]     (NOST=1 for Nostradamus, BDIR=<build dir>)
set -e
cd "$(dirname "$0")"
ROM="$1"; OUT="$2"; shift 2
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="${BDIR:-$HOME/build_mcatadv/snd}"; mkdir -p "$B"
python3 - "$ROM" "$B" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
open(sys.argv[2] + '/z80.hex', 'w').write(''.join('%02x\n' % b for b in d[0x100000:0x140000]))
open(sys.argv[2] + '/pcm.hex', 'w').write(''.join('%02x\n' % b for b in d[0xA40000:0xB40000]))
PY
if [ -z "$NOBUILD" ]; then
JT=${JTDIR:-../modules/jt10}
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt10.qip | sed "s|^|$JT/|" | tr '\n' ' ')
verilator $VFLAGS --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNDRIVEN --public-flat-rw \
    --top-module tb_snd_top -Mdir "$B/obj" \
    ../rtl/mcatadv_ram.sv ../rtl/mcatadv_pcmrd.sv ../rtl/mcatadv_zcache.sv ../rtl/mcatadv_sound.sv \
    ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_mcode.v ../modules/cpu-tv80/tv80_reg.v ../modules/cpu-tv80/tv80s_cen.v \
    $JTFILES ../modules/jt49/jt49.v ../modules/jt49/jt49_cen.v ../modules/jt49/jt49_div.v ../modules/jt49/jt49_eg.v ../modules/jt49/jt49_exp.v ../modules/jt49/jt49_noise.v tb_snd_top.sv tb_snd.cpp > "$B/build.log" 2>&1 || { grep -E "%Error" "$B/build.log" | head -20; exit 1; }
fi
cd "$B"
./obj/Vtb_snd_top "$OUT" "$@"
