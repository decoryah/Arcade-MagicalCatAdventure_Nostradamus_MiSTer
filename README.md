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

The newest build, `mcatadv_20261023.rbf`, has been run on a board by the repository owner and works: Scale, CRT Adjust and fast
loading (see below), the reworked Flip Screen (the first version showed a shifted picture without its sprites, "Screen flip"
below), the Nostradamus coin switches (they offered four of their eight settings) and the gamepad's button list (only the
buttons the games use).

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
* The newer features, on the whole MiSTer top level (`sim/emu/run_emu.sh`: the framework's `hps_io` and PLLs stubbed, an
  SDRAM chip and an Avalon DDR3 modelled, the machine real):
  * fast loading: the 11.8 MB image replayed from the DDR3 in 0.435 s, every one of its 5,898,240 words where the memory's ports
    read it (0 wrong) and the configuration captured, for Magical Cat Adventure and Nostradamus; with the DDR3 model refusing 10 %
    of the clocks, no protocol error on the loader's commands; a fast load interrupted by a streamed download, then started
    again, completes with the same result; a streamed load is unchanged; with the picture being rotated into the frame buffer
    before the load, `screen_rotate` writes nothing while the loader owns the port and writes again after it;
  * CRT Adjust: with it On and the amounts at 0 the picture is byte for byte the Off one (the first row even sits the same number
    of lines from the vertical sync); sizes, positions and shifts come out where the arithmetic says (`sim/run_crt.sh`), no pixel
    lost or doubled; it switches itself off with the scandoubler;
  * Scale: the sizes the core asks the scaler for, for the five modes at two screen sizes and with Full Screen, match the
    framework's integer rule; the 15 kHz picture is unchanged;
  * the scandoubler (Scandoubler Fx, MiSTer.ini's forced_scandoubler): a vertical sync on every frame in all ten modes
    (`sim/run_sd.sh`; the fault that froze the Gaiapolis port's picture, a horizontal blank held through the vertical blank,
    would stall it, and this core does not have it);
  * the raster moved to 56 MHz: all 13 RAM dumps of the real programs (Magical Cat Adventure, Catt, Nostradamus with Flip Screen,
    Nostradamus (Japan)) come out pixel for pixel identical to the reference renderer, as before.
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

   The MRAs carry the `address=` attribute of fast loading, which only `mcatadv_20261022.rbf` and newer understand: used with
   an older RBF a recent Main_MiSTer hands it an empty download and nothing loads. Their button lists (Fire, Jump, Start, Coin;
   Shot, Start, Coin) are the ones of `mcatadv_20261023.rbf`: with an older RBF Start and Coin would be other buttons. Update the
   RBF and the MRAs together.
2. Put your MAME 0.289 `mcatadv.zip` (the parent; the Japan and Catt sets' ROMs are in the merged set,
   or in `mcatadvj.zip` / `catt.zip` next to it) and `nost.zip` (Nostradamus, `nostj.zip`, `nostk.zip`) in
   `/media/fat/games/mame/`.
3. Start a game from the Arcade menu. With a recent Main_MiSTer (one that knows the MRA's `address=` attribute) the ROM image
   is copied to the DDR3 in one go and loaded in about a second; an older one streams it through the HPS port, which takes
   several seconds (see "Fast loading"). **A cold start shows a black
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
| Scale | Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+ | integer scaling for the HDMI scaler; shown only while the picture is not turned (see "Scale") |
| Orientation | Game default, Horizontal, Rotate CCW, Rotate CW | Nostradamus is a vertical game (MAME's ROT270): its default is the scaler rotating the picture counter-clockwise a quarter turn into the DDR3 framebuffer (`screen_rotate`); the 15 kHz outputs are never rotated |
| Scandoubler Fx | None, HQ2x, CRT 25/50/75 % | |
| CRT Adjust | Off, On; H-Size, H-Position, V-Shift | the size and place of the picture on a 15 kHz analog output (see "CRT Adjust") |
| DIP switches | per game | the MRA's switches (Lives, Difficulty, Coin A/B, Service Mode, ...); F2 toggles the service switch |
| SDRAM read capture | Normal, Late | for a module that answers slowly; try it if the picture is garbage |
| Diagnostic overlay | Off, On | three rows of squares along the bottom: clocks, SDRAM and ROM load, 68000 / interrupt / Z80 activity, watchdog resets, line overruns, and the sound chain (since the reset: ADPCM-A key-on, FM key-on, SSG level, sample ROM reads, commands received; `rtl/mcatadv_ovl.sv` lists the bits) |
| Reset | | restarts the machine; RAM is kept, so the boot is quick |

Controls: the joystick and, in the controller dialog, only what the games use: Fire, Jump, Start and Coin on Magical Cat
Adventure, Shot, Start and Coin on Nostradamus (it plays with one button). The boards' test-mode inputs (MAME's driver notes:
Magical Cat Adventure's button 3, which selects "object ROM check" and changes the background number; Nostradamus' buttons 2 and
3 and "test 3"; SERVICE1) are not on the gamepad. The test mode is entered with the "Service Mode" DIP switch (OSD, then Reset) or
F2 (a toggle, as in MAME; if the game does not react at once, press Reset), and the keyboard's 9 is Service, which steps through
Nostradamus' test screens.
Keyboard: 1/2 start, 5/6 coin, 9 service, F2 service switch.

## Scale

Integer scaling for the HDMI scaler, with the framework's `video_freak`, which gives the scaler an exact size in pixels
instead of the aspect ratio. V-Integer makes the picture a whole number of times as tall as its 224 rows (the width follows
the aspect ratio); the three HV modes make the width a whole number of times the picture's 320 columns as well: Narrower
HV-Integer takes the whole-number width below the aspect-correct one, HV-Integer+ the one above (when it fits the screen),
HV-Integer the nearer of the two. Normal leaves the size to the scaler. The 15 kHz analog output is not touched.

When the picture is turned a quarter turn through the DDR3 frame buffer (Nostradamus' default orientation, or Rotate CCW /
CW) the scaler shows that buffer, which `video_freak` does not know about, so Scale stays Normal there and the entry is
hidden. It acts on Magical Cat Adventure with its default orientation, and on Nostradamus with Orientation Horizontal.
With an integer Scale, Full Screen means the screen's own proportions.

## CRT Adjust

For a 15 kHz CRT (rmonic79's [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust), core-side variant, in
`modules/crt-adjust`; the glue is `rtl/mcatadv_crt.sv`). The picture goes through a line buffer and is read out at a different
pixel rate (**H-Size**) or from a different place in the line (**H-Position**), and the vertical sync is delayed by whole lines
(**V-Shift**); the sync pulses keep their rate and place, so the monitor stays locked. It acts on the analog output (and
therefore on what HDMI gets) only while it is On, and not at all with the scandoubler in use (31 kHz). With On and the three
amounts at 0 the picture is the unadjusted one, pixel for pixel.

The raster runs on a 56 MHz clock, eight to a pixel, so that a step of H-Size is 1/32 of the picture's width. The ranges follow
the line: it is 448 pixels, the hsync pulse starts at pixel 360, the picture (320 pixels) starts 88 pixels after the hsync's
leading edge and ends 40 before the next. H-Size goes from -16 (half the width) to +8, H-Position from -48 to +40, V-Shift
from -16 to +10 lines (the blank is 36 lines; further than that the sync would run into the picture). At H-Position 0 the
picture can grow by 3 steps only before its right end runs past the next hsync and is cut: larger sizes need a negative
H-Position (with -48 it fits up to +7).

## Fast loading

With `address="0x32000000"` on the MRA's ROM (all six MRAs carry it), a recent Main_MiSTer copies the whole assembled image
(11.8 MB) into the DDR3 in one go and ends a download that has no data bytes, only a start address that is the image's length
(an ordinary download starts at 0, which is how the core tells them apart). The core stays in reset, reads the image back in
256-byte blocks (a 32-beat burst) and hands the bytes to the same ROM loader the streamed bytes go to, as fast as the loader
takes them: a word every ten clocks or so, under a second for the image. An older Main_MiSTer ignores the attribute and
streams as before, with the same RBF and MRAs. The DDR3 port is on the raster clock, where the framework's `screen_rotate`
writes the rotated picture of Nostradamus; it cannot be held off, so it is held quiet (no pixel enable) for the whole load and
the port is handed over for one burst at a time (`target/mister/mcatadv_fastload.sv`).

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
* a 15.625 kHz / 60.1 Hz raster derived from the board's 28 MHz crystal (run as 56 MHz, eight clocks to a pixel);
* the 68000 at 16 MHz as clock enables, zero wait states on RAM and cache hits;
* the YM2610's ADPCM-A samples read from SDRAM (the Pocket core had them muted: its PSRAM could not
  meet the chip's timing) and the SSG;
* Nostradamus: the same board with another sound map (Z80 ROM 256 KB, YM2610 on I/O ports), other DIP switches,
  the tile ROMs wrapped at 12288 tiles, rotated for the vertical monitor;
* MAME's 3 s watchdog instead of a per-boot hack.

Screen flip (the Flip Screen DIP switch) turns the whole picture, sprites included, through 180 degrees. MAME's driver does not
finish this (MACHINE_NO_COCKTAIL, "fix sprites and rowscroll/select for cocktail"): its tilemaps flip with constants that do not
match what the games write, and its sprites vanish, since the sprite origin register's flip bit is not masked off. The games'
own RAM shows what happens (`tools/flip_check.py` compares captures of the same scene with the switch off and on, for both games,
the title screens with row scroll and row select and the gameplay): the tile RAM, line RAM, sprite RAM and palette stay exactly as
they are, and only the video registers change: bit 15 of the tilemap registers and of the sprite origin registers is flipped, the
scroll values become C - scroll (0x33f in X and 0x2df in Y, modulo 512) and the sprite origin takes values only the chip can use.
So the core turns the registers back into their unflipped values, draws the picture as usual and mirrors it: the line to draw is
223 - line (vertical), the line buffer is read backwards (horizontal). Rendered that way, the flipped capture of every scene is the
unflipped scene turned 180 degrees, pixel for pixel (`tools/refrender.py` has the same model, and the RTL matches it). Whether the
real board's flipped picture is exactly such a mirror, to the pixel, is not known; the cocktail cabinet setting of the Cabinet DIP
switch (Magical Cat Adventure) is not implemented. The diagnostic overlay is drawn on the output and is not mirrored. The DIP
switches are read by the game at start-up: change them and press Reset.

## Build

Quartus Prime Lite 17.0.2 (MiSTer's toolchain):

    quartus_sh --flow compile MCatAdv

The newest build (`releases/mcatadv_20261023.rbf`: Flip Screen as described above, and the gamepad's button list cut to what the
games use): 36 % of the ALMs, 324 of 553 RAM blocks, 41 of 112 DSPs; every setup, hold, recovery and removal slack is positive
(setup: the 56 MHz raster +3.35 ns, the 96 MHz machine +1.79 ns, the YM2610's 48 MHz clock +0.91 ns, the HDMI scaler +0.41 ns;
smallest hold +0.25 ns), the paths of jt10's clock enables being checked in one clock like any other (`releases/*.summary` are
the fitter's and the timing analyser's reports). `mcatadv_20261022.rbf` (37 %, 324 blocks, setup +0.36 ns at the tightest)
added Scale, CRT Adjust and fast loading; the first, `mcatadv_20261005.rbf` (35 %, 321 blocks), ran
its raster on 28 MHz with the vertical sync starting at pixel 0 of a line, not on the hsync pulse's edge (the picture sits 0.2
line lower, relative to it, in the newer builds). MRAs from the first test builds use an older image layout and do not work
with it: use the ones in `mra/`; the button lists of the MRAs and the core go together (this RBF with these MRAs).

`tools/make_mra.py` writes the MRAs and `tools/check_dips.py` checks their DIP switches against MAME's input ports (every
switch, its bits, each of its settings and the defaults; MiSTer reads `bits="first,last"` as a range, a list of three bits
offers only four settings); `tools/mra_build.py` assembles an image from an MRA and
`tools/mamerom.py` builds the same image straight from MAME's region definitions (the two agree byte for byte for all six sets).

