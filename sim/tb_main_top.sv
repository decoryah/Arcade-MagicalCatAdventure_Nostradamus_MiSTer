// CPU-side bring-up bench: the 68000, its memory map, the ROM cache and a behavioural
// SDRAM burst server holding the real program. Frames are paced like the board's.
`default_nettype none
module tb_main_top (
    input  logic clk,
    input  logic reset,
    output logic        trc_stb,
    output logic [23:1] trc_addr,
    output logic        trc_rw,
    output logic [15:0] trc_data,
    output logic [1:0]  trc_be,
    output logic        cpu_halted,
    output logic        wdog_reset_o,
    output logic        wdog_kick_o,
    output logic        snd_cmd_wr_o,
    output logic [7:0]  snd_cmd_o,
    output logic        vbl_o,
    input  logic [15:0] p1_in, p2_in,
    input  logic [15:0] dsw1_in, dsw2_in,
    input  logic        nost,               // Nostradamus: the stand-in for the sound board answers the boot handshake
    input  logic        dump,
    input  logic [15:0] dump_tag
);
    // the machine's reset: the input, and a stretched watchdog expiry
    logic        wd_pulse;
    logic [7:0]  wd_stretch = 8'd0;
    logic        wd_seen = 1'b0;                     // after the first expiry the real 3 s limit is used
    always_ff @(posedge clk) begin
        if (wd_pulse) begin wd_stretch <= 8'hff; wd_seen <= 1'b1; end
        else if (wd_stretch != 0) wd_stretch <= wd_stretch - 8'd1;
    end
    wire mreset = reset | (wd_stretch != 0);
    wire [31:0] wd_limit = wd_seen ? 32'd96_000_000 : 32'd1_000_000;   // the first boot waits for it: shortened here
    assign wdog_reset_o = wd_pulse;

    // fast mode: two clocks to a 68000 clock, a third of the real clocks to a frame (this bench only needs
    // the game's logic to run, not the exact bus timing)
    logic cen_phi1, cen_phi2, fc = 1'b0;
    always_ff @(posedge clk) begin fc <= ~fc; cen_phi1 <= fc; cen_phi2 <= ~fc; end

    // program ROM, as the loader leaves it in SDRAM: word k = the 68000 word at 2k
    logic [15:0] rom [0:524287];
    initial $readmemh("prog.hex", rom);

    // frame pacing: 6144 clocks a line, 260 lines; the vblank interrupt at line 224
    logic [31:0] fcnt = 0;
    logic vblank_irq;
    always_ff @(posedge clk) begin
        vblank_irq <= 1'b0;
        if (mreset) fcnt <= 0;
        else begin
            fcnt <= (fcnt == 32'd532479) ? 32'd0 : fcnt + 32'd1;
            if (fcnt == 32'd458751) vblank_irq <= 1'b1;
        end
    end
    assign vbl_o = vblank_irq;

    logic        rom_req, rom_ack;
    logic [19:1] rom_addr;
    logic [15:0] rom_data;
    logic        fill_req, fill_wr, fill_done;
    logic [19:4] fill_addr;
    logic [2:0]  fill_idx;
    logic [15:0] fill_data;

    mcatadv_cache u_cache (
        .clk(clk), .inval(1'b0), .busy(),
        .req(rom_req), .addr(rom_addr), .ack(rom_ack), .data(rom_data),
        .fill_req(fill_req), .fill_addr(fill_addr), .fill_wr(fill_wr), .fill_idx(fill_idx),
        .fill_data(fill_data), .fill_done(fill_done));

    // burst server: 24 clocks to the first word, then one a clock
    logic [5:0] bcnt = 0;
    logic       bact = 0;
    always_ff @(posedge clk) begin
        fill_wr <= 1'b0; fill_done <= 1'b0;
        if (!fill_req) begin bact <= 1'b0; bcnt <= 0; end
        else if (!bact) begin bact <= 1'b1; bcnt <= 0; end
        else if (bact && !fill_done) begin
            bcnt <= bcnt + 1'd1;
            if (bcnt >= 6'd24 && bcnt < 6'd32) begin
                fill_wr <= 1'b1; fill_idx <= bcnt[2:0];
                fill_data <= rom[{fill_addr[19:4], bcnt[2:0]}];
            end
            if (bcnt == 6'd32) begin fill_done <= 1'b1; bact <= 1'b0; end
        end
    end

    logic [7:0] snd_cmd;
    logic snd_cmd_wr;
    // The sound board is not here. Nostradamus' program waits for it at boot: the Z80 echoes the 68000's commands on the
    // answer latch (command 01 first) and, after its ROM test (5 s in MAME), reports 80. This stand-in does the same.
    logic [7:0]  ans_r = 8'h00;
    logic [23:0] ans_t = 24'd0;
    always_ff @(posedge clk) begin
        if (snd_cmd_wr) begin ans_r <= snd_cmd; ans_t <= (snd_cmd == 8'h01) ? 24'd1 : 24'd0; end
        else if (ans_t != 24'd0) begin
            ans_t <= ans_t + 24'd1;
            if (ans_t == 24'd6_000_000) begin ans_r <= 8'h80; ans_t <= 24'd0; end
        end
    end
    assign snd_cmd_wr_o = snd_cmd_wr;
    assign snd_cmd_o = snd_cmd;

    logic [11:0] t_ra0 = 0, t_ra1 = 0;
    logic [47:0] vreg0, vreg1;
    logic [15:0] vid_x, vid_y, vid_bank;

    mcatadv_main u_main (
        .clk(clk), .reset(mreset), .hard_reset(reset), .wdog_limit(wd_limit), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_data(rom_data),
        .p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
        .vblank_irq(vblank_irq),
        .snd_cmd(snd_cmd), .snd_cmd_wr(snd_cmd_wr), .snd_ans(nost ? ans_r : 8'h00), .snd_ans_rd(),
        .t0_raddr(t_ra0), .t1_raddr(t_ra1), .t0_rdata(), .t1_rdata(),
        .vreg0(vreg0), .vreg1(vreg1), .vid_x(vid_x), .vid_y(vid_y), .vid_bank(vid_bank),
        .pal_clk(clk), .pal_raddr(12'd0), .pal_rdata(),
        .spr_raddr(14'd0), .spr_rdata(),
        .wdog_reset(wd_pulse), .wdog_kick_o(wdog_kick_o),
        .trc_stb(trc_stb), .trc_addr(trc_addr), .trc_rw(trc_rw), .trc_data(trc_data), .trc_be(trc_be),
        .cpu_halted(cpu_halted));

    // state dumps for the video benches: the RAMs the video chips read, as 16-bit hex words
    task automatic dump_ram(input string name, input int n, input int which);
        integer f, i;
        string fn;
        begin
            $sformat(fn, "dump_%0d_%s.hex", dump_tag, name);
            f = $fopen(fn, "w");
            for (i = 0; i < n; i++) begin
                case (which)
                    0: $fwrite(f, "%02x%02x\n", u_main.u_t0.hi[i],   u_main.u_t0.lo[i]);
                    1: $fwrite(f, "%02x%02x\n", u_main.u_t1.hi[i],   u_main.u_t1.lo[i]);
                    2: $fwrite(f, "%02x%02x\n", u_main.u_pal.hi[i],  u_main.u_pal.lo[i]);
                    3: $fwrite(f, "%02x%02x\n", u_main.u_spr.hi[i],  u_main.u_spr.lo[i]);
                    4: $fwrite(f, "%02x%02x\n", u_main.u_wram.hi[i], u_main.u_wram.lo[i]);
                    default: ;
                endcase
            end
            $fclose(f);
        end
    endtask
    logic dump_d;
    always_ff @(posedge clk) begin
        dump_d <= dump;
        if (dump && !dump_d) begin
            dump_ram("t0", 4096, 0);
            dump_ram("t1", 4096, 1);
            dump_ram("pal", 4096, 2);
            dump_ram("spr", 16384, 3);
            dump_ram("wram", 32768, 4);
            begin : regs
                integer f2;
                string fn2;
                $sformat(fn2, "dump_%0d_regs.hex", dump_tag);
                f2 = $fopen(fn2, "w");
                $fwrite(f2, "%012x\n%012x\n%04x\n%04x\n%04x\n", vreg0, vreg1, vid_x, vid_y, vid_bank);
                $fclose(f2);
            end
        end
    end
endmodule
