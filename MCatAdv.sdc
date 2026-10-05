derive_pll_clocks
derive_clock_uncertainty

# ==============================================================================
# SDRAM. The chip is clocked by the PLL's second 96 MHz output, shifted about half a period
# (pll/pll_0002.v); like JTFRAME's MiSTer builds the pin's clock is modelled as the machine
# clock inverted, and the read data -- launched by the chip's edge, captured by sdram_ctrl's input
# register three edges after the READ command -- gets a two-cycle path. The register assignments
# in sys/sys.tcl put the SDRAM pins' registers in the IO cells.
# ==============================================================================
set sdram_clk_src [get_pins -nowarn {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
if { [get_collection_size $sdram_clk_src] == 0 } {
    set sdram_clk_src [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
}
create_generated_clock -name SDRAM_CLK -source $sdram_clk_src -divide_by 1 -phase 180 [get_ports {SDRAM_CLK}]

set sys_clk [get_clocks -nowarn {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
if { [get_collection_size $sys_clk] == 0 } {
    set sys_clk [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
}
set snd_clk [get_clocks -nowarn {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[2].output_counter|divclk}]
if { [get_collection_size $snd_clk] == 0 } {
    set snd_clk [get_clocks {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]
}
set vid_clk [get_clocks -nowarn {emu|pll_vid|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
if { [get_collection_size $vid_clk] == 0 } {
    set vid_clk [get_clocks {emu|pll_vid|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
}
set_multicycle_path -from [get_clocks {SDRAM_CLK}] -to $sys_clk -setup -end 2
set_multicycle_path -from [get_clocks {SDRAM_CLK}] -to $sys_clk -hold  -end 2

# the controller's round-robin pointer settles long before it is used (S_IDLE -> S_ARB)
set_multicycle_path -setup 3 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]
set_multicycle_path -hold  2 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]

# ==============================================================================
# The machine clock (96 MHz) and the raster clock (28 MHz) are unrelated; what crosses between them
# is the raster's event toggles (three-flop synchronisers), the line buffers and the palette RAM
# (separate write and read clocks), and the video RAM's register copies that change a line at a time.
# ==============================================================================
set_clock_groups -asynchronous -group [add_to_collection $sys_clk $snd_clk] -group $vid_clk

# The framework's sys_top.sdc keeps its core-clock group ({*|pll|pll_inst|...}) apart from the HDMI, audio, SPI and
# HPS clocks. The raster clock comes from a second PLL (pll_vid), so it is put in the same position here: CLK_VIDEO
# is the picture's clock into the scaler, which crosses to the HDMI clock inside the framework.
set_clock_groups -exclusive \
   -group $vid_clk \
   -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { spi_sck}] \
   -group [get_clocks { hdmi_sck}] \
   -group [get_clocks { *|h2f_user0_clk}] \
   -group [get_clocks { FPGA_CLK1_50 }] \
   -group [get_clocks { FPGA_CLK2_50 }] \
   -group [get_clocks { FPGA_CLK3_50 }]

# ==============================================================================
# The YM2610 (jt10), on the 48 MHz clock (the PLL's third output, in phase with the 96 MHz one: the two are related, edge to
# edge). Its registers step on clock enables, the fastest an 8 MHz one (6 clocks apart); the paths between them have at least
# that long. What is NOT relaxed: the enables themselves (jt12_div's clk_en*, made on the falling edge, so a half-cycle path
# to every flip-flop they enable), the reset (jt12_rst) and cen_reg, which must make it in one clock. (The input interface's
# edge detectors are one or two LUTs deep.)
# ==============================================================================
set JT_ALL  [get_registers {*|jt10:*|*}]
set JT_EN   [get_registers {*|jt10:*|*jt12_div:*|clk_en* *|jt10:*|*jt12_rst:*|rst_n *|jt10:*|*jt12_top:*|cen_reg}]
set JT_DATA [remove_from_collection $JT_ALL $JT_EN]
set_multicycle_path -setup 4 -from $JT_DATA -to $JT_ALL
set_multicycle_path -hold  3 -from $JT_DATA -to $JT_ALL

# ==============================================================================
# The Z80 (tv80) steps on cen_z80, one clock in 24: its registers, and the sound board's registers and RAM ports
# it drives, change only at those steps, and what the board hands back (data) is sampled only there.
# ==============================================================================
set Z80 [get_keepers {*|tv80s_cen:*|*}]
set SND [get_keepers {*|mcatadv_sound:*|*}]
set_multicycle_path -setup 4 -from $Z80 -to $Z80
set_multicycle_path -hold  3 -from $Z80 -to $Z80
set_multicycle_path -setup 4 -from $Z80 -to $SND
set_multicycle_path -hold  3 -from $Z80 -to $SND
set_multicycle_path -setup 4 -from $SND -to $Z80
set_multicycle_path -hold  3 -from $SND -to $Z80

# ==============================================================================
# The 68000 (fx68k) steps on enPhi1 / enPhi2, which alternate every third clock: its registers change on an enable
# and so are at least three clocks apart.
# ==============================================================================
set FX68 [get_keepers {*|fx68k:*|*}]
set_multicycle_path -setup 3 -from $FX68 -to $FX68
set_multicycle_path -hold  2 -from $FX68 -to $FX68
