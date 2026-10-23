// The raster of this core (rtl/mcatadv_video.sv, on the 56 MHz raster clock as the machine runs it: one pixel every 8
// clocks) into the framework's arcade_video as MCatAdv.sv wires it, with Scandoubler Fx / forced_scandoubler selectable
// and nothing else: what does the scandoubled (31 kHz) output do?
//
// bad_blank reproduces the fault that froze the picture of the Gaiapolis core with the scandoubler on (no vertical sync
// at all): HBlank held high through the whole vertical blank instead of toggling on every line. This core does not do
// that (hblank is the horizontal window alone); the switch is only there to show that the bench would notice.
`default_nettype none
module tb_sd_top (
    input  wire        clk,
    input  wire  [2:0] fx,
    input  wire        fsd,
    input  wire        bad_blank,
    output wire        CE_PIXEL,
    output wire  [7:0] VGA_R, VGA_G, VGA_B,
    output wire        VGA_HS, VGA_VS, VGA_DE
);
    wire        ce_pix, hblank, vblank, hsync, vsync;
    wire [23:0] vrgb;
    wire [11:0] pal_raddr;
    mcatadv_video v (
        .clk_vid(clk), .clk_sys(clk),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .vblank_nl(), .rgb(vrgb),
        .ls_pulse(), .frame_pulse(), .vbl_pulse(),
        .t0_we(1'b0), .t0_waddr(10'd0), .t0_wdata(15'd0),
        .t1_we(1'b0), .t1_waddr(10'd0), .t1_wdata(15'd0),
        .sp_we(1'b0), .sp_waddr(10'd0), .sp_wdata(13'd0),
        .t0_en(2'b00), .t1_en(2'b00), .flip_x(1'b0),
        .pal_raddr(pal_raddr), .pal_rdata(16'd0)
    );

    // a picture that shows where it is: red = pixel index, green = line, blue fixed
    reg [8:0] x = 9'd0, y = 9'd0;
    reg       hb_d = 1'b0;
    always @(posedge clk) if (ce_pix) begin
        hb_d <= hblank;
        x <= hblank ? 9'd0 : x + 9'd1;
        if (vblank) y <= 9'h1ff;
        else if (hb_d && !hblank) y <= y + 9'd1;
    end
    wire [23:0] rgb = (hblank | vblank) ? 24'd0 : {x[7:0], y[7:0], 8'h80};

    wire [21:0] gamma_bus;
    assign gamma_bus[20:0] = {clk, 20'd0};
    wire [1:0] sl;
    arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) av (
        .clk_video(clk), .ce_pix(ce_pix), .RGB_in(rgb),
        .HBlank(bad_blank ? (hblank | vblank) : hblank), .VBlank(vblank), .HSync(hsync), .VSync(vsync),
        .CLK_VIDEO(), .CE_PIXEL(CE_PIXEL), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE), .VGA_SL(sl),
        .fx(fx), .forced_scandoubler(fsd), .gamma_bus(gamma_bus)
    );
endmodule
