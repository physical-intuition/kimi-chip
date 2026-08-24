// fullchip_v13 - fullchip_v12's memory macros re-grouped for PAIRED reads:
// 128 bits per operand per cycle -> 2 elements/lane -> 512 MACs/cycle.
//
// Same 16 fakeram45_512x64 macros (64 KB total), organized per operand as
// TWO groups of 4 banks: group 0 holds even elements, group 1 odd. A pair
// index reads both groups at the same row -> both words of the pair arrive
// together, no bank conflict, single-port macros unchanged.
//
// Address map (element i, 12 bits): group = i[0], bank = i[11:10],
// row = i[9:1]. Pair index p reads row p[8:0] of bank p[10:9] in BOTH
// groups. Capacity: 2 groups x 4 banks x 512 = 4096 elements per operand.
//
// Read pipeline unchanged from v12 (3 cycles to the interface register,
// then the core's lane register): T addr, T+1 bank read + select register,
// T+2 4:1 mux -> rdata_q, T+3 lane register, T+4 MACs.
module fullchip_v13 (
    input  wire        clk,
    input  wire        rst_n,
    // host load port (write-only; quiesce before start)
    input  wire        h_we,
    input  wire        h_sel,        // 0 = weight mem, 1 = activation mem
    input  wire [11:0] h_addr,       // ELEMENT index
    input  wire [63:0] h_wdata,
    // control
    input  wire        start,
    input  wire [15:0] k_dim,        // elements; <= 4096 usable here
    output wire        done,
    // result readout
    input  wire [7:0]  r_addr,
    output reg  [23:0] r_data
);
    wire        wgt_cs, act_cs;
    wire [15:0] wgt_addr, act_addr;
    reg  [63:0] wgt_rdata0, wgt_rdata1, act_rdata0, act_rdata1;
    wire [256*24-1:0] acc_out;

    compute_core_v13 #(.RD_LAT(3)) core (
        .clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr),
        .wgt_rdata0(wgt_rdata0), .wgt_rdata1(wgt_rdata1),
        .act_cs(act_cs), .act_addr(act_addr),
        .act_rdata0(act_rdata0), .act_rdata1(act_rdata1),
        .acc_out(acc_out), .done(done));

    genvar m, grp, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;   // PAIR index
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        for (grp = 0; grp < 2; grp = grp + 1) begin : g
            wire [63:0] bank_rd [0:3];
            wire        hwg = hw && (h_addr[0] == grp[0]);
            // select registered ONCE, same edge as the bank read (v12 rule)
            reg  [1:0]  tsel_q1;
            reg  [63:0] rdata_q;
            always @(posedge clk) begin
                tsel_q1 <= raddr[10:9];
                rdata_q <= bank_rd[tsel_q1];
            end
            for (b = 0; b < 4; b = b + 1) begin : bank
                wire h_hit = hwg && (h_addr[11:10] == b[1:0]);
                wire r_hit = ren && (raddr[10:9] == b[1:0]);
                fakeram45_512x64 u (
                    .clk(clk),
                    .ce_in(h_hit | r_hit),
                    .we_in(h_hit),
                    .addr_in(h_hit ? h_addr[9:1] : raddr[8:0]),
                    .wd_in(h_wdata),
                    .w_mask_in(64'hFFFFFFFFFFFFFFFF),
                    .rd_out(bank_rd[b]));
            end
        end
    end endgenerate

    always @(*) begin
        wgt_rdata0 = mem[0].g[0].rdata_q;
        wgt_rdata1 = mem[0].g[1].rdata_q;
        act_rdata0 = mem[1].g[0].rdata_q;
        act_rdata1 = mem[1].g[1].rdata_q;
    end

    // ---- narrow readout ----
    always @(posedge clk) r_data <= acc_out[r_addr*24 +: 24];
endmodule
