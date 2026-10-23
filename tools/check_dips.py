#!/usr/bin/env python3
"""Checks the DIP switches of the MRAs against MAME's input ports (mcatadv.cpp: the mcatadv and nost INPUT_PORTS).

    python tools/check_dips.py [--mame <path to mcatadv.cpp>] [mra dir]

For every MRA (mra/ and mra/_alternatives/*/) it compares each <dip> with MAME's DSW1 / DSW2 of the game:
  * the same switches (name, which bits), no more, no fewer, none overlapping;
  * bits="first,last" as MiSTer reads it: a range (one bit is a single number), 2^bits settings in ids=, no comma inside a name;
  * every setting where MAME has it (the switch's value 0 first), so that the OSD's n-th entry is the n-th value of the field;
    a setting MAME shows only for one of two states of another switch (PORT_CONDITION: Magical Cat Adventure's Coin Mode) is
    "<Mode 2's> or <Mode 1's>";
  * the default byte of each DSW (the bits of MAME's default settings).
The bytes of <switches> are the high bytes of DSW1 and DSW2 (the low bytes are not switches on these boards).
Exit status 1 if anything differs."""
import os, re, sys, glob

HERE = os.path.dirname(os.path.abspath(__file__))
DEF_STR = {"Demo_Sounds": "Demo Sounds", "Flip_Screen": "Flip Screen", "Coin_A": "Coin A", "Coin_B": "Coin B", "Difficulty": "Difficulty",
           "Lives": "Lives", "Cabinet": "Cabinet", "Cocktail": "Cocktail", "Bonus_Life": "Bonus Life", "None": "None", "Free_Play": "Free Play",
           "Off": "Off", "On": "On", "Easy": "Easy", "Normal": "Normal", "Hard": "Hard", "Hardest": "Hardest"}

