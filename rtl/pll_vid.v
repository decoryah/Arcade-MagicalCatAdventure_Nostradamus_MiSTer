// PLL for the raster: 50 MHz reference in, the board's 28 MHz oscillator out (pixel clock = 28 MHz / 4).
// 50 MHz x 14 = 700 MHz VCO, / 25 = 28 MHz: integer, so no jitter.
`timescale 1 ps / 1 ps
module pll_vid (
		input  wire  refclk,
		input  wire  rst,
		output wire  outclk_0,   // 28 MHz
		output wire  locked
	);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("28.000000 MHz"),
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
