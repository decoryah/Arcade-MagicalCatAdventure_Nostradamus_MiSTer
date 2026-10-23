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

# DIP switches. Bytes 0 and 1 of the MRA's <switches> are the high bytes of MAME's DSW1 and DSW2 (a 1 is MAME's default), so
# switch bit 0..7 is DSW1's bit 8..15 and 8..15 is DSW2's. Each field is (name, first bit, number of bits, the settings by
# value: the first is the field's value 0, the last all ones). MiSTer reads a <dip>'s bits="first,last" as a RANGE of bits
# (a single number for one bit), not as a list: a three-bit field written "8,9,10" is read as bits 8..9 and the OSD offers
# only the first four of its eight settings. tools/check_dips.py checks all this against MAME's input ports.
DIPS_MCAT = [
    ("Demo Sounds",  0, 1, "Off,On"),
    ("Flip Screen",  1, 1, "On,Off"),
    ("Service Mode", 2, 1, "On,Off"),
    ("Coin Mode",    3, 1, "Mode 2,Mode 1"),
    # what the two coin switches mean depends on Coin Mode (MAME's PORT_CONDITION): the first is Mode 2's, the second Mode 1's
    ("Coin A",       4, 2, "4C/1C or 2C/3C|3C/1C or 2C/1C|1C/4C or 1C/2C|1C/1C"),
    ("Coin B",       6, 2, "4C/1C or 2C/3C|3C/1C or 2C/1C|1C/4C or 1C/2C|1C/1C"),
    ("Difficulty",   8, 2, "Hardest|Hard|Easy|Normal"),
    ("Lives",       10, 2, "5|2|4|3"),
    ("Energy",      12, 2, "8|5|4|3"),
    ("Cabinet",     14, 2, "Upright 2P (same)|Upright 1P|Cocktail (unused)|Upright 2P"),
]
DIPS_NOST = [
    ("Lives",        0, 2, "5|4|2|3"),
    ("Difficulty",   2, 2, "Hardest|Hard|Easy|Normal"),
    ("Flip Screen",  4, 1, "On,Off"),
    ("Demo Sounds",  5, 1, "Off,On"),
    ("Bonus Life",   6, 2, "None|1000k 2000k|500k 1000k|800k 1500k"),
    ("Coin A",       8, 3, "Free Play|3C/2C|3C/1C|2C/3C|2C/1C|1C/3C|1C/2C|1C/1C"),
    ("Coin B",      11, 3, "4C/1C|3C/2C|3C/1C|2C/3C|2C/1C|1C/3C|1C/2C|1C/1C"),
    ("Unused (SW2:7)", 14, 1, "On,Off"),
    ("Service Mode", 15, 1, "On,Off"),
]

def switches_xml(dips):
    lines = ['    <switches default="FF,FF" base="16">']
    for name, first, n, ids in dips:
        ids = ids.replace("|", ",").split(",") if "|" in ids or "," in ids else [ids]
        assert len(ids) == 1 << n, (name, len(ids), n)               # every field has 2^bits settings
        assert all(ids) and first + n <= 16, name
        rng = str(first) if n == 1 else "%d,%d" % (first, first + n - 1)
        lines.append('        <dip bits="%s" name="%s" ids="%s"/>' % (rng, name, ",".join(ids)))
    lines.append('    </switches>')
    return "\n".join(lines)

SW_MCAT = switches_xml(DIPS_MCAT)
SW_NOST = switches_xml(DIPS_NOST)


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
        # the game plays with one button; the board's other inputs (buttons 2 and 3 and "test 3" in the test mode, Service) are not
        # offered: the core takes the test mode from the Service Mode switch / F2 and the keyboard's 9. The order is the joystick bits
        # from bit 4 on, which MCatAdv.sv decodes per game
        rot, buttons = "vertical (ccw)", '<buttons names="Shot,Start,Coin" default="A,Start,Select"/>'
    else:
        rot, buttons = "horizontal", '<buttons names="Fire,Jump,Start,Coin" default="A,B,Start,Select"/>'
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

      Fast loading: address="0x32000000" makes a recent Main_MiSTer copy the assembled image into the DDR3 in one go; the
      core then reads it back from there (about a second) instead of waiting for it to be streamed through the HPS port.
      An older Main_MiSTer ignores the attribute and streams the image as before.
    -->
{SW_NOST if nost else SW_MCAT}

    <rom index="0" zip="{zipname}" md5="None" address="0x32000000">

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
