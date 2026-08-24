// fullchip_os16p - systolic_os16p (paired output-stationary, 512
// MACs/cycle) + the v13 memory system. The core streams one PAIR per
// operand per cycle; the wrapper reads pair p and hands over BOTH group
// words (elements 2p and 2p+1) -- the two words/cycle the banked
// memories always supplied, now both consumed. Host load port and
// readout identical to v13.
module fullchip_os16p (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        h_we,
    input  wire        h_sel,
    input  wire [11:0] h_addr,       // ELEMENT index
    input  wire [63:0] h_wdata,
    input  wire        start,
    input  wire        accum,
    input  wire [15:0] k_dim,
    output wire        done,
    input  wire [7:0]  r_addr,
    output reg  [23:0] r_data
);
    wire        wgt_cs, act_cs;
    wire [15:0] wgt_addr, act_addr;
    wire [256*24-1:0] acc_out;

    wire [63:0] ww0, ww1, aw0, aw1;

    systolic_os16p core (
        .clk(clk), .rst_n(rst_n), .start(start), .accum(accum), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr),
        .wgt_word0(ww0), .wgt_word1(ww1),
        .act_cs(act_cs), .act_addr(act_addr),
        .act_word0(aw0), .act_word1(aw1),
        .acc_out(acc_out), .done(done));

    genvar m, grp, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;   // PAIR index
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        for (grp = 0; grp < 2; grp = grp + 1) begin : g
            wire [63:0] bank_rd [0:3];
            wire        hwg = hw && (h_addr[0] == grp[0]);
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

    assign ww0 = mem[0].g[0].rdata_q;
    assign ww1 = mem[0].g[1].rdata_q;
    assign aw0 = mem[1].g[0].rdata_q;
    assign aw1 = mem[1].g[1].rdata_q;

    always @(posedge clk) r_data <= acc_out[r_addr*24 +: 24];
endmodule
