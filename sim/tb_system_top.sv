// Whole-machine bench: mcatadv_core behind mcatadv_mem and a behavioural SDRAM chip.
// The C++ side preloads the chip (DPI) in the memory layout the loader makes, or pushes a
// ROM image through the loader (dl_*), and can preload the video RAMs from a dump
// (+dump=<prefix> reads <prefix>_t0.hex ... written by tb_main_top) with the CPU held in reset.
`default_nettype none
module tb_system_top (
    input  logic        clk,
    input  logic        clk_snd,
    input  logic        clk_vid,
    input  logic        rst,                // the machine (CPU, sound)
    input  logic        vid_rst,            // the renderers
    input  logic        init,               // the SDRAM controller

    input  logic        dl_start,
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,
    output logic        mem_ready,

    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,
    input  logic [31:0] wdog_limit,

    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic signed [15:0] snd_l, snd_r,
    output logic        snd_valid,

    output logic        dbg_ovr_t0, dbg_ovr_t1, dbg_ovr_s,
    output logic        dbg_irq, dbg_halted, dbg_wdog,
    output logic [23:1] dbg_addr,
    output logic        trc_stb, trc_rw,
    output logic [15:0] trc_data,
    output logic [1:0]  trc_be,
    output logic        busy_s, busy_t0, busy_t1,
    output logic        dbg_z80, ym_wr, nmi_pend, z80_wr, z80_m1
);
    wire  [15:0] dram_dq;
    wire  [12:0] dram_a;
    wire  [1:0]  dram_ba;
    wire         dram_dqml, dram_dqmh, dram_ncs, dram_nras, dram_ncas, dram_nwe, dram_cke, dram_clk;

    logic        p_req, t0_req, t1_req, s_req, pcm_req, z_req;
    logic [19:4] p_addr;
    logic [17:4] z_addr;
    logic [24:1] t0_addr, t1_addr, s_addr;
    logic [4:0]  s_len;
    logic [19:0] pcm_addr;
    logic        p_wr, t0_wr, t1_wr, s_wr, z_wr, p_done, t0_done, t1_done, s_done, z_done, pcm_ack;
    logic [2:0]  p_idx, z_idx;
    logic [1:0]  t0_idx, t1_idx;
    logic [3:0]  s_idx;
    logic [15:0] p_data, t0_data, t1_data, s_data, z_data;
    logic [7:0]  pcm_q;
    logic        cfg_game, cfg_spr0_blank;
    logic [15:0] cfg_bg0, cfg_bg1;

    mcatadv_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_start(dl_start), .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(dl_wait), .dl_busy(dl_busy),
        .cfg_game(cfg_game), .cfg_spr0_blank(cfg_spr0_blank), .cfg_bg0(cfg_bg0), .cfg_bg1(cfg_bg1),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .z_req(z_req), .z_addr(z_addr), .z_wr(z_wr), .z_idx(z_idx), .z_data(z_data), .z_done(z_done),
        .t0_req(t0_req), .t0_addr(t0_addr), .t0_wr(t0_wr), .t0_idx(t0_idx), .t0_data(t0_data), .t0_done(t0_done),
        .t1_req(t1_req), .t1_addr(t1_addr), .t1_wr(t1_wr), .t1_idx(t1_idx), .t1_data(t1_data), .t1_done(t1_done),
        .s_req(s_req), .s_addr(s_addr), .s_len(s_len), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQML(dram_dqml), .SDRAM_DQMH(dram_dqmh), .SDRAM_BA(dram_ba),
        .SDRAM_nCS(dram_ncs), .SDRAM_nWE(dram_nwe), .SDRAM_nRAS(dram_nras), .SDRAM_nCAS(dram_ncas),
        .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk)
    );

    sdram_model #(.PHASE_LAG(0), .AW(23)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqml), .dqmh(dram_dqmh),
        .cs_n(dram_ncs), .ras_n(dram_nras), .cas_n(dram_ncas), .we_n(dram_nwe), .cke(dram_cke)
    );

    // the first boot waits for the watchdog: the bench may shorten that wait, once
    logic wd_seen = 1'b0;
    always_ff @(posedge clk) if (dbg_wdog) wd_seen <= 1'b1;

    mcatadv_core u_core (
        .clk(clk), .clk_snd(clk_snd), .clk_vid(clk_vid), .rst(rst), .vid_rst(vid_rst), .wdog_limit(wd_seen ? 32'd288_000_000 : wdog_limit),
        .cache_inval(dl_start | init), .cfg_game(cfg_game), .cfg_spr0_blank(cfg_spr0_blank), .cfg_bg0(cfg_bg0), .cfg_bg1(cfg_bg1),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .z_req(z_req), .z_addr(z_addr), .z_wr(z_wr), .z_idx(z_idx), .z_data(z_data), .z_done(z_done),
        .t0_req(t0_req), .t0_addr(t0_addr), .t0_wr(t0_wr), .t0_idx(t0_idx), .t0_data(t0_data), .t0_done(t0_done),
        .t1_req(t1_req), .t1_addr(t1_addr), .t1_wr(t1_wr), .t1_idx(t1_idx), .t1_data(t1_data), .t1_done(t1_done),
        .s_req(s_req), .s_addr(s_addr), .s_len(s_len), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
        .dbg_ovr_t0(dbg_ovr_t0), .dbg_ovr_t1(dbg_ovr_t1), .dbg_ovr_s(dbg_ovr_s),
        .dbg_irq(dbg_irq), .dbg_halted(dbg_halted), .dbg_wdog(dbg_wdog), .dbg_z80(dbg_z80), .dbg_addr(dbg_addr),
        .trc_stb(trc_stb), .trc_rw(trc_rw), .trc_data(trc_data), .trc_be(trc_be)
    );


    assign ym_wr    = ~u_core.u_sound.ym_cs_n & ~u_core.u_sound.wr_n;
    assign nmi_pend = u_core.u_sound.nmi_pend;
    assign z80_wr   = u_core.u_sound.mem_wr;
    assign z80_m1   = ~u_core.u_sound.m1_n & ~u_core.u_sound.mreq_n;
    assign busy_s  = u_core.u_spr.busy;
    assign busy_t0 = u_core.u_tm0.busy;
    assign busy_t1 = u_core.u_tm1.busy;

    // ---------------------------------------------------------------- backdoors for the C++ side
    export "DPI-C" function tb_sdram_write;
    function void tb_sdram_write(input int idx, input int w);
        chip.mem[idx[22:0]] = w[15:0];
    endfunction
    export "DPI-C" function tb_sdram_read;
    function int tb_sdram_read(input int idx);
        return {16'd0, chip.mem[idx[22:0]]};
    endfunction
    // the configuration the loader would have captured (a preloaded image does not go through it)
    export "DPI-C" function tb_cfg;
    function void tb_cfg(input int game, input int bg0, input int bg1, input int spr0_blank);
        u_mem.spr0_nz = !spr0_blank[0];
        u_mem.cfg_game = game[0];
        u_mem.cfg_bg0  = bg0[15:0];
        u_mem.cfg_bg1  = bg1[15:0];
    endfunction

    // video RAMs from a dump (tb_main_top's dump_<tag>_*.hex files)
    string dumppre;
    logic [15:0] tmp4k [0:4095];
    logic [15:0] tmp16k [0:16383];
    initial begin
        if ($value$plusargs("dump=%s", dumppre)) begin
            $readmemh({dumppre, "_t0.hex"}, tmp4k);
            for (int i = 0; i < 4096; i++) begin u_core.u_main.u_t0.hi[i] = tmp4k[i][15:8]; u_core.u_main.u_t0.lo[i] = tmp4k[i][7:0]; end
            $readmemh({dumppre, "_t1.hex"}, tmp4k);
            for (int i = 0; i < 4096; i++) begin u_core.u_main.u_t1.hi[i] = tmp4k[i][15:8]; u_core.u_main.u_t1.lo[i] = tmp4k[i][7:0]; end
            $readmemh({dumppre, "_pal.hex"}, tmp4k);
            for (int i = 0; i < 4096; i++) begin u_core.u_main.u_pal.hi[i] = tmp4k[i][15:8]; u_core.u_main.u_pal.lo[i] = tmp4k[i][7:0]; end
            $readmemh({dumppre, "_spr.hex"}, tmp16k);
            for (int i = 0; i < 16384; i++) begin u_core.u_main.u_spr.hi[i] = tmp16k[i][15:8]; u_core.u_main.u_spr.lo[i] = tmp16k[i][7:0]; end
        end
    end

    // registers from the dump, forced into the CPU board's register file
    logic [47:0] r_v0, r_v1;
    logic [15:0] r_x, r_y, r_b;
    string regfile;
    integer rf, rc;
    initial begin
        if ($value$plusargs("dump=%s", dumppre)) begin
            regfile = {dumppre, "_regs.hex"};
            rf = $fopen(regfile, "r");
            rc = $fscanf(rf, "%h\n%h\n%h\n%h\n%h\n", r_v0, r_v1, r_x, r_y, r_b);
            $fclose(rf);
            u_core.u_main.v0[0] = r_v0[15:0];  u_core.u_main.v0[1] = r_v0[31:16];  u_core.u_main.v0[2] = r_v0[47:32];
            u_core.u_main.v1[0] = r_v1[15:0];  u_core.u_main.v1[1] = r_v1[31:16];  u_core.u_main.v1[2] = r_v1[47:32];
            u_core.u_main.vid[0] = r_x; u_core.u_main.vid[1] = r_y; u_core.u_main.vid[2] = r_b;
        end
    end
endmodule
