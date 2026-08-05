// Matrix Multiply Controller FSM
// Simplified for 16x16 single-tile operation
module mm_controller #(
    parameter TILE_SIZE = 16,
    parameter MAX_DIM = 256
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface
    input  wire        start,
    input  wire [7:0]  m_dim,
    input  wire [7:0]  n_dim,  
    input  wire [7:0]  k_dim,
    output reg         busy,
    output reg         done,
    
    // Weight SRAM interface
    output reg         wgt_cs,
    output reg  [11:0] wgt_addr,
    
    // Activation SRAM interface
    output reg         act_cs,
    output reg  [11:0] act_addr,
    
    // MAC array control
    output reg         mac_en,
    output reg         mac_clear,
    
    // Output control
    output reg         out_valid,
    output reg  [7:0]  out_row,
    output reg  [7:0]  out_col
);

    // FSM states
    localparam IDLE    = 3'd0;
    localparam CLEAR   = 3'd1;
    localparam FETCH   = 3'd2;
    localparam COMPUTE = 3'd3;
    localparam OUTPUT  = 3'd4;
    localparam DONE    = 3'd5;

    reg [2:0]  state;
    reg [7:0]  k_cnt;
    reg        start_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            k_cnt <= 8'd0;
            wgt_cs <= 1'b0;
            wgt_addr <= 12'd0;
            act_cs <= 1'b0;
            act_addr <= 12'd0;
            mac_en <= 1'b0;
            mac_clear <= 1'b0;
            out_valid <= 1'b0;
            out_row <= 8'd0;
            out_col <= 8'd0;
            start_latched <= 1'b0;
        end else begin
            // Latch start signal
            if (start) start_latched <= 1'b1;
            
            // Defaults
            mac_clear <= 1'b0;
            mac_en <= 1'b0;
            out_valid <= 1'b0;
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_latched) begin
                        busy <= 1'b1;
                        start_latched <= 1'b0;
                        k_cnt <= 8'd0;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    mac_clear <= 1'b1;
                    wgt_cs <= 1'b1;
                    act_cs <= 1'b1;
                    wgt_addr <= 12'd0;
                    act_addr <= 12'd0;
                    state <= FETCH;
                end

                FETCH: begin
                    // Pre-fetch next data while previous is being processed
                    wgt_addr <= k_cnt;
                    act_addr <= k_cnt;
                    state <= COMPUTE;
                end

                COMPUTE: begin
                    mac_en <= 1'b1;
                    k_cnt <= k_cnt + 1;
                    
                    if (k_cnt < k_dim - 1) begin
                        wgt_addr <= k_cnt + 1;
                        act_addr <= k_cnt + 1;
                        state <= COMPUTE;
                    end else begin
                        wgt_cs <= 1'b0;
                        act_cs <= 1'b0;
                        state <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    out_valid <= 1'b1;
                    out_row <= 8'd0;
                    out_col <= 8'd0;
                    state <= DONE;
                end

                DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
