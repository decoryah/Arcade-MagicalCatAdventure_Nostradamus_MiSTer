// Magical Cat Adventure / Catt (Face "LINDA" board, Wintechno 1993): the 68000 side.
//
// The 68000 (fx68k, 16 MHz), its memory map (MAME src/mame/misc/mcatadv.cpp,
// mcatadv_state::main_map), the RAMs the video chips read, the inputs, the sound
// latches and the watchdog.
//
//   000000-0FFFFF  program ROM (SDRAM, through a cache)
//   100000-10FFFF  work RAM
//   200000-200005  tilemap 0 registers      300000-300005  tilemap 1 registers
//   400000-401FFF  tilemap 0 RAM            500000-501FFF  tilemap 1 RAM
//                    0000-0FFF tiles (1024 x 2 words), 1000-17FF line RAM, rest scratch
//   600000-601FFF  palette RAM (xGRB555)    602000-602FFF  RAM
//   700000-707FFF  sprite RAM               708000-70FFFF  RAM
//   800000 P1  800002 P2  A00000 DSW1  A00002 DSW2
//   B00000-B0000F  video registers (RAM)    B00018 watchdog (w)  B0001E watchdog (r)
//   C00000         sound latch (w, low byte) / latch 2 (r, low byte)
//
// Every access completes with DTACK from here: block-RAM accesses with no wait states,
// ROM accesses when the cache has the word. Unmapped addresses read as 0.
`default_nettype none

module mcatadv_main (
    input  logic        clk,
    input  logic        reset,
    input  logic        hard_reset,                   // the reset without the watchdog's own
    input  logic [31:0] wdog_limit,                   // clocks without a kick before the reset: 3 s (MAME's time) = 288000000 at 96 MHz
    input  logic        cen_phi1, cen_phi2,           // 16 MHz CPU clock as alternating enables

    // program ROM word read (through the cache): level request until ack
    output logic        rom_req,
    output logic [19:1] rom_addr,
    input  logic        rom_ack,                      // one cycle, rom_data valid
    input  logic [15:0] rom_data,

    // inputs, active low, in the board's bit order
    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,

    input  logic        vblank_irq,                   // pulse: raise the level 1 interrupt

    // sound: the 68000 writes the command latch, reads the answer latch
    output logic [7:0]  snd_cmd,
    output logic        snd_cmd_wr,                   // one-cycle pulse
    input  logic [7:0]  snd_ans,
    output logic        snd_ans_rd,                   // one-cycle pulse

    // video: tilemap RAM read ports (machine clock)
    input  logic [11:0] t0_raddr, t1_raddr,
    output logic [15:0] t0_rdata, t1_rdata,
    // video: tilemap registers (3 words each, flattened) and sprite registers
    output logic [47:0] vreg0, vreg1,
    output logic [15:0] vid_x, vid_y, vid_bank,       // B00000, B00002, B00004 (live)
    // video: palette RAM read port, on the video clock
    input  logic        pal_clk,
    input  logic [11:0] pal_raddr,
    output logic [15:0] pal_rdata,
    // video: live sprite RAM read port (the copy engine's)
    input  logic [13:0] spr_raddr,
    output logic [15:0] spr_rdata,

    output logic        wdog_reset,                   // one cycle: the watchdog expired
    output logic        wdog_kick_o,                  // one cycle: the game kicked it

    // bus trace for the simulation
    output logic        trc_stb,
    output logic [23:1] trc_addr,
    output logic        trc_rw,
    output logic [15:0] trc_data,
    output logic [1:0]  trc_be,
    output logic        cpu_halted
);

    // ------------------------------------------------------------------ CPU
    logic [23:1] eab;
    logic [15:0] oEdb, iEdb;
    logic        eRWn, ASn, LDSn, UDSn, VMAn, E;
    logic        FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
    logic        DTACKn;

    wire iack = FC2 & FC1 & FC0 & ~ASn;

    // level 1 interrupt, held until acknowledged (MAME: irq1_line_hold)
    logic irq1;
    logic iack_d;
    always_ff @(posedge clk) begin
        iack_d <= iack;
        if (reset)                   irq1 <= 1'b0;
        else if (iack_d & ~iack)     irq1 <= 1'b0;
        else if (vblank_irq)         irq1 <= 1'b1;
    end

    logic pwr_d;
    always_ff @(posedge clk) pwr_d <= reset;

    fx68k u_cpu (
        .clk(clk), .HALTn(1'b1),
        .extReset(reset | pwr_d), .pwrUp(reset),
        .enPhi1(cen_phi1), .enPhi2(cen_phi2),
        .eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn),
        .E(E), .VMAn(VMAn),
        .FC0(FC0), .FC1(FC1), .FC2(FC2),
        .BGn(BGn),
        .oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
        .DTACKn(DTACKn), .VPAn(~iack),
        .BERRn(1'b1),
        .BRn(1'b1), .BGACKn(1'b1),
        .IPL0n(~irq1), .IPL1n(1'b1), .IPL2n(1'b1),
        .iEdb(iEdb), .oEdb(oEdb),
        .eab(eab)
    );
    assign cpu_halted = ~oHALTEDn;

    // ------------------------------------------------------------------ decode
    wire [23:0] ba = {eab, 1'b0};
    wire sel_rom   = ba[23:20] == 4'h0;
    wire sel_wram  = ba[23:16] == 8'h10;
    wire sel_v0    = ba[23:4] == 20'h20000 && ba[3:1] <= 3'd2;
    wire sel_v1    = ba[23:4] == 20'h30000 && ba[3:1] <= 3'd2;
    wire sel_t0    = ba[23:13] == 11'h200;
    wire sel_t1    = ba[23:13] == 11'h280;
    wire sel_pal   = ba[23:13] == 11'h300;
    wire sel_ram2  = ba[23:12] == 12'h602;
    wire sel_spr   = ba[23:15] == 9'h0e0;
    wire sel_spr2  = ba[23:15] == 9'h0e1;
    wire sel_p1    = eab == 23'h400000;
    wire sel_p2    = eab == 23'h400001;
    wire sel_dsw1  = eab == 23'h500000;
    wire sel_dsw2  = eab == 23'h500001;
    wire sel_vid   = ba[23:4] == 20'hb0000;
    wire sel_wdw   = eab == 23'h58000c;      // B00018
    wire sel_wdr   = eab == 23'h58000f;      // B0001E
    wire sel_snd   = eab == 23'h600000;

    // ------------------------------------------------------------------ RAMs
    logic        we;                         // one-cycle write strobe
    wire  [1:0]  be = {~UDSn, ~LDSn};

    logic [15:0] q_wram, q_t0, q_t1, q_pal, q_ram2, q_spr, q_spr2;
    logic [15:0] unused_b;

    mcatadv_ram16 #(.AW(15)) u_wram (
        .clka(clk), .addra(eab[15:1]), .da(oEdb), .wea(we && sel_wram ? be : 2'b00), .qa(q_wram),
        .clkb(clk), .addrb(15'd0), .qb());
    mcatadv_ram16 #(.AW(12)) u_t0 (
        .clka(clk), .addra(eab[12:1]), .da(oEdb), .wea(we && sel_t0 ? be : 2'b00), .qa(q_t0),
        .clkb(clk), .addrb(t0_raddr), .qb(t0_rdata));
    mcatadv_ram16 #(.AW(12)) u_t1 (
        .clka(clk), .addra(eab[12:1]), .da(oEdb), .wea(we && sel_t1 ? be : 2'b00), .qa(q_t1),
        .clkb(clk), .addrb(t1_raddr), .qb(t1_rdata));
    mcatadv_ram16 #(.AW(12)) u_pal (
        .clka(clk), .addra(eab[12:1]), .da(oEdb), .wea(we && sel_pal ? be : 2'b00), .qa(q_pal),
        .clkb(pal_clk), .addrb(pal_raddr), .qb(pal_rdata));
    mcatadv_ram16 #(.AW(11)) u_ram2 (
        .clka(clk), .addra(eab[11:1]), .da(oEdb), .wea(we && sel_ram2 ? be : 2'b00), .qa(q_ram2),
        .clkb(clk), .addrb(11'd0), .qb());
    mcatadv_ram16 #(.AW(14)) u_spr (
        .clka(clk), .addra(eab[14:1]), .da(oEdb), .wea(we && sel_spr ? be : 2'b00), .qa(q_spr),
        .clkb(clk), .addrb(spr_raddr), .qb(spr_rdata));
    mcatadv_ram16 #(.AW(14)) u_spr2 (
        .clka(clk), .addra(eab[14:1]), .da(oEdb), .wea(we && sel_spr2 ? be : 2'b00), .qa(q_spr2),
        .clkb(clk), .addrb(14'd0), .qb());

    // registers
    logic [15:0] v0 [3], v1 [3], vid [8];
    always_ff @(posedge clk) begin
        if (we && sel_v0) begin
            if (be[1]) v0[ba[2:1]][15:8] <= oEdb[15:8];
            if (be[0]) v0[ba[2:1]][7:0]  <= oEdb[7:0];
        end
        if (we && sel_v1) begin
            if (be[1]) v1[ba[2:1]][15:8] <= oEdb[15:8];
            if (be[0]) v1[ba[2:1]][7:0]  <= oEdb[7:0];
        end
        if (we && sel_vid) begin
            if (be[1]) vid[ba[3:1]][15:8] <= oEdb[15:8];
            if (be[0]) vid[ba[3:1]][7:0]  <= oEdb[7:0];
        end
    end
    assign vreg0    = {v0[2], v0[1], v0[0]};
    assign vreg1    = {v1[2], v1[1], v1[0]};
    assign vid_x    = vid[0];
    assign vid_y    = vid[1];
    assign vid_bank = vid[2];

    // ------------------------------------------------------------------ watchdog (MAME: 3 s)
    // A cold start, with no signature in the RAM, ends in a wait for this reset (the game writes
    // "MASICAL CAT ADVENTURE" into its RAM and spins until the watchdog resets it). A boot that goes on kicks the
    // watchdog for the first time about 95 ms after the reset, so until the first kick the limit is an eighth of
    // the full one (0.375 s for MAME's 3 s): the cold start's wait is shorter and no boot that goes on is hit. The short
    // limit is for the start after a hard reset only: once the watchdog has expired or been kicked (Nostradamus' first
    // kick comes later than 0.375 s) the limit is MAME's.

    logic [31:0] wd_cnt;
    logic        wd_kick, wd_seen;
    wire  [31:0] wd_lim = wd_seen ? wdog_limit : {3'b000, wdog_limit[31:3]};
    always_ff @(posedge clk) begin
        wdog_reset <= 1'b0;
        if (hard_reset) wd_seen <= 1'b0;
        else if (wd_kick || wdog_reset) wd_seen <= 1'b1;
        if (reset || wd_kick) wd_cnt <= 32'd0;
        else if (wd_cnt == wd_lim) begin wd_cnt <= 32'd0; wdog_reset <= 1'b1; end
        else wd_cnt <= wd_cnt + 32'd1;
    end

    // ------------------------------------------------------------------ bus cycle
    logic        rdy;                         // DTACK
    logic [2:0]  cnt;
    logic        wr_seen;
    assign DTACKn = ~rdy;
    assign wdog_kick_o = wd_kick;

    logic [15:0] rd_mux;
    always_comb begin
        rd_mux = 16'h0000;
        if      (sel_wram)  rd_mux = q_wram;
        else if (sel_t0)    rd_mux = q_t0;
        else if (sel_t1)    rd_mux = q_t1;
        else if (sel_pal)   rd_mux = q_pal;
        else if (sel_ram2)  rd_mux = q_ram2;
        else if (sel_spr)   rd_mux = q_spr;
        else if (sel_spr2)  rd_mux = q_spr2;
        else if (sel_v0)    rd_mux = v0[ba[2:1]];
        else if (sel_v1)    rd_mux = v1[ba[2:1]];
        else if (sel_vid)   rd_mux = vid[ba[3:1]];
        else if (sel_p1)    rd_mux = p1_in;
        else if (sel_p2)    rd_mux = p2_in;
        else if (sel_dsw1)  rd_mux = dsw1_in;
        else if (sel_dsw2)  rd_mux = dsw2_in;
        else if (sel_wdr)   rd_mux = 16'h0c00;            // MAME: mcatadv_wd_r
        else if (sel_snd)   rd_mux = {8'h00, snd_ans};
    end

    assign rom_addr = eab[19:1];

    always_ff @(posedge clk) begin
        we         <= 1'b0;
        snd_cmd_wr <= 1'b0;
        snd_ans_rd <= 1'b0;
        wd_kick    <= 1'b0;
        trc_stb    <= 1'b0;
        if (reset || ASn) begin
            rdy     <= 1'b0;
            cnt     <= 3'd0;
            wr_seen <= 1'b0;
            rom_req <= 1'b0;
        end else if (!iack && !rdy) begin
            if (!eRWn) begin
                // write: the data strobes (and the data) arrive a clock after AS
                if (!wr_seen) begin
                    if (be != 2'b00) begin
                        wr_seen <= 1'b1;
                        we      <= 1'b1;
                        if (sel_snd && be[0]) begin snd_cmd <= oEdb[7:0]; snd_cmd_wr <= 1'b1; end
                        if (sel_wdw)          wd_kick <= 1'b1;
                        trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b0; trc_data <= oEdb; trc_be <= be;
                    end
                end else begin
                    rdy <= 1'b1;
                end
            end else if (sel_rom) begin
                // read from the ROM cache
                rom_req <= 1'b1;
                if (rom_ack) begin
                    iEdb    <= rom_data;
                    rom_req <= 1'b0;
                    rdy     <= 1'b1;
                    trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b1; trc_data <= rom_data; trc_be <= be;
                end
            end else begin
                cnt <= cnt + 3'd1;
                if (cnt == 3'd3) begin
                    iEdb <= rd_mux;
                    rdy  <= 1'b1;
                    if (sel_snd && be[0]) snd_ans_rd <= 1'b1;
                    if (sel_wdr)          wd_kick <= 1'b1;
                    trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b1; trc_data <= rd_mux; trc_be <= be;
                end
            end
        end
    end
endmodule
`default_nettype wire
