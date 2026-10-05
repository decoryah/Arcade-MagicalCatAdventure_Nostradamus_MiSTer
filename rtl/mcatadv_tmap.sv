// One 038 tilemap layer, drawn a scan line at a time into a line buffer.
//
// MAME (mcatadv_state::draw_tilemap_part and tilemap038_device):
//   scrollx = (reg0 & 1FF) - 194, scrolly = (reg1 & 1FF) - 1DF
//   row select (reg1 bit 14): scrolly = lineram[((line + scrolly) & 1FF) * 2 + 1] - line
//   row scroll (reg0 bit 14): scrollx += lineram[((line + scrolly) & 1FF) * 2]
//   the 512 x 512 map is 32 x 32 tiles of 16 x 16; a tile is two words of the tile RAM:
//     word 0 [15:14] priority [13:8] colour, word 1 the tile code
//   a tile is four 8x8 4bpp tiles of the tile ROM, code * 4 + (x half) + 2 * (y half);
//   the colour is the tile's plus 64 times reg2[3:0] (palette bank); pen 0 is clear
//   reg2 bit 4 disables the layer.
//
// The loader rearranges the tile ROM so that the 16 pixels a tile contributes to a line are
// 8 consecutive bytes: tile * 128 + (y half) * 64 + (line in the half) * 8, the left 8x8's
// four bytes and then the right's. That is one 4-word burst per tile and line.
//
// Screen flip (reg0 / reg1 bit 15 = 0 flips X / Y), as MAME's draw_tilemap_part and tilemap_t do it: the scroll is lowered by
// 19 / 141 (hex) and the whole 512 x 512 map is mirrored, so that screen pixel (x, y) shows map pixel
//     X flip:  (scroll_x - x + 319) mod 512        Y flip:  (scroll_y + 223 - y) mod 512
// with the row select / row scroll lookups done as without the flip. The sprites are not flipped (the part of MAME's driver that
// would is disabled).
`default_nettype none
module mcatadv_tmap #(
    parameter [24:1] GFX_BASE = 24'h300000    // word address of this layer's tile ROM in SDRAM
) (
    input  logic        clk,
    input  logic        rst,

    input  logic [15:0] ntiles,               // tiles (16x16) in this layer's ROM: tile codes wrap modulo this

    input  logic        start,                // draw `line` into bank `bank`
    input  logic [7:0]  line,
    input  logic        bank,
    output logic        busy,
    output logic        overrun,              // a line start arrived while drawing: that line is lost
    output logic [1:0]  en_bank,              // per bank: the layer was enabled for the line drawn into it

    input  logic [47:0] vregs,                // 3 words: scroll x, scroll y, control
    output logic [11:0] vram_addr,
    input  logic [15:0] vram_data,            // two clocks after the address

    // tile ROM: a 4-word burst per tile row
    output logic        m_req,
    output logic [24:1] m_addr,
    input  logic        m_wr,
    input  logic [1:0]  m_idx,
    input  logic [15:0] m_data,
    input  logic        m_done,

    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [14:0] lb_data
);
    // ---------------------------------------------------------------- per line state
    logic [8:0]  scrollx_base, scrolly_base;
    logic        rowscroll_en, rowselect_en;
    logic [3:0]  pal_bank;
    logic        enabled;
    logic [7:0]  y;
    logic        bnk;
    logic [8:0]  map_y;                       // line of the 512-line map
    logic [8:0]  scroll_x;                    // effective, after row scroll
    logic        flipx, flipy;
    wire  [8:0]  tile_y = flipy ? (map_y - {y, 1'b0} - 9'd98) : map_y;     // the map row drawn on this line (Y flip: scroll_y - 321 + 223 - y)
    wire  [8:0]  fx_sp  = scroll_x + 9'd294;                                // X flip: (scroll_x - 25) + 319
    wire  [3:0]  fine   = flipx ? (4'd15 - fx_sp[3:0]) : scroll_x[3:0];     // the first slice starts this many pixels left of the screen

    typedef enum logic [4:0] {
        F_IDLE, F_LR0, F_LR1, F_LR2, F_LR3, F_LR4, F_LR5, F_GO,
        F_V0, F_V1, F_V2, F_V3, F_M1, F_M2, F_M3, F_REQ, F_WAIT, F_PUT, F_DONE
    } f_t;
    f_t f;
    logic [4:0]  slice;                       // 0..20
    logic [4:0]  tcol;
    logic [15:0] attr, code, code_mod;
    logic [15:0] w_row [4];                   // the 4 words of the fetched tile row

    // mailbox to the writer
    logic        mb_valid, mb_set;
    logic [63:0] mb_px;
    logic [5:0]  mb_color;
    logic [1:0]  mb_pri;
    logic [4:0]  mb_slice;
    logic        wr_busy;

    // ---------------------------------------------------------------- tile code -> ROM tile
    // MAME wraps a tile code modulo the number of tiles in the ROM. A power of two is a mask; otherwise (12288, 20480 tiles)
    // the code, at most 65535, is less than 8 times the size: subtract 4N, 2N, N when they fit.
    wire        n_pow2 = (ntiles & (ntiles - 16'd1)) == 16'd0;
    wire [18:0] n1 = {3'b000, ntiles}, n2 = {2'b00, ntiles, 1'b0}, n4 = {1'b0, ntiles, 2'b00};
    logic [18:0] cm1, cm2;                    // the subtractions, one a clock
    wire [18:0] c0 = {3'b000, code};
    wire [18:0] c1 = (c0 >= n4) ? c0 - n4 : c0;
    wire [18:0] c2 = (cm1 >= n2) ? cm1 - n2 : cm1;
    wire [18:0] c3 = (cm2 >= n1) ? cm2 - n1 : cm2;
    wire [15:0] code_mod_c = n_pow2 ? (code & (ntiles - 16'd1)) : c3[15:0];
    
    // the 4-word row: tile * 64 words + (y half) * 32 + (line in half) * 4
    wire [24:1] tile_word = GFX_BASE + {2'b00, code_mod, 6'b0} + {18'b0, tile_y[3], tile_y[2:0], 2'b00};

    wire [8:0] y_scr = {1'b0, y} + scrolly_base;

    // ---------------------------------------------------------------- fetch
    always_ff @(posedge clk) begin
        mb_set <= 1'b0;
        if (rst) begin
            f <= F_IDLE; busy <= 1'b0; m_req <= 1'b0; overrun <= 1'b0; en_bank <= 2'b00;
        end else if (start) begin
            if (f != F_IDLE) overrun <= 1'b1;
            else begin
                overrun <= 1'b0;
                busy <= 1'b1;
                y <= line; bnk <= bank;
                scrollx_base <= vregs[8:0] - 9'h194;
                scrolly_base <= vregs[24:16] - 9'h1df;
                rowscroll_en <= vregs[14];
                rowselect_en <= vregs[30];
                pal_bank     <= vregs[35:32];
                enabled      <= ~vregs[36];
                flipx        <= ~vregs[15];
                flipy        <= ~vregs[31];
                en_bank[bank] <= ~vregs[36];
                f <= F_LR0;
            end
        end else case (f)
            F_IDLE: ;
            // row select: lineram[((line + scrolly) & 1FF) * 2 + 1]
            F_LR0: begin
                if (!enabled) f <= F_DONE;
                else if (rowselect_en) begin
                    vram_addr <= {2'b10, y_scr, 1'b1};        // 0x800 + index * 2 + 1
                    f <= F_LR1;
                end else begin
                    map_y <= y_scr;
                    f <= F_LR3;
                end
            end
            F_LR1: f <= F_LR2;
            F_LR2: begin map_y <= vram_data[8:0]; f <= F_LR3; end
            // row scroll: lineram[map_y * 2]
            F_LR3: begin
                if (rowscroll_en) begin
                    vram_addr <= {2'b10, map_y, 1'b0};
                    f <= F_LR4;
                end else begin
                    scroll_x <= scrollx_base;
                    slice <= 5'd0;
                    f <= F_GO;
                end
            end
            F_LR4: f <= F_LR5;
            F_LR5: begin
                scroll_x <= scrollx_base + vram_data[8:0];
                slice <= 5'd0;
                f <= F_GO;
            end
            // one slice: the tile RAM words, then the ROM burst
            F_GO: begin
                tcol <= flipx ? (fx_sp[8:4] - slice) : (scroll_x[8:4] + slice);
                f <= F_V0;
            end
            F_V0: begin
                vram_addr <= {1'b0, tile_y[8:4], tcol, 1'b0};  // tile (row, col): word 0 = attribute
                f <= F_V1;
            end
            F_V1: begin
                vram_addr <= {1'b0, tile_y[8:4], tcol, 1'b1};  // word 1 = code
                f <= F_V2;
            end
            F_V2: begin attr <= vram_data; f <= F_V3; end     // word 0, the attribute
            F_V3: begin code <= vram_data; f <= F_M1; end     // word 1, the code
            F_M1: begin cm1 <= c1; f <= F_M2; end
            F_M2: begin cm2 <= c2; f <= F_M3; end
            F_M3: begin code_mod <= code_mod_c; f <= F_REQ; end
            F_REQ: begin
                if (!mb_valid && !wr_busy) begin
                    m_req  <= 1'b1;
                    m_addr <= tile_word;
                    f <= F_WAIT;
                end
            end
            F_WAIT: begin
                if (m_wr) w_row[m_idx] <= m_data;
                if (m_done) begin m_req <= 1'b0; f <= F_PUT; end
            end
            F_PUT: begin
                mb_set   <= 1'b1;
                mb_px    <= {w_row[3], w_row[2], w_row[1], w_row[0]};
                mb_color <= attr[13:8];
                mb_pri   <= attr[15:14];
                mb_slice <= slice;
                if (slice == 5'd20) f <= F_DONE;
                else begin slice <= slice + 5'd1; f <= F_GO; end
            end
            F_DONE: begin
                if (!mb_valid && !mb_set && !wr_busy) begin f <= F_IDLE; busy <= 1'b0; end
            end
            default: f <= F_IDLE;
        endcase
    end

    // ---------------------------------------------------------------- writer: 16 pixels a slice
    logic [3:0]  wp;
    logic [63:0] wr_px;
    logic [5:0]  wr_color;
    logic [1:0]  wr_pri;
    logic [4:0]  wr_slice;
    logic [3:0]  nib;

    // pixel p is the high nibble of byte p>>1 for even p; byte b of the row is wr_px[8b+7:8b]
    wire [3:0] wpi = flipx ? ~wp : wp;                  // X flip: the tile row read right to left
    always_comb begin
        case (wpi[3:1])
            3'd0: nib = wpi[0] ? wr_px[3:0]   : wr_px[7:4];
            3'd1: nib = wpi[0] ? wr_px[11:8]  : wr_px[15:12];
            3'd2: nib = wpi[0] ? wr_px[19:16] : wr_px[23:20];
            3'd3: nib = wpi[0] ? wr_px[27:24] : wr_px[31:28];
            3'd4: nib = wpi[0] ? wr_px[35:32] : wr_px[39:36];
            3'd5: nib = wpi[0] ? wr_px[43:40] : wr_px[47:44];
            3'd6: nib = wpi[0] ? wr_px[51:48] : wr_px[55:52];
            default: nib = wpi[0] ? wr_px[59:56] : wr_px[63:60];
        endcase
    end

    wire signed [10:0] px_x = $signed({2'b00, wr_slice, 4'b0000}) + $signed({7'b0, wp}) - $signed({7'b0, fine});
    wire        px_vis = (px_x >= 0) && (px_x < 11'sd320);
    wire [7:0]  color8 = {2'b00, wr_color} + {pal_bank[1:0], 6'b000000};   // (colour + 64 * bank) mod 256
    wire [11:0] pal12  = {color8, nib};

    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (rst) begin wr_busy <= 1'b0; mb_valid <= 1'b0; end
        else begin
            if (mb_set) mb_valid <= 1'b1;
            if (!wr_busy) begin
                if (mb_valid) begin
                    wr_busy <= 1'b1; wp <= 4'd0;
                    wr_px <= mb_px; wr_color <= mb_color; wr_pri <= mb_pri; wr_slice <= mb_slice;
                    mb_valid <= 1'b0;
                end
            end else begin
                if (px_vis) begin
                    lb_we   <= 1'b1;
                    lb_addr <= {bnk, px_x[8:0]};
                    lb_data <= {nib != 4'd0, wr_pri, pal12};
                end
                wp <= wp + 4'd1;
                if (wp == 4'd15) wr_busy <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
