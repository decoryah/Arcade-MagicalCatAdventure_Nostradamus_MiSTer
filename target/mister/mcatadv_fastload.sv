// Fast load: the MRA's address= attribute makes Main_MiSTer copy the whole assembled image into the DDR3 at byte
// 0x32000000 in one go (instead of sending it a byte at a time through the HPS port) and then end a download that has no
// data bytes. This reads the image back in 256-byte blocks (a 32-beat burst of 64 bits) and hands its bytes, in order, to
// the ROM loader (target/mister/mcatadv_mem.sv) exactly as the HPS would have streamed them: a write enable, the byte's
// address and the byte, held back while the loader says it is full (dl_wait). The loader is the limit: a word every
// ten clocks or so, about 0.8 s for the 11.8 MB image.
//
// Two clocks. The DDR3 port runs on the raster clock (clk_ddr = CLK_VIDEO, 56 MHz): that is where the framework's
// screen_rotate writes the rotated picture of Nostradamus, and screen_rotate cannot be stopped by DDRAM_BUSY, so the
// port stays as it is and this module takes it over (`own`) only for a burst, with screen_rotate's pixel enable held off
// for the whole load (MCatAdv.sv). The loader and the bytes run on the machine clock (clk, 96 MHz). Between them, one
// block at a time through a 32 x 64-bit RAM with a four-phase handshake (req / ack, each through two flip-flops):
//
//     clk:      set blk, req = 1 ................... ack seen: read the block's bytes, req = 0 ......... ack gone: next
//     clk_ddr:       req seen: read burst, fill the RAM, ack = 1 ................ req gone: ack = 0
//
// `abort` (a download starts, or the memory is re-initialised) ends the work; the module waits for the reader to be idle
// again (it cannot cancel a burst) before it takes a new `go`.
`default_nettype none
module mcatadv_fastload #(
    parameter [28:0] BASE = 29'h06400000          // DDRAM_ADDR of image byte 0: byte address 0x32000000 / 8
) (
    // machine clock
    input  logic        clk,
    input  logic        go,                       // pulse: the image is in the DDR3 (the fast download ended)
    input  logic [24:0] len,                      // the image's length in bytes
    input  logic        abort,                    // pulse: stop (a new download, a memory re-initialisation)
    output logic        we,                       // loader write enable, like the HPS port's ioctl_wr
    output logic [24:0] addr,
    output logic  [7:0] data,
    input  logic        full,                     // the loader's dl_wait
    input  logic        loader_idle,              // the loader has written everything it was given
    output logic        done,                     // pulse: the whole image has gone through the loader

    // DDR3 port clock
    input  logic        clk_ddr,
    output logic        own,                      // this module drives the DDR3 port (a burst is in flight)
    output logic        ddr_rd,
    output logic [28:0] ddr_addr,
    output logic  [7:0] ddr_burst,
    input  logic        ddr_busy,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dready
);
    // ------------------------------------------------------------------ the reader (clk_ddr)
    logic        req = 1'b0;                      // clk domain
    logic [16:0] blk;                             // clk domain, stable while req is high
    logic        ack = 1'b0, rd_idle = 1'b1;      // clk_ddr domain
    logic  [1:0] req_s = 2'b00;                   // req into clk_ddr
    logic        buf_we = 1'b0;
    logic  [4:0] beats = 5'd0;
    logic [63:0] buf_d;
    logic  [4:0] w_addr;                          // the beat that buf_d holds

    typedef enum logic [1:0] { R_IDLE, R_CMD, R_DAT, R_DONE } rs_t;
    rs_t rs = R_IDLE;
    logic own_r = 1'b0, rd_r = 1'b0;
    assign own    = own_r;
    assign ddr_rd = rd_r;
    always_ff @(posedge clk_ddr) begin
        req_s  <= {req_s[0], req};
        buf_we <= 1'b0;
        case (rs)
            R_IDLE: begin
                ack <= 1'b0;
                if (req_s[1]) begin
                    ddr_addr <= BASE + {7'd0, blk, 5'd0};          // 32 beats of 8 bytes = 256 bytes a block
                    ddr_burst <= 8'd32;
                    rd_r <= 1'b1; own_r <= 1'b1; rd_idle <= 1'b0; beats <= 5'd0;
                    rs <= R_CMD;
                end else rd_idle <= 1'b1;
            end
            R_CMD: if (!ddr_busy) begin rd_r <= 1'b0; rs <= R_DAT; end         // accepted on this edge
            R_DAT: if (ddr_dready) begin
                buf_d <= ddr_dout; buf_we <= 1'b1; w_addr <= beats;             // written into the RAM on the next edge
                beats <= beats + 5'd1;
                if (beats == 5'd31) begin own_r <= 1'b0; ack <= 1'b1; rs <= R_DONE; end
            end
            R_DONE: if (!req_s[1]) begin ack <= 1'b0; rs <= R_IDLE; end
            default: rs <= R_IDLE;
        endcase
    end

    logic [63:0] rdata;
    logic  [4:0] raddr;
    mcatadv_sdp2 #(.AW(5), .DW(64)) u_buf (
        .wclk(clk_ddr), .we(buf_we), .waddr(w_addr), .wdata(buf_d),
        .rclk(clk), .raddr(raddr), .rdata(rdata)
    );

    // ------------------------------------------------------------------ the feeder (clk)
    logic [1:0] ack_s = 2'b00, idle_s = 2'b11;
    always_ff @(posedge clk) begin ack_s <= {ack_s[0], ack}; idle_s <= {idle_s[0], rd_idle}; end

    typedef enum logic [2:0] { F_IDLE, F_REQ, F_FEED, F_REL, F_FIN, F_ABRT } fst_t;
    fst_t        fst = F_IDLE;
    logic [16:0] nblk;
    logic [24:0] flen;
    logic  [7:0] fidx;                            // byte within the block
    logic [24:0] fa;                              // byte address of the next byte to hand out
    logic        p_v = 1'b0;                      // stage 1: a byte was asked of the RAM
    logic [24:0] p_a;
    logic  [2:0] p_lane;
    logic  [6:0] acnt;
    logic        we_r = 1'b0, done_r = 1'b0;
    logic        go_p = 1'b0;                     // `go` is a pulse: kept until the state machine can take it
    assign we   = we_r;
    assign done = done_r;

    assign raddr = fidx[7:3];
    wire   can   = (fst == F_FEED) && !full && (fa < flen);
    wire   blk_end = (fidx == 8'd255) || (fa + 25'd1 >= flen);

    always_ff @(posedge clk) begin
        done_r <= 1'b0;
        if (go) go_p <= 1'b1;
        // stage 2: the byte of the word the RAM has just read
        we_r <= p_v;
        addr <= p_a;
        data <= rdata[8 * p_lane +: 8];
        p_v  <= 1'b0;
        if (abort && fst != F_IDLE) begin
            req <= 1'b0; we_r <= 1'b0; p_v <= 1'b0; acnt <= 7'd0; fst <= F_ABRT;
        end else case (fst)
            F_IDLE: if (go || go_p) begin
                go_p <= 1'b0;
                blk <= 17'd0; fa <= 25'd0; fidx <= 8'd0; flen <= len;
                nblk <= 17'((len + 25'd255) >> 8);
                fst <= (len == 25'd0) ? F_FIN : F_REQ;
            end
            F_REQ: begin
                req <= 1'b1;
                if (req && ack_s[1]) begin fidx <= 8'd0; fst <= F_FEED; end
            end
            F_FEED: begin
                if (can) begin
                    p_v <= 1'b1; p_a <= fa; p_lane <= fidx[2:0];
                    fa <= fa + 25'd1; fidx <= fidx + 8'd1;
                    if (blk_end) begin req <= 1'b0; fst <= F_REL; end
                end else if (fa >= flen) begin req <= 1'b0; fst <= F_REL; end
            end
            F_REL: if (!ack_s[1]) begin
                blk <= blk + 17'd1;
                fst <= (blk + 17'd1 >= nblk) ? F_FIN : F_REQ;
            end
            F_FIN: if (loader_idle && !p_v && !we_r) begin done_r <= 1'b1; fst <= F_IDLE; end
            F_ABRT: begin
                acnt <= acnt + 7'd1;
                if (acnt == 7'd127 && idle_s[1] && !ack_s[1]) fst <= F_IDLE;
            end
            default: fst <= F_IDLE;
        endcase
    end
endmodule
`default_nettype wire
