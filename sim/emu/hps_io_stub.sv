// Bench stand-in for the framework's hps_io: the ioctl download strobes, the OSD status word and the joysticks are plain
// registers the C++ bench writes. Same name and the ports MCatAdv.sv uses, so `emu` compiles against it unchanged.
`default_nettype none
module hps_io #(parameter CONF_STR = "", parameter int WIDE = 0, parameter int PS2DIV = 0) (
    input  wire         clk_sys,
    inout  wire  [45:0] HPS_BUS,
    inout  wire  [35:0] EXT_BUS,

    output wire   [1:0] buttons,
    output wire [127:0] status,
    input  wire  [15:0] status_menumask,
    output wire         forced_scandoubler,
    input  wire         video_rotated,
    output wire         direct_video,
    inout  wire  [21:0] gamma_bus,

    output wire         ioctl_download,
    output wire  [15:0] ioctl_index,
    output wire         ioctl_wr,
    output wire  [26:0] ioctl_addr,
    output wire   [7:0] ioctl_dout,
    input  wire         ioctl_wait,

    output wire  [31:0] joystick_0,
    output wire  [31:0] joystick_1,
    output wire  [10:0] ps2_key
);
    reg [127:0] r_status   /*verilator public_flat_rw*/ = 128'd0;
    reg         r_download /*verilator public_flat_rw*/ = 1'b0;
    reg  [15:0] r_index    /*verilator public_flat_rw*/ = 16'd0;
    reg         r_wr       /*verilator public_flat_rw*/ = 1'b0;
    reg  [26:0] r_addr     /*verilator public_flat_rw*/ = 27'd0;
    reg   [7:0] r_dout     /*verilator public_flat_rw*/ = 8'd0;
    reg  [31:0] r_joy0     /*verilator public_flat_rw*/ = 32'd0;
    reg  [31:0] r_joy1     /*verilator public_flat_rw*/ = 32'd0;
    reg         r_wait_seen /*verilator public_flat_rw*/ = 1'b0;
    reg  [15:0] r_mask_seen /*verilator public_flat_rw*/ = 16'd0;    // the menu mask the core computes
    always @(posedge clk_sys) begin
        r_wait_seen <= ioctl_wait;
        r_mask_seen <= status_menumask;
    end
    // the gamma bus as the real module drives it with no gamma file loaded: its clock, the enable low (an undriven bus
    // floats, and a set enable bit would select an empty curve)
    assign gamma_bus[20:0] = {clk_sys, 20'd0};
    assign buttons = 2'b00;
    assign status = r_status;
    reg r_fsd /*verilator public_flat_rw*/ = 1'b0;        // the framework's forced scandoubler (MiSTer.ini)
    reg r_direct /*verilator public_flat_rw*/ = 1'b0;     // direct_video
    assign forced_scandoubler = r_fsd;
    assign direct_video = r_direct;
    assign ioctl_download = r_download;
    assign ioctl_index = r_index;
    assign ioctl_wr = r_wr;
    assign ioctl_addr = r_addr;
    assign ioctl_dout = r_dout;
    assign joystick_0 = r_joy0;
    assign joystick_1 = r_joy1;
    assign ps2_key = 11'd0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{HPS_BUS, EXT_BUS, video_rotated, gamma_bus};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
