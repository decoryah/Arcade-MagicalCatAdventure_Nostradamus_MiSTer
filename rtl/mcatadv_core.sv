// The whole machine, without its memory (SDRAM) and the platform: the 68000 board, the sound board,
// the two tilemaps and the sprites, and the raster with its mixer. Clocks: clk 96 MHz, clk_vid 28 MHz.
`default_nettype none
module mcatadv_core (
    input  logic        clk,
    input  logic        clk_snd,              // 48 MHz, in phase with clk: the YM2610
    input  logic        clk_vid,
    input  logic        rst,                  // the machine
    input  logic        vid_rst,              // the video renderers (normally = rst)
    input  logic [31:0] wdog_limit,

    // program load
    input  logic        cache_inval,          // a ROM load starts
    input  logic        cfg_game,             // 1: Nostradamus
    input  logic        cfg_spr0_blank,       // the sprite ROM's tile 0 is blank
    input  logic [15:0] cfg_bg0, cfg_bg1,     // tiles (16x16) in the BG ROMs

    // memory clients (target/mister/mcatadv_mem.sv)
    output logic        p_req,  output logic [19:4] p_addr,
    input  logic        p_wr,   input logic [2:0] p_idx,  input logic [15:0] p_data,  input logic p_done,
    output logic        z_req,  output logic [17:4] z_addr,
    input  logic        z_wr,   input logic [2:0] z_idx,  input logic [15:0] z_data,  input logic z_done,
    output logic        t0_req, output logic [24:1] t0_addr,
    input  logic        t0_wr,  input logic [1:0] t0_idx, input logic [15:0] t0_data, input logic t0_done,
    output logic        t1_req, output logic [24:1] t1_addr,
    input  logic        t1_wr,  input logic [1:0] t1_idx, input logic [15:0] t1_data, input logic t1_done,
    output logic        s_req,  output logic [24:1] s_addr, output logic [4:0] s_len,
    input  logic        s_wr,   input logic [3:0] s_idx,  input logic [15:0] s_data,  input logic s_done,
    output logic        pcm_req, output logic [19:0] pcm_addr,
    input  logic        pcm_ack, input logic [7:0] pcm_q,

    // controls (active low, the board's bit order)
    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,

    // picture and sound
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic signed [15:0] snd_l, snd_r,
    output logic        snd_valid,

    // debug
    output logic        dbg_ovr_t0, dbg_ovr_t1, dbg_ovr_s,
    output logic        dbg_irq,
    output logic        dbg_halted,
    output logic        dbg_wdog,
    output logic        dbg_z80,
    output logic [9:0]  dbg_snd,
    output logic [23:1] dbg_addr,
    output logic        trc_stb, output logic trc_rw, output logic [15:0] trc_data, output logic [1:0] trc_be
);
    // ---------------------------------------------------------------- reset: the input and the watchdog
    logic        wd_pulse;
    logic [7:0]  wd_stretch = 8'd0;
    always_ff @(posedge clk) begin
        if (wd_pulse) wd_stretch <= 8'hff;
        else if (wd_stretch != 8'd0) wd_stretch <= wd_stretch - 8'd1;
    end
    wire mreset = rst | (wd_stretch != 8'd0);
    assign dbg_wdog = wd_stretch != 8'd0;

    logic cen_phi1, cen_phi2, cen_z80, cen_ym;
    mcatadv_cen u_cen (.clk(clk), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2), .cen_z80(cen_z80), .cen_ym(cen_ym));

    // ---------------------------------------------------------------- raster
    logic ls_pulse, frame_pulse, vbl_pulse;
    logic [11:0] pal_raddr;
    logic [15:0] pal_rdata;
    logic        t0_lb_we, t1_lb_we, sp_lb_we;
    logic [9:0]  t0_lb_addr, t1_lb_addr, sp_lb_addr;
    logic [14:0] t0_lb_data, t1_lb_data;
    logic [12:0] sp_lb_data;
    logic [1:0]  t0_en, t1_en;
    mcatadv_video u_video (
        .clk_vid(clk_vid), .clk_sys(clk),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .ls_pulse(ls_pulse), .frame_pulse(frame_pulse), .vbl_pulse(vbl_pulse),
        .t0_we(t0_lb_we), .t0_waddr(t0_lb_addr), .t0_wdata(t0_lb_data),
        .t1_we(t1_lb_we), .t1_waddr(t1_lb_addr), .t1_wdata(t1_lb_data),
        .sp_we(sp_lb_we), .sp_waddr(sp_lb_addr), .sp_wdata(sp_lb_data),
        .t0_en(t0_en), .t1_en(t1_en),
        .pal_raddr(pal_raddr), .pal_rdata(pal_rdata)
    );

    // a line is drawn while the one before it is shown: when line k starts, draw k + 1
    // (the last line of the frame draws line 0 of the next)
    logic [8:0] lk = 9'd0;
    wire  [8:0] lk_new = frame_pulse ? 9'd0 : lk + 9'd1;
    wire  [8:0] tgt    = (lk_new == 9'd259) ? 9'd0 : lk_new + 9'd1;
    logic       r_start;
    logic [7:0] r_line;
    logic       r_bank;
    always_ff @(posedge clk) begin
        r_start <= 1'b0;
        if (ls_pulse) begin
            lk <= lk_new;
            if (tgt <= 9'd223) begin r_start <= 1'b1; r_line <= tgt[7:0]; r_bank <= tgt[0]; end
        end
    end

    // ---------------------------------------------------------------- the 68000 board
    logic        rom_req, rom_ack;
    logic [19:1] rom_addr;
    logic [15:0] rom_data;
    logic [7:0]  snd_cmd, snd_ans;
    logic        snd_cmd_wr, snd_ans_rd;
    logic [11:0] t0_raddr, t1_raddr;
    logic [15:0] t0_rdata, t1_rdata;
    logic [47:0] vreg0, vreg1;
    logic [15:0] vid_x, vid_y, vid_bank;
    logic [13:0] spr_raddr;
    logic [15:0] spr_rdata;

    mcatadv_main u_main (
        .clk(clk), .reset(mreset), .hard_reset(rst), .wdog_limit(wdog_limit), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_data(rom_data),
        .p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
        .vblank_irq(vbl_pulse),
        .snd_cmd(snd_cmd), .snd_cmd_wr(snd_cmd_wr), .snd_ans(snd_ans), .snd_ans_rd(snd_ans_rd),
        .t0_raddr(t0_raddr), .t1_raddr(t1_raddr), .t0_rdata(t0_rdata), .t1_rdata(t1_rdata),
        .vreg0(vreg0), .vreg1(vreg1), .vid_x(vid_x), .vid_y(vid_y), .vid_bank(vid_bank),
        .pal_clk(clk_vid), .pal_raddr(pal_raddr), .pal_rdata(pal_rdata),
        .spr_raddr(spr_raddr), .spr_rdata(spr_rdata),
        .wdog_reset(wd_pulse), .wdog_kick_o(),
        .trc_stb(trc_stb), .trc_addr(dbg_addr), .trc_rw(trc_rw), .trc_data(trc_data), .trc_be(trc_be),
        .cpu_halted(dbg_halted)
    );
    assign dbg_irq = vbl_pulse;

    logic        fill_req, fill_wr, fill_done;
    logic [19:4] fill_addr;
    logic [2:0]  fill_idx;
    logic [15:0] fill_data;
    mcatadv_cache u_cache (
        .clk(clk), .inval(cache_inval), .busy(),
        .req(rom_req), .addr(rom_addr), .ack(rom_ack), .data(rom_data),
        .fill_req(p_req), .fill_addr(p_addr), .fill_wr(p_wr), .fill_idx(p_idx), .fill_data(p_data), .fill_done(p_done)
    );

    // ---------------------------------------------------------------- the sound board
    mcatadv_sound u_sound (
        .clk(clk), .clk_snd(clk_snd), .rst(mreset), .cen_z80(cen_z80), .nost(cfg_game),
        .cmd(snd_cmd), .cmd_wr(snd_cmd_wr), .ans(snd_ans), .ans_rd(snd_ans_rd),
        .cache_inval(cache_inval),
        .zr_req(z_req), .zr_addr(z_addr), .zr_wr(z_wr), .zr_idx(z_idx), .zr_data(z_data), .zr_done(z_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid), .dbg_z80_rd(dbg_z80), .dbg_snd(dbg_snd)
    );

    // ---------------------------------------------------------------- the video chips
    mcatadv_tmap #(.GFX_BASE(24'h300000)) u_tm0 (
        .clk(clk), .rst(vid_rst), .ntiles(cfg_bg0), .start(r_start), .line(r_line), .bank(r_bank),
        .busy(), .overrun(dbg_ovr_t0), .en_bank(t0_en),
        .vregs(vreg0), .vram_addr(t0_raddr), .vram_data(t0_rdata),
        .m_req(t0_req), .m_addr(t0_addr), .m_wr(t0_wr), .m_idx(t0_idx), .m_data(t0_data), .m_done(t0_done),
        .lb_we(t0_lb_we), .lb_addr(t0_lb_addr), .lb_data(t0_lb_data)
    );
    mcatadv_tmap #(.GFX_BASE(24'h3C0000)) u_tm1 (
        .clk(clk), .rst(vid_rst), .ntiles(cfg_bg1), .start(r_start), .line(r_line), .bank(r_bank),
        .busy(), .overrun(dbg_ovr_t1), .en_bank(t1_en),
        .vregs(vreg1), .vram_addr(t1_raddr), .vram_data(t1_rdata),
        .m_req(t1_req), .m_addr(t1_addr), .m_wr(t1_wr), .m_idx(t1_idx), .m_data(t1_data), .m_done(t1_done),
        .lb_we(t1_lb_we), .lb_addr(t1_lb_addr), .lb_data(t1_lb_data)
    );

    logic        spr_half;
    logic [10:0] e_addr;
    logic [15:0] ev_w0, ev_w1, ev_w2, ev_w3, od_w0, od_w1, od_w2, od_w3;
    mcatadv_sprbuf u_sprbuf (
        .clk(clk), .copy(vbl_pulse), .vid_bank(vid_bank), .half(spr_half),
        .live_addr(spr_raddr), .live_data(spr_rdata),
        .e_addr(e_addr), .ev_w0(ev_w0), .ev_w1(ev_w1), .ev_w2(ev_w2), .ev_w3(ev_w3),
        .od_w0(od_w0), .od_w1(od_w1), .od_w2(od_w2), .od_w3(od_w3)
    );
    mcatadv_spr #(.SPR_BASE(24'h080000)) u_spr (
        .clk(clk), .rst(vid_rst), .start(r_start), .line(r_line), .bank(r_bank), .skip_blank0(cfg_spr0_blank), .busy(), .overrun(dbg_ovr_s),
        .vid_x(vid_x), .vid_y(vid_y), .half(spr_half), .e_addr(e_addr),
        .ev_w0(ev_w0), .ev_w1(ev_w1), .ev_w2(ev_w2), .ev_w3(ev_w3),
        .od_w0(od_w0), .od_w1(od_w1), .od_w2(od_w2), .od_w3(od_w3),
        .m_req(s_req), .m_addr(s_addr), .m_len(s_len), .m_wr(s_wr), .m_idx(s_idx), .m_data(s_data), .m_done(s_done),
        .sb_we(sp_lb_we), .sb_addr(sp_lb_addr), .sb_data(sp_lb_data)
    );

    wire unused = ^{fill_req, fill_wr, fill_done, fill_addr, fill_idx, fill_data};
endmodule
`default_nettype wire
