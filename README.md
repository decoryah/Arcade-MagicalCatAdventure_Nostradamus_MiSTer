# Magical Cat Adventure (Wintechno) / Nostradamus (Face) for MiSTer

Wintechno's **Magical Cat Adventure** (1993) and its clones **Catt**, and Face's **Nostradamus** (1993) with its
clones, on the Face "LINDA" board (68000 + Z80 + YM2610, two NEC 038 tilemap chips and a FACE FX1037 sprite
chip), for the MiSTer FPGA platform.

It started from the Analogue Pocket core by **finner**
([openFPGA-Wintechno](https://github.com/finner/openFPGA-Wintechno)): the board's memory map, the
choice of CPU and sound cores (fx68k, tv80, jt10) and the ROM layout come from there, and so does
the evidence that the hardware is as MAME describes it. The video chips, the memory system, the raster, the
clocks and the platform layer are new, written for MiSTer from MAME's driver
(`src/mame/misc/mcatadv.cpp`, `src/devices/video/tmap038.cpp`); see "Differences from the Pocket core".
Nostradamus and the YM2610 set-up were checked against **kyledlester**'s
[Nostradamus_Magical_Cat_Adventure_MiSTer](https://github.com/kyledlester/Nostradamus_Magical_Cat_Adventure_MiSTer),
an independent MiSTer core for the same board (see "Credits").

No ROMs or other copyrighted data are in this repository; you supply your own MAME romsets.

## Status

All six sets (Magical Cat Adventure, Magical Cat Adventure (Japan), Catt, Nostradamus, Nostradamus (Japan), Nostradamus
Yeeon (Korea)) are tested on a real MiSTer and work, including the Flip Screen and the other DIP switches that were tried,
and the service mode.

What has been checked in simulation (Verilator) and in the Quartus flow:

* The video, against a reference renderer (`tools/refrender.py`) that is MAME's `screen_update` written out
  literally: RAM states of the real programs (title screens with rotating backgrounds, row scroll and row select, level
  intros, game play) come out of the RTL **pixel for pixel identical**, through the real memory system (the SDRAM
  controller and a behavioural chip).
* The 68000 side: the real programs boot, pass their RAM and ROM tests, write the power-on signature,
  wait for the watchdog as MAME's driver comments say they should, and reach the attract mode.
* The sound chain on the real memory system (`sim/run_sndsys.sh`: the RTL loader, the SDRAM controller and chip model, the
  Z80's cache, the sample reads, the YM2610, with the video's traffic on the bus): the loader's SDRAM image equals the
  ROM image word for word, and every ADPCM-A sample byte the chip asked for came back right (370,000 of 370,000, the
  slowest in 86 of the 144 clocks the chip allows).
* Quartus Prime Lite 17.0.2 (MiSTer's toolchain): see "Build".

## Install

1. Put `releases/mcatadv_YYYYMMDD.rbf` in `/media/fat/_Arcade/cores/` and the contents of `mra/` (the two `.mra` files and
   the `_alternatives` folder) in `/media/fat/_Arcade/`. Keep the RBF's `mcatadv_` name and date: MiSTer finds the core by
   the MRA's `<rbf>` name plus the date.

       /media/fat/_Arcade/Magical Cat Adventure.mra
       /media/fat/_Arcade/Nostradamus.mra
       /media/fat/_Arcade/_alternatives/_Magical Cat Adventure/   Magical Cat Adventure (Japan), Catt (Japan)
       /media/fat/_Arcade/_alternatives/_Nostradamus/             Nostradamus (Japan), Nostradamus Yeeon (Korea)
       /media/fat/_Arcade/cores/mcatadv_YYYYMMDD.rbf
2. Put your MAME 0.289 `mcatadv.zip` (the parent; the Japan and Catt sets' ROMs are in the merged set,
   or in `mcatadvj.zip` / `catt.zip` next to it) and `nost.zip` (Nostradamus, `nostj.zip`, `nostk.zip`) in
   `/media/fat/games/mame/`.
3. Start a game from the Arcade menu. The ROM takes a few seconds to load. **A cold start shows a black
   screen for a moment** (about 0.4 s): the game writes a signature into its RAM and waits for the watchdog to
   reset it, as on the board (MAME does the same, with a 3 s watchdog). The OSD's Reset starts at once.

The six MRAs (`tools/make_mra.py` writes them from the ROM lists in `tools/mamerom.py`): the parent sets, Magical Cat
Adventure and Nostradamus, are in `mra/`; their clones are in `mra/_alternatives/_<title>/`, where MiSTer's menu keeps the
alternative versions of a title: Magical Cat Adventure (Japan) and Catt (Japan), Nostradamus (Japan) and Nostradamus Yeeon
(Korea).

## OSD options

| Option | Values | |
|---|---|---|
| Aspect ratio | Original, Full Screen, [ARC1], [ARC2] | Original is 4:3 (3:4 when rotated) |
| Orientation | Game default, Horizontal, Rotate CCW, Rotate CW | Nostradamus is a vertical game (MAME's ROT270): its default is the scaler rotating the picture counter-clockwise a quarter turn into the DDR3 framebuffer (`screen_rotate`); the 15 kHz outputs are never rotated |
| Scandoubler Fx | None, HQ2x, CRT 25/50/75 % | |
| DIP switches | per game | the MRA's switches (Lives, Difficulty, Coin A/B, Service Mode, ...); F2 toggles the service switch |
| SDRAM read capture | Normal, Late | for a module that answers slowly; try it if the picture is garbage |
| Diagnostic overlay | Off, On | three rows of squares along the bottom: clocks, SDRAM and ROM load, 68000 / interrupt / Z80 activity, watchdog resets, line overruns, and the sound chain (since the reset: ADPCM-A key-on, FM key-on, SSG level, sample ROM reads, commands received; `rtl/mcatadv_ovl.sv` lists the bits) |
| Reset | | restarts the machine; RAM is kept, so the boot is quick |

Controls: the joystick, Fire (button 1), Jump (button 2), Start, Coin. **Nostradamus plays with one button** (Shot); on both
boards the extra buttons exist for the test mode only (MAME's driver notes): button 3 (Magical Cat Adventure: selects "object
ROM check" and changes the background number), buttons 2 and 3 and "Test 3" (Nostradamus), and **Service**, which steps
through the test mode's screens. Map them in the controller dialog (Service and Test 3 are the 6th and 7th buttons).
Entering the test mode: the "Service Mode" DIP switch (OSD, then Reset) or F2 (a toggle, as in MAME; if the game does not
react at once, press Reset).
Keyboard: 1/2 start, 5/6 coin, 9 service, F2 service switch.

## Sound

The YM2610 is jt10 from JT12 (Jose Tejada), the revision (and the unmodified files) that the Nostradamus MiSTer core of
kyledlester runs, with the SSG (jt49) in it. The mix follows MAME's routes into one speaker: the SSG with 1.0 (0.6 on
Nostradamus), the FM and ADPCM-A left and right 0.5 each. The Z80's program is in SDRAM behind an 8 KB cache
(`rtl/mcatadv_zcache.sv`), the ADPCM-A samples are read from SDRAM a byte at a time. After a reset the sound board is held in
reset 85 us longer than the rest, as the other core does, for jt10's shift registers.

**The chip runs on 48 MHz** (a third output of the PLL, in phase with the 96 MHz machine clock; the other core runs it at
49 MHz). jt10 makes its clock enables on the falling edge of its clock, a half-cycle path to every flip-flop they enable:
10 ns at 48 MHz, 5.2 ns at the 96 MHz this core used before, where the fitted design missed it by 0.3 ns in the slowest timing
model (and where the multicycle constraint on jt10 hid that from the timing analyser). The Z80 and the sample reads stay on
96 MHz; what crosses is held for whole Z80 cycles or whole sample slots and goes edge to edge between the two PLL clocks.

## Differences from the Pocket core

The Pocket core is a working alpha, tested on hardware; its README lists what it could not do. Its video
path was built for the Pocket's 18K-ALM FPGA and its slow PSRAM (an 8-bit colour line buffer, a tile fetch
state machine of about ten states per pixel, row scroll switched off, a simplified tile/sprite priority). The
MiSTer FPGA has room for MAME's behaviour, so this core implements it:

* 15-bit colour (xGRB555 palette), read live per pixel;
* both tilemaps with row scroll and row select (the title screen uses them), per-tile priority,
  the palette bank, MAME's tile/sprite priority comparison and sprite masking;
* sprites from the vblank-buffered copy of the sprite RAM, with MAME's flip, size and clipping rules;
* a 15.625 kHz / 60.1 Hz raster derived from the board's 28 MHz crystal;
* the 68000 at 16 MHz as clock enables, zero wait states on RAM and cache hits;
* the YM2610's ADPCM-A samples read from SDRAM (the Pocket core had them muted: its PSRAM could not
  meet the chip's timing) and the SSG;
* Nostradamus: the same board with another sound map (Z80 ROM 256 KB, YM2610 on I/O ports), other DIP switches,
  the tile ROMs wrapped at 12288 tiles, rotated for the vertical monitor;
* MAME's 3 s watchdog instead of a per-boot hack.

Screen flip (the Flip Screen DIP switch; the game then sets bit 15 of the tilemap registers to 0) mirrors the two tilemaps as MAME's
`draw_tilemap_part` does (checked pixel for pixel against the reference renderer, with X, Y and both flips, row scroll/select
and arbitrary scrolls). The sprites are not flipped: the part of MAME's driver that would is disabled (`#if 0`), and the driver
carries the flag MACHINE_NO_COCKTAIL. The cocktail cabinet setting is not implemented either. The DIP switches are read by the
game at start-up: change them and press Reset.

## Build

Quartus Prime Lite 17.0.2 (MiSTer's toolchain):

    quartus_sh --flow compile MCatAdv

The released build (`releases/mcatadv_20261005.rbf`): 35 % of the ALMs, 321 of 553 RAM blocks, 41 of 112 DSPs; every setup
slack is positive (the YM2610's 48 MHz clock +0.45 ns, the 96 MHz machine +1.48 ns, the HDMI scaler +0.34 ns), the paths
of jt10's clock enables being checked in one clock like any other (`releases/*.summary` are the fitter's and the timing
analyser's reports). MRAs from the first test builds use an older image layout and do not work with it: use the ones in `mra/`.

`tools/make_mra.py` writes the MRAs; `tools/mra_build.py` assembles an image from an MRA and
`tools/mamerom.py` builds the same image straight from MAME's region definitions (the two agree byte for byte for all six sets).

## Simulation

Needs Verilator 5 (the OSS CAD Suite) and Python 3:

    sim/run_main.sh   <game.rom> <frames>          # the 68000 side only, with traces and RAM dumps
    sim/run_system.sh <game.rom> <frames> <name> [+dump=<prefix> +hold +fast +trace +load=rtl +coin=<frame>]
    sim/run_sndsys.sh <game.rom> <seconds> <out.wav> [cmd@ms ...]   # the sound board on the real memory system (TRAFFIC=n)
    sim/run_snd.sh    <game.rom> <out.wav> <seconds> [cmd@ms ...]   # the sound board alone, ideal memories (NOST=1)
    tools/refrender.py <mcatadv.zip> <set> <dump-prefix> ref.ppm rtl.ppm    # reference + comparison

## Repository layout

| | |
|---|---|
| `MCatAdv.sv`, `MCatAdv.qsf/.qpf/.sdc`, `files.qip` | the MiSTer top level (OSD, inputs, video output, DIP switches) and the Quartus project |
| `rtl/` | the board: 68000 side, tilemaps, sprites, raster, palette, sound board, diagnostic overlay |
| `target/mister/` | the SDRAM controller and the ROM loader / memory arbiter |
| `modules/` | other people's cores, with their licences: fx68k, tv80, jt10 (JT12), jt49 |
| `sys/` | the MiSTer framework |
| `mra/` | the MRAs: parents in the folder, clones in `_alternatives/` |
| `releases/` | the tested RBF and its reports |
| `tools/` | MRA writer and builder, reference renderer, ROM-image builder (Python) |
| `sim/` | Verilator benches |
| `docs/` | memory map, clocks, timing |

## License

GPL-3.0, see `LICENSE`. The cores in `modules/` keep their own licences (GPL-3.0, and MIT for tv80; in their folders); the
files of the MiSTer framework in `sys/` keep their own headers (GPL-2.0-or-later for most, GPL-3.0 for some).

## Credits

* finner, the Analogue Pocket core and its research (GPL-3.0).
* MAME (Paul Priest, David Haywood, Luca Elia; BSD-3-Clause): `mcatadv.cpp`, `tmap038.cpp`. The video RTL and
  `tools/refrender.py` follow their logic.
* fx68k, Jorge Cwik (GPL-3.0); tv80, Guy Hutchison (MIT); JT12 / JT10 and JT49, Jose Tejada (GPL-3.0).
* kyledlester, [Nostradamus_Magical_Cat_Adventure_MiSTer](https://github.com/kyledlester/Nostradamus_Magical_Cat_Adventure_MiSTer)
  (GPL-3.0): an independent MiSTer core for the same board. Its notes on the sound board (Nostradamus' Z80 and YM2610
  maps, the mix levels, the reset length) and its copy of JT10 (`modules/jt10`, see `UPSTREAM.txt`) were used here; its
  video and RTL are not.
* The MiSTer framework (Sorgelig and contributors); the SDRAM controller and the PLL phase are those of the
  Gaiapolis MiSTer port.
