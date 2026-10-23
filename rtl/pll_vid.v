// PLL for the raster: 50 MHz reference in, twice the board's 28 MHz oscillator out (pixel clock = 56 MHz / 8 = 7 MHz,
// the same as the board's 28 MHz / 4). Eight clocks to a pixel instead of four is what lets CRT Adjust size the picture in
// steps of 1/32 pixel period (rtl/mcatadv_crt.sv). 56 MHz = 50 MHz x 28 / 25 is an integer ratio of counters (the fitter
// picks the VCO), so there is no fractional-N jitter.
`timescale 1 ps / 1 ps
module pll_vid (
		input  wire  refclk,
		input  wire  rst,
		output wire  outclk_0,   // 56 MHz
		output wire  locked
	);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("56.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst	(rst),
		.outclk	(outclk_0),
		.locked	(locked),
		.fboutclk	( ),
		.fbclk	(1'b0),
		.refclk	(refclk)
	);
endmodule
