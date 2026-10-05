// Memory of the MCatAdv core on MiSTer: the SDRAM (through sdram_ctrl), the ROM loader and
// the arbiter of the clients of its burst port.
//
// The MRA's image (tools/make_mra.py) arrives a byte at a time; a pair is one 16-bit word of
// the SDRAM (first byte in the low half). Image offset -> memory:
//
//   000000-0FFFFF  68000 program      SDRAM word 000000   (the program cache, 8-word line fills)
//   100000-13FFFF  Z80 program        SDRAM word 580000   (the Z80's cache, 8-word line fills)
//   140000-63FFFF  sprite ROM         SDRAM word 080000   (sprites, bursts of up to 16 words)
//   640000-7BFFFF  BG0 tile ROM       SDRAM word 300000   (rearranged, see below)
//   7C0000-A3FFFF  BG1 tile ROM       SDRAM word 3C0000
//   A40000-B3FFFF  ADPCM-A samples    SDRAM word 500000   (the sound chip's byte reads)
//   B40000-B4000F  configuration      registers: [0] game (0 Magical Cat Adventure / Catt, 1 Nostradamus),
//                                     [1:2] tiles in the BG0 ROM, [3:4] tiles in the BG1 ROM (16x16, little endian)
//
// The tile ROMs are rearranged on the way in: an 8x8 tile is 32 bytes, 4 per row, and a 16x16
// tile is its four 8x8 (top left, top right, bottom left, bottom right). A tile row of the
// 16x16 tile is then 4 bytes in one 8x8 and 4 in the next, 32 bytes apart. Here the byte
// bits of a 128-byte tile  [6] y half [5] x half [4:2] row [1:0] byte  become
//                         [6] y half [5:3] row  [2] x half [1:0] byte
// so a row of the 16x16 tile is 8 bytes in a row: one 4-word burst.
`default_nettype none
module mcatadv_mem (
    input  logic        clk,
    input  logic        clk_sdram,
    input  logic        init,             // reset / (re)initialise the chip
    input  logic        rd_late,
    output logic        ready,

    // loader
    input  logic        dl_start,
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,          // words still being written
    output logic        cfg_game,         // 1: Nostradamus
    output logic        cfg_spr0_blank,   // the sprite ROM's first block (tile 0, 128 bytes) is all zero
    output logic [15:0] cfg_bg0, cfg_bg1, // tiles (16x16) in the BG ROMs

    // burst clients: level request, a word per m_wr with its index, a pulse at the end
    input  logic        p_req,            // 68000 program cache line fill
    input  logic [19:4] p_addr,
    output logic        p_wr, output logic [2:0] p_idx, output logic [15:0] p_data, output logic p_done,

    input  logic        z_req,            // Z80 program cache line fill
    input  logic [17:4] z_addr,
    output logic        z_wr, output logic [2:0] z_idx, output logic [15:0] z_data, output logic z_done,

    input  logic        t0_req,           // tilemap 0 rows (4 words)
    input  logic [24:1] t0_addr,
    output logic        t0_wr, output logic [1:0] t0_idx, output logic [15:0] t0_data, output logic t0_done,

    input  logic        t1_req,           // tilemap 1
    input  logic [24:1] t1_addr,
    output logic        t1_wr, output logic [1:0] t1_idx, output logic [15:0] t1_data, output logic t1_done,

    input  logic        s_req,            // sprite rows (1..16 words)
    input  logic [24:1] s_addr,
    input  logic [4:0]  s_len,
    output logic        s_wr, output logic [3:0] s_idx, output logic [15:0] s_data, output logic s_done,

    // ADPCM-A sample byte read: level request, one-cycle ack with the byte
    input  logic        pcm_req,
    input  logic [19:0] pcm_addr,
    output logic        pcm_ack,
    output logic [7:0]  pcm_q,

    // chip
    inout  wire  [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_A,
    output logic        SDRAM_DQML, SDRAM_DQMH,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS,
    output logic        SDRAM_CKE, SDRAM_CLK
);
    localparam [24:1] SD_PROG = 24'h000000, SD_SPR = 24'h080000, SD_BG0 = 24'h300000, SD_BG1 = 24'h3C0000, SD_PCM = 24'h500000, SD_Z80 = 24'h580000;

    // ------------------------------------------------------------ the loader
    // bytes -> words (the image is sequential)
    logic        lo_v;
    logic [7:0]  lo_d;
    logic        spr0_nz = 1'b0;
    assign cfg_spr0_blank = !spr0_nz;
    logic        wf_push;
    logic [39:0] wf_in;                           // {byte address of the word [24:1] (24), data (16)}
    always_comb begin
        wf_push = 1'b0; wf_in = '0;
        if (dl_we && dl_addr[0] && lo_v) begin
            wf_push = 1'b1; wf_in = {dl_addr[24:1], dl_data, lo_d};
        end
    end
    always_ff @(posedge clk) begin
        if (dl_we) begin
            if (!dl_addr[0]) begin lo_v <= 1'b1; lo_d <= dl_data; end
            else lo_v <= 1'b0;
            // the first block of the sprite ROM (image 140000-14007F): blank?
            if (dl_addr == 25'h000000) spr0_nz <= 1'b0;
            if (dl_addr[24:7] == 18'h2800 && dl_data != 8'h00) spr0_nz <= 1'b1;
            // the configuration bytes at the end of the image
            if (dl_addr[24:4] == 21'hB4000) begin
                case (dl_addr[3:0])
                    4'd0: cfg_game <= dl_data[0];
                    4'd1: cfg_bg0[7:0]  <= dl_data;
                    4'd2: cfg_bg0[15:8] <= dl_data;
                    4'd3: cfg_bg1[7:0]  <= dl_data;
                    4'd4: cfg_bg1[15:8] <= dl_data;
                    default: ;
                endcase
            end
        end
    end

    (* ramstyle = "no_rw_check" *) logic [39:0] wfifo [64];
    logic  [6:0] wf_wp, wf_rp;
    wire         wf_empty = (wf_wp == wf_rp);
    assign dl_wait = ((wf_wp - wf_rp) >= 7'd32);
    assign dl_busy = !wf_empty;

    logic [39:0] hd;
    wire  [24:1] wa = hd[39:16];                  // word index of the image
    wire  [15:0] wd = hd[15:0];
    // the SDRAM word of an image word
    logic [24:1] sd_w;
    wire         is_bg  = (wa >= 24'h320000) && (wa < 24'h520000);          // 640000 .. A3FFFF
    wire  [5:0]  wlo    = wa[6:1];
    wire  [5:0]  wperm  = {wlo[5], wlo[3], wlo[2], wlo[1], wlo[4], wlo[0]};
    always_comb begin
        if (wa < 24'h080000)       sd_w = SD_PROG + wa;                    // program
        else if (wa < 24'h0A0000)  sd_w = SD_Z80 + (wa - 24'h080000);      // Z80 program
        else if (is_bg)            sd_w = {wa[24:7], wperm} - 24'h020000;  // tiles: 0x40000 bytes (the Z80's) less
        else                       sd_w = wa - 24'h020000;                 // sprites, samples
    end

    typedef enum logic [1:0] { W_IDLE, W_DEC, W_SDRAM } wst_t;
    wst_t wst;
    logic        sd_wr_req;
    logic [24:1] sd_wr_addr;

    always_ff @(posedge clk) begin
        if (init) begin
            wf_wp <= '0; wf_rp <= '0; wst <= W_IDLE; sd_wr_req <= 1'b0;
        end else begin
            if (wf_push) begin wfifo[wf_wp[5:0]] <= wf_in; wf_wp <= wf_wp + 7'd1; end
            case (wst)
                W_IDLE: if (!wf_empty) begin hd <= wfifo[wf_rp[5:0]]; wst <= W_DEC; end
                W_DEC: begin
                    if (wa >= 24'h5A0000) begin wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end                      // past the image
                    else begin sd_wr_addr <= sd_w; sd_wr_req <= 1'b1; wst <= W_SDRAM; end
                end
                W_SDRAM: if (sd_wr_ack) begin sd_wr_req <= 1'b0; wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end
                default: wst <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------ SDRAM controller
    logic [24:1] c_addr  [2];
    logic        c_req   [2];
    logic        c_we    [2];
    logic [15:0] c_wdata [2];
    logic  [1:0] c_be    [2];
    logic        c_ack   [2];
    logic [15:0] sd_rdata;
    logic [24:1] b_addr;
    logic  [9:0] b_len, b_idx;
    logic        b_req, b_done, b_wr;
    logic [15:0] b_data;
    logic  [9:0] b_widx;
    logic        sd_ready;
    wire         sd_wr_ack = c_ack[1];

    // client 1: the loader
    assign c_addr[1] = sd_wr_addr;
    assign c_req[1]  = sd_wr_req;
    assign c_we[1]   = 1'b1;
    assign c_wdata[1] = wd;
    assign c_be[1]   = 2'b11;

    // client 0: ADPCM-A byte reads, behind a registered stage
    typedef enum logic [1:0] { Q_IDLE, Q_BUSY, Q_ACK } qst_t;
    qst_t        qst;
    logic [19:0] pcm_a_l;
    logic [15:0] pcm_word;
    always_ff @(posedge clk) begin
        pcm_ack <= 1'b0;
        if (init) begin qst <= Q_IDLE; c_req[0] <= 1'b0; end
        else case (qst)
            Q_IDLE: if (pcm_req && !pcm_ack) begin
                pcm_a_l <= pcm_addr; c_addr[0] <= SD_PCM + {5'b0, pcm_addr[19:1]}; c_req[0] <= 1'b1; qst <= Q_BUSY;
            end
            Q_BUSY: if (c_ack[0]) begin pcm_word <= sd_rdata; c_req[0] <= 1'b0; qst <= Q_ACK; end
            Q_ACK: begin
                if (pcm_req && pcm_addr == pcm_a_l) pcm_ack <= 1'b1;
                qst <= Q_IDLE;
            end
            default: qst <= Q_IDLE;
        endcase
    end
    assign c_we[0]    = 1'b0;
    assign c_wdata[0] = '0;
    assign c_be[0]    = 2'b11;
    assign pcm_q      = pcm_a_l[0] ? pcm_word[15:8] : pcm_word[7:0];

    // ------------------------------------------------------------ burst arbiter
    typedef enum logic [1:0] { B_IDLE, B_RUN, B_ACK } bst_t;
    bst_t        bst;
    logic [2:0]  bsel;                            // 0 program, 1 tiles 0, 2 tiles 1, 3 sprites, 4 Z80 program
    always_ff @(posedge clk) begin
        if (init) begin bst <= B_IDLE; b_req <= 1'b0; end
        else case (bst)
            B_IDLE: begin
                if (p_req)       begin bsel <= 3'd0; b_addr <= SD_PROG + {1'b0, p_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (z_req)  begin bsel <= 3'd4; b_addr <= SD_Z80 + {7'd0, z_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (t0_req) begin bsel <= 3'd1; b_addr <= t0_addr; b_len <= 10'd4;  b_req <= 1'b1; bst <= B_RUN; end
                else if (t1_req) begin bsel <= 3'd2; b_addr <= t1_addr; b_len <= 10'd4;  b_req <= 1'b1; bst <= B_RUN; end
                else if (s_req)  begin bsel <= 3'd3; b_addr <= s_addr;  b_len <= {5'd0, s_len}; b_req <= 1'b1; bst <= B_RUN; end
            end
            B_RUN: if (b_done) begin b_req <= 1'b0; bst <= B_ACK; end
            B_ACK: bst <= B_IDLE;                 // the client sees its done pulse and drops its request
            default: bst <= B_IDLE;
        endcase
    end
    wire run = (bst == B_RUN) && b_wr;
    assign p_wr  = run && bsel == 3'd0;  assign p_idx  = b_idx[2:0]; assign p_data  = b_data;
    assign t0_wr = run && bsel == 3'd1;  assign t0_idx = b_idx[1:0]; assign t0_data = b_data;
    assign t1_wr = run && bsel == 3'd2;  assign t1_idx = b_idx[1:0]; assign t1_data = b_data;
    assign s_wr  = run && bsel == 3'd3;  assign s_idx  = b_idx[3:0]; assign s_data  = b_data;
    assign z_wr  = run && bsel == 3'd4;  assign z_idx  = b_idx[2:0]; assign z_data  = b_data;
    assign p_done  = (bst == B_ACK) && bsel == 3'd0;
    assign t0_done = (bst == B_ACK) && bsel == 3'd1;
    assign t1_done = (bst == B_ACK) && bsel == 3'd2;
    assign s_done  = (bst == B_ACK) && bsel == 3'd3;
    assign z_done  = (bst == B_ACK) && bsel == 3'd4;

    sdram_ctrl #(.NCLI(2)) u_sdram (
        .clk(clk), .clk_pin(clk_sdram), .init(init), .rd_late(rd_late), .burst_slow(1'b0), .ready(sd_ready),
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
        .c_addr(c_addr), .c_req(c_req), .c_we(c_we), .c_wdata(c_wdata), .c_be(c_be), .c_ack(c_ack), .rdata(sd_rdata),
        .b_addr(b_addr), .b_len(b_len), .b_req(b_req), .b_abort(1'b0), .b_wr(b_wr), .b_idx(b_idx), .b_data(b_data), .b_done(b_done),
        .b_we(1'b0), .b_wdata(16'd0), .b_be(2'b00), .b_widx(b_widx)
    );
    assign ready = sd_ready;

    wire unused = ^{b_widx, dl_start, b_idx[9:4]};
endmodule
`default_nettype wire
