// FX1037 sprites, drawn a scan line at a time.
//
// MAME (mcatadv_state::draw_sprites): the sprite RAM holds 2048 entries of four words per
// half (B00004 picks the half). Entry:
//   w0 [15:14] priority [13:8] palette [7] flip x [6] flip y
//   w1 tile number     w2 [15:12] width/16  [9:0] x (signed)     w3 [15:12] height/16  [9:0] y (signed)
// screen x = x + column - (B00000 - 184), y = y + row - (B00002 - 1F1). The pixels are read from the
// sprite ROM in plain rows, width * height of them from tile * 256 on, 4 bits each, the first
// of a byte in its low nibble; a flipped sprite is the same data read backwards (flip x: the row
// from its right end, flip y: the rows from the bottom). MAME draws the entries from the last to the
// first and a pixel that is non-zero in a sprite hides the ones under it, so the highest entry
// number wins: drawn here from the first to the last, each over the last. An entry whose w3 equals
// its w0 is skipped (MAME: "don't draw sprites while it's testing the RAM").
// Pixel value = palette * 16 + pen. The priority against the tiles is decided in the mixer.
//
// A line takes: clear the line's buffer, then the 1024 pairs of entries one a clock; an entry that crosses
// the line takes a burst from the sprite ROM per 16 words (64 pixels) of its visible part, whose words
// are drawn four pixels at a time, a pixel a clock, while the rest of the burst arrives.
`default_nettype none
module mcatadv_spr #(
    parameter [24:1] SPR_BASE = 24'h080000    // word address of the sprite ROM in SDRAM
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [7:0]  line,
    input  logic        bank,
    input  logic        skip_blank0,          // the sprite ROM's tile 0 is blank: entries of tile 0 draw nothing
    output logic        busy,
    output logic        overrun,

    input  logic [15:0] vid_x, vid_y,         // B00000, B00002
    input  logic        half,
    output logic [10:0] e_addr,               // {half, pair}
    input  logic [15:0] ev_w0, ev_w1, ev_w2, ev_w3,    // entry 2 * pair
    input  logic [15:0] od_w0, od_w1, od_w2, od_w3,    // entry 2 * pair + 1

    output logic        m_req,
    output logic [24:1] m_addr,
    output logic [4:0]  m_len,                // words, 1..16
    input  logic        m_wr,
    input  logic [3:0]  m_idx,
    input  logic [15:0] m_data,
    input  logic        m_done,

    output logic        sb_we,
    output logic [9:0]  sb_addr,
    output logic [12:0] sb_data
);
    localparam [24:1] ROM_END = SPR_BASE + 24'h280000;   // 5 MB of sprite ROM; MAME's region is FF past it

    typedef enum logic [4:0] {
        Q_IDLE, Q_CLR, Q_PRIME, Q_SCAN, Q_SEL, Q_G1, Q_G2, Q_G3, Q_G4, Q_G5, Q_G6, Q_REQ, Q_WAITB, Q_DRAIN, Q_NEXT, Q_DONE
    } q_t;
    q_t q;

    logic               bnk;
    logic signed [18:0] ygy, gx;
    logic [8:0]         clr_x;
    logic [9:0]         ea, ea_q, ec;
    logic               fill;

    assign e_addr = {half, ea};

    // ---------------------------------------------------------------- scan: the hit test
    // An entry of tile 0 draws nothing when the ROM's first block is blank (skip_blank0, from the loader): Nostradamus clears
    // its list with 1000 of them (0, 0, 1000, 1000 -- a 16 x 16 sprite at the corner) and they would use up the first lines.
    function automatic logic is_hit(input [15:0] w0, input [15:0] w1, input [15:0] w2, input [15:0] w3, input signed [18:0] yline);
        logic signed [18:0] ycnt;
        logic [8:0] h, w;
        begin
            ycnt = yline - {{9{w3[9]}}, w3[9:0]};
            h = {w3[15:12], 4'b0000};
            w = {w2[15:12], 4'b0000};
            is_hit = (w3 != w0) && !(skip_blank0 && w1 == 16'd0) && (h != 9'd0) && (w != 9'd0) && (ycnt >= 19'sd0) && (ycnt < $signed({10'b0, h}));
        end
    endfunction
    wire hit_e = is_hit(ev_w0, ev_w1, ev_w2, ev_w3, ygy);
    wire hit_o = is_hit(od_w0, od_w1, od_w2, od_w3, ygy);

    // the pair that hit, and which of its entries are still to draw
    logic [15:0] pe_w0, pe_w1, pe_w2, pe_w3, po_w0, po_w1, po_w2, po_w3;
    logic        p_e, p_o;

    // ---------------------------------------------------------------- the entry being drawn
    logic [15:0]        h_w0, h_w1, h_w2, h_w3;
    logic signed [18:0] x0, xr, ycnt, xs0, xs1;
    logic [8:0]         width, height;
    logic [7:0]         rom_row;
    logic               flipx, flipy;
    logic [3:0]         n16;                  // width / 16
    logic [8:0]         cmin, cmax;
    logic [6:0]         wleft;                // words still to fetch
    logic [11:0]        rowmul;
    logic [22:0]        woff;
    logic [24:1]        chunk_addr;
    logic [4:0]         chunk_len;
    logic [4:0]         f_cnt;
    wire  [4:0]         cl = (wleft > 7'd16) ? 5'd16 : wleft[4:0];   // words of the next burst

    // ---------------------------------------------------------------- word FIFO (16)
    logic [15:0] fifo [16];
    logic [4:0]  f_wr, f_rd;
    wire  [24:1] word_abs  = chunk_addr + {20'b0, m_idx};
    wire  [15:0] push_data = (word_abs >= ROM_END) ? 16'hFFFF : m_data;
    wire         f_empty   = (f_wr == f_rd);
    assign       f_cnt     = f_wr - f_rd;

    // ---------------------------------------------------------------- drawer
    logic        d_busy;
    logic [15:0] d_word;
    logic [8:0]  d_cbase;                     // column of the word's first pixel
    logic [1:0]  d_j;
    logic [6:0]  d_wi;                        // row word index of the next word to take
    logic        d_en;                        // the entry's geometry is final: draw its words
    wire  [8:0]  d_c   = d_cbase + {7'b0, d_j};
    wire         d_inr = (d_c >= cmin) && (d_c <= cmax);
    wire signed [18:0] d_x = flipx ? (xr - $signed({10'b0, d_c})) : (x0 + $signed({10'b0, d_c}));
    logic [3:0]  d_nib;
    always_comb begin
        case (d_j)
            2'd0:    d_nib = d_word[3:0];
            2'd1:    d_nib = d_word[7:4];
            2'd2:    d_nib = d_word[11:8];
            default: d_nib = d_word[15:12];
        endcase
    end

`ifdef SPRDBG
    always_ff @(posedge clk) if (sb_we && sb_addr[9] == 1'b1 && sb_addr[8:0] >= 9'd74 && sb_addr[8:0] <= 9'd78)
        $display("SPRW t=%0t x=%0d data=%04x q=%0d ygy=%0d bnk=%0d", $time, sb_addr[8:0], sb_data, q, ygy, bnk);
`endif
    always_ff @(posedge clk) begin
        sb_we <= 1'b0;

        // ---- the drawer
        if (!d_busy) begin
            if (d_en && !f_empty) begin
                d_word <= fifo[f_rd[3:0]]; f_rd <= f_rd + 5'd1;
                d_cbase <= {d_wi, 2'b00}; d_wi <= d_wi + 7'd1;
                d_j <= 2'd0; d_busy <= 1'b1;
            end
        end else begin
            if (d_inr && d_nib != 4'd0) begin
                sb_we   <= 1'b1;
                sb_addr <= {bnk, d_x[8:0]};
                sb_data <= {1'b1, h_w0[15:14], h_w0[13:8], d_nib};
            end
            d_j <= d_j + 2'd1;
            if (d_j == 2'd3) d_busy <= 1'b0;
        end

        // ---- a word from the burst
        if (m_wr) begin fifo[f_wr[3:0]] <= push_data; f_wr <= f_wr + 5'd1; end

        if (rst) begin
            q <= Q_IDLE; busy <= 1'b0; m_req <= 1'b0; overrun <= 1'b0; f_wr <= 5'd0; f_rd <= 5'd0; d_busy <= 1'b0; d_en <= 1'b0;
            p_e <= 1'b0; p_o <= 1'b0;
        end else if (start) begin
`ifdef SPRDBG
            $display("SPRSTART line %0d bank %0d q=%0d", line, bank, q);
`endif
            if (q != Q_IDLE) overrun <= 1'b1;
            else begin
                overrun <= 1'b0;
                busy <= 1'b1;
                bnk  <= bank;
                ygy  <= $signed({11'b0, line}) + $signed({3'b0, vid_y}) - 19'sd497;      // line + (B00002 - 1F1)
                gx   <= $signed({3'b0, vid_x}) - 19'sd388;                               // B00000 - 184
                clr_x <= 9'd0;
                f_wr <= 5'd0; f_rd <= 5'd0; d_busy <= 1'b0; d_en <= 1'b0;
                p_e <= 1'b0; p_o <= 1'b0;
                q <= Q_CLR;
            end
        end else case (q)
            Q_IDLE: ;
            Q_CLR: begin
                sb_we <= 1'b1; sb_addr <= {bnk, clr_x}; sb_data <= 13'd0;
                clr_x <= clr_x + 9'd1;
                if (clr_x == 9'd319) begin ea <= 10'd0; fill <= 1'b1; q <= Q_SCAN; end
            end
            // restart the pair pipeline at the pair after ec
            Q_PRIME: begin
                d_en <= 1'b0;
                ea <= ec + 10'd1; fill <= 1'b1;
                if (ec == 10'd1023) q <= Q_DONE; else q <= Q_SCAN;
            end
            // one pair a clock: ea is the address being read, ea_q the pair whose words are on the ports
            Q_SCAN: begin
                ea   <= ea + 10'd1;
                ea_q <= ea;
                fill <= 1'b0;
                if (!fill) begin
                    if (hit_e || hit_o) begin
                        pe_w0 <= ev_w0; pe_w1 <= ev_w1; pe_w2 <= ev_w2; pe_w3 <= ev_w3;
                        po_w0 <= od_w0; po_w1 <= od_w1; po_w2 <= od_w2; po_w3 <= od_w3;
                        p_e <= hit_e; p_o <= hit_o;
                        ec <= ea_q;
                        q <= Q_SEL;
                    end else if (ea_q == 10'd1023) q <= Q_DONE;
                end
            end
            // the next entry of the pair that hit: the even one first
            Q_SEL: begin
                if (p_e) begin
                    h_w0 <= pe_w0; h_w1 <= pe_w1; h_w2 <= pe_w2; h_w3 <= pe_w3; p_e <= 1'b0; q <= Q_G1;
                end else if (p_o) begin
                    h_w0 <= po_w0; h_w1 <= po_w1; h_w2 <= po_w2; h_w3 <= po_w3; p_o <= 1'b0; q <= Q_G1;
                end else q <= Q_PRIME;
            end
            // geometry of the entry
            Q_G1: begin
`ifdef SPRDBG
                $display("SPRDBG line_bank %0d ygy %0d entry words %04x %04x %04x %04x", bnk, ygy, h_w0, h_w1, h_w2, h_w3);
`endif
                width  <= {h_w2[15:12], 4'b0000};
                height <= {h_w3[15:12], 4'b0000};
                n16    <= h_w2[15:12];
                flipx  <= h_w0[7]; flipy <= h_w0[6];
                x0     <= {{9{h_w2[9]}}, h_w2[9:0]} - gx;
                ycnt   <= ygy - {{9{h_w3[9]}}, h_w3[9:0]};
                q <= Q_G2;
            end
            Q_G2: begin
                xr      <= x0 + $signed({10'b0, width}) - 19'sd1;
                rom_row <= flipy ? (height[7:0] - 8'd1 - ycnt[7:0]) : ycnt[7:0];     // ycnt < height <= 240
                q <= Q_G3;
            end
            Q_G3: begin
                xs0 <= (x0 < 19'sd0)   ? 19'sd0   : x0;
                xs1 <= (xr > 19'sd319) ? 19'sd319 : xr;
                q <= Q_G4;
            end
            Q_G4: begin
                if (xs0 > xs1) q <= Q_NEXT;                       // not on the screen
                else begin
                    cmin   <= flipx ? (xr[8:0] - xs1[8:0]) : (xs0[8:0] - x0[8:0]);
                    cmax   <= flipx ? (xr[8:0] - xs0[8:0]) : (xs1[8:0] - x0[8:0]);
                    rowmul <= rom_row * n16;
                    q <= Q_G5;
                end
            end
            Q_G5: begin
                wleft <= cmax[8:2] - cmin[8:2] + 7'd1;            // 1..64 words
                woff  <= {h_w1, 6'b0} + {9'b0, rowmul, 2'b00} + {16'b0, cmin[8:2]};
                d_wi  <= cmin[8:2];
                q <= Q_G6;
            end
            Q_G6: begin
                chunk_addr <= SPR_BASE + {2'b00, woff[21:0]};     // the ROM address wraps at 8 MB
                d_en <= 1'b1;
                q <= Q_REQ;
            end
            // one burst of up to 16 words
            Q_REQ: begin
                chunk_len <= cl;
                if (({1'b0, f_cnt} + {1'b0, cl}) <= 6'd16) begin   // room for the burst in the FIFO
                    m_len  <= cl;
                    m_addr <= chunk_addr;
                    m_req  <= 1'b1;
                    q <= Q_WAITB;
                end
            end
            Q_WAITB: begin
                if (m_done) begin
                    m_req <= 1'b0;
                    wleft <= wleft - {2'b00, chunk_len};
                    chunk_addr <= chunk_addr + {19'b0, chunk_len};
                    q <= (wleft == {2'b00, chunk_len}) ? Q_DRAIN : Q_REQ;
                end
            end
            Q_DRAIN: begin
                if (f_empty && !d_busy) q <= Q_NEXT;
            end
            Q_NEXT: begin
                d_en <= 1'b0;
                q <= (p_e || p_o) ? Q_SEL : Q_PRIME;
            end
            Q_DONE: begin
                if (f_empty && !d_busy) begin busy <= 1'b0; q <= Q_IDLE; d_en <= 1'b0; end
            end
            default: q <= Q_IDLE;
        endcase
    end
endmodule
`default_nettype wire
