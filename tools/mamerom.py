#!/usr/bin/env python3
"""MAME's memory regions for the mcatadv family (Magical Cat Adventure, Catt, Nostradamus), built straight from the
ROM_START definitions in src/mame/misc/mcatadv.cpp, and packed into the core's flat image.

Independent of the .mra files: `python tools/mamerom.py <mcatadv.zip> [<nost.zip>] [<dir of mra_build images>]`
builds the images this way and compares them with what the MRAs assemble (tools/mra_build.py) -- the two must
agree byte for byte.

The image (docs/memory.md, target/mister/mcatadv_mem.sv):
    000000  100000  68000 program
    100000  040000  Z80 program (a 128 KB ROM is followed by FF)
    140000  500000  sprite ROM
    640000  180000  BG0 tile ROM (padded with FF)
    7C0000  280000  BG1 tile ROM (padded with FF)
    A40000  100000  ADPCM-A samples (a 512 KB ROM is repeated)
    B40000  000010  configuration: [0] game, [1:2] tiles in BG0, [3:4] tiles in BG1
"""
import sys, os, zipfile, zlib, hashlib

# set -> region -> list of (file, crc, dest offset, size, how)   how: 'b0' = ROM_LOAD16_BYTE at +0, 'b1' at +1, 'l' = ROM_LOAD
def mcat(cpu, spr1, spr2, bg0, bg1c, pcm, spr1_big=False):
    return {
        "maincpu":  [(cpu[0], cpu[1], 0, 0x80000, "b0"), (cpu[2], cpu[3], 0, 0x80000, "b1")],
        "soundcpu": [("u9.bin", 0xfda05171, 0, 0x20000, "l")],
        "sprdata":  [("mca-u82.bin", 0x5f01d746, 0x000000, 0x100000, "b0"), ("mca-u83.bin", 0x4e1be5a6, 0x000000, 0x100000, "b1"),
                     (spr1[0], spr1[1], 0x200000, 0x100000 if spr1_big else 0x80000, "b0"),
                     (spr1[2], spr1[3], 0x200000, 0x100000 if spr1_big else 0x80000, "b1"),
                     (spr2[0], spr2[1], 0x400000, 0x80000, "b0"), (spr2[2], spr2[3], 0x400000, 0x80000, "b1")],
        "bg0":      [bg0],
        "bg1":      [("mca-u60.bin", 0xc8942614, 0x000000, 0x100000, "l"), ("mca-u61.bin", 0x51af66c9, 0x100000, 0x100000, "l"), bg1c],
        "adpcma":   [pcm],
    }

SETS = {
    "mcatadv": dict(game=0, sizes=dict(maincpu=0x100000, soundcpu=0x20000, sprdata=0x800000, bg0=0x80000, bg1=0x280000, adpcma=0x80000),
        defs=mcat(("mca-u30e", 0xc62fbb65, "mca-u29e", 0xcf21227c), ("mca-u84.bin", 0xdf202790, "mca-u85.bin", 0xa85771d2),
                  ("mca-u86e", 0x017bf1da, "mca-u87e", 0xbc9dc9b9), ("mca-u58.bin", 0x3a8186e2, 0, 0x80000, "l"),
                  ("mca-u100", 0xb273f1b0, 0x200000, 0x80000, "l"), ("mca-u53.bin", 0x64c76e05, 0, 0x80000, "l"))),
    "mcatadvj": dict(game=0, sizes=dict(maincpu=0x100000, soundcpu=0x20000, sprdata=0x800000, bg0=0x80000, bg1=0x280000, adpcma=0x80000),
        defs=mcat(("u30.bin", 0x05762f42, "u29.bin", 0x4c59d648), ("mca-u84.bin", 0xdf202790, "mca-u85.bin", 0xa85771d2),
                  ("u86.bin", 0x2d3725ed, "u87.bin", 0x4ddefe08), ("mca-u58.bin", 0x3a8186e2, 0, 0x80000, "l"),
                  ("u100.bin", 0xe2c311da, 0x200000, 0x80000, "l"), ("mca-u53.bin", 0x64c76e05, 0, 0x80000, "l"))),
    "catt": dict(game=0, sizes=dict(maincpu=0x100000, soundcpu=0x20000, sprdata=0x800000, bg0=0x100000, bg1=0x280000, adpcma=0x100000),
        defs=mcat(("catt-u30.bin", 0x8c921e1e, "catt-u29.bin", 0xe725af6d), ("u84.bin", 0x843fd624, "u85.bin", 0x5ee7b628),
                  ("mca-u86e", 0x017bf1da, "mca-u87e", 0xbc9dc9b9), ("u58.bin", 0x73c9343a, 0, 0x100000, "l"),
                  ("mca-u100", 0xb273f1b0, 0x200000, 0x80000, "l"), ("u53.bin", 0x99f2a624, 0, 0x100000, "l"), spr1_big=True)),
}

def nost(cpu):
    return {
        "maincpu":  [(cpu[0], cpu[1], 0, 0x80000, "b0"), (cpu[2], cpu[3], 0, 0x80000, "b1")],
        "soundcpu": [("nos-ps.u9", 0x832551e9, 0, 0x40000, "l")],
        "sprdata":  [("nos-se-0.u82", 0x9d99108d, 0x000000, 0x100000, "b0"), ("nos-so-0.u83", 0x7df0fc7e, 0x000000, 0x100000, "b1"),
                     ("nos-se-1.u84", 0xaad07607, 0x200000, 0x100000, "b0"), ("nos-so-1.u85", 0x83d0012c, 0x200000, 0x100000, "b1"),
                     ("nos-se-2.u86", 0xd99e6005, 0x400000, 0x080000, "b0"), ("nos-so-2.u87", 0xf60e8ef3, 0x400000, 0x080000, "b1")],
        "bg0":      [("nos-b0-0.u58", 0x0214b0f2, 0, 0x100000, "l"), ("nos-b0-1.u59", 0x3f8b6b34, 0x100000, 0x80000, "l")],
        "bg1":      [("nos-b1-0.u60", 0xba6fd0c7, 0, 0x100000, "l"), ("nos-b1-1.u61", 0xdabd8009, 0x100000, 0x80000, "l")],
        "adpcma":   [("nossn-00.u53", 0x3bd1bcbc, 0, 0x100000, "l")],
    }
