#!/usr/bin/env python3
"""Classify the YM2610 writes of a sound-command sweep (sim YMLOG): which sections each command uses.
usage: ymclass.py <ymlog> <cmdfile>     cmdfile lines: "<cmd decimal> <ms>" (the window of a command runs to the next one)"""
import sys
log = [l.split() for l in open(sys.argv[1])]
cmds = [tuple(map(float, l.split())) for l in open(sys.argv[2]) if l.strip()]
ev = []
sel = {0: 0, 2: 0}
for ms, a, d in log:
    ms = float(ms); a = int(a); d = int(d, 16)
    if a in (0, 2): sel[a] = d
    else: ev.append((ms, 0 if a == 1 else 1, sel[a - 1], d))
for i, (c, lo) in enumerate(cmds):
    hi = cmds[i + 1][1] if i + 1 < len(cmds) else lo + 400
    w = [e for e in ev if lo <= e[0] < hi]
    ssg = sum(1 for e in w if e[1] == 0 and e[2] < 0x10)
    ssg_vol = [e[3] for e in w if e[1] == 0 and 8 <= e[2] <= 10 and e[3] & 15]
    fmkon = sum(1 for e in w if e[1] == 0 and e[2] == 0x28 and (e[3] & 0xF0))
    aon_on = [e[3] for e in w if e[1] == 1 and e[2] == 0x00 and not e[3] & 0x80]
    bon = sum(1 for e in w if e[1] == 0 and e[2] == 0x10 and e[3] & 0x80)
    print("cmd %02x: %4d writes  ssg %3d (audible vol writes %d)  fm-keyon %3d  adpcmA-keyon %2d %s  adpcmB-start %d" % (
        int(c), len(w), ssg, len(ssg_vol), fmkon, len(aon_on), ["%02x" % x for x in aon_on][:6], bon))