def label(s):
    s = s.strip()
    m = re.fullmatch(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if m:
        k = m.group(1)
        c = re.fullmatch(r'(\d)C_(\d)C', k)
        if c:
            return "%sC/%sC" % c.groups()
        return DEF_STR[k]
    return s.strip('"')

def norm(s):                       # "Upright 2 Players" == "Upright 2P (same)"
    s = re.sub(r'\(.*?\)', '', s.lower())
    s = re.sub(r'players?', 'p', s)
    return re.sub(r'\s+', '', s)

def mame_dips(src, ports):
    m = re.search(r'INPUT_PORTS_START\(\s*%s\s*\)(.*?)INPUT_PORTS_END' % ports, src, re.S)
    blk = m.group(1)
    out = {}
    for dsw in ("DSW1", "DSW2"):
        seg = re.search(r'PORT_START\("%s"\)(.*?)(?=PORT_START|\Z)' % dsw, blk, re.S).group(1)
        dips = []                  # [mask, default, name, [(value, label, condition value or None)]]
        for line in seg.splitlines():
            line = line.split('//')[0].strip()
            m = re.match(r'PORT_DIPNAME\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*(.*?)\s*\)\s*(PORT_DIPLOCATION.*)?$', line)
            if m:
                dips.append([int(m.group(1), 16), int(m.group(2), 16), label(m.group(3)), []])
                continue
            m = re.match(r'PORT_DIPSETTING\(\s*(0x[0-9a-fA-F]+)\s*,\s*(.*?)\s*\)\s*(PORT_CONDITION\(.*?,\s*(0x[0-9a-fA-F]+)\s*,\s*EQUALS\s*,\s*(0x[0-9a-fA-F]+)\s*\))?\s*$', line)
            if m:
                cond = int(m.group(5), 16) if m.group(3) else None
                dips[-1][3].append((int(m.group(1), 16), label(m.group(2)), cond))
                continue
            m = re.match(r'PORT_DIPUNUSED_DIPLOC\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*"(.*?)"\s*\)', line)
            if m:
                mk = int(m.group(1), 16)
                dips.append([mk, int(m.group(2), 16), "Unused (%s)" % m.group(3), [(mk, "Off", None), (0, "On", None)]])
                continue
            m = re.match(r'PORT_SERVICE_DIPLOC\(\s*(0x[0-9a-fA-F]+)\s*,\s*IP_ACTIVE_LOW\s*,\s*"(.*?)"\s*\)', line)
            if m:
                mk = int(m.group(1), 16)
                dips.append([mk, mk, "Service Mode", [(mk, "Off", None), (0, "On", None)]])
        out[dsw] = dips
    return out

def expected(dips_by_dsw):
    """-> ([(name, first bit, nbits, [labels by value])], [default byte of DSW1 high, DSW2 high])"""
    fields, defaults = [], []
    for k, dsw in enumerate(("DSW1", "DSW2")):
        d = 0
        for mask, dflt, name, settings in dips_by_dsw[dsw]:
            assert mask & 0xff == 0, (name, "a switch in the low byte")
            mk = mask >> 8
            first = (mk & -mk).bit_length() - 1
            n = bin(mk).count("1")
            assert mk == ((1 << n) - 1) << first, (name, "bits not contiguous")
            labels = []
            for v in range(1 << n):
                same = [(c, l) for val, l, c in settings if val >> 8 == v << first]
                if not same:
                    labels.append("?")
                    continue
                same.sort(key=lambda x: -1 if x[0] is None else x[0])      # Mode 2 (condition 0) first
                labels.append(" or ".join(l for c, l in same) if len(same) > 1 else same[0][1])
            fields.append((name, 8 * k + first, n, labels))
            d |= (dflt >> 8)
        defaults.append(d)
    return fields, defaults

def mra_dips(path):
    s = open(path, encoding="utf-8").read()
    head = re.search(r'<switches default="([^"]*)"', s).group(1)
    dips = []
    for m in re.finditer(r'<dip\s+bits="([\d,]+)"\s+name="([^"]*)"\s+ids="([^"]*)"\s*/>', s):
        dips.append((m.group(1), m.group(2), m.group(3)))
    game = re.search(r'<setname>(\w+)</setname>', s).group(1)
    return game, head, dips

def main():
    args = sys.argv[1:]
    mame = os.path.join(HERE, "..", "..", "ref", "mame", "misc__mcatadv.cpp")
    if "--mame" in args:
        i = args.index("--mame"); mame = args[i + 1]; del args[i:i + 2]
    mradir = args[0] if args else os.path.join(HERE, "..", "mra")
    if not os.path.exists(mame):
        sys.exit("MAME's mcatadv.cpp not found (%s): pass --mame <path>" % mame)
    src = open(mame, encoding="utf-8").read()
    want = {"mcatadv": expected(mame_dips(src, "mcatadv")), "nost": expected(mame_dips(src, "nost"))}
    errors = 0
    paths = sorted(glob.glob(os.path.join(mradir, "*.mra")) + glob.glob(os.path.join(mradir, "_alternatives", "*", "*.mra")))
    for path in paths:
        game, head, dips = mra_dips(path)
        kind = "nost" if game.startswith("nost") else "mcatadv"
        fields, defaults = want[kind]
        bad = []
        # MiSTer's reading of bits: "n" or "first,last"
        got = []
        for bits, name, ids in dips:
            nums = [int(b) for b in bits.split(",")]
            if len(nums) > 2:
                bad.append("%s: bits=\"%s\" lists %d bits (MiSTer reads \"first,last\" as a range)" % (name, bits, len(nums)))
            first, last = nums[0], nums[-1] if len(nums) > 1 else nums[0]
            n = last - first + 1
            idl = ids.split(",")
            if len(idl) != 1 << n:
                bad.append("%s: bits %s are %d bits, %d settings wanted, ids= has %d" % (name, bits, n, 1 << n, len(idl)))
            got.append((name, first, n, idl))
        used = 0
        for name, first, n, labels in fields:
            hit = [g for g in got if g[0] == name]
            if len(hit) != 1:
                bad.append("%s: %d entries in the MRA" % (name, len(hit))); continue
            g = hit[0]
            if (g[1], g[2]) != (first, n):
                bad.append("%s: MRA bits %d..%d, MAME's %d..%d" % (name, g[1], g[1] + g[2] - 1, first, first + n - 1))
            if [norm(x) for x in g[3]] != [norm(x) for x in labels]:
                bad.append("%s: settings %s, MAME's %s" % (name, g[3], labels))
            used |= ((1 << n) - 1) << first
        extra = [g[0] for g in got if g[0] not in [f[0] for f in fields]]
        if extra:
            bad.append("not in MAME: %s" % extra)
        want_head = ",".join("%02X" % d for d in defaults)
        if head.upper() != want_head:
            bad.append("default=\"%s\", MAME's defaults give %s" % (head, want_head))
        print("%-72s %s" % (os.path.relpath(path, mradir), "ok (%d switches, default %s)" % (len(got), head) if not bad else "FAIL"))
        for b in bad:
            print("      " + b)
        errors += len(bad)
    print("%d MRAs checked, %d problems" % (len(paths), errors))
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
