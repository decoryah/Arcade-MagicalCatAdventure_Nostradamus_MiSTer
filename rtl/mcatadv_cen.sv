// Clock enables for the board's two crystals, derived from the 96 MHz machine clock:
// the 68000 at 16 MHz (as the alternating phase enables fx68k wants), the Z80 at 4 MHz
// and the YM2610 at 8 MHz, all in phase as on the board (16 MHz / 4, / 2).
`default_nettype none
module mcatadv_cen (
    input  logic clk,
    output logic cen_phi1, cen_phi2,
    output logic cen_z80,
    output logic cen_ym
);
    logic [2:0] c6  = 3'd0;
    logic [4:0] c24 = 5'd0;
    always_ff @(posedge clk) begin
        c6  <= (c6  == 3'd5)  ? 3'd0 : c6  + 3'd1;
        c24 <= (c24 == 5'd23) ? 5'd0 : c24 + 5'd1;
        cen_phi1 <= (c6 == 3'd5);
        cen_phi2 <= (c6 == 3'd2);
        cen_z80  <= (c24 == 5'd23);
        cen_ym   <= (c24 == 5'd23) || (c24 == 5'd11);
    end
endmodule
`default_nettype wire
