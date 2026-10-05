// 68000 program ROM cache: direct mapped, 16 KB, 16-byte lines (8 words), over the
// 1 MB program in SDRAM. A miss asks the memory arbiter for the whole line.
//
// word address a = addr[19:1] (19 bits):  tag a[18:13] | index a[12:3] | word in line a[2:0]
`default_nettype none
module mcatadv_cache (
    input  logic        clk,
    input  logic        inval,            // rising edge: sweep all lines invalid (after a ROM load)
    output logic        busy,

    // CPU side: level request, ack for one cycle with the word valid
    input  logic        req,
    input  logic [19:1] addr,
    output logic        ack,
    output logic [15:0] data,

    // memory side: one burst of 8 words per line
    output logic        fill_req,         // level, until fill_done
    output logic [19:4] fill_addr,        // line address (16-byte units)
    input  logic        fill_wr,
    input  logic [2:0]  fill_idx,
    input  logic [15:0] fill_data,
    input  logic        fill_done
);
    logic [18:0] a;
    wire  [9:0]  index = a[12:3];
    wire  [5:0]  tag   = a[18:13];

    typedef enum logic [2:0] {S_SWEEP, S_IDLE, S_RD, S_CMP, S_FILL} st_t;
    st_t st = S_SWEEP;
    logic [9:0] sweep = 10'd0;
    logic       inval_d;

    // tag RAM: {valid, tag[5:0]}; written combinationally from the state so a line is
    // visible to the read that follows the fill
    wire         tag_we    = (st == S_SWEEP) || (st == S_FILL && fill_done);
    wire  [9:0]  tag_waddr = (st == S_SWEEP) ? sweep : index;
    wire  [6:0]  tag_wdata = (st == S_SWEEP) ? 7'd0  : {1'b1, tag};
    logic [6:0]  tag_q;
    mcatadv_sdp #(.AW(10), .DW(7)) u_tag (.clk(clk), .we(tag_we), .waddr(tag_waddr), .wdata(tag_wdata),
                                           .raddr(index), .rdata(tag_q));

    // data RAM: 8192 words
    logic [15:0] dat_q;
    mcatadv_sdp #(.AW(13), .DW(16)) u_dat (.clk(clk), .we(fill_wr), .waddr({index, fill_idx}), .wdata(fill_data),
                                            .raddr(a[12:0]), .rdata(dat_q));

    wire hit = tag_q[6] && (tag_q[5:0] == tag);
    assign ack       = (st == S_CMP) && hit;
    assign data      = dat_q;
    assign busy      = (st == S_SWEEP);
    assign fill_addr = {tag, index};

    always_ff @(posedge clk) begin
        inval_d <= inval;
        if (inval && !inval_d) begin
            st <= S_SWEEP; sweep <= 10'd0; fill_req <= 1'b0;
        end else case (st)
            S_SWEEP: begin
                sweep <= sweep + 10'd1;
                if (sweep == 10'h3ff) st <= S_IDLE;
            end
            S_IDLE: if (req) begin a <= addr; st <= S_RD; end
            S_RD:   st <= S_CMP;
            S_CMP:  if (hit) st <= S_IDLE;
                    else begin fill_req <= 1'b1; st <= S_FILL; end
            S_FILL: if (fill_done) begin fill_req <= 1'b0; st <= S_RD; end
            default: st <= S_IDLE;
        endcase
    end
endmodule
`default_nettype wire