## Simulation

Needs Verilator 5 (the OSS CAD Suite) and Python 3:

    sim/run_main.sh   <game.rom> <frames>          # the 68000 side only, with traces and RAM dumps
    sim/run_system.sh <game.rom> <frames> <name> [+dump=<prefix> +hold +fast +trace +load=rtl +coin=<frame>]
    sim/run_sndsys.sh <game.rom> <seconds> <out.wav> [cmd@ms ...]   # the sound board on the real memory system (TRAFFIC=n)
    sim/run_snd.sh    <game.rom> <out.wav> <seconds> [cmd@ms ...]   # the sound board alone, ideal memories (NOST=1)
    sim/run_sd.sh     [frames] [fx] [forced_scandoubler]            # the raster through the framework's scandoubler (vertical sync on every frame)
    sim/run_crt.sh                                                  # CRT Adjust on the raster: sizes, positions and shifts as a monitor sees them
    sim/emu/run_emu.sh <game.rom> [frames] [prefix]                 # the whole MiSTer top level, HPS and DDR3 modelled (FAST=1: fast load; see the script)
    tools/refrender.py <mcatadv.zip> <set> <dump-prefix> ref.ppm rtl.ppm    # reference + comparison

## Repository layout

| | |
|---|---|
| `MCatAdv.sv`, `MCatAdv.qsf/.qpf/.sdc`, `files.qip` | the MiSTer top level (OSD, inputs, video output, DIP switches) and the Quartus project |
| `rtl/` | the board: 68000 side, tilemaps, sprites, raster, palette, sound board, diagnostic overlay |
| `target/mister/` | the SDRAM controller and the ROM loader / memory arbiter |
| `modules/` | other people's cores, with their licences: fx68k, tv80, jt10 (JT12), jt49, crt-adjust |
| `sys/` | the MiSTer framework |
| `mra/` | the MRAs: parents in the folder, clones in `_alternatives/` |
| `releases/` | the tested RBF and its reports |
| `tools/` | MRA writer, builder and DIP checker, reference renderer and its Flip Screen check, ROM-image builder (Python) |
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
* rmonic79 (Umberto Parisi), with Andrea Bogazzi, [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust) (GPL-3.0
  or later): CRT Adjust. Scale is the framework's `video_freak`.
* kyledlester, [Nostradamus_Magical_Cat_Adventure_MiSTer](https://github.com/kyledlester/Nostradamus_Magical_Cat_Adventure_MiSTer)
  (GPL-3.0): an independent MiSTer core for the same board. Its notes on the sound board (Nostradamus' Z80 and YM2610
  maps, the mix levels, the reset length) and its copy of JT10 (`modules/jt10`, see `UPSTREAM.txt`) were used here; its
  video and RTL are not.
* The MiSTer framework (Sorgelig and contributors); the SDRAM controller and the PLL phase are those of the
  Gaiapolis MiSTer port.
