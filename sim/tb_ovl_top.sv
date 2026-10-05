// Diagnostic overlay bench: the raster, the overlay and a status pattern.
`default_nettype none
module tb_ovl_top (
    input  logic clk, input logic clk_vid,
    output logic ce_pix, hblank, vblank,
    output logic [23:0] rgb
);
    logic hsync, vsync, ls, fr, vbl;
    logic [23:0] rgb_v;
    mcatadv_video u_v (
        .clk_vid(clk_vid), .clk_sys(clk), .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb_v),
        .ls_pulse(ls), .frame_pulse(fr), .vbl_pulse(vbl),
        .t0_we(1'b0), .t0_waddr(10'd0), .t0_wdata(15'd0), .t1_we(1'b0), .t1_waddr(10'd0), .t1_wdata(15'd0),
        .sp_we(1'b0), .sp_waddr(10'd0), .sp_wdata(13'd0), .t0_en(2'b00), .t1_en(2'b00),
        .pal_raddr(), .pal_rdata(16'h7fff));
    // a recognisable status: bit n set when n is a multiple of 3 or n < 8
    logic [95:0] st;
    always_comb begin for (int n = 0; n < 96; n++) st[n] = (n % 3 == 0) || (n < 8); end
    mcatadv_ovl u_o (.clk(clk_vid), .ce_pix(ce_pix), .enable(1'b1), .hblank(hblank), .vblank(vblank), .rgb_in(rgb_v), .status(st), .rgb_out(rgb));
    int dbgc = 0;
    always_ff @(posedge clk_vid) if (ce_pix && !hblank && !vblank && u_o.x == 9'd5 && dbgc < 300) begin dbgc <= dbgc + 1; if (u_o.y > 195 && u_o.y < 225) $display("y=%0d x=%0d row=%0d col=%0d in_rows=%0d on=%0d", u_o.y, u_o.x, u_o.row, u_o.col, u_o.in_rows, u_o.on); end
endmodule
