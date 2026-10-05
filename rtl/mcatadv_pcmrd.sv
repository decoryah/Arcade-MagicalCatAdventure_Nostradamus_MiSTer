// The YM2610's ADPCM-A sample ROM port: the chip puts a byte address out (a new one every 1.5 us slot, for each of
// its six channels in turn) and wants the byte back before the slot ends. The byte is read from the SDRAM whenever
// the address changes and held in a register.
`default_nettype none
module mcatadv_pcmrd (
    input  logic        clk,
    input  logic        rst,
    input  logic [19:0] addr,           // from the chip
    output logic [7:0]  data,           // to the chip
    output logic        pcm_req,        // to the memory: level until pcm_ack
    output logic [19:0] pcm_addr,
    input  logic        pcm_ack,
    input  logic [7:0]  pcm_q
);
    logic [19:0] a_q;
    always_ff @(posedge clk) begin
        if (rst) begin pcm_req <= 1'b0; data <= 8'h00; a_q <= 20'd0; end
        else begin
            if (pcm_ack) begin data <= pcm_q; pcm_req <= 1'b0; end
            if (!pcm_req && !pcm_ack && a_q != addr) begin
                a_q <= addr; pcm_addr <= addr; pcm_req <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
