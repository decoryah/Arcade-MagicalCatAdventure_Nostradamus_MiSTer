#!/usr/bin/env python3
"""Writes the MRAs of the core: Magical Cat Adventure, Catt and Nostradamus, from the set definitions in
tools/mamerom.py (MAME's ROM_START lists), so that the MRAs and the independent reference image cannot disagree.

The two parent sets are in mra/; the clones go where MiSTer's menu expects the alternatives of a title,
mra/_alternatives/_<title of the parent>/ (copy mra/ into /media/fat/_Arcade/ as it is).

The image layout (docs/memory.md, target/mister/mcatadv_mem.sv) is shared by all the sets:

    0x000000  0x100000  68000 program (16-bit words, byte-swapped: see below)
    0x100000  0x040000  Z80 sound program (128 KB + FF on Magical Cat Adventure, 256 KB on Nostradamus)
    0x140000  0x500000  FX1037 sprite ROM, linear 4bpp
    0x640000  0x180000  BG0 tile ROM (FF beyond the ROM)
    0x7C0000  0x280000  BG1 tile ROM (FF beyond the ROMs)
    0xA40000  0x100000  YM2610 ADPCM-A samples (512 KB is repeated)
    0xB40000  0x000010  configuration: [0] game, [1:2] tiles in BG0, [3:4] tiles in BG1

    python tools/make_mra.py            # writes mra/ and mra/_alternatives/   (the CRCs come from mamerom.py; no ROM files are read)
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mamerom

TITLES = {
    "mcatadv":  ("Magical Cat Adventure",          "Wintechno", "World",  "mcatadv.zip"),
    "mcatadvj": ("Magical Cat Adventure (Japan)",  "Wintechno", "Japan",  "mcatadvj.zip|mcatadv.zip"),
    "catt":     ("Catt (Japan)",                   "Wintechno", "Japan",  "catt.zip|mcatadv.zip"),
    "nost":     ("Nostradamus",                    "Face",      "World",  "nost.zip"),
    "nostj":    ("Nostradamus (Japan)",            "Face",      "Japan",  "nostj.zip|nost.zip"),
    "nostk":    ("Nostradamus Yeeon (Korea)",      "Face",      "Korea",  "nostk.zip|nost.zip"),
}

# the parent of each clone: the clone's MRA goes to mra/_alternatives/_<parent's title>/, the parents' to mra/
CLONE_OF = {"mcatadvj": "mcatadv", "catt": "mcatadv", "nostj": "nost", "nostk": "nost"}

L = mamerom.LAYOUT
SLOT = dict(z80=L["spr"] - L["z80"], spr=0x500000, bg0=L["bg1"] - L["bg0"], bg1=L["pcm"] - L["bg1"], pcm=L["cfg"] - L["pcm"])

# DIP switches: bytes 0 and 1 are the high bytes of MAME's DSW1 and DSW2 (a 1 is MAME's default), eight bits each
SW_MCAT = """    <switches default="FF,FF" base="16">
        <dip bits="0" name="Demo Sounds" ids="Off,On"/>
        <dip bits="1" name="Flip Screen" ids="On,Off"/>
        <dip bits="2" name="Service Mode" ids="On,Off"/>
        <dip bits="3" name="Coin Mode" ids="Mode 2,Mode 1"/>
        <dip bits="4,5" name="Coin A" ids="4C/1C or 2C/3C,3C/1C or 2C/1C,1C/4C or 1C/2C,1C/1C"/>
        <dip bits="6,7" name="Coin B" ids="4C/1C or 2C/3C,3C/1C or 2C/1C,1C/4C or 1C/2C,1C/1C"/>
        <dip bits="8,9" name="Difficulty" ids="Hardest,Hard,Easy,Normal"/>
        <dip bits="10,11" name="Lives" ids="5,2,4,3"/>
        <dip bits="12,13" name="Energy" ids="8,5,4,3"/>
        <dip bits="14,15" name="Cabinet" ids="Upright 2P (same),Upright 1P,Cocktail (unused),Upright 2P"/>
    </switches>"""
SW_NOST = """    <switches default="FF,FF" base="16">
        <dip bits="0,1" name="Lives" ids="5,4,2,3"/>
        <dip bits="2,3" name="Difficulty" ids="Hardest,Hard,Easy,Normal"/>
        <dip bits="4" name="Flip Screen" ids="On,Off"/>
        <dip bits="5" name="Demo Sounds" ids="Off,On"/>
        <dip bits="6,7" name="Bonus Life" ids="None,1000k 2000k,500k 1000k,800k 1500k"/>
        <dip bits="8,9,10" name="Coin A" ids="Free Play,3C/2C,3C/1C,2C/3C,2C/1C,1C/3C,1C/2C,1C/1C"/>
        <dip bits="11,12,13" name="Coin B" ids="4C/1C,3C/2C,3C/1C,2C/3C,2C/1C,1C/3C,1C/2C,1C/1C"/>
        <dip bits="14" name="Unused (SW2:7)" ids="On,Off"/>
        <dip bits="15" name="Service Mode" ids="On,Off"/>
    </switches>"""


def part(name, crc):
    return f'<part name="{name}" crc="{crc:08x}"/>'

def fill(n, byte="FF"):
    return f'<part repeat="0x{n:X}">{byte}</part>' if n else None

def mra(setname):
    s = mamerom.SETS[setname]
    d = s["defs"]
    title, maker, region, zipname = TITLES[setname]
    nost = s["game"] == 1
    out = []                                    # (comment, [lines])

    # 68000 program: the loader packs the stream little-endian (first byte low), so the ROM of the odd bytes (the low
    # byte of each 68000 word) comes first
    (e, ecrc, _, _, _), (o, ocrc, _, _, _) = d["maincpu"]
    out.append(("68000 program: the loader packs the stream little-endian (first byte low), so the ROM of the low "
                "bytes of the words comes first", [
        '<interleave output="16">',
        f'    <part name="{e}" crc="{ecrc:08x}" map="10"/>',
        f'    <part name="{o}" crc="{ocrc:08x}" map="01"/>',
        '</interleave>']))

    # Z80 program
    zn, zcrc, _, zsize, _ = d["soundcpu"][0]
    out.append(("Z80 sound program" + ("" if zsize == SLOT["z80"] else " (the board has half the space: FF)"),
                [part(zn, zcrc)] + ([fill(SLOT["z80"] - zsize)] if zsize != SLOT["z80"] else [])))

    # sprite ROM: pairs of ROMs, the first with the even bytes; MAME fills the unpopulated space with FF
    pairs = {}
    for name, crc, off, size, how in d["sprdata"]:
        pairs.setdefault(off, {})[how] = (name, crc, size)
    pos, lines = 0, []
    for off in sorted(pairs):
        if off > pos:
            lines += ["<!-- the board has no ROMs here: MAME fills the sprite space with FF -->", fill(off - pos)]
            pos = off
        (n0, c0, sz0), (n1, c1, sz1) = pairs[off]["b0"], pairs[off]["b1"]
        assert sz0 == sz1
        lines += ['<interleave output="16">', f'    <part name="{n0}" crc="{c0:08x}" map="01"/>',
                  f'    <part name="{n1}" crc="{c1:08x}" map="10"/>', '</interleave>']
        pos += 2 * sz0
    if pos < SLOT["spr"]:
        lines += ["<!-- the board has no ROMs here: MAME fills the sprite space with FF -->", fill(SLOT["spr"] - pos)]
    out.append(("FX1037 sprite ROM: the first ROM of each pair holds the even bytes", lines))

    # tile ROMs and samples: sequential, then padding
    def seq(region, slot, pad_byte="FF", mirror=False):
        lines, end = [], 0
        for name, crc, off, size, how in d[region]:
            assert off == end and how == "l"
            lines.append(part(name, crc)); end += size
        if mirror:
            assert slot % end == 0
            lines = lines * (slot // end)
        elif end < slot:
            lines.append(fill(slot - end, pad_byte))
        return lines, end
    bg0, nbg0 = seq("bg0", SLOT["bg0"])
    bg1, nbg1 = seq("bg1", SLOT["bg1"])
    pcm, npcm = seq("adpcma", SLOT["pcm"], mirror=True)
    out.append(("BG0 tile ROM, 8x8 4bpp packed (FF beyond the ROM)", bg0))
    out.append(("BG1 tile ROM", bg1))
    out.append(("YM2610 ADPCM-A samples" + (" (the 512 KB ROM twice, as the chip's address wraps)" if npcm < SLOT["pcm"] else ""), pcm))

    t0, t1 = nbg0 // 128, nbg1 // 128
    cfg = [s["game"], t0 & 255, t0 >> 8, t1 & 255, t1 >> 8] + [0] * 11
    out.append(("configuration: game (0 Magical Cat Adventure / Catt, 1 Nostradamus), tiles in BG0 and BG1 (16x16, little endian)",
                ['<part>' + " ".join("%02X" % b for b in cfg) + '</part>']))

    body = []
    for comment, lines in out:
        body.append(f"        <!-- {comment} -->")
        for l in lines:
            for ll in l.split("\n"):
                body.append("        " + ll if not l.startswith("    ") else "        " + ll)
        body.append("")
    body = "\n".join(body)

    if nost:
        # the game plays with one button; buttons 2 and 3, "test 3" and Service are the test mode's (MAME's driver notes)
        rot, buttons = "vertical (ccw)", '<buttons names="Shot,Button 2 (test),Button 3 (test),Start,Coin,Service,Test 3" default="A,B,X,Start,Select,R,L"/>'
    else:
        rot, buttons = "horizontal", '<buttons names="Fire,Jump,Button 3 (test),Start,Coin,Service" default="A,B,X,Start,Select,R"/>'
    return f"""<misterromdescription>
    <rotation>{rot}</rotation>
    <name>{title}</name>
    <setname>{setname}</setname>
    <mameversion>0289</mameversion>
    <year>1993</year>
    <manufacturer>{maker}</manufacturer>
    <players>2</players>
    <joystick>8</joystick>
    <rbf>mcatadv</rbf>
    <region>{region}</region>
    <platform>Face LINDA</platform>

    <!--
      Flat image for the MCatAdv core (target/mister/mcatadv_mem.sv), the same for every set:

        0x000000  0x100000  68000 program
        0x100000  0x040000  Z80 sound program
        0x140000  0x500000  FX1037 sprite ROM, 4bpp, the first pixel of a byte in its low nibble
        0x640000  0x180000  BG0 tile ROM
        0x7C0000  0x280000  BG1 tile ROM
        0xA40000  0x100000  YM2610 ADPCM-A samples
        0xB40000  0x000010  configuration
        0xB40010            end

      Expects the MAME 0.289 merged romset or the split sets: parts are found by name and CRC,
      whatever zip or folder holds them.

      DIP switches (ioctl index 254): byte 0 is the high byte of MAME's DSW1 port, byte 1 the high byte of DSW2
      (bit 0 is SW1:1 / SW2:1 ... a 1 is MAME's default setting).
    -->
{SW_NOST if nost else SW_MCAT}

    <rom index="0" zip="{zipname}" md5="None">

{body}    </rom>

    {buttons}
</misterromdescription>
"""

def mra_path(out, setname):
    title = TITLES[setname][0] + ".mra"
    if setname in CLONE_OF:
        return os.path.join(out, "_alternatives", "_" + TITLES[CLONE_OF[setname]][0], title)
    return os.path.join(out, title)

def main():
    assert set(CLONE_OF) <= set(mamerom.SETS) and all(p in mamerom.SETS and p not in CLONE_OF for p in CLONE_OF.values())
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mra")
    os.makedirs(out, exist_ok=True)
    for here, dirs, files in os.walk(out, topdown=False):       # the MRAs of an earlier run, wherever they were
        for old in files:
            if old.endswith(".mra"):
                os.remove(os.path.join(here, old))
        if here != out and not os.listdir(here):
            os.rmdir(here)
    for setname in mamerom.SETS:
        path = mra_path(out, setname)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(mra(setname))
        print("wrote", os.path.normpath(path))

if __name__ == "__main__":
    sys.exit(main())
