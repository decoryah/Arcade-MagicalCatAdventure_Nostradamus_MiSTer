# MCatAdv: memory, clocks, timing

## Clocks

| clock | from | used for |
|---|---|---|
| `clk_sys` 96 MHz | PLL `pll_0002` (960 MHz VCO) | everything but the raster and the YM2610 |
| `clk_sdram` 96 MHz, -5078 ps | same PLL | the SDRAM chip's clock pin |
| `clk_snd` 48 MHz | same PLL, third output, in phase with `clk_sys` | the YM2610 (jt10) and the sound board's mix; its enable is ÷6 = 8 MHz |
| `clk_vid` 28 MHz | PLL `pll_vid` (700 MHz VCO / 25) | the raster; pixel clock = `clk_vid` / 4 = 7 MHz |

The board has a 16 MHz and a 28 MHz crystal (MAME: `XTAL(16'000'000)`; the Nostradamus PCB photo lists
OSC 28.000 MHz and OSC 16.000 MHz). From `clk_sys`, as clock enables (`rtl/mcatadv_cen.sv`):
68000 16 MHz (÷6, as fx68k's alternating phase enables) and Z80 4 MHz (÷24); the YM2610's 8 MHz is
`clk_snd` ÷ 6 (`rtl/mcatadv_sound.sv`), all in phase as on the board (16 MHz / 4 and / 2). jt10 is on its own,
48 MHz clock because it makes its clock enables on the falling edge, a half-cycle path that 96 MHz does not meet
(`MCatAdv.sdc`); what crosses between `clk_sys` and `clk_snd` is held for whole Z80 cycles or sample slots,
and the two PLL outputs are edge to edge.

The raster is the usual 15.625 kHz arcade one: 448 x 260 pixels at 7 MHz = 60.1 Hz, 320 x 224 visible.
MAME gives only "60 Hz, 320 x 256 total, 320 x 224 visible", so the totals and the position of the
sync pulses are a choice (`rtl/mcatadv_video.sv`).

## The ROM image and the SDRAM (word addresses; the 32 MB module is more than enough, the image is 11 MB)

Every set, Magical Cat Adventure, Catt and Nostradamus alike, is the same flat image (`tools/make_mra.py` writes
the MRAs, `tools/mamerom.py` builds the same image from MAME's region lists):

| image bytes | SDRAM words | content |
|---|---|---|
| 000000-0FFFFF | 000000 | 68000 program (16-bit words, little endian: the cache fills it 8 words a time) |
| 100000-13FFFF | 580000 | Z80 program: 128 KB (Magical Cat Adventure, then FF) or 256 KB (Nostradamus); the Z80's cache fills 8 words a time |
| 140000-63FFFF | 080000 | sprite ROM (5 MB; MAME's region is 8 MB, FF past 5 MB, which the sprite renderer supplies) |
| 640000-7BFFFF | 300000 | BG0 tile ROM, 1.5 MB slot (FF beyond the ROM) |
| 7C0000-A3FFFF | 3C0000 | BG1 tile ROM, 2.5 MB slot (FF beyond the ROM(s)) |
| A40000-B3FFFF | 500000 | YM2610 ADPCM-A samples, 1 MB (a 512 KB ROM twice: the chip's address wraps) |
| B40000-B4000F | (registers) | configuration: [0] game (0 Magical Cat Adventure / Catt, 1 Nostradamus), [1:2] 16x16 tiles in the BG0 ROM, [3:4] in the BG1 ROM (little endian) |

The tile counts are what MAME wraps a tile code by (4096 / 20480 on Magical Cat Adventure, 8192 / 20480 on Catt, 12288 / 12288 on
Nostradamus); `mcatadv_tmap` takes the code modulo `ntiles` (a mask when it is a power of two).

### Tile ROM rearrangement

MAME's `gfx_8x8x4_packed_msb`: an 8x8 tile is 32 bytes, 4 a row, the left pixel in the high nibble; a 16x16
tile of the 038 is code * 4 + (x half) + 2 * (y half) of those. A 16-pixel row of it would be 4 bytes in
one 8x8 and 4 in the next, 32 bytes apart. The loader (`target/mister/mcatadv_mem.sv`) swaps two groups
of address bits inside each 128-byte tile:

    [6] y half  [5] x half  [4:2] row  [1:0] byte      ->      [6] y half  [5:3] row  [2] x half  [1:0] byte

so a tile's row is 8 consecutive bytes, one 4-word burst. Sim: `tb_system.cpp` and `tb_sndsys.cpp` apply the same swap to
their backdoor preload / readback and compare the RTL loader's result with it.

## The sound board's memories

* **Z80 program**: SDRAM, through `rtl/mcatadv_zcache.sv`, a direct-mapped 8 KB cache of 16-byte lines. A read that misses holds
  the Z80 with WAIT until the line has come (about 0.5 us; MAME has no waits) and the cache is swept empty when a ROM
  load starts. 256 KB of block RAM would have cost 50 of the FPGA's 553 M10K blocks the video needs.
* **ADPCM-A samples**: the chip asks for a byte address every 1.5 us slot, for each of its six channels in turn
  (`rtl/mcatadv_pcmrd.sv`); the byte is read from SDRAM whenever the address changes. The random-access port is served before the
  burst port's next chunk, so the wait is at most about 100 clocks of the 144 the slot gives.

## The line pipeline

One display line is drawn while the one before it is shown (double-buffered line buffers):
when line k starts, `mcatadv_core` starts line k + 1 in the renderers. The two tilemaps (`mcatadv_tmap`)
and the sprites (`mcatadv_spr`) run side by side, reading the tile RAM / sprite buffer from block RAM and
the ROMs through the SDRAM controller's burst port (`mcatadv_mem`: program cache fills first, then the
tile rows, then the sprite rows). A line that is not finished when the next starts is dropped and counted
(`dbg_ovr_*`; the LED blinks).

* Tilemaps: 21 tile slices of 16 pixels, each a tile RAM read (2 words) and a 4-word ROM burst; the pixels go
  into the line buffer (`{opaque, priority, palette index}`), 1 pixel a clock.
* Sprites: the line buffer is cleared, then the 2048 entries are scanned one a clock; an entry that crosses
  the line gets bursts from the sprite ROM (16 words, 64 pixels, at most) drawn 1 pixel a clock.
  Entries are drawn first to last, each over the last (MAME draws last to first and lets the first
  non-zero pixel win).
  Nostradamus clears its sprite list with a thousand entries of `0, 0, 1000, 1000` (a 16 x 16 sprite of tile 0 at the
  corner). They draw nothing because the first block of the sprite ROM is blank in every set, but fetching it a thousand
  times a line would starve the first lines of the frame (and leave the last lines of the previous frame's sprites in the
  line buffer: the dropped lines are not redrawn). The loader checks the first 128 bytes of the sprite ROM and the scanner
  skips entries of tile 0 when they are zero (`cfg_spr0_blank`); the result is the same as MAME's.
* Display (28 MHz): the three line buffers are read, mixed (MAME's `screen_update` priority rules) and looked
  up in the palette RAM, which the 68000 writes on the other clock, so palette changes show in the
  middle of a line as on the board.

`tools/refrender.py` is MAME's `screen_update` written out literally (tilemap passes, priority bitmap,
sprite loop); the RTL frame of a RAM dump matches it pixel for pixel.

## Watchdog

MAME's driver has a 3 s watchdog (it says itself "a guess, and certainly wrong") that resets the machine, and
the game relies on it: on a cold start it writes `MASICAL CAT ADVENTURE` into RAM (an unusual spelling,
MAME's driver comments on it) and waits for the reset, which happens 3 s later; with the signature present it
boots at once. The RAM is not cleared by the reset (the FPGA's block RAM keeps its contents), so the OSD's
Reset boots at once; loading the game does not. A boot that goes on kicks the watchdog (a write to B00018)
for the first time about 95 ms after the reset on Magical Cat Adventure, so after a reset from outside (a game
loading, the OSD's Reset: `hard_reset` in `rtl/mcatadv_main.sv`) the limit is an eighth of MAME's 3 s (0.375 s)
until the watchdog has been kicked or has expired once: the cold start's wait is short, and Magical Cat Adventure's
boot that goes on is not hit. Nostradamus' first kick comes later than 0.375 s, so the short limit runs out once
(a watchdog reset) and from then on the limit is MAME's 3 s; the watchdog's own resets never bring the short
limit back.
