#!/usr/bin/env python3
"""Convert binary PPM (P6) files to PNG: ppm2png.py in.ppm [out.png]  (several files: ppm2png.py a.ppm b.ppm ...).
Optional scale: ppm2png.py --scale N in.ppm..."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio

def read_ppm(p):
    d = open(p, 'rb').read()
    # P6\nW H\n255\n
    parts = d.split(b'\n', 3)
    assert parts[0] == b'P6'
    w, h = map(int, parts[1].split())
    return w, h, bytearray(parts[3][:w * h * 3])

def scale(w, h, px, n):
    out = bytearray(w * n * h * n * 3)
    for y in range(h * n):
        for x in range(w * n):
            o = (y * w * n + x) * 3
            i = ((y // n) * w + (x // n)) * 3
            out[o:o + 3] = px[i:i + 3]
    return w * n, h * n, out

if __name__ == '__main__':
    args = sys.argv[1:]
    n = 1
    if args and args[0] == '--scale':
        n = int(args[1]); args = args[2:]
    files = [a for a in args if a.endswith('.ppm')]
    for f in files:
        w, h, px = read_ppm(f)
        if n > 1:
            w, h, px = scale(w, h, px, n)
        out = f[:-4] + '.png'
        pngio.write(out, w, h, px)
        print('wrote', out)
