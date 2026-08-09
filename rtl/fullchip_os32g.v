// fullchip_os32g - fullchip_os32p with the readout done right: the 32x32
// signoff showed the ONLY setup violator was the flat 1024:1 readout mux
// (ra_q -> r_data, an architecturally static path). os32g replaces it
// with a THREE-STAGE REGISTERED TREE, so no cycle carries more than one
// small mux plus local wire:
//   stage 1: 64 parallel 16:1 muxes (select = r_addr[3:0]), registered
//            beside their accumulator groups
//   stage 2: 8 parallel 8:1 muxes over stage-1 registers
//   stage 3: final 8:1 -> r_data
// Readout latency: r_data is valid FOUR cycles after r_addr (address
// register + three tree stages) -- free, the host reads after done.
// The systolic core and memory system are fullchip_os32p's, unchanged.
module fullchip_os32g (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        h_we,
    input  wire        h_sel,
    input  wire [11:0] h_addr,
    input  wire [63:0] h_wdata,
    input  wire        start,
    input  wire        accum,
    input  wire [15:0] k_dim,
    output wire        done,
    input  wire [9:0]  r_addr,
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

    genvar m, g, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;
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

    assign ww00 = mem[0].grp[0].rdata_q;
    assign ww01 = mem[0].grp[1].rdata_q;
    assign ww10 = mem[0].grp[2].rdata_q;
    assign ww11 = mem[0].grp[3].rdata_q;
    assign aw00 = mem[1].grp[0].rdata_q;
    assign aw01 = mem[1].grp[1].rdata_q;
    assign aw10 = mem[1].grp[2].rdata_q;
    assign aw11 = mem[1].grp[3].rdata_q;

    // ---- three-stage registered readout tree ----
    reg [9:0] ra_q;
    reg [5:0] rhi_q1;               // r_addr[9:4] delayed to stage 2/3
    reg [2:0] rhi_q2;
    reg [23:0] s1 [0:63];
    reg [23:0] s2 [0:7];
    integer x;
    always @(posedge clk) begin
        ra_q  <= r_addr;
        rhi_q1 <= ra_q[9:4];
        rhi_q2 <= rhi_q1[5:3];
        for (x = 0; x < 64; x = x + 1)
            s1[x] <= acc_out[(x*16 + ra_q[3:0])*24 +: 24];
        for (x = 0; x < 8; x = x + 1)
            s2[x] <= s1[{x[2:0], rhi_q1[2:0]}];
        r_data <= s2[rhi_q2];
    end
endmodule
