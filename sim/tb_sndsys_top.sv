// The sound board on the real memory system: mcatadv_sound behind mcatadv_mem (loader, arbiter, sdram_ctrl) and a
// behavioural SDRAM chip, with the other clients (68000 program, tilemaps, sprites) making random traffic.
`default_nettype none
module tb_sndsys_top (
    input  logic        clk,
    input  logic        clk_snd,
    input  logic        init,
    input  logic        rst,                // the sound board
    input  logic [7:0]  traffic,            // 0..255: how busy the other clients are

    input  logic        dl_start,
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,
    output logic        mem_ready,
    output logic        cfg_game,
    output logic [15:0] cfg_bg0, cfg_bg1,

    input  logic [7:0]  cmd,
    input  logic        cmd_wr,
    output logic signed [15:0] snd_l,
    output logic        snd_valid,
    output logic        ym_wr, nmi_pend,
    output logic [1:0]  ym_a,
    output logic [7:0]  ym_d,
    output logic        pcm_req_o, pcm_ack_o,
    output logic [19:0] pcm_addr_o,
    output logic [7:0]  pcm_q_o,
    output logic signed [15:0] adpcma_dbg
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

    mcatadv_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_start(dl_start), .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(dl_wait), .dl_busy(dl_busy),
        .cfg_game(cfg_game), .cfg_spr0_blank(), .cfg_bg0(cfg_bg0), .cfg_bg1(cfg_bg1),
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

    // other traffic: each client starts a request now and then (random address in its region), holds it until done
    logic [31:0] lfsr = 32'h1234567;
    always_ff @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    wire go = lfsr[7:0] < traffic;
    always_ff @(posedge clk) begin
        if (init) begin p_req <= 1'b0; t0_req <= 1'b0; t1_req <= 1'b0; s_req <= 1'b0; end
        else begin
            if (!p_req && go && lfsr[12:10] == 3'd0) begin p_req <= 1'b1; p_addr <= lfsr[27:12]; end
            if (p_done) p_req <= 1'b0;
            if (!t0_req && go && lfsr[12:10] == 3'd1) begin t0_req <= 1'b1; t0_addr <= 24'h300000 + {lfsr[26:13], 2'b0}; end
            if (t0_done) t0_req <= 1'b0;
            if (!t1_req && go && lfsr[12:10] == 3'd2) begin t1_req <= 1'b1; t1_addr <= 24'h3C0000 + {lfsr[26:13], 2'b0}; end
            if (t1_done) t1_req <= 1'b0;
            if (!s_req && go && lfsr[12:10] >= 3'd3) begin s_req <= 1'b1; s_addr <= 24'h080000 + {lfsr[28:8]}; s_len <= 5'd16; end
            if (s_done) s_req <= 1'b0;
        end
    end

    logic cen_phi1, cen_phi2, cen_z80, cen_ym;
    mcatadv_cen u_cen (.clk(clk), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2), .cen_z80(cen_z80), .cen_ym(cen_ym));

    logic signed [15:0] sr;
    mcatadv_sound u_snd (
        .clk(clk), .clk_snd(clk_snd), .rst(rst), .cen_z80(cen_z80), .nost(cfg_game),
        .cmd(cmd), .cmd_wr(cmd_wr), .ans(), .ans_rd(1'b0),
        .cache_inval(dl_start | init),
        .zr_req(z_req), .zr_addr(z_addr), .zr_wr(z_wr), .zr_idx(z_idx), .zr_data(z_data), .zr_done(z_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .snd_l(snd_l), .snd_r(sr), .snd_valid(snd_valid), .dbg_z80_rd());
    assign ym_wr    = ~u_snd.ym_cs_n & ~u_snd.wr_n;
    assign nmi_pend = u_snd.nmi_pend;
    assign ym_a = u_snd.A[1:0];
    assign adpcma_dbg = u_snd.adpcm_l;
    assign ym_d = u_snd.dout;
    assign pcm_req_o = pcm_req; assign pcm_ack_o = pcm_ack; assign pcm_addr_o = pcm_addr; assign pcm_q_o = pcm_q;

    export "DPI-C" function tb_sdram_read;
    function int tb_sdram_read(input int idx);
        return {16'd0, chip.mem[idx[22:0]]};
    endfunction
endmodule
