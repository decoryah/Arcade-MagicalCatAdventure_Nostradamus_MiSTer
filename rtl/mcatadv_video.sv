// Raster, line buffers, priority mix and palette lookup (the display side).
//
// The board's pixel clock is its 28 MHz oscillator / 4 = 7 MHz; the line is 448 pixels
// (15.625 kHz) and the frame 260 lines (60.1 Hz), 320 x 224 of it visible. MAME gives
// 60 Hz and a 320 x 224 visible area; the totals are the usual 15 kHz arcade ones.
// The raster runs on its own 28 MHz clock (clk_vid); the renderers on the machine clock
// (clk_sys) fill one bank of the line buffers a line ahead of the display, which reads
// the other.
//
// Line buffer entries:
//   tile layers  {opaque, pri[1:0], palette[11:0]}                15 bits
//   sprites      {valid, pri[1:0], palette[9:0]}                  13 bits
// The mix is MAME's screen_update: tile layer 1 over layer 0 unless layer 0's tile
// has the higher priority; a sprite over the tiles when its priority is higher than
// the tile's (or there is no tile); the background is palette entry 0x3F0.
`default_nettype none
module mcatadv_video (
    input  logic        clk_vid,
    input  logic        clk_sys,

    // raster out (clk_vid)
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,

    // raster events in the machine clock domain: one-cycle pulses
    output logic        ls_pulse,         // a display line starts
    output logic        frame_pulse,      // line 0 starts (together with ls_pulse)
    output logic        vbl_pulse,        // vertical blanking starts (line 224)

    // renderer write ports (clk_sys); bit 9 of the address selects the bank
    input  logic        t0_we,  input logic [9:0] t0_waddr,  input logic [14:0] t0_wdata,
    input  logic        t1_we,  input logic [9:0] t1_waddr,  input logic [14:0] t1_wdata,
    input  logic        sp_we,  input logic [9:0] sp_waddr,  input logic [12:0] sp_wdata,
    input  logic [1:0]  t0_en, t1_en,     // per bank: the layer was enabled when the line was drawn

    // palette RAM read port (clk_vid)
    output logic [11:0] pal_raddr,
    input  logic [15:0] pal_rdata
);
    localparam H_ACT = 320, H_TOT = 448, V_ACT = 224, V_TOT = 260;
    localparam H_SYNC0 = 360, H_SYNC1 = 392;          // 32 pixels, 40 after the picture, 56 before the next
    localparam V_SYNC0 = 236, V_SYNC1 = 239;          // 3 lines, 12 after the picture, 21 before the next

    // ------------------------------------------------------------ raster
    logic [1:0] ph = 2'd0;
    logic [8:0] hc = 9'd0, vc = 9'd0;
    always_ff @(posedge clk_vid) begin
        ph <= ph + 2'd1;
        ce_pix <= (ph == 2'd3);
        if (ph == 2'd3) begin
            if (hc == H_TOT - 1) begin
                hc <= 9'd0;
                vc <= (vc == V_TOT - 1) ? 9'd0 : vc + 9'd1;
            end else hc <= hc + 9'd1;
        end
    end

    // sync and blanking, registered with the pixel
    logic [8:0] hn, vn;                                // the counters at the next pixel
    always_comb begin
        hn = (hc == H_TOT - 1) ? 9'd0 : hc + 9'd1;
        vn = (hc == H_TOT - 1) ? ((vc == V_TOT - 1) ? 9'd0 : vc + 9'd1) : vc;
    end
    always_ff @(posedge clk_vid) if (ph == 2'd3) begin
        hblank <= (hn >= H_ACT);
        vblank <= (vn >= V_ACT);
        hsync  <= (hn >= H_SYNC0) && (hn < H_SYNC1);
        vsync  <= (vn >= V_SYNC0) && (vn < V_SYNC1);
    end

    // events as toggles, to the machine clock
    logic tg_ls = 1'b0, tg_frame = 1'b0, tg_vbl = 1'b0;
    always_ff @(posedge clk_vid) if (ph == 2'd3 && hn == 9'd0) begin
        tg_ls <= ~tg_ls;
        if (vn == 9'd0)     tg_frame <= ~tg_frame;
        if (vn == V_ACT)    tg_vbl   <= ~tg_vbl;
    end
    logic [2:0] s_ls, s_frame, s_vbl;
    always_ff @(posedge clk_sys) begin
        s_ls    <= {s_ls[1:0],    tg_ls};
        s_frame <= {s_frame[1:0], tg_frame};
        s_vbl   <= {s_vbl[1:0],   tg_vbl};
        ls_pulse    <= s_ls[2]    ^ s_ls[1];
        frame_pulse <= s_frame[2] ^ s_frame[1];
        vbl_pulse   <= s_vbl[2]   ^ s_vbl[1];
    end

    // ------------------------------------------------------------ line buffers
    logic [9:0]  rd_addr;                              // {bank, x}
    logic [14:0] q_t0, q_t1;
    logic [12:0] q_sp;
    mcatadv_sdp2 #(.AW(10), .DW(15)) u_t0 (.wclk(clk_sys), .we(t0_we), .waddr(t0_waddr), .wdata(t0_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_t0));
    mcatadv_sdp2 #(.AW(10), .DW(15)) u_t1 (.wclk(clk_sys), .we(t1_we), .waddr(t1_waddr), .wdata(t1_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_t1));
    mcatadv_sdp2 #(.AW(10), .DW(13)) u_sp (.wclk(clk_sys), .we(sp_we), .waddr(sp_waddr), .wdata(sp_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_sp));

    // ------------------------------------------------------------ display pipeline
    // Pixel P is registered into rgb at the edge that makes it the current pixel (end of phase 3 of the
    // period before it), so its line buffer address is set two edges earlier: at the end of phase 3 of
    // the period before that. Phase 0: the address is visible; end of 0: the line buffers capture it;
    // phase 1: mix, palette address registered; end of 2: the palette captures it; phase 3: its data.
    wire        wrap = (hn == H_TOT - 1);
    wire [8:0]  hn2  = wrap ? 9'd0 : hn + 9'd1;               // the pixel after the next
    always_ff @(posedge clk_vid) begin
        if (ph == 2'd3) rd_addr <= {wrap ? ~vn[0] : vn[0], hn2};
    end

    // mix, comb on the line-buffer outputs (visible in phase 1)
    wire        o0 = q_t0[14] & t0_en[rd_addr[9]], o1 = q_t1[14] & t1_en[rd_addr[9]];
    wire [1:0]  p0 = q_t0[13:12], p1 = q_t1[13:12];
    wire        use1     = o1 && (!o0 || p1 >= p0);
    wire        tile_any = o0 | o1;
    wire [1:0]  tile_pri = use1 ? p1 : p0;
    wire [11:0] tile_pal = use1 ? q_t1[11:0] : q_t0[11:0];
    wire        sv       = q_sp[12];
    wire [1:0]  sp_pri   = q_sp[11:10];
    wire        spr_wins = sv && (!tile_any || tile_pri < sp_pri);
    wire [11:0] mix_pal  = spr_wins ? {2'b00, q_sp[9:0]} : (tile_any ? tile_pal : 12'h3F0);

    always_ff @(posedge clk_vid) if (ph == 2'd1) pal_raddr <= mix_pal;

    // palette entry: xGRB555
    wire [4:0] cr = pal_rdata[9:5], cg = pal_rdata[14:10], cb = pal_rdata[4:0];
    always_ff @(posedge clk_vid) if (ph == 2'd3) begin
        rgb <= {cr, cr[4:2], cg, cg[4:2], cb, cb[4:2]};
    end
endmodule
`default_nettype wire
