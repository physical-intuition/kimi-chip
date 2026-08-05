// Compute Core v3 - restructured MAC array
module compute_core_v3 #(
    parameter TILE = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  k_dim,
    output reg         busy,
    output reg         done,
    output reg         wgt_cs,
    output reg  [11:0] wgt_addr,
    input  wire [63:0] wgt_rdata,
    output reg         act_cs,
    output reg  [11:0] act_addr,
    input  wire [63:0] act_rdata,
    output reg         out_valid,
    output wire [TILE*TILE*16-1:0] acc_out
);

    reg mac_en, mac_clear;
    reg [7:0] k_cnt;
    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0; busy <= 0; done <= 0;
            mac_en <= 0; mac_clear <= 0;
            wgt_cs <= 0; act_cs <= 0;
            wgt_addr <= 0; act_addr <= 0;
            out_valid <= 0; k_cnt <= 0;
        end else begin
            done <= 0; out_valid <= 0; mac_clear <= 0;
            case (state)
                0: if (start) begin
                    busy <= 1; mac_clear <= 1;
                    wgt_cs <= 1; act_cs <= 1;
                    wgt_addr <= 0; act_addr <= 0;
                    k_cnt <= 0; state <= 1;
                end
                1: begin
                    mac_en <= 1;
                    k_cnt <= k_cnt + 1;
                    wgt_addr <= k_cnt + 1;
                    act_addr <= k_cnt + 1;
                    if (k_cnt >= k_dim - 1) begin
                        mac_en <= 0;
                        wgt_cs <= 0; act_cs <= 0;
                        state <= 2;
                    end
                end
                2: begin
                    out_valid <= 1; done <= 1;
                    busy <= 0; state <= 0;
                end
            endcase
        end
    end

    mac_array_v3 #(.ROWS(TILE), .COLS(TILE)) u_mac (
        .clk(clk), .rst_n(rst_n), .en(mac_en), .clear(mac_clear),
        .act_in(act_rdata[TILE*4-1:0]),
        .wgt_in(wgt_rdata[TILE*4-1:0]),
        .acc_out(acc_out)
    );

endmodule
