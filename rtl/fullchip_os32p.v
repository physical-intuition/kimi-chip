// fullchip_os32p - systolic_os32p (32x32 paired, 2048 MACs/cycle) + the
// SAME 16 fakeram45_512x64 macros, re-grouped once more: each operand's
// 8 banks form FOUR groups of two (lane-half x element-parity), so pair
// index p reads 4 x 64b = 256 bits/operand/cycle, single ports, no
// conflicts. A 32-lane element is two words (128b); capacity 2048
// elements per operand (the same 64 KB).
//
// Host port (64b): address = {element[10:0], half}: group {half,
// element parity}, bank element[10] ... concretely for h_addr[11:0]:
// half = h_addr[0], e = h_addr[11:1]; group = {h_addr[0], h_addr[1]},
// bank-in-group = h_addr[11], row = h_addr[10:2].
// Readout: r_addr registered before the 1024:1 mux (one extra cycle;
// keeps the port + mux off a single path).
module fullchip_os32p (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        h_we,
    input  wire        h_sel,
    input  wire [11:0] h_addr,       // {element, half}
    input  wire [63:0] h_wdata,
    input  wire        start,
    input  wire        accum,
    input  wire [15:0] k_dim,
    output wire        done,
    input  wire [9:0]  r_addr,       // which of the 1024 accumulators
    output reg  [23:0] r_data
);
    wire        wgt_cs, act_cs;
    wire [15:0] wgt_addr, act_addr;
    wire [1024*24-1:0] acc_out;
    wire [63:0] ww00, ww01, ww10, ww11, aw00, aw01, aw10, aw11;

    systolic_os32p core (
        .clk(clk), .rst_n(rst_n), .start(start), .accum(accum), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr),
        .wgt_w00(ww00), .wgt_w01(ww01), .wgt_w10(ww10), .wgt_w11(ww11),
        .act_cs(act_cs), .act_addr(act_addr),
        .act_w00(aw00), .act_w01(aw01), .act_w10(aw10), .act_w11(aw11),
        .acc_out(acc_out), .done(done));

    // group index g = {half, parity}; bank-in-group b; each bank 512 rows
    genvar m, g, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;   // PAIR index
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        for (g = 0; g < 4; g = g + 1) begin : grp
            wire [63:0] bank_rd [0:1];
            wire        hwg = hw && ({h_addr[0], h_addr[1]} == g[1:0]);
            reg         tsel_q1;
            reg  [63:0] rdata_q;
            always @(posedge clk) begin
                tsel_q1 <= raddr[9];
                rdata_q <= bank_rd[tsel_q1];
            end
            for (b = 0; b < 2; b = b + 1) begin : bank
                wire h_hit = hwg && (h_addr[11] == b[0]);
                wire r_hit = ren && (raddr[9] == b[0]);
                fakeram45_512x64 u (
                    .clk(clk),
                    .ce_in(h_hit | r_hit),
                    .we_in(h_hit),
                    .addr_in(h_hit ? h_addr[10:2] : raddr[8:0]),
                    .wd_in(h_wdata),
                    .w_mask_in(64'hFFFFFFFFFFFFFFFF),
                    .rd_out(bank_rd[b]));
            end
        end
    end endgenerate

    // group {half, parity}: g = half*2 + parity
    assign ww00 = mem[0].grp[0].rdata_q;  // half0, even
    assign ww01 = mem[0].grp[1].rdata_q;  // half0, odd
    assign ww10 = mem[0].grp[2].rdata_q;  // half1, even
    assign ww11 = mem[0].grp[3].rdata_q;  // half1, odd
    assign aw00 = mem[1].grp[0].rdata_q;
    assign aw01 = mem[1].grp[1].rdata_q;
    assign aw10 = mem[1].grp[2].rdata_q;
    assign aw11 = mem[1].grp[3].rdata_q;

    reg [9:0] ra_q;
    always @(posedge clk) begin
        ra_q   <= r_addr;
        r_data <= acc_out[ra_q*24 +: 24];
    end
endmodule
