#!/usr/bin/env python3
"""Does the Flip Screen model of tools/refrender.py reproduce what the games do?

    flip_check.py <mcatadv.zip[|parent.zip]> <set> <unflipped dump prefix> <flipped dump prefix> [out prefix]

The two dumps are captures of one scene of one game, with the Flip Screen DIP switch off and on (sim/run_main.sh's bench:
DSW1=FFFF / FDFF for Magical Cat Adventure, FF00 / EF00 for Nostradamus, the same frame). The picture rendered from the flipped
state must be the one rendered from the unflipped state turned through 180 degrees: it is when the game changes only its
registers, as it does, and the model turns them back. Prints the number of differing pixels (0 expected) and the registers."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mamerom, refrender as R

def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    zpath, setname, un, fl = sys.argv[1:5]
    outp = sys.argv[5] if len(sys.argv) > 5 else None
    files = [f for z in zpath.split("|") for f in mamerom.load_zip(z)]
    regions = mamerom.regions(files, setname)
    dn, df = R.load_dump(un), R.load_dump(fl)
    print("unflipped: tilemap 0 %s 1 %s sprite regs %s" % ([hex(v) for v in dn["v0"]], [hex(v) for v in dn["v1"]], [hex(v) for v in dn["vid"]]))
    print("flipped:   tilemap 0 %s 1 %s sprite regs %s" % ([hex(v) for v in df["v0"]], [hex(v) for v in df["v1"]], [hex(v) for v in df["vid"]]))
    pn, pf = R.render(dn, regions), R.render(df, regions)
    w, h = 320, 224
    rot = bytearray(len(pn))
    for y in range(h):
        for x in range(w):
            s = (y * w + x) * 3
            t = ((h - 1 - y) * w + (w - 1 - x)) * 3
            rot[t:t + 3] = pn[s:s + 3]
    bad = [i for i in range(w * h) if rot[3 * i:3 * i + 3] != pf[3 * i:3 * i + 3]]
    print("flipped picture vs the unflipped one turned 180 degrees: %d of %d pixels differ" % (len(bad), w * h))
    if outp:
        R.write_ppm(outp + "_unflipped.ppm", w, h, pn)
        R.write_ppm(outp + "_flipped.ppm", w, h, pf)
        diff = bytearray(pf)
        for i in bad:
            diff[3 * i:3 * i + 3] = b"\xff\x00\xff"
        R.write_ppm(outp + "_diff.ppm", w, h, diff)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
