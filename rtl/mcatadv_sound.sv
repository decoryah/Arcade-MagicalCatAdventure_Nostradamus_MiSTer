// The sound board: a Z80 at 4 MHz, a YM2610 (jt10) at 8 MHz, and the two latches to the 68000.
//
// MAME (mcatadv_sound_map / mcatadv_sound_io_map, and the Nostradamus pair nost_sound_map / nost_sound_io_map):
//
//   Magical Cat Adventure / Catt          Nostradamus
//   0000-3FFF  ROM                        0000-7FFF  ROM
//   4000-BFFF  ROM, 16 KB bank steps      8000-BFFF  ROM bank (16 KB)
//   C000-DFFF  RAM                        C000-DFFF  RAM
//   E000-E003  YM2610                     I/O 00-03  YM2610 (write)   04-07  YM2610 (read)
//   F000       bank register (write)      I/O 40     bank register (write)
//   I/O 80     read: the 68000's latch (clears its pending flag and so the NMI), write: the answer latch
//
// The bank is 1 when a ROM is loaded (MAME sets it in machine_start only; a reset leaves it). The command latch raises the Z80's NMI while it holds an unread byte (generic_latch_8's
// data pending output); the YM2610's IRQ output is the Z80's INT.
//
// The program is read from the SDRAM through mcatadv_zcache (WAIT holds the Z80 on a miss). ADPCM-A reads its samples a
// byte at a time through mcatadv_pcmrd.
`default_nettype none
module mcatadv_sound #(
    parameter [12:0] RST_EXTRA = 13'h1fff,    // clocks the sound board stays in reset after the board's (85 us)
    parameter        YM_DIV    = 6            // clk_snd clocks to the YM2610's 8 MHz enable (48 MHz / 6)
) (
    input  logic        clk,
    input  logic        clk_snd,          // the YM2610's clock (48 MHz from the same PLL, in phase with clk)
    input  logic        rst,
    input  logic        cen_z80,          // 4 MHz
    input  logic        nost,             // Nostradamus' memory map

    input  logic [7:0]  cmd,
    input  logic        cmd_wr,           // 68000 writes the command latch
    output logic [7:0]  ans,
    input  logic        ans_rd,           // 68000 reads the answer latch

    input  logic        cache_inval,      // a ROM load starts
    output logic        zr_req,           // Z80 program: line fills (8 words) from the SDRAM
    output logic [17:4] zr_addr,
    input  logic        zr_wr,
    input  logic [2:0]  zr_idx,
    input  logic [15:0] zr_data,
    input  logic        zr_done,

    output logic        pcm_req,
    output logic [19:0] pcm_addr,
    input  logic        pcm_ack,
    input  logic [7:0]  pcm_q,

    output logic signed [15:0] snd_l, snd_r,
    output logic        snd_valid,

    output logic        dbg_z80_rd,       // debug: the Z80 ran
    output logic [9:0]  dbg_snd           // debug events, one clock each: [0] ADPCM-A key on, [1] FM key on, [2] SSG level > 0,
                                          // [3] sample byte read, [4] non-zero sample byte, [5] command latched, [6] command
                                          // read by the Z80, [7] Z80 held for its program ROM, [8] ADPCM-A output, [9] YM IRQ
);
    // ---------------------------------------------------------------- reset
    // The YM2610's pipelines (jt10's shift registers) need a long reset to take their reset values: it is held 85 us
    // (some 700 chip clocks) beyond the board's.
    logic [12:0] rst_cnt = '1;
    logic        rst_q = 1'b1;
    always_ff @(posedge clk) begin
        if (rst) rst_cnt <= RST_EXTRA;
        else if (rst_cnt != 13'd0) rst_cnt <= rst_cnt - 13'd1;
        rst_q <= rst | (rst_cnt != 13'd0);
    end

    // ---------------------------------------------------------------- Z80
    logic        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    logic [15:0] A;
    logic  [7:0] di, dout;
    logic        ym_irq_n;
    logic        nmi_pend;
    logic        wait_n;

    tv80s_cen u_z80 (
        .reset_n(~rst_q), .clk(clk), .cen(cen_z80), .wait_n(wait_n), .int_n(ym_irq_n), .nmi_n(~nmi_pend), .busrq_n(1'b1),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(A), .di(di), .dout(dout)
    );

    wire mem_rd = ~mreq_n & ~rd_n;
    wire mem_wr = ~mreq_n & ~wr_n;
    wire io_rd  = ~iorq_n & ~rd_n & m1_n;
    wire io_wr  = ~iorq_n & ~wr_n & m1_n;
    wire io_80  = A[7:0] == 8'h80;

    wire sel_rom0 = nost ? ~A[15] : (~A[15] & ~A[14]);                 // fixed ROM
    wire sel_bnk  = nost ? (A[15] & ~A[14]) : (A >= 16'h4000 && A < 16'hC000);
    wire sel_ram  = (A >= 16'hC000) && (A < 16'hE000);
    wire sel_ym   = ~nost && (A[15:2] == 14'h3800);                    // E000-E003
    wire sel_breg = ~nost && (A == 16'hF000);
    wire io_bnk   = nost && io_wr && (A[7:0] == 8'h40);
    wire io_ymw   = nost && io_wr && (A[7:2] == 6'b000000);            // 00-03
    wire io_ymr   = nost && io_rd && (A[7:2] == 6'b000001);            // 04-07

    // ---------------------------------------------------------------- program ROM and bank
    // (MAME sets the bank once, in machine_start: a reset leaves it as the program last wrote it)
    logic [3:0]  bank = 4'd1;
    always_ff @(posedge clk) begin
        if (cache_inval) bank <= 4'd1;
        else if (mem_wr && sel_breg) bank <= {1'b0, dout[2:0]};
        else if (io_bnk) bank <= dout[3:0];
    end
    wire [17:0] rom_a = !sel_bnk ? {2'b00, A} :
                        nost     ? {bank, A[13:0]} :
                                   {1'b0, ({bank[2:0], 14'b0} + {2'b00, A - 16'h4000})};
    wire        rom_rd = mem_rd && (sel_rom0 || sel_bnk);
    logic       zhit;
    logic [7:0] rom_q;
    mcatadv_zcache u_zc (
        .clk(clk), .inval(cache_inval), .rd(rom_rd), .addr(rom_a), .hit(zhit), .data(rom_q),
        .fill_req(zr_req), .fill_addr(zr_addr), .fill_wr(zr_wr), .fill_idx(zr_idx), .fill_data(zr_data), .fill_done(zr_done)
    );
    assign wait_n = ~(rom_rd & ~zhit);

    // ---------------------------------------------------------------- RAM
    logic [7:0] ram_q;
    mcatadv_ram8 #(.AW(13)) u_ram (.clk(clk), .we(mem_wr && sel_ram), .addr(A[12:0]), .d(dout), .q(ram_q));

    // ---------------------------------------------------------------- latches
    logic [7:0] cmd_l;
    always_ff @(posedge clk) begin
        if (rst_q) begin nmi_pend <= 1'b0; ans <= 8'h00; end
        else begin
            if (cmd_wr) begin cmd_l <= cmd; nmi_pend <= 1'b1; end
            else if (io_rd & io_80) nmi_pend <= 1'b0;
            if (io_wr & io_80) ans <= dout;
        end
    end

    // ---------------------------------------------------------------- YM2610
    logic [7:0] ym_q;
    logic [19:0] adpcma_addr;
    logic [4:0]  adpcma_bank;
    logic        adpcma_roe_n;
    logic [7:0]  adpcma_data;
    logic signed [15:0] fm_l, fm_r;             // FM and ADPCM
    logic [7:0]  psg_a, psg_b, psg_c;           // SSG
    logic        ym_sample;
    wire         ym_cs_n = ~(((mem_rd | mem_wr) & sel_ym) | io_ymw | io_ymr);

    // The chip runs on clk_snd with its own 8 MHz enable. The Z80's side of it (address, data, strobes: held for whole
    // Z80 cycles) and the sample reads cross between two clocks of one PLL, edge to edge.
    logic [2:0] ydiv = 3'd0;
    logic       cen_ym = 1'b0;
    always_ff @(posedge clk_snd) begin
        ydiv   <= (ydiv == YM_DIV - 1) ? 3'd0 : ydiv + 3'd1;
        cen_ym <= (ydiv == YM_DIV - 1);
    end
    logic signed [15:0] adpcm_l;

    logic rst_snd = 1'b1;                       // the reset, registered on the chip's clock
    always_ff @(posedge clk_snd) rst_snd <= rst_q;

    jt10 u_ym (
        .rst(rst_snd), .clk(clk_snd), .cen(cen_ym),
        .din(dout), .addr(A[1:0]), .cs_n(ym_cs_n), .wr_n(wr_n),
        .dout(ym_q), .irq_n(ym_irq_n),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank), .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(), .adpcmb_roe_n(), .adpcmb_data(8'h00),
        .psg_A(psg_a), .psg_B(psg_b), .psg_C(psg_c), .fm_left(fm_l), .fm_right(fm_r),
        .psg_snd(), .snd_right(), .snd_left(), .snd_sample(ym_sample), .ch_enable(6'h3F), .adpcmA_l_dbg(adpcm_l)
    );

    // ADPCM-A sample bytes
    mcatadv_pcmrd u_pcm (.clk(clk), .rst(rst_q), .addr(adpcma_addr), .data(adpcma_data),
                         .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q));

    // ---------------------------------------------------------------- Z80 data bus
    always_comb begin
        di = 8'h00;                                              // MAME's unmapped read
        if (~iorq_n & ~m1_n & ~rd_n) di = 8'hFF;                 // interrupt acknowledge
        else if (io_rd & io_80)  di = cmd_l;
        else if (io_ymr)         di = ym_q;
        else if (mem_rd) begin
            if (sel_ym)                       di = ym_q;
            else if (sel_ram)                 di = ram_q;
            else if (sel_bnk | sel_rom0)      di = rom_q;
        end
    end

    // ---------------------------------------------------------------- mix: MAME's YM2610 routes into one speaker
    // MAME: the SSG (ymfm: (a + b + c) * 2/3, channel levels 0..16382) with 1.0 for Magical Cat Adventure and 0.6 for
    // Nostradamus, the FM + ADPCM left and right with 0.5 each. A jt49 level (8 bit) is 64.25 of ymfm's steps:
    //   mono = (A + B + C) * 42.8 (nost 25.7) + (L + R) / 2    ->    ((A + B + C) * K + (L + R) * 32) >> 6
    wire signed [24:0] mix = ($signed({15'd0, psg_a} + {15'd0, psg_b} + {15'd0, psg_c}) * (nost ? 25'sd1645 : 25'sd2741) +
                              ($signed(fm_l) + $signed(fm_r)) * 25'sd32) >>> 6;
    wire signed [15:0] mono = (mix > 25'sd32767) ? 16'sd32767 : (mix < -25'sd32768) ? -16'sd32768 : mix[15:0];
    // (made on the chip's clock, where the multiply has 20 ns; handed over registered)
    logic ym_sample_d = 1'b0;
    logic signed [15:0] mono_r;
    always_ff @(posedge clk_snd) begin
        ym_sample_d <= ym_sample;
        if (ym_sample) mono_r <= mono;
    end
    always_ff @(posedge clk) begin
        snd_valid <= ym_sample_d;
        if (ym_sample_d) begin snd_l <= mono_r; snd_r <= mono_r; end
    end
    assign dbg_z80_rd = mem_rd;

    // ---------------------------------------------------------------- debug events (the diagnostic overlay)
    logic       ywr_d, ywr_dd, nmi_d;
    logic [7:0] ysel0, ysel1;
    wire        ywr = ~ym_cs_n & ~wr_n;
    always_ff @(posedge clk) begin
        ywr_d <= ywr; ywr_dd <= ywr_d; nmi_d <= nmi_pend;
        dbg_snd <= 10'd0;
        if (ywr_d & ~ywr_dd) begin                    // the data is stable a clock into the write
            case (A[1:0])
                2'd0: ysel0 <= dout;
                2'd2: ysel1 <= dout;
                2'd1: if (ysel0 == 8'h28 && dout[7:4] != 4'd0) dbg_snd[1] <= 1'b1;
                2'd3: if (ysel1 == 8'h00 && !dout[7] && dout[5:0] != 6'd0) dbg_snd[0] <= 1'b1;
                default: ;
            endcase
        end
        dbg_snd[2] <= (psg_a != 8'd0) | (psg_b != 8'd0) | (psg_c != 8'd0);
        dbg_snd[3] <= pcm_ack;
        dbg_snd[4] <= pcm_ack & (pcm_q != 8'd0);
        dbg_snd[5] <= nmi_pend & ~nmi_d;
        dbg_snd[6] <= io_rd & io_80;
        dbg_snd[7] <= rom_rd & ~zhit;
        dbg_snd[8] <= (adpcm_l > 16'sd8) | (adpcm_l < -16'sd8);
        dbg_snd[9] <= ~ym_irq_n;
    end
endmodule
`default_nettype wire
