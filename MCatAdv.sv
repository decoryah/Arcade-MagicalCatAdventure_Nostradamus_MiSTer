//============================================================================
//
//  Face "LINDA" board -- Magical Cat Adventure / Catt (Wintechno, 1993) and Nostradamus
//  (Face, 1993) -- for MiSTer.
//
//  Written for MiSTer from MAME's driver (src/mame/misc/mcatadv.cpp, tmap038.cpp), after
//  the Analogue Pocket core of finner (https://github.com/finner/openFPGA-Wintechno):
//  the CPUs (fx68k, tv80), the YM2610 (jt10, Jose Tejada) and the memory map come from
//  there; the memories, the video chips, the clocks and the platform layer are new.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;       // signed samples
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

// the DDR3 holds the rotated picture (screen_rotate, below)
assign FB_FORCE_BLANK = 0;

//////////////////////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

// Nostradamus (cfg_game from the ROM image) is a vertical game, MAME's ROT270: the scaler shows its 320x224 raster
// rotated a quarter turn counter-clockwise. Orientation: 0 the game's own, 1 as the raster is, 2 / 3 counter-clockwise /
// clockwise a quarter turn. (The 15 kHz outputs are never rotated.)
wire        nost;
wire  [1:0] osel = status[8:7];
wire  [1:0] orient = (osel == 2'd0) ? (nost ? 2'd2 : 2'd1) : osel;
wire        rotate_ccw = (orient == 2'd2);
wire        no_rotate  = direct_video | (orient == 2'd1);
wire        flip = 1'b0;
wire        video_rotated;

// Aspect ratio and Scale. The framework's video_freak (after arcade_video, below) turns the two into VIDEO_ARX / VIDEO_ARY:
// with Scale Normal they pass through as they are; the integer modes replace them with the exact size in pixels (bit 12 set)
// that the HDMI scaler should give the picture. The menu's order is the user's; video_freak's SCALE input counts
// 0 Normal, 1 V-Integer, 2 Narrower HV-Integer, 3 HV-Integer+ (wider), 4 HV-Integer.
// With the picture turned through the DDR3 frame buffer (Nostradamus' default, or either Rotate) the scaler shows that
// buffer, which video_freak does not know about, so Scale stays Normal then (and the menu entry is hidden); with
// Orientation Horizontal, and on Magical Cat Adventure, the picture is scaled like any other game's.
wire  [1:0] ar = status[122:121];
reg   [2:0] scale_sel;
always @* begin
	case (status[34:32])
		3'd1:    scale_sel = 3'd1;   // V-Integer
		3'd2:    scale_sel = 3'd4;   // HV-Integer
		3'd3:    scale_sel = 3'd2;   // Narrower HV-Integer
		3'd4:    scale_sel = 3'd3;   // HV-Integer+
		default: scale_sel = 3'd0;   // Normal
	endcase
	if (!no_rotate) scale_sel = 3'd0;
end
// Full Screen is ARX = ARY = 0 ("fill"), which has no proportions for the integer rule to size the width from: it sizes the
// height from the width instead and asks for more rows than the screen has. With an integer Scale the screen's own
// proportions stand in for it, so the picture is a whole-number size in the screen's aspect
wire        fs_int = (ar == 2'd1) && (scale_sel != 3'd0) && (HDMI_WIDTH != 12'd0) && (HDMI_HEIGHT != 12'd0);
wire [11:0] arx    = fs_int ? HDMI_WIDTH  : (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
wire [11:0] ary    = fs_int ? HDMI_HEIGHT : (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"A.MCATADV;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H1O[34:32],Scale,Normal,V-Integer,HV-Integer,Narrower HV-Integer,HV-Integer+;",
	"O[8:7],Orientation,Game default,Horizontal,Rotate CCW,Rotate CW;",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1,CRT Adjust;",
	"P1O[40],CRT Adjust,Off,On;",
	"H2P1O[45:41],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H2P1O[52:46],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H2P1O[57:53],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	"O[20],SDRAM read capture,Normal,Late;",
	"O[21],Diagnostic overlay,Off,On;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Jump,Start,Coin;",
	"jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;           // 96 MHz: the machine
wire clk_sdram;         // 96 MHz, shifted: the SDRAM chip's clock pin
wire clk_snd;           // 48 MHz: the YM2610 (jt10's enables are made on the falling edge: a half cycle of 96 MHz is too short)
wire clk_vid;           // 56 MHz: the raster (pixel clock = this / 8 = 7 MHz) and the video output, and the DDR3 port's clock
wire pll_locked;

wire pll_locked_sys, pll_locked_vid;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.outclk_2(clk_snd),
	.locked(pll_locked_sys)
);
pll_vid pll_vid
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
	.locked(pll_locked_vid)
);
assign pll_locked = pll_locked_sys & pll_locked_vid;

///////////////////////////////////////////////////

wire         ioctl_download;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({13'd0, ~status[40], ~no_rotate, direct_video}),   // H1: Scale (hidden while the picture is turned), H2: the CRT Adjust values (hidden while it is Off)
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.video_rotated(video_rotated),
	.gamma_bus(gamma_bus),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

///////////////////////   CONTROLS   ///////////////////////

// keyboard: 1/2 start, 5/6 coin, 9 service, F2 test (MAME's defaults)
reg key_start1, key_start2, key_coin1, key_coin2, key_service, svc_tog;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		case (ps2_key[7:0])
			8'h16: key_start1  <= ps2_key[9];
			8'h1E: key_start2  <= ps2_key[9];
			8'h2E: key_coin1   <= ps2_key[9];
			8'h36: key_coin2   <= ps2_key[9];
			8'h46: key_service <= ps2_key[9];
			8'h06: if (ps2_key[9]) svc_tog <= ~svc_tog;       // F2: the service switch, a toggle as in MAME
			default: ;
		endcase
	end
end

// joystick bits: 0 right, 1 left, 2 down, 3 up, then the buttons in the order of the MRA's <buttons> (tools/make_mra.py), which
// is the game's own: Magical Cat Adventure 4 Fire, 5 Jump, 6 Start, 7 Coin; Nostradamus (one button) 4 Shot, 5 Start, 6 Coin.
// The boards' other inputs, SERVICE1 and the test mode's extra buttons (MAME: "button 2 / 3 in test mode", "test 3"), are not on
// the gamepad: the test mode is entered with the OSD's Service Mode switch or F2, and its screens are stepped with the
// keyboard's 9.
wire j1_r = joystick_0[0], j1_l = joystick_0[1], j1_d = joystick_0[2], j1_u = joystick_0[3];
wire j1_b1 = joystick_0[4], j1_b2 = ~nost & joystick_0[5];
wire j1_start = (nost ? joystick_0[5] : joystick_0[6]) | key_start1, j1_coin = (nost ? joystick_0[6] : joystick_0[7]) | key_coin1;
wire svc_btn = key_service;                                      // SERVICE1: steps through the test mode's screens
wire j2_r = joystick_1[0], j2_l = joystick_1[1], j2_d = joystick_1[2], j2_u = joystick_1[3];
wire j2_b1 = joystick_1[4], j2_b2 = ~nost & joystick_1[5];
wire j2_start = (nost ? joystick_1[5] : joystick_1[6]) | key_start2, j2_coin = (nost ? joystick_1[6] : joystick_1[7]) | key_coin2;

// the board's inputs, active low (MAME's INPUT_PORTS mcatadv, nost):
//   P1: bit 0 up, 1 down, 2 left, 3 right, 4 button 1 (fire), 5 button 2 (jump), 6 button 3 (test mode only, not wired),
//       7 start 1, 8 coin 1, Nostradamus also 9 "test 3" (test mode only, not wired)
//       (Nostradamus: bit 11 is active high and must read 0 or the start-up freezes)
//   P2: the same, bit 7 start 2, 8 coin 2, 9 service 1
wire [15:0] p1_base = ~{6'd0, 1'b0, j1_coin, j1_start, 1'b0, j1_b2, j1_b1, j1_r, j1_l, j1_d, j1_u};
wire [15:0] p1_in = nost ? (p1_base & ~16'h0800) : p1_base;
wire [15:0] p2_in = ~{6'd0, svc_btn, j2_coin, j2_start, 1'b0, j2_b2, j2_b1, j2_r, j2_l, j2_d, j2_u};

// DIP switches: the MRA's <switches> arrive as ioctl index 254, byte 0 = DSW1 bits 15:8 and byte 1 = DSW2 bits 15:8 as
// MAME's ports hold them (a 1 is MAME's default). The low bytes: 1s on Magical Cat Adventure, 0s on Nostradamus.
// F2 toggles the service/test switch (DSW1 bit 10 on Magical Cat Adventure, DSW2 bit 15 on Nostradamus), as does the DIP
// switch's own entry in the OSD.
reg [7:0] sw [8];
initial begin sw[0] = 8'hFF; sw[1] = 8'hFF; end
always @(posedge clk_sys) if (ioctl_wr && ioctl_index[7:0] == 8'd254 && !ioctl_addr[26:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;
wire [7:0]  dsw_lo  = nost ? 8'h00 : 8'hFF;
wire [15:0] dsw1_in = {sw[0] & ~{5'd0, svc_tog & ~nost, 2'd0}, dsw_lo};
wire [15:0] dsw2_in = {sw[1] & ~{svc_tog & nost, 7'd0}, dsw_lo};

///////////////////////   MEMORY   ///////////////////////

// the ROM image: MRA index 0
wire        rom_dl = ioctl_download && (ioctl_index[7:0] == 8'd0);
wire        dl_we  = rom_dl && ioctl_wr;
reg         rom_dl_d;
always @(posedge clk_sys) rom_dl_d <= rom_dl;
wire        dl_start = rom_dl && !rom_dl_d;
wire        dl_done  = !rom_dl && rom_dl_d;

// Fast load: with address= on the MRA's index-0 <rom>, Main_MiSTer copies the whole assembled image into the DDR3 in one
// go and then ends a download that has no data bytes, only a start address: the image's length (ioctl_addr, which is 0 at
// the start of an ordinary download). The machine stays in reset from that start until mcatadv_fastload has read the image
// back and pushed it through the loader (fl_done). An older Main_MiSTer ignores the attribute and streams the bytes as
// before; nothing here touches that path.
wire        mem_init = ~pll_locked | RESET;
reg         fast_dl = 1'b0;
reg  [24:0] fast_len;
wire        fl_done;
always @(posedge clk_sys) begin
	if (dl_start) begin fast_dl <= (ioctl_addr != 27'd0); fast_len <= ioctl_addr[24:0]; end
	else if (fl_done || mem_init) fast_dl <= 1'b0;
end
wire        fl_go = fast_dl && dl_done;

wire        mem_ready;

wire        p_req, t0_req, t1_req, s_req, pcm_req;
wire [19:4] p_addr;
wire [24:1] t0_addr, t1_addr, s_addr;
wire  [4:0] s_len;
wire [19:0] pcm_addr;
wire        p_wr, t0_wr, t1_wr, s_wr, p_done, t0_done, t1_done, s_done, pcm_ack;
wire  [2:0] p_idx;
wire  [1:0] t0_idx, t1_idx;
wire  [3:0] s_idx;
wire [15:0] p_data, t0_data, t1_data, s_data;
wire  [7:0] pcm_q;
wire        z_req, z_wr, z_done;
wire [17:4] z_addr;
wire  [2:0] z_idx;
wire [15:0] z_data;
wire        dl_busy;
wire [15:0] cfg_bg0, cfg_bg1;
wire        cfg_spr0_blank;

// the loader's bytes: the HPS's stream, or a fast load's replay of the image from the DDR3 (never both)
wire        fl_we;
wire [24:0] fl_a;
wire  [7:0] fl_d;

mcatadv_mem u_mem
(
	.clk(clk_sys), .clk_sdram(clk_sdram), .init(mem_init), .rd_late(status[20]), .ready(mem_ready),
	.dl_start(1'b0), .dl_we(dl_we | fl_we), .dl_addr(fl_we ? fl_a : ioctl_addr[24:0]), .dl_data(fl_we ? fl_d : ioctl_dout),
	.dl_wait(ioctl_wait), .dl_busy(dl_busy),
	.cfg_game(nost), .cfg_bg0(cfg_bg0), .cfg_bg1(cfg_bg1), .cfg_spr0_blank(cfg_spr0_blank),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.z_req(z_req), .z_addr(z_addr), .z_wr(z_wr), .z_idx(z_idx), .z_data(z_data), .z_done(z_done),
	.t0_req(t0_req), .t0_addr(t0_addr), .t0_wr(t0_wr), .t0_idx(t0_idx), .t0_data(t0_data), .t0_done(t0_done),
	.t1_req(t1_req), .t1_addr(t1_addr), .t1_wr(t1_wr), .t1_idx(t1_idx), .t1_data(t1_data), .t1_done(t1_done),
	.s_req(s_req), .s_addr(s_addr), .s_len(s_len), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

///////////////////////   THE MACHINE   ///////////////////////

wire        reset_sw = RESET | status[0] | buttons[1];
// the machine is held while a ROM loads and until the memory is up; registered, it fans out to the whole core
reg         mc_rst = 1'b1, vid_rst = 1'b1;
always @(posedge clk_sys) begin
	mc_rst  <= reset_sw | rom_dl | fast_dl | dl_busy | ~mem_ready | ~pll_locked;
	vid_rst <= rom_dl | fast_dl | dl_busy | ~mem_ready | ~pll_locked;
end

wire        ce_pix, hblank, vblank, hsync, vsync, vblank_nl;
wire [23:0] rgb;
wire signed [15:0] snd_l, snd_r;
wire        snd_valid;
wire        dbg_ovr_t0, dbg_ovr_t1, dbg_ovr_s, dbg_irq, dbg_halted, dbg_wdog, dbg_z80;
wire  [9:0] dbg_snd;
wire [23:1] dbg_addr;
wire        trc_stb;

mcatadv_core u_core
(
	.clk(clk_sys), .clk_snd(clk_snd), .clk_vid(clk_vid), .rst(mc_rst), .vid_rst(vid_rst), .wdog_limit(32'd288_000_000),
	.cache_inval(rom_dl | fast_dl | mem_init), .cfg_game(nost), .cfg_spr0_blank(cfg_spr0_blank), .cfg_bg0(cfg_bg0), .cfg_bg1(cfg_bg1),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.z_req(z_req), .z_addr(z_addr), .z_wr(z_wr), .z_idx(z_idx), .z_data(z_data), .z_done(z_done),
	.t0_req(t0_req), .t0_addr(t0_addr), .t0_wr(t0_wr), .t0_idx(t0_idx), .t0_data(t0_data), .t0_done(t0_done),
	.t1_req(t1_req), .t1_addr(t1_addr), .t1_wr(t1_wr), .t1_idx(t1_idx), .t1_data(t1_data), .t1_done(t1_done),
	.s_req(s_req), .s_addr(s_addr), .s_len(s_len), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
	.p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
	.ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .vblank_nl(vblank_nl), .rgb(rgb),
	.snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
	.dbg_ovr_t0(dbg_ovr_t0), .dbg_ovr_t1(dbg_ovr_t1), .dbg_ovr_s(dbg_ovr_s),
	.dbg_irq(dbg_irq), .dbg_halted(dbg_halted), .dbg_wdog(dbg_wdog), .dbg_z80(dbg_z80), .dbg_snd(dbg_snd), .dbg_addr(dbg_addr),
	.trc_stb(trc_stb), .trc_rw(), .trc_data(), .trc_be()
);

///////////////////////   AUDIO   ///////////////////////

reg [15:0] aud_l, aud_r;
always @(posedge clk_sys) if (snd_valid) begin aud_l <= snd_l; aud_r <= snd_r; end
assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

///////////////////////   DIAGNOSTIC OVERLAY   ///////////////////////
// the machine's vital signs along the bottom of the picture (rtl/mcatadv_ovl.sv)
reg  [7:0] ovl_frames, ovl_wd, ovl_ovs, ovl_ovt, ovl_aon;
reg  [9:0] ovl_snd;
reg        ovl_bus, ovl_irq, ovl_z80, ovl_ym, ovl_smp, ovl_o0, ovl_o1, ovl_os, ovl_o0_l, ovl_o1_l, ovl_os_l;
reg        ovl_bus_l, ovl_irq_l, ovl_z80_l;
reg        ovl_irq_d, ovl_wd_d, ovl_o0_d, ovl_o1_d, ovl_os_d, ovl_z80_d;
always @(posedge clk_sys) begin
	ovl_irq_d <= dbg_irq; ovl_wd_d <= dbg_wdog; ovl_o0_d <= dbg_ovr_t0; ovl_o1_d <= dbg_ovr_t1; ovl_os_d <= dbg_ovr_s; ovl_z80_d <= dbg_z80;
	if (trc_stb) ovl_bus <= 1'b1;
	if (dbg_z80 != ovl_z80_d) ovl_z80 <= 1'b1;
	if (dbg_irq && !ovl_irq_d) begin
		ovl_frames <= ovl_frames + 8'd1;
		ovl_bus_l <= ovl_bus; ovl_bus <= 1'b0;
		ovl_irq_l <= 1'b1;
		ovl_z80_l <= ovl_z80; ovl_z80 <= 1'b0;
		ovl_o0_l <= ovl_o0; ovl_o1_l <= ovl_o1; ovl_os_l <= ovl_os; ovl_o0 <= 1'b0; ovl_o1 <= 1'b0; ovl_os <= 1'b0;
	end
	if (dbg_wdog && !ovl_wd_d && ovl_wd != 8'hff) ovl_wd <= ovl_wd + 8'd1;
	if (dbg_ovr_t0 && !ovl_o0_d) begin ovl_o0 <= 1'b1; if (ovl_ovt != 8'hff) ovl_ovt <= ovl_ovt + 8'd1; end
	if (dbg_ovr_t1 && !ovl_o1_d) begin ovl_o1 <= 1'b1; if (ovl_ovt != 8'hff) ovl_ovt <= ovl_ovt + 8'd1; end
	if (dbg_ovr_s  && !ovl_os_d) begin ovl_os <= 1'b1; if (ovl_ovs != 8'hff) ovl_ovs <= ovl_ovs + 8'd1; end
	if (snd_valid) begin ovl_smp <= 1'b1; if (snd_l != 16'd0) ovl_ym <= 1'b1; end
	// sound: what the Z80 and the sample ROM have done since the reset
	if (mc_rst) begin ovl_snd <= 10'd0; ovl_aon <= 8'd0; end
	else begin
		ovl_snd <= ovl_snd | dbg_snd;
		if (dbg_snd[0] && ovl_aon != 8'hff) ovl_aon <= ovl_aon + 8'd1;
	end
end
reg [95:0] ovl_status;
always @* begin
	ovl_status = 96'd0;
	ovl_status[7:0]   = ovl_frames;
	ovl_status[8]     = pll_locked;
	ovl_status[9]     = mem_ready;
	ovl_status[10]    = rom_dl | fast_dl;
	ovl_status[11]    = mc_rst;
	ovl_status[12]    = vid_rst;
	ovl_status[13]    = ovl_bus_l;
	ovl_status[14]    = ovl_irq_l;
	ovl_status[15]    = ovl_z80_l;
	ovl_status[23:16] = ovl_wd;
	ovl_status[24]    = ovl_ym;
	ovl_status[25]    = ovl_smp;
	ovl_status[54:32] = dbg_addr;
	ovl_status[55]    = dbg_halted;
	ovl_status[64]    = ovl_o0_l;
	ovl_status[65]    = ovl_o1_l;
	ovl_status[66]    = ovl_os_l;
	ovl_status[74:67] = ovl_ovs;
	ovl_status[82:75] = ovl_ovt;
	ovl_status[63:56] = ovl_snd;
	ovl_status[90:83] = ovl_aon;
	ovl_status[91]    = nost;
	ovl_status[92]    = ovl_snd[8];
	ovl_status[93]    = ovl_snd[9];
end
wire [23:0] ovl_rgb;
mcatadv_ovl u_ovl
(
	.clk(clk_vid), .ce_pix(ce_pix), .enable(status[21]), .hblank(hblank), .vblank(vblank),
	.rgb_in(rgb), .status(ovl_status), .rgb_out(ovl_rgb)
);

///////////////////////   VIDEO   ///////////////////////

// CRT Adjust: the size and the place of the picture on a 15 kHz analog output (rtl/mcatadv_crt.sv, rmonic79's module).
// Off, or with the scandoubler in use (31 kHz), the picture passes through unchanged. The horizontal blank the
// scandoubler (Scandoubler Fx, MiSTer.ini's forced_scandoubler) gets is the horizontal window alone, toggling on every
// line, with the vertical blank on VBlank: it takes its line timing from the horizontal blank's edges.
wire        crt_sd = (|status[5:3]) | forced_scandoubler;
wire        crt_ce, crt_hb, crt_vb, crt_hs, crt_vs;
wire [23:0] crt_rgb;
mcatadv_crt u_crt
(
	.clk(clk_vid), .ce_pix(ce_pix), .enable(status[40] & ~crt_sd),
	.osd_hsize(status[45:41]), .osd_hpos(status[52:46]), .osd_vshift(status[57:53]),
	.rgb_i(ovl_rgb), .hblank_i(hblank), .vblank_i(vblank), .vblank_nl_i(vblank_nl), .hsync_i(hsync), .vsync_i(vsync),
	.ce_o(crt_ce), .rgb_o(crt_rgb), .hblank_o(crt_hb), .vblank_o(crt_vb), .hsync_o(crt_hs), .vsync_o(crt_vs)
);

wire vga_de_av;
arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_vid),
	.ce_pix(crt_ce),
	.RGB_in(crt_rgb),
	.HBlank(crt_hb),
	.VBlank(crt_vb),
	.HSync(crt_hs),
	.VSync(crt_vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(vga_de_av),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// Scale: integer scaling on the HDMI scaler (framework module; it measures the picture's rows and width from the
// finished stream, scandoubler and CRT Adjust included, and works out the size from HDMI_WIDTH / HEIGHT). Crop is unused.
// With Normal (and always while the picture is turned through the frame buffer) it adds nothing but a few clocks of
// delay to VGA_DE, and passes the aspect ratio through.
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.VGA_DE_IN(vga_de_av),
	.ARX(arx),
	.ARY(ary),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(scale_sel)
);

///////////////////////   DDR3   ///////////////////////

// The DDR3 port is on the raster clock, where the framework's screen_rotate writes the rotated picture (it raises
// DDRAM_WE for a clock per pixel and never looks at DDRAM_BUSY, so it cannot be held off). A fast load takes the port over
// for a burst at a time (mcatadv_fastload: `fl_own`); for that whole load screen_rotate's pixel enable is held off (the
// machine is in reset and there is no picture), so it writes nothing and the port is free. Without a fast load fl_own
// stays 0 and the port is screen_rotate's alone, as it always was.
reg  [1:0] fast_v;                                  // fast_dl in the raster clock's domain
always @(posedge CLK_VIDEO) fast_v <= {fast_v[0], fast_dl};

wire        rot_we, rot_rd_unused, rot_clk_unused;
wire [28:0] rot_addr;
wire [63:0] rot_din;
wire  [7:0] rot_be, rot_burst_unused;

// the scaler's picture, rotated a quarter turn into the DDR3 framebuffer when asked (sys/arcade_video.v)
screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL & ~fast_v[1]),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),

	.rotate_ccw(rotate_ccw),
	.no_rotate(no_rotate),
	.flip(flip),
	.video_rotated(video_rotated),

	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),

	.DDRAM_CLK(rot_clk_unused),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(rot_burst_unused),
	.DDRAM_ADDR(rot_addr),
	.DDRAM_DIN(rot_din),
	.DDRAM_BE(rot_be),
	.DDRAM_WE(rot_we),
	.DDRAM_RD(rot_rd_unused)
);

wire        fl_own, fl_rd;
wire [28:0] fl_addr;
wire  [7:0] fl_burst;
mcatadv_fastload u_fl
(
	.clk(clk_sys), .go(fl_go), .len(fast_len), .abort(dl_start | mem_init),
	.we(fl_we), .addr(fl_a), .data(fl_d), .full(ioctl_wait), .loader_idle(~dl_busy), .done(fl_done),
	.clk_ddr(CLK_VIDEO), .own(fl_own), .ddr_rd(fl_rd), .ddr_addr(fl_addr), .ddr_burst(fl_burst),
	.ddr_busy(DDRAM_BUSY), .ddr_dout(DDRAM_DOUT), .ddr_dready(DDRAM_DOUT_READY)
);

assign DDRAM_CLK      = CLK_VIDEO;
assign DDRAM_BURSTCNT = fl_own ? fl_burst : 8'd1;
assign DDRAM_ADDR     = fl_own ? fl_addr : rot_addr;
assign DDRAM_RD       = fl_own & fl_rd;
assign DDRAM_WE       = ~fl_own & rot_we;
assign DDRAM_DIN      = rot_din;
assign DDRAM_BE       = rot_be;

///////////////////////   LED   ///////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = mc_rst ? act_cnt[24] : (dbg_ovr_t0 | dbg_ovr_t1 | dbg_ovr_s) ? act_cnt[22] : ~dbg_irq | act_cnt[26];

endmodule
