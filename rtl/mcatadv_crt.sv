// CRT Adjust: the size, the horizontal position and the vertical position of the picture on a 15 kHz analog output, with
// rmonic79's MiSTer-CRT-Adjust module (modules/crt-adjust, core-side variant). The picture goes through a line buffer and is
// read out at a different pixel rate (H-Size) or from a different place in the line (H-Position), and the vertical sync is
// delayed by whole lines (V-Shift); the sync pulses themselves keep their rate and place, so the monitor stays locked.
// Off (or with the scandoubler in use: 31 kHz), the picture takes the path it always had.
//
// Runs on the raster clock (56 MHz, a pixel every 8 clocks). The module wants a read-rate enable that makes
// (base + H-Size) quarters of a clock to a pixel: base = 8 clocks x 4 = 32 quarters, so a step of H-Size is 1/32 of the
// picture's width (3 %), and a source pixel lasts 8 or 9 clocks (a fractional accumulator), whatever the size.
//
// The geometry the ranges come from (rtl/mcatadv_video.sv): the line is 448 pixels, the hsync pulse starts at pixel 360
// and the module restarts its read at the hsync's rising edge, so the picture (320 pixels, pixels 0 to 319 of the line)
// starts 88 pixels after that edge and ends 40 before the next one. At H-Position 0 it can therefore grow by +3 steps only
// before its right end runs past the next hsync and is cut; larger sizes need a negative H-Position (the picture's left
// edge may go as far as the end of the hsync pulse, -56, the menu stops at -48; the right as far as +40). With -48 the
// picture fits up to H-Size +7, and +8 loses its last pixel or two at the right. Vertically the blank is 36 lines with the
// sync 11.8 lines after the picture, so the sync may move 11 lines towards it (V-Shift +10; further it would run into the
// picture) and 21 away.
//
// OSD values, as the menu counts them:
//   H-Size     0 .. +8, then -16 .. -1              (index 0..8 -> 0..+8, 9..24 -> -16..-1)
//   H-Position 0 .. +40, then -48 .. -1             (index 0..40, 41..88)
//   V-Shift    0 .. +10, then -16 .. -1             (index 0..10, 11..26)
`default_nettype none
module mcatadv_crt (
    input  logic        clk,
    input  logic        ce_pix,                     // the raster's pixel enable
    input  logic        enable,                     // On, and not scandoubled
    input  logic  [4:0] osd_hsize,
    input  logic  [6:0] osd_hpos,
    input  logic  [4:0] osd_vshift,

    // the finished picture, aligned with ce_pix
    input  logic [23:0] rgb_i,
    input  logic        hblank_i,                   // the horizontal blank alone (toggles on every line)
    input  logic        vblank_i,
    input  logic        vblank_nl_i,                // the next line is in the vertical blank
    input  logic        hsync_i, vsync_i,

    // to arcade_video
    output logic        ce_o,
    output logic [23:0] rgb_o,
    output logic        hblank_o, vblank_o, hsync_o, vsync_o
);
    localparam integer VTOTAL = 260, HTOTAL = 448;
    localparam signed [8:0] HBIAS = -9'sd1;         // cancels the module's own one-pixel delay of the picture

    // the finished picture's signals, one clock later, before they meet the select: the long path from the 68000's
    // registers through the diagnostic overlay ends in this register instead of behind the select
    logic [23:0] q_rgb;
    logic        q_hb, q_vb, q_vbn, q_hs, q_vs, q_ce;
    always_ff @(posedge clk) begin
        q_rgb <= rgb_i; q_hb <= hblank_i; q_vb <= vblank_i; q_vbn <= vblank_nl_i; q_hs <= hsync_i; q_vs <= vsync_i; q_ce <= ce_pix;
    end

    // the OSD values as signed numbers
    wire signed [5:0] hsz  = (osd_hsize <= 5'd8)  ? $signed({1'b0, osd_hsize}) : $signed({1'b0, osd_hsize}) - 6'sd25;
    wire signed [8:0] hpos = (osd_hpos <= 7'd40)  ? $signed({2'b00, osd_hpos}) : $signed({2'b00, osd_hpos}) - 9'sd89;
    wire signed [5:0] vsh  = (osd_vshift <= 5'd10) ? $signed({1'b0, osd_vshift}) : $signed({1'b0, osd_vshift}) - 6'sd27;
    // the picture is read a line after it is written, so the sync is delayed one line to keep its place; a positive V-Shift
    // moves the picture down, which is the sync coming earlier (a negative delay counts from the frame's length, VTOTAL)
    wire signed [6:0] vs_t = 7'sd1 - $signed({vsh[5], vsh});

    logic              on    = 1'b0;
    logic signed [4:0] hsize = 5'sd0;
    logic signed [8:0] hoff  = 9'sd0;
    logic signed [5:0] voff  = 6'sd0;
    always_ff @(posedge clk) if (q_ce) begin
        on    <= enable;
        hsize <= hsz[4:0];
        hoff  <= hpos + HBIAS;
        voff  <= vs_t[5:0];
    end

    // the pixel read enable: one every (32 + H-Size) quarters of a clock, counted from the module's own line reference
    logic        hs_ref;
    logic        hs_ref_d = 1'b0;
    logic  [7:0] acc      = 8'd0;
    wire   [7:0] period = 8'd32 + {{3{hsize[4]}}, hsize};
    wire         tick   = (acc + 8'd4) >= period;
    always_ff @(posedge clk) begin
        hs_ref_d <= hs_ref;
        if      (hs_ref & ~hs_ref_d) acc <= 8'd0;
        else if (tick)               acc <= acc + 8'd4 - period;
        else                         acc <= acc + 8'd4;
    end
    wire rd_en = on ? tick : q_ce;

    logic [7:0] c_r, c_g, c_b;
    logic       c_hs, c_vs, c_hb, c_vb_unused;
    crt_adjust #(.VTOTAL(VTOTAL), .HTOTAL(HTOTAL), .HPOS_MODE(1)) u_crt
    (
        .clk(clk), .pxl_cen(q_ce), .pxl2_cen(rd_en), .active(on),
        .hsize(hsize), .hoffset(hoff), .voffset(voff),
        .r_in(q_rgb[23:16]), .g_in(q_rgb[15:8]), .b_in(q_rgb[7:0]),
        .hs_in(q_hs), .vs_in(q_vs), .hb_in(q_hb | q_vb), .vb_in(q_vbn),
        .r_out(c_r), .g_out(c_g), .b_out(c_b),
        .hs_out(c_hs), .vs_out(c_vs), .hb_out(c_hb), .vb_out(c_vb_unused),
        .hs_ref_out(hs_ref)
    );

    // adjusted: the module's blank already includes the vertical one, and nothing of the picture goes inside the hsync pulse
    assign ce_o     = rd_en;
    assign rgb_o    = on ? {c_r, c_g, c_b} : q_rgb;
    assign hblank_o = on ? (c_hb | c_hs) : q_hb;
    assign vblank_o = on ? 1'b0 : q_vb;
    assign hsync_o  = on ? c_hs : q_hs;
    assign vsync_o  = on ? c_vs : q_vs;
endmodule
`default_nettype wire
