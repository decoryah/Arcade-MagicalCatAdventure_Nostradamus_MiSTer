// Diagnostic overlay: three rows of 32 squares along the bottom of the picture (green = 1, dark red = 0),
// the machine's vital signs, so that a first run on real hardware says what is and is not working even
// if the picture is wrong. The squares replace the picture; the status comes from the machine clock and is
// re-timed here (a multi-bit value may tear, which is fine for a display like this).
//
//   row 0  [7:0]   frames (count of vertical blanks)
//          [8] PLLs locked  [9] SDRAM up  [10] ROM loading  [11] machine in reset  [12] renderers in reset
//          [13] 68000 bus active this frame  [14] vblank interrupt this frame  [15] Z80 active this frame
//          [23:16] watchdog resets  [24] YM2610 output seen non-zero  [25] YM2610 samples seen
//   row 1  [22:0] the 68000's last bus address (word address bits 23:1)  [23] CPU halted (double fault)
//          [56] ADPCM-A key on seen  [57] FM key on  [58] SSG level > 0  [59] sample ROM read  [60] non-zero sample byte
//          [61] sound command latched  [62] command read by the Z80  [63] Z80 held for its program ROM (all since the reset)
//   row 2  [0] tilemap 0 line overrun  [1] tilemap 1  [2] sprites  (any this frame, last frame)
//          [10:3] sprite line overruns (count, to 255)  [18:11] tile line overruns (count)
//          [26:19] ADPCM-A key-ons (count, to 255)  [27] Nostradamus board  [28] ADPCM-A output non-zero  [29] YM2610 IRQ seen
`default_nettype none
module mcatadv_ovl (
    input  logic        clk,            // video clock
    input  logic        ce_pix,
    input  logic        enable,
    input  logic        hblank, vblank,
    input  logic [23:0] rgb_in,
    input  logic [95:0] status,         // machine clock domain
    output logic [23:0] rgb_out
);
    logic [95:0] s1, s2;
    always_ff @(posedge clk) begin s1 <= status; s2 <= s1; end

    logic [8:0] x = 9'd0, y = 9'd0;
    logic       vis_row = 1'b0, hb_d = 1'b1, vb_d = 1'b1;
    always_ff @(posedge clk) if (ce_pix) begin
        hb_d <= hblank; vb_d <= vblank;
        if (vblank) begin x <= 9'd0; y <= 9'd0; vis_row <= 1'b0; end
        else if (hblank) begin
            if (!hb_d && vis_row) begin y <= y + 9'd1; vis_row <= 1'b0; end
            x <= 9'd0;
        end else begin
            x <= x + 9'd1; vis_row <= 1'b1;
        end
    end

    // the picture is 224 lines: the rows are lines 200-205, 208-213 and 216-221
    wire [8:0] ry = y - 9'd200;
    wire       in_rows = (y >= 9'd200) && (y < 9'd222) && (ry[2:0] < 3'd6);
    wire [1:0] row = ry[4:3];
    wire [8:0] px = x;
    wire [4:0] col = px / 10;
    wire [3:0] sub = px - col * 10;
    wire       on = (sub < 4'd9) && (row < 2'd3) && in_rows;
    wire       bit_v = s2[{row, col}];
    assign rgb_out = (enable && on && !hblank && !vblank) ? (bit_v ? 24'h00ff00 : 24'h600000) : rgb_in;
endmodule
`default_nettype wire
