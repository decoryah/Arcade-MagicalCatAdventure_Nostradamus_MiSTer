// CRT Adjust (rtl/mcatadv_crt.sv with rmonic79's module) on this core's raster (rtl/mcatadv_video.sv, 56 MHz, a pixel every
// 8 clocks) and a picture that shows where it is: red = pixel index, green = line, blue fixed. What does the analog output
// do with the OSD amounts (H-Size, H-Position, V-Shift)? With the module Off the picture is the raster's; On with all amounts
// 0 it must come out the same.
`default_nettype none
module tb_crt_top (
    input  wire        clk,
    input  wire        on_i,
    input  wire  [4:0] hsize_i,
    input  wire  [6:0] hpos_i,
    input  wire  [4:0] vshift_i,
    output wire        ce_o,
    output wire  [7:0] R, G, B,
    output wire        hs_o, vs_o, hb_o, vb_o
);
    wire        ce_pix, hblank, vblank, hsync, vsync, vblank_nl;
    wire [23:0] vrgb;
    wire [11:0] pal_raddr;
    mcatadv_video v (
        .clk_vid(clk), .clk_sys(clk),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .vblank_nl(vblank_nl), .rgb(vrgb),
        .ls_pulse(), .frame_pulse(), .vbl_pulse(),
        .t0_we(1'b0), .t0_waddr(10'd0), .t0_wdata(15'd0),
        .t1_we(1'b0), .t1_waddr(10'd0), .t1_wdata(15'd0),
        .sp_we(1'b0), .sp_waddr(10'd0), .sp_wdata(13'd0),
        .t0_en(2'b00), .t1_en(2'b00), .flip_x(1'b0),
        .pal_raddr(pal_raddr), .pal_rdata(16'd0)
    );

    reg [8:0] x = 9'd0, y = 9'd0;
    reg       hb_d = 1'b0;
    always @(posedge clk) if (ce_pix) begin
        hb_d <= hblank;
        x <= hblank ? 9'd0 : x + 9'd1;
        if (vblank) y <= 9'h1ff;
        else if (hb_d && !hblank) y <= y + 9'd1;
    end
    wire [23:0] rgb = (hblank | vblank) ? 24'd0 : {x[7:0], y[7:0], 8'h80};

    wire [23:0] rgb_o;
    mcatadv_crt u_crt (
        .clk(clk), .ce_pix(ce_pix), .enable(on_i), .osd_hsize(hsize_i), .osd_hpos(hpos_i), .osd_vshift(vshift_i),
        .rgb_i(rgb), .hblank_i(hblank), .vblank_i(vblank), .vblank_nl_i(vblank_nl), .hsync_i(hsync), .vsync_i(vsync),
        .ce_o(ce_o), .rgb_o(rgb_o), .hblank_o(hb_o), .vblank_o(vb_o), .hsync_o(hs_o), .vsync_o(vs_o)
    );
    assign {R, G, B} = rgb_o;
endmodule
