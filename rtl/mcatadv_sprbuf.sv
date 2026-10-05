// The sprite RAM's frame buffer. MAME draws the sprites from a copy of the sprite RAM
// made at the start of vertical blanking (buffered_spriteram16 on a vblank rising edge);
// the registers at B00000/B00002 (the sprite offset) are read live, B00004 (the buffer
// half) is copied with it.
//
// The copy is split into the four words of an entry (4 x ...) and into even and odd entries
// (x 2), so the sprite renderer reads two whole entries, entries 2n and 2n + 1, in one clock.
`default_nettype none
module mcatadv_sprbuf (
    input  logic        clk,
    input  logic        copy,              // pulse: copy now
    input  logic [15:0] vid_bank,          // live B00004
    output logic        half,              // the half of the buffer the sprites are drawn from (1 when B00004 = 1)
    output logic [13:0] live_addr,         // read port of the live sprite RAM (data two clocks later)
    input  logic [15:0] live_data,

    input  logic [10:0] e_addr,            // {half, pair[9:0]}: entries 2 * pair and 2 * pair + 1 of the half
    output logic [15:0] ev_w0, ev_w1, ev_w2, ev_w3,   // the even entry
    output logic [15:0] od_w0, od_w1, od_w2, od_w3    // the odd entry
);
    logic        run = 1'b0;
    logic [13:0] i;
    logic        v0, v1;
    logic [13:0] a0, a1;
    always_ff @(posedge clk) begin
        v0 <= 1'b0;
        if (copy && !run) begin
            run <= 1'b1; i <= 14'd0; half <= (vid_bank == 16'h0001);
        end else if (run) begin
            live_addr <= i; v0 <= 1'b1; a0 <= i;
            i <= i + 14'd1;
            if (i == 14'h3fff) run <= 1'b0;
        end
        v1 <= v0; a1 <= a0;
    end
    // word a1 = {half, entry[10:0], word[1:0]}: pair address {half, entry[10:1]} = a1[13:3], parity entry[0] = a1[2]
    wire [10:0] waddr = a1[13:3];
    wire        odd   = a1[2];
    wire  [1:0] wd    = a1[1:0];
    mcatadv_sdp #(.AW(11), .DW(16)) u_e0 (.clk(clk), .we(v1 && !odd && wd == 2'd0), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(ev_w0));
    mcatadv_sdp #(.AW(11), .DW(16)) u_e1 (.clk(clk), .we(v1 && !odd && wd == 2'd1), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(ev_w1));
    mcatadv_sdp #(.AW(11), .DW(16)) u_e2 (.clk(clk), .we(v1 && !odd && wd == 2'd2), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(ev_w2));
    mcatadv_sdp #(.AW(11), .DW(16)) u_e3 (.clk(clk), .we(v1 && !odd && wd == 2'd3), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(ev_w3));
    mcatadv_sdp #(.AW(11), .DW(16)) u_o0 (.clk(clk), .we(v1 &&  odd && wd == 2'd0), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(od_w0));
    mcatadv_sdp #(.AW(11), .DW(16)) u_o1 (.clk(clk), .we(v1 &&  odd && wd == 2'd1), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(od_w1));
    mcatadv_sdp #(.AW(11), .DW(16)) u_o2 (.clk(clk), .we(v1 &&  odd && wd == 2'd2), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(od_w2));
    mcatadv_sdp #(.AW(11), .DW(16)) u_o3 (.clk(clk), .we(v1 &&  odd && wd == 2'd3), .waddr(waddr), .wdata(live_data), .raddr(e_addr), .rdata(od_w3));
endmodule
`default_nettype wire
