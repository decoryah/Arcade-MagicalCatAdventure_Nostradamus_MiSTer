#!/usr/bin/env python3
"""Reference renderer for the mcatadv family: MAME's screen_update, written out literally.

    refrender.py <mcatadv.zip> <set> <dump-prefix> <out.ppm> [compare.ppm]

Renders one frame from a RAM dump (sim/tb_main_top.sv writes <prefix>_{t0,t1,pal,spr}.hex and
_regs.hex: tile RAMs, palette, sprite RAM, tilemap registers and B00000-B00004) and, if given,
compares it with an RTL frame (sim/tb_system.cpp): prints the number of differing pixels and writes
<out>.diff.ppm. Follows src/mame/misc/mcatadv.cpp and src/devices/video/tmap038.cpp: the
sprites and tilemaps are drawn exactly as MAME does, line by line with the priority bitmap --
except for the Flip Screen DIP switch, which MAME does not finish (MACHINE_NO_COCKTAIL: its tilemaps flip with constants that
do not match what the game writes, and the sprites vanish, since the origin register's flip bit is not masked).

Flip, as the real games' RAM shows it (a pair of captures of one scene, switch off and on): the game leaves the tile RAM, line
RAM, sprite RAM and palette as they are and changes only registers: bit 15 of each tilemap register 0 / 1 and of the sprite
origin registers is cleared / set, the scrolls become C - scroll (X: 0x33f, Y: 0x2df, modulo 512), the sprite origin
changes to values that the chip alone can use. So the flipped scene is the unflipped one, mirrored by the hardware.
Here the registers are turned back into their unflipped values (scroll = 0x13f - the field in X, 0xdf - the field in Y, as
fields modulo 512; the sprite origin = the unflipped constants), the picture is drawn as usual, and the finished
picture is mirrored: in X when tilemap 0's register 0 has bit 15 clear, in Y when its register 1 has. This is what
the core does (sim/emu, tools/flip_check.py compare it with the unflipped scene turned through 180 degrees).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mamerom

def hexwords(path):
    return [int(l.strip(), 16) for l in open(path) if l.strip()]

def load_dump(prefix):
    d = {n: hexwords("%s_%s.hex" % (prefix, n)) for n in ("t0", "t1", "pal", "spr")}
    regs = [l.strip() for l in open(prefix + "_regs.hex") if l.strip()]
    v0 = int(regs[0], 16); v1 = int(regs[1], 16)
    d["v0"] = [(v0 >> (16 * i)) & 0xffff for i in range(3)]
    d["v1"] = [(v1 >> (16 * i)) & 0xffff for i in range(3)]
    d["vid"] = [int(regs[2], 16), int(regs[3], 16), int(regs[4], 16)]
    return d

def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def pal_rgb(w):
    r = (w >> 5) & 31; g = (w >> 10) & 31; b = w & 31
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))

def render(d, regions, width=320, height=224):
    bitmap = [[0x3f0] * width for _ in range(height)]
    prio = [[0] * width for _ in range(height)]
    gfx = [regions["bg0"], regions["bg1"]]
    nelem = [len(regions["bg0"]) // 32, len(regions["bg1"]) // 32]
    vram = [d["t0"], d["t1"]]
    regs = [d["v0"], d["v1"]]

    def layer_pixel(layer, x, y, scrollx_l, map_y):
        mx = (x + scrollx_l) & 0x1ff
        tx, ty = mx >> 4, map_y >> 4
        idx = (ty * 32 + tx) * 2
        attr, code = vram[layer][idx], vram[layer][idx + 1]
        color = (attr >> 8) & 0x3f
        pri = (attr >> 14) & 3
        sub = ((mx >> 3) & 1) + 2 * ((map_y >> 3) & 1)
        c8 = ((code * 4) + sub) % nelem[layer]
        px, py = mx & 7, map_y & 7
        b = gfx[layer][c8 * 32 + py * 4 + (px >> 1)]
        pen = (b >> 4) if (px & 1) == 0 else (b & 15)
        bank = regs[layer][2] & 0xf
        return pen, pri, (((color + bank * 0x40) * 16) + pen) & 0xfff

    # tilemaps: 4 passes (priority), layer 0 then layer 1 in each
    lines = []
    for layer in (0, 1):
        r = regs[layer]
        enable = not (r[2] >> 4) & 1
        lr = d["t0"] if layer == 0 else d["t1"]
        per = []
        # the scroll fields: with Flip Screen the game writes 0x33f - scroll (X) and 0x2df - scroll (Y); back to the unflipped ones
        fldx, fldy = r[0] & 0x1ff, r[1] & 0x1ff
        if not (r[0] >> 15) & 1: fldx = (0x13f - fldx) & 0x1ff
        if not (r[1] >> 15) & 1: fldy = (0x0df - fldy) & 0x1ff
        for y in range(height):
            scrollx = fldx - 0x194
            scrolly = fldy - 0x1df
            if (r[1] >> 14) & 1:
                rs = lr[0x800 + ((y + scrolly) & 0x1ff) * 2 + 1]
                scrolly = rs - y
            if (r[0] >> 14) & 1:
                scrollx += lr[0x800 + ((y + scrolly) & 0x1ff) * 2]
            my = (y + scrolly) & 0x1ff
            per.append((scrollx, my))
        lines.append((enable, per))
    for i in range(4):
        for layer in (0, 1):
            enable, per = lines[layer]
            if not enable:
                continue
            for y in range(height):
                sx, my = per[y]
                for x in range(width):
                    pen, pri, pal = layer_pixel(layer, x, y, sx, my)
                    if pen != 0 and pri == i:
                        bitmap[y][x] = pal
                        prio[y][x] = i | 8

    # sprites (draw_sprites)
    spr = d["spr"]
    sprdata = regions["sprdata"]
    sprmask = len(sprdata) - 1
    # (with Flip Screen the game sets bit 15 of the origin registers and gives other values: the unflipped origin is used)
    global_x = 0 if d["vid"][0] & 0x8000 else d["vid"][0] - 0x184
    global_y = 0 if d["vid"][1] & 0x8000 else d["vid"][1] - 0x1f1
    base = 0x2000 if d["vid"][2] == 1 else 0
    for e in range(2047, -1, -1):
        s = spr[base + e * 4: base + e * 4 + 4]
        if s[3] == s[0]:
            continue
        pen = (s[0] & 0x3f00) >> 8
        tileno = s[1]
        pri = 8 | ((s[0] & 0xc000) >> 14)
        x = sext(s[2], 10); y = sext(s[3], 10)
        flipy = (s[0] >> 6) & 1; flipx = (s[0] >> 7) & 1
        h = ((s[3] & 0xf000) >> 12) * 16
        w = ((s[2] & 0xf000) >> 12) * 16
        offset = tileno * 256
        xs, xe, xi = (0, w, 1) if not flipx else (w - 1, -1, -1)
        ys, ye, yi = (0, h, 1) if not flipy else (h - 1, -1, -1)
        ycnt = ys
        while ycnt != ye:
            dy = y + ycnt - global_y
            if 0 <= dy < height:
                xcnt = xs
                while xcnt != xe:
                    dx = x + xcnt - global_x
                    if 0 <= dx < width:
                        if not (prio[dy][dx] & 0x10):
                            b = sprdata[(offset // 2) & sprmask]
                            if offset & 1:
                                b >>= 4
                            b &= 15
                            if b:
                                if prio[dy][dx] < pri:
                                    bitmap[dy][dx] = b + (pen << 4)
                                prio[dy][dx] |= 0x10
                    offset += 1
                    xcnt += xi
            else:
                offset += w
            ycnt += yi
    pal = d["pal"]
    # Flip Screen: the finished picture mirrored (X when tilemap 0's register 0 has bit 15 clear, Y when its register 1 has)
    mir_x = not (regs[0][0] >> 15) & 1
    mir_y = not (regs[0][1] >> 15) & 1
    out = bytearray(width * height * 3)
    for y in range(height):
        for x in range(width):
            r, g, b = pal_rgb(pal[bitmap[y][x] & 0xfff])
            o = (((height - 1 - y) if mir_y else y) * width + ((width - 1 - x) if mir_x else x)) * 3
            out[o] = r; out[o + 1] = g; out[o + 2] = b
    return out

def read_ppm(p):
    dd = open(p, 'rb').read()
    parts = dd.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    return w, h, bytearray(parts[3][:w * h * 3])

def write_ppm(p, w, h, px):
    with open(p, 'wb') as f:
        f.write(b"P6\n%d %d\n255\n" % (w, h)); f.write(px)

if __name__ == "__main__":
    zpath, setname, prefix, outp = sys.argv[1:5]
    files = [f for z in zpath.split("|") for f in mamerom.load_zip(z)]      # a clone's zip and its parent's, separated by |
    regions = mamerom.regions(files, setname)
    d = load_dump(prefix)
    px = render(d, regions)
    write_ppm(outp, 320, 224, px)
    print("wrote", outp)
    if len(sys.argv) > 5:
        w, h, rtl = read_ppm(sys.argv[5])
        assert (w, h) == (320, 224)
        diff = bytearray(w * h * 3)
        n = 0
        first = []
        for i in range(w * h):
            if px[3 * i:3 * i + 3] != rtl[3 * i:3 * i + 3]:
                n += 1
                diff[3 * i:3 * i + 3] = b"\xff\x00\x00"
                if len(first) < 12:
                    first.append((i % w, i // w, tuple(px[3 * i:3 * i + 3]), tuple(rtl[3 * i:3 * i + 3])))
            else:
                diff[3 * i:3 * i + 3] = px[3 * i:3 * i + 3]
        print("differing pixels: %d of %d" % (n, w * h))
        for f in first:
            print("  x=%d y=%d  ref=%s rtl=%s" % f)
        write_ppm(outp[:-4] + ".diff.ppm", w, h, diff)
