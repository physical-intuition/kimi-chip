// fullchip_v14 - fullchip_v13 + PING-PONG TILES: load and compute overlap.
//
// Each operand memory's 4 banks per group are split into two TILES:
//   tile 0 = bank-within-group 0, tile 1 = bank-within-group 1
// (2 groups x 1 bank x 512 rows = 2048 elements per operand per tile).
// The host writes h_tile while the core streams c_tile: different
// physical banks, so the single-port macros never see a port conflict
// and loads run at full rate DURING compute.
//
// Tiling protocol (host side):
//   load tile 0 -> start(c_tile=0, accum=0), load tile 1 during compute
//   -> on done: start(c_tile=1, accum=1), reload tile 0 during compute
//   -> ... sustained throughput ~= peak for back-to-back tiles.
// Cross-pass accumulation lifts usable K from the 4096-element memory
// bound to the arithmetic bound: total elements <= 131,071.
//
// Address map: a tile is 2 groups x 2 banks x 512 rows. Element-in-tile
// i (11 bits): group = i[0], bank offset = i[10], row = i[9:1]. Tile-local
// pair index p (10 bits): bank offset = p[9], row = p[8:0], both groups.
// Bank index b = {tile, offset}.
module fullchip_v14 (
    input  wire        clk,
    input  wire        rst_n,
    // host load port (may run concurrently with compute on the OTHER tile)
    input  wire        h_we,
    input  wire        h_sel,        // 0 = weight mem, 1 = activation mem
    input  wire        h_tile,       // which tile to write
    input  wire [10:0] h_addr,       // ELEMENT index within the tile
    input  wire [63:0] h_wdata,
    // control
    input  wire        start,
    input  wire        accum,        // 1 = keep accumulators (multi-tile K)
    input  wire        c_tile,       // which tile to compute from
    input  wire [15:0] k_dim,        // elements THIS PASS; <= 2048 usable
    output wire        done,
    // result readout
    input  wire [7:0]  r_addr,
    output reg  [23:0] r_data
);
    wire        wgt_cs, act_cs;
    wire [15:0] wgt_addr, act_addr;
    reg  [63:0] wgt_rdata0, wgt_rdata1, act_rdata0, act_rdata1;
    wire [256*24-1:0] acc_out;
    reg         c_tile_q;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) c_tile_q <= 1'b0;
        else if (start) c_tile_q <= c_tile;

    compute_core_v14 #(.RD_LAT(3)) core (
        .clk(clk), .rst_n(rst_n), .start(start), .accum(accum), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr),
        .wgt_rdata0(wgt_rdata0), .wgt_rdata1(wgt_rdata1),
        .act_cs(act_cs), .act_addr(act_addr),
        .act_rdata0(act_rdata0), .act_rdata1(act_rdata1),
        .acc_out(acc_out), .done(done));

    genvar m, grp, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] raddr = m ? act_addr : wgt_addr;   // tile-local PAIR index
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        for (grp = 0; grp < 2; grp = grp + 1) begin : g
            wire [63:0] bank_rd [0:3];
            wire        hwg = hw && (h_addr[0] == grp[0]);
            reg  [1:0]  tsel_q1;
            reg  [63:0] rdata_q;
            always @(posedge clk) begin
                tsel_q1 <= {c_tile_q, raddr[9]};
                rdata_q <= bank_rd[tsel_q1];
            end
            // bank index b = {tile, offset}: tile = b[1], offset = b[0]
            for (b = 0; b < 4; b = b + 1) begin : bank
                wire h_hit = hwg && (h_tile   == b[1]) && (h_addr[10] == b[0]);
                wire r_hit = ren && (c_tile_q == b[1]) && (raddr[9]   == b[0]);
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

    always @(posedge clk) r_data <= acc_out[r_addr*24 +: 24];
endmodule
