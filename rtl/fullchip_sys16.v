// fullchip_sys16 - systolic_core16 + the v13 memory system (16x
// fakeram45_512x64, 2 even/odd groups x 4 banks per operand, 4096
// elements each). The systolic core consumes ONE word per operand per
// cycle during its load phases; the wrapper reads the pair containing
// element k and selects the group by k[0] (delayed to match the read
// pipeline). Host load port and readout identical to v13.
module fullchip_sys16 (
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
    wire [63:0] wgt_word, act_word;
    wire [256*24-1:0] acc_out;

    systolic_core16 core (
        .clk(clk), .rst_n(rst_n), .start(start), .accum(accum), .k_dim(k_dim),
        .wgt_cs(wgt_cs), .wgt_addr(wgt_addr), .wgt_word(wgt_word),
        .act_cs(act_cs), .act_addr(act_addr), .act_word(act_word),
        .acc_out(acc_out), .done(done));

    genvar m, grp, b;
    generate for (m = 0; m < 2; m = m + 1) begin : mem
        wire [15:0] eaddr = m ? act_addr : wgt_addr;   // ELEMENT index
        wire        ren   = m ? act_cs   : wgt_cs;
        wire        hw    = h_we && (h_sel == m[0]);
        wire [15:0] raddr = {1'b0, eaddr[15:1]};       // PAIR index
        // group select pipelined to the word-valid cycle
        reg gsel_q1, gsel_q2;
        always @(posedge clk) begin gsel_q1 <= eaddr[0]; gsel_q2 <= gsel_q1; end
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
        wire [63:0] word = mem[m].gsel_q2 ? mem[m].g[1].rdata_q
                                          : mem[m].g[0].rdata_q;
    end endgenerate

    assign wgt_word = mem[0].word;
    assign act_word = mem[1].word;

    always @(posedge clk) r_data <= acc_out[r_addr*24 +: 24];
endmodule
