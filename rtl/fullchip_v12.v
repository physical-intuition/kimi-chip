// fullchip_v12 - fullchip_v10's memory system + compute_core_v12's
// registered read-data broadcast, chasing the ~9% broadcast tax the v10
// signoff measured (mem rdata_q -> array-interior MAC in one cycle).
//
// Identical to fullchip_v10 except compute_core_v12 (lane register tree;
// total read latency 4). The write mask stays a constant all-ones tie,
// exactly as fullchip_v10 -- a registered mask constant-propagates back to
// tie cells in synthesis anyway, and resetting it to 0 would mask the first
// host write.
//
// Memory read pipeline (per element):
//   T   : core registers addr
//   T+1 : fakeram registers the read, bank selects register
//   T+2 : 8:1 bank mux -> interface register
//   T+3 : lane register tree (the broadcast crossing, its own cycle)
//   T+4 : MACs consume locally
module fullchip_v12 (
    input  wire        clk,
    input  wire        rst_n,
    // host load port (write-only; quiesce before start)
    input  wire        h_we,
    input  wire        h_sel,        // 0 = weight mem, 1 = activation mem
    input  wire [11:0] h_addr,
    input  wire [63:0] h_wdata,
    // control
    input  wire        start,
    input  wire [15:0] k_dim,        // elements; <= 4096 usable here
    output wire        done,
    // result readout
    input  wire [7:0]  r_addr,       // which of the 256 accumulators
    output reg  [23:0] r_data
);
    wire        wgt_cs, act_cs;
    wire [15:0] wgt_addr, act_addr;
    reg  [63:0] wgt_rdata, act_rdata;
    wire [256*24-1:0] acc_out;

    compute_core_v12 #(.RD_LAT(3)) core (
        .clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr), .wgt_rdata(wgt_rdata),
        .act_cs(act_cs), .act_addr(act_addr), .act_rdata(act_rdata),
        .acc_out(acc_out), .done(done));

    // ---- two 4096x64 memories: 8x fakeram45_512x64 each ----
    genvar m, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        wire [63:0] bank_rd [0:7];
        // select registered ONCE: fakeram rd_out is valid the cycle after
        // ce/addr, and tsel_q1 (registered the same edge) is that address's
        // bank - data and select arrive at the mux in the same cycle.
        reg  [2:0]  tsel_q1;
        reg  [63:0] rdata_q;
        always @(posedge clk) begin
            tsel_q1 <= raddr[11:9];
            rdata_q <= bank_rd[tsel_q1];
        end
        for (b = 0; b < 8; b = b + 1) begin : bank
            wire h_hit = hw && (h_addr[11:9] == b[2:0]);
            wire r_hit = ren && (raddr[11:9] == b[2:0]);
            fakeram45_512x64 u (
                .clk(clk),
                .ce_in(h_hit | r_hit),
                .we_in(h_hit),
                .addr_in(h_hit ? h_addr[8:0] : raddr[8:0]),
                .wd_in(h_wdata),
                .w_mask_in(64'hFFFFFFFFFFFFFFFF),
                .rd_out(bank_rd[b]));
        end
    end endgenerate

    always @(*) begin
        wgt_rdata = mem[0].rdata_q;
        act_rdata = mem[1].rdata_q;
    end

    // ---- narrow readout ----
    always @(posedge clk) r_data <= acc_out[r_addr*24 +: 24];
endmodule
