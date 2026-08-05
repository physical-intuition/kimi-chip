// 8x32 array - wider output, narrower input
// Better for memory-bound workloads
module compute_core_v5 (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] k_dim,
    output reg wgt_cs,
    output reg [9:0] wgt_addr,
    input wire [127:0] wgt_rdata,  // 32 weights = 128 bits
    output reg act_cs,
    output reg [9:0] act_addr,
    input wire [31:0] act_rdata,   // 8 activations = 32 bits
    output wire [256*16-1:0] acc_out,
    output reg done
);
    localparam IDLE=0, CLEAR=1, FETCH=2, COMPUTE=3, DONE=4;
    reg [2:0] state;
    reg [7:0] k_cnt;
    reg mac_en, mac_clear;
    
    mac_array_v5 #(.ROWS(8), .COLS(32), .ACC_WIDTH(16)) array (
        .clk(clk), .rst_n(rst_n),
        .en(mac_en), .clear(mac_clear),
        .activations(act_rdata),
        .weights(wgt_rdata),
        .acc_out(acc_out)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; k_cnt <= 0; done <= 0;
            mac_en <= 0; mac_clear <= 0;
            wgt_cs <= 0; act_cs <= 0;
        end else case (state)
            IDLE: if (start) begin state <= CLEAR; mac_clear <= 1; end
            CLEAR: begin mac_clear <= 0; state <= FETCH; k_cnt <= 0; end
            FETCH: begin
                wgt_cs <= 1; act_cs <= 1;
                wgt_addr <= k_cnt; act_addr <= k_cnt;
                state <= COMPUTE;
            end
            COMPUTE: begin
                mac_en <= 1;
                if (k_cnt == k_dim - 1) state <= DONE;
                else begin k_cnt <= k_cnt + 1; state <= FETCH; end
            end
            DONE: begin done <= 1; mac_en <= 0; wgt_cs <= 0; act_cs <= 0; end
        endcase
    end
endmodule
