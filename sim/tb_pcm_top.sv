// ADPCM-A sample path bench: mcatadv_pcmrd -> mcatadv_mem -> SDRAM controller -> chip model, with the other
// burst clients (program cache, both tilemaps, sprites) hammering the same port.
`default_nettype none
module tb_pcm_top (
    input  logic clk,
    input  logic init,
    input  logic load_en,
    input  logic [19:0] addr,
    output logic [7:0]  data,
    output logic        mem_ready
);
    wire  [15:0] dram_dq; wire [12:0] dram_a; wire [1:0] dram_ba;
    wire         dram_dqml, dram_dqmh, dram_ncs, dram_nras, dram_ncas, dram_nwe, dram_cke, dram_clk;
    logic        p_req, t0_req, t1_req, s_req, pcm_req, pcm_ack;
    logic [19:4] p_addr; logic [24:1] t0_addr, t1_addr, s_addr; logic [4:0] s_len;
    logic [19:0] pcm_addr; logic [7:0] pcm_q;
    logic        p_done, t0_done, t1_done, s_done;

    mcatadv_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_start(1'b0), .dl_we(1'b0), .dl_addr(25'd0), .dl_data(8'd0), .dl_wait(), .dl_busy(),
        .z80_we(), .z80_waddr(), .z80_wdata(),
        .p_req(p_req), .p_addr(p_addr), .p_wr(), .p_idx(), .p_data(), .p_done(p_done),
        .t0_req(t0_req), .t0_addr(t0_addr), .t0_wr(), .t0_idx(), .t0_data(), .t0_done(t0_done),
        .t1_req(t1_req), .t1_addr(t1_addr), .t1_wr(), .t1_idx(), .t1_data(), .t1_done(t1_done),
        .s_req(s_req), .s_addr(s_addr), .s_len(s_len), .s_wr(), .s_idx(), .s_data(), .s_done(s_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQML(dram_dqml), .SDRAM_DQMH(dram_dqmh), .SDRAM_BA(dram_ba),
        .SDRAM_nCS(dram_ncs), .SDRAM_nWE(dram_nwe), .SDRAM_nRAS(dram_nras), .SDRAM_nCAS(dram_ncas),
        .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk));
    sdram_model #(.PHASE_LAG(0), .AW(23)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqml), .dqmh(dram_dqmh),
        .cs_n(dram_ncs), .ras_n(dram_nras), .cas_n(dram_ncas), .we_n(dram_nwe), .cke(dram_cke));
    mcatadv_pcmrd u_rd (.clk(clk), .rst(init), .addr(addr), .data(data),
                        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q));

    // the other clients: request, wait for done, pause, again
    logic [31:0] lfsr = 32'hace1;
    always_ff @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    logic [3:0] pp, pt0, pt1, ps;
    always_ff @(posedge clk) begin
        if (init || !load_en) begin p_req <= 0; t0_req <= 0; t1_req <= 0; s_req <= 0; pp <= 0; pt0 <= 0; pt1 <= 0; ps <= 0; end
        else begin
            if (p_done) begin p_req <= 0; pp <= 4'd9; end else if (!p_req) begin if (pp != 0) pp <= pp - 1'b1; else begin p_req <= 1; p_addr <= lfsr[19:4]; end end
            if (t0_done) begin t0_req <= 0; pt0 <= 4'd3; end else if (!t0_req) begin if (pt0 != 0) pt0 <= pt0 - 1'b1; else begin t0_req <= 1; t0_addr <= 24'h300000 + {10'd0, lfsr[23:10]}; end end
            if (t1_done) begin t1_req <= 0; pt1 <= 4'd3; end else if (!t1_req) begin if (pt1 != 0) pt1 <= pt1 - 1'b1; else begin t1_req <= 1; t1_addr <= 24'h380000 + {10'd0, lfsr[27:14]}; end end
            if (s_done) begin s_req <= 0; ps <= 4'd2; end else if (!s_req) begin if (ps != 0) ps <= ps - 1'b1; else begin s_req <= 1; s_addr <= 24'h080000 + {5'd0, lfsr[18:0]}; s_len <= 5'd16; end end
        end
    end

    export "DPI-C" function tb_sdram_write;
    function void tb_sdram_write(input int idx, input int w);
        chip.mem[idx[22:0]] = w[15:0];
    endfunction
endmodule
