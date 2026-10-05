// Block RAM building blocks.
//
// Written the way Quartus 17 infers M10K reliably: a byte-wide array per lane with
// whole-element writes (a 16-bit array with byte enables was mapped to registers by
// the Pocket core's first attempts), registered reads, no read-during-write check.

// 16-bit word RAM, port A read/write (byte enables), port B read only, optionally
// on another clock (port B is the display side for the palette RAM).
module mcatadv_ram16 #(
    parameter AW = 12
) (
    input  logic          clka,
    input  logic [AW-1:0] addra,
    input  logic [15:0]   da,
    input  logic [1:0]    wea,       // [1] high byte, [0] low byte
    output logic [15:0]   qa,
    input  logic          clkb,
    input  logic [AW-1:0] addrb,
    output logic [15:0]   qb
);
    (* ramstyle = "no_rw_check" *) logic [7:0] hi [0:(1<<AW)-1];
    (* ramstyle = "no_rw_check" *) logic [7:0] lo [0:(1<<AW)-1];

    always_ff @(posedge clka) begin
        if (wea[1]) hi[addra] <= da[15:8];
        qa[15:8] <= hi[addra];
    end
    always_ff @(posedge clka) begin
        if (wea[0]) lo[addra] <= da[7:0];
        qa[7:0] <= lo[addra];
    end
    always_ff @(posedge clkb) qb <= {hi[addrb], lo[addrb]};
endmodule

// Simple dual port, one clock: write port + read port (no byte enables).
module mcatadv_sdp #(
    parameter AW = 12,
    parameter DW = 16
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
);
    (* ramstyle = "no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

// Simple dual port with separate write and read clocks (line buffers: the renderer
// writes on the machine clock, the display reads on the video clock).
module mcatadv_sdp2 #(
    parameter AW = 9,
    parameter DW = 16
) (
    input  logic          wclk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic          rclk,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
);
    (* ramstyle = "no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
    always_ff @(posedge wclk) if (we) mem[waddr] <= wdata;
    always_ff @(posedge rclk) rdata <= mem[raddr];
endmodule

// Byte-wide RAM with an initial-content-free single port (Z80 RAM)
module mcatadv_ram8 #(
    parameter AW = 13
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] addr,
    input  logic [7:0]    d,
    output logic [7:0]    q
);
    (* ramstyle = "no_rw_check" *) logic [7:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clk) begin
        if (we) mem[addr] <= d;
        q <= mem[addr];
    end
endmodule
