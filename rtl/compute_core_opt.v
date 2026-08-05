// Optimized Compute Core - MAC Array + Controller
// Optimizations:
// 1. 20-bit accumulators (vs 32-bit) - saves 3072 flops
// 2. Simplified controller with reduced state encoding
// 3. Black-boxed memory interfaces
module compute_core_opt #(
    parameter TILE_SIZE = 16,
    parameter ACC_WIDTH = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface  
    input  wire        start,
    input  wire [7:0]  k_dim,
    output wire        busy,
    output wire        done,
    
    // Weight memory interface (to external SRAM macro)
    output wire        wgt_cs,
    output wire [11:0] wgt_addr,
    input  wire [63:0] wgt_rdata,
    
    // Activation memory interface (to external SRAM macro)
    output wire        act_cs,
    output wire [11:0] act_addr,
    input  wire [63:0] act_rdata,
    
    // Output interface
    output wire        out_valid,
    output wire [TILE_SIZE*TILE_SIZE*ACC_WIDTH-1:0] acc_out
);

    // Simplified controller signals
    reg        mac_en, mac_clear;
    reg        r_busy, r_done;
    reg        r_wgt_cs, r_act_cs;
    reg [11:0] r_addr;
    reg        r_out_valid;
    reg [7:0]  k_cnt;
    reg [1:0]  state;
    
    localparam IDLE = 2'd0, COMPUTE = 2'd1, OUTPUT = 2'd2;
    
    assign busy = r_busy;
    assign done = r_done;
    assign wgt_cs = r_wgt_cs;
    assign act_cs = r_act_cs;
    assign wgt_addr = r_addr;
    assign act_addr = r_addr;
    assign out_valid = r_out_valid;

    // Data unpacking for MAC array
    wire [TILE_SIZE*4-1:0] act_to_mac = act_rdata[TILE_SIZE*4-1:0];
    wire [TILE_SIZE*4-1:0] wgt_to_mac = wgt_rdata[TILE_SIZE*4-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            r_busy <= 0;
            r_done <= 0;
            mac_en <= 0;
            mac_clear <= 0;
            r_wgt_cs <= 0;
            r_act_cs <= 0;
            r_addr <= 0;
            r_out_valid <= 0;
            k_cnt <= 0;
        end else begin
            r_done <= 0;
            r_out_valid <= 0;
            mac_clear <= 0;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        r_busy <= 1;
                        mac_clear <= 1;
                        r_wgt_cs <= 1;
                        r_act_cs <= 1;
                        r_addr <= 0;
                        k_cnt <= 0;
                        state <= COMPUTE;
                    end
                end
                
                COMPUTE: begin
                    mac_en <= 1;
                    k_cnt <= k_cnt + 1;
                    r_addr <= k_cnt + 1;
                    
                    if (k_cnt >= k_dim - 1) begin
                        mac_en <= 0;
                        r_wgt_cs <= 0;
                        r_act_cs <= 0;
                        state <= OUTPUT;
                    end
                end
                
                OUTPUT: begin
                    r_out_valid <= 1;
                    r_done <= 1;
                    r_busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end

    // Optimized 16x16 INT4 MAC array
    mac_array_opt #(
        .ROWS(TILE_SIZE),
        .COLS(TILE_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_mac (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (mac_en),
        .clear   (mac_clear),
        .act_in  (act_to_mac),
        .wgt_in  (wgt_to_mac),
        .acc_out (acc_out)
    );

endmodule
