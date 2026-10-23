// Bench stand-ins for the two Altera PLL wrappers (rtl/pll.v, rtl/pll_vid.v). The bench drives the four clocks itself
// (96 MHz, 48 MHz, 56 MHz: tb_emu.cpp, from one base tick) and the stubs hand them to the design by hierarchical
// reference to the bench top's inputs; both are "locked" a few clocks after reset.
`default_nettype none
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,       // clk_sys
    output wire outclk_1,       // clk_sdram: the bench's chip model samples on clk_sys, as sim/tb_system_top.sv's does
    output wire outclk_2,       // clk_snd
    output reg  locked
);
    assign outclk_0 = tb_emu_top.clk_sys_i;
    assign outclk_1 = tb_emu_top.clk_sys_i;
    assign outclk_2 = tb_emu_top.clk_snd_i;
    reg [4:0] n = 5'd0;
    always @(posedge refclk) begin
        if (rst) begin n <= 5'd0; locked <= 1'b0; end
        else if (n != 5'd31) n <= n + 5'd1;
        else locked <= 1'b1;
    end
endmodule

module pll_vid (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,       // clk_vid
    output reg  locked
);
    assign outclk_0 = tb_emu_top.clk_vid_i;
    reg [4:0] n = 5'd0;
    always @(posedge refclk) begin
        if (rst) begin n <= 5'd0; locked <= 1'b0; end
        else if (n != 5'd31) n <= n + 5'd1;
        else locked <= 1'b1;
    end
endmodule