NOST_SIZES = dict(maincpu=0x100000, soundcpu=0x40000, sprdata=0x800000, bg0=0x180000, bg1=0x180000, adpcma=0x100000)
SETS["nost"]  = dict(game=1, sizes=NOST_SIZES, defs=nost(("nos-pe-u.bin", 0x4b080149, "nos-po-u.bin", 0x9e3cd6d9)))
SETS["nostj"] = dict(game=1, sizes=NOST_SIZES, defs=nost(("nos-pe-u.bin", 0x4b080149, "nos-po-j.u29", 0x7fe241de)))   # (nos-pe-j.u30 is the same ROM)
SETS["nostk"] = dict(game=1, sizes=NOST_SIZES, defs=nost(("nos-pe-t.u30", 0xbee5fbc8, "nos-po-t.u29", 0xf4736331)))
ERASEFF = {"sprdata"}

LAYOUT = {"prog": 0x000000, "z80": 0x100000, "spr": 0x140000, "bg0": 0x640000, "bg1": 0x7C0000, "pcm": 0xA40000, "cfg": 0xB40000, "end": 0xB40010}


def load_zip(path):
    files = []
    with zipfile.ZipFile(path) as z:
        for i in z.infolist():
            if not i.is_dir():
                files.append((i.filename, z.read(i)))
    return files

def find(files, name, crc):
    for fn, data in files:
        if os.path.basename(fn).lower() == name.lower() and (zlib.crc32(data) & 0xffffffff) == crc:
            return data
    for fn, data in files:      # renamed copies
        if (zlib.crc32(data) & 0xffffffff) == crc:
            return data
    raise SystemExit("missing %s crc %08x" % (name, crc))

def regions(files, setname):
    s = SETS[setname]
    out = {}
    for region, items in s["defs"].items():
        buf = bytearray(b"\xff" * s["sizes"][region] if region in ERASEFF else bytes(s["sizes"][region]))
        for name, crc, off, size, how in items:
            data = find(files, name, crc)
            assert len(data) == size, (name, len(data), size)
            if how == "l":
                buf[off:off + size] = data
            else:
                buf[off + int(how[1]):off + 2 * size:2] = data
        out[region] = bytes(buf)
    return out

def pack(files, setname):
    r = regions(files, setname)
    img = bytearray(b"\xff" * LAYOUT["end"])
    # 68000: stored little-endian by the loader, so each 68000 word {hi, lo} is stored as lo, hi
    prog = r["maincpu"]
    swapped = bytearray(len(prog))
    swapped[0::2] = prog[1::2]
    swapped[1::2] = prog[0::2]
    img[LAYOUT["prog"]:LAYOUT["prog"] + len(swapped)] = swapped
    img[LAYOUT["z80"]:LAYOUT["z80"] + len(r["soundcpu"])] = r["soundcpu"]
    spr = r["sprdata"][:0x500000]
    img[LAYOUT["spr"]:LAYOUT["spr"] + len(spr)] = spr
    img[LAYOUT["bg0"]:LAYOUT["bg0"] + len(r["bg0"])] = r["bg0"]
    img[LAYOUT["bg1"]:LAYOUT["bg1"] + len(r["bg1"])] = r["bg1"]
    pcm = r["adpcma"]
    img[LAYOUT["pcm"]:LAYOUT["pcm"] + 0x100000] = (pcm * (0x100000 // len(pcm)))[:0x100000]
    cfg = bytearray(16)
    cfg[0] = SETS[setname]["game"]
    nb0, nb1 = len(r["bg0"]) // 128, len(r["bg1"]) // 128
    cfg[1], cfg[2], cfg[3], cfg[4] = nb0 & 255, nb0 >> 8, nb1 & 255, nb1 >> 8
    img[LAYOUT["cfg"]:LAYOUT["cfg"] + 16] = cfg
    return bytes(img)

if __name__ == "__main__":
    zips = [a for a in sys.argv[1:] if a.endswith(".zip")]
    dirs = [a for a in sys.argv[1:] if not a.endswith(".zip")]
    workdir = dirs[0] if dirs else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "work")
    files = []
    for z in zips:
        files += load_zip(z)
    ok = True
    for s in SETS:
        try:
            mine = pack(files, s)
        except SystemExit as e:
            print("%-9s skipped: %s" % (s, e)); continue
        theirs_path = os.path.join(workdir, s + ".rom")
        if os.path.exists(theirs_path):
            theirs = open(theirs_path, "rb").read()
            same = mine == theirs
            print("%-9s %d bytes md5 %s  vs MRA image: %s" % (s, len(mine), hashlib.md5(mine).hexdigest(), "IDENTICAL" if same else "DIFFERENT"))
            ok &= same
        else:
            print("%-9s %d bytes md5 %s (no MRA image to compare)" % (s, len(mine), hashlib.md5(mine).hexdigest()))
    sys.exit(0 if ok else 1)
