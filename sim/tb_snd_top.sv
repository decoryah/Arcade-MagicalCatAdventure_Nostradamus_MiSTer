// Sound board bench: the Z80, the YM2610 and the sample ROM, driven by scripted 68000 commands.
// (Ideal memories: the Z80 program through the same line-fill protocol as the SDRAM's, the samples after a fixed delay.
//  sim/tb_sndsys_top.sv runs the same board on the real memory system.)
`default_nettype none
module tb_snd_top #(
    parameter [12:0] RST_EXTRA = 13'h1fff
) (
    input  logic clk,
    input  logic rst,
    input  logic nost,
    input  logic [7:0] cmd,
    input  logic       cmd_wr,
    output logic signed [15:0] snd_l,
    output logic       snd_valid,
    output logic [7:0] ans,
    output logic       z80_rd,
    output logic       ym_wr, nmi_pend, z80_wr,
    output logic [19:0] pcm_addr_o,
    output logic       pcm_req_o,
    output logic [1:0] ym_a,
    output logic [7:0] ym_d,
    output logic signed [15:0] adpcma_dbg      // the ADPCM-A part of the mix, inside jt12_top
);
    // the clock here is 16 MHz: the YM2610's 8 MHz enable every 2nd clock, the Z80's 4 MHz every 4th (an eighth of the
    // work per second of sound compared to the 96 MHz machine; the sound board does not care)
    logic [1:0] cdiv = 2'd0;
    logic cen_z80;
    always_ff @(posedge clk) begin cdiv <= cdiv + 2'd1; cen_z80 <= (cdiv == 2'd3); end

    logic [7:0] zrom [0:262143];
    logic [7:0] pcm  [0:1048575];
    initial begin $readmemh("z80.hex", zrom); $readmemh("pcm.hex", pcm); end

    // the Z80 program's line fills: 8 words, as the SDRAM arbiter delivers them
    logic        zr_req, zr_wr = 1'b0, zr_done = 1'b0;
    logic [17:4] zr_addr;
    logic [2:0]  zr_idx;
    logic [15:0] zr_data;
    typedef enum logic [2:0] { Z_IDLE, Z_WAIT, Z_DATA, Z_DONE, Z_END } zst_t;
    zst_t zst = Z_IDLE;
    logic [4:0] zcnt;
    logic [3:0] zi;
    always_ff @(posedge clk) begin
        zr_wr <= 1'b0; zr_done <= 1'b0;
        case (zst)
            Z_IDLE: if (zr_req) begin zcnt <= 5'd20; zst <= Z_WAIT; end
            Z_WAIT: if (zcnt == 0) begin zi <= 4'd0; zst <= Z_DATA; end else zcnt <= zcnt - 5'd1;
            Z_DATA: begin
                zr_wr <= 1'b1; zr_idx <= zi[2:0];
                zr_data <= {zrom[{zr_addr, zi[2:0], 1'b1}], zrom[{zr_addr, zi[2:0], 1'b0}]};
                zi <= zi + 4'd1;
                if (zi == 4'd7) zst <= Z_DONE;
            end
            Z_DONE: begin zr_done <= 1'b1; zst <= Z_END; end
            Z_END: if (!zr_req) zst <= Z_IDLE;
            default: zst <= Z_IDLE;
        endcase
    end

    logic        pcm_req, pcm_ack;
    logic [19:0] pcm_addr;
    logic [7:0]  pcm_q;
    logic [4:0]  pdly = 5'd0;
    logic        pbusy = 1'b0;
    always_ff @(posedge clk) begin
        pcm_ack <= 1'b0;
        if (pcm_req && !pbusy && !pcm_ack) begin pbusy <= 1'b1; pdly <= 5'd20; end
        else if (pbusy) begin
            if (pdly == 0) begin pcm_q <= pcm[pcm_addr]; pcm_ack <= 1'b1; pbusy <= 1'b0; end
            else pdly <= pdly - 5'd1;
        end
    end
    assign pcm_addr_o = pcm_addr; assign pcm_req_o = pcm_req;

    logic signed [15:0] sr;
    mcatadv_sound #(.RST_EXTRA(RST_EXTRA), .YM_DIV(2)) u_snd (
        .clk(clk), .clk_snd(clk), .rst(rst), .cen_z80(cen_z80), .nost(nost),
        .cmd(cmd), .cmd_wr(cmd_wr), .ans(ans), .ans_rd(1'b0),
        .cache_inval(1'b0),
        .zr_req(zr_req), .zr_addr(zr_addr), .zr_wr(zr_wr), .zr_idx(zr_idx), .zr_data(zr_data), .zr_done(zr_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .snd_l(snd_l), .snd_r(sr), .snd_valid(snd_valid), .dbg_z80_rd(z80_rd));
    assign ym_wr    = ~u_snd.ym_cs_n & ~u_snd.wr_n;
    assign nmi_pend = u_snd.nmi_pend;
    assign z80_wr   = u_snd.mem_wr;
    assign ym_a = u_snd.A[1:0];
    assign adpcma_dbg = u_snd.adpcm_l;
    assign ym_d = u_snd.dout;
endmodule
