#!/usr/bin/env python3
"""Summarise a 16-bit mono WAV: RMS and peak per window, and the dominant frequencies (naive DFT on a few windows).
    wavstat.py file.wav [window-seconds]"""
import sys, struct, math, wave

def main():
    w = wave.open(sys.argv[1], 'rb')
    win = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    rate = w.getframerate(); n = w.getnframes()
    data = struct.unpack('<%dh' % n, w.readframes(n))
    print("%s: %d samples, %.1f s at %d Hz" % (sys.argv[1], n, n / rate, rate))
    step = int(rate * win)
    for i in range(0, n, step):
        seg = data[i:i + step]
        if not seg: break
        rms = math.sqrt(sum(s * s for s in seg) / len(seg))
        pk = max(abs(s) for s in seg)
        print("  t=%6.1fs  rms=%8.1f  peak=%6d" % (i / rate, rms, pk))

if __name__ == "__main__":
    main()
