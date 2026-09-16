`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Layer Controller for Hybrid KDA/MLA Architecture
// X5Y4: Same RTL as X5Y3, testing 0.42ns into 2x64 cycles for faster FSM transitions
//
// Key optimization: pre-compute phase_done one cycle ahead to reduce
// critical path from phase_cycle comparison to current_phase transition.
//-----------------------------------------------------------------------------
module layer_controller #(
    parameter N_LAYERS      = 2,
    parameter LAYER_PATTERN = 2'b01,
    parameter D_MODEL       = 64,
    parameter KDA_HEADS     = 2,
    parameter KDA_DIM       = 32,
    parameter MLA_HEADS     = 2,
    parameter MLA_DK        = 32,
    parameter MLA_DR        = 16,
    parameter MLA_DV        = 32,
    parameter MLA_DC        = 128,
    parameter MAX_SEQ       = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    token_valid,
    output wire                    token_ready,
    input  wire [D_MODEL*32-1:0]   token_emb,
    input  wire                    seq_start,
    output reg                     output_valid,
    output reg  [D_MODEL*32-1:0]   output_h,
    output reg                     busy,
    output reg  [3:0]              current_layer,
    output reg  [4:0]              current_phase
);

    // FSM states - same as before
    localparam IDLE         = 5'd0;
    localparam KDA_PROJ_Q   = 5'd1;
    localparam KDA_PROJ_K   = 5'd2;
    localparam KDA_PROJ_V   = 5'd3;
    localparam KDA_CONV_Q   = 5'd4;
    localparam KDA_CONV_K   = 5'd5;
    localparam KDA_CONV_V   = 5'd6;
    localparam KDA_GATES    = 5'd7;
    localparam KDA_STATE_RD = 5'd8;
    localparam KDA_STATE_UP = 5'd9;
    localparam KDA_STATE_WR = 5'd10;
    localparam KDA_OUTPUT   = 5'd11;
    localparam MLA_LATENT   = 5'd12;
    localparam MLA_PROJ_Q   = 5'd13;
    localparam MLA_PROJ_K   = 5'd14;
    localparam MLA_PROJ_V   = 5'd15;
    localparam MLA_KV_STORE = 5'd16;
    localparam MLA_ATTN_A   = 5'd17;
    localparam MLA_ATTN_B   = 5'd23;
    localparam MLA_ATTN_B   = 5'd18;
    localparam NORM         = 5'd19;
    localparam RESIDUAL     = 5'd20;
    localparam NEXT_LAYER   = 5'd21;
    localparam DONE         = 5'd22;
    
    // Phase cycle counter
    reg [7:0] phase_cycle;
    
    // PRE-COMPUTED phase done signals (registered, one cycle ahead)
    // These are set when phase_cycle reaches threshold-1
    reg phase_done_7;    // for 8-cycle phases
    reg phase_done_15;   // for 16-cycle phases  
    reg phase_done_31;   // for 32-cycle phases
    reg phase_done_63;   // for 64-cycle phases
    reg phase_done_127;  // for 128-cycle phases
    
    // Control signals
    reg  conv_push_valid;
    reg  [1:0] conv_stream_sel;
    reg  kda_state_rd_en;
    reg  kda_state_wr_en;
    reg  mla_kv_append;
    reg  mla_cache_reset;
    reg [D_MODEL*32-1:0] h_reg;
    
    assign token_ready = !busy && (current_phase == IDLE);
    
    // Pre-compute phase_done signals one cycle ahead
    // These compare against threshold-1, so they're ready the cycle BEFORE transition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_done_7   <= 1'b0;
            phase_done_15  <= 1'b0;
            phase_done_31  <= 1'b0;
            phase_done_63  <= 1'b0;
            phase_done_127 <= 1'b0;
        end else begin
            // Pre-compute: set when we reach threshold-1
            // Next cycle, these will be valid for transition decision
            phase_done_7   <= (phase_cycle == 8'd6);
            phase_done_15  <= (phase_cycle == 8'd14);
            phase_done_31  <= (phase_cycle == 8'd30);
            phase_done_63  <= (phase_cycle == 8'd62);
            phase_done_127 <= (phase_cycle == 8'd126);
        end
    end
    
    // Main FSM - uses pre-computed phase_done signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            current_layer <= 4'd0;
            current_phase <= IDLE;
            phase_cycle <= 8'd0;
            output_valid <= 1'b0;
            conv_push_valid <= 1'b0;
            kda_state_rd_en <= 1'b0;
            kda_state_wr_en <= 1'b0;
            mla_kv_append <= 1'b0;
            mla_cache_reset <= 1'b0;
            h_reg <= {(D_MODEL*32){1'b0}};
        end else begin
            output_valid <= 1'b0;
            conv_push_valid <= 1'b0;
            kda_state_rd_en <= 1'b0;
            kda_state_wr_en <= 1'b0;
            mla_kv_append <= 1'b0;
            mla_cache_reset <= 1'b0;
            
            case (current_phase)
                IDLE: begin
                    if (seq_start) begin
                        mla_cache_reset <= 1'b1;
                        current_layer <= 4'd0;
                    end else if (token_valid) begin
                        busy <= 1'b1;
                        h_reg <= token_emb;
                        current_layer <= 4'd0;
                        phase_cycle <= 8'd0;
                        if (LAYER_PATTERN[0])
                            current_phase <= MLA_LATENT;
                        else
                            current_phase <= KDA_PROJ_Q;
                    end
                end
                
                // KDA phases - use pre-computed phase_done signals
                KDA_PROJ_Q: begin
                    if (phase_done_15) begin
                        current_phase <= KDA_PROJ_K;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_PROJ_K: begin
                    if (phase_done_15) begin
                        current_phase <= KDA_PROJ_V;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_PROJ_V: begin
                    if (phase_done_15) begin
                        current_phase <= KDA_CONV_Q;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_CONV_Q: begin
                    conv_stream_sel <= 2'd0;
                    conv_push_valid <= 1'b1;
                    current_phase <= KDA_CONV_K;
                end
                
                KDA_CONV_K: begin
                    conv_stream_sel <= 2'd1;
                    conv_push_valid <= 1'b1;
                    current_phase <= KDA_CONV_V;
                end
                
                KDA_CONV_V: begin
                    conv_stream_sel <= 2'd2;
                    conv_push_valid <= 1'b1;
                    current_phase <= KDA_GATES;
                end
                
                KDA_GATES: begin
                    if (phase_done_7) begin
                        current_phase <= KDA_STATE_RD;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_STATE_RD: begin
                    kda_state_rd_en <= 1'b1;
                    current_phase <= KDA_STATE_UP;
                    phase_cycle <= 8'd0;
                end
                
                KDA_STATE_UP: begin
                    if (phase_done_63) begin
                        current_phase <= KDA_STATE_WR;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_STATE_WR: begin
                    kda_state_wr_en <= 1'b1;
                    current_phase <= KDA_OUTPUT;
                end
                
                KDA_OUTPUT: begin
                    if (phase_done_31) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                // MLA phases
                MLA_LATENT: begin
                    if (phase_done_31) begin
                        current_phase <= MLA_PROJ_Q;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_Q: begin
                    if (phase_done_15) begin
                        current_phase <= MLA_PROJ_K;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_K: begin
                    if (phase_done_15) begin
                        current_phase <= MLA_PROJ_V;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_V: begin
                    if (phase_done_15) begin
                        current_phase <= MLA_KV_STORE;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_KV_STORE: begin
                    mla_kv_append <= 1'b1;
                    current_phase <= MLA_ATTN_A;
                    phase_cycle <= 8'd0;
                end
                
                MLA_ATTN_A: begin
                    if (phase_done_63) begin
                        current_phase <= MLA_ATTN_B;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_ATTN_B: begin
                    if (phase_done_63) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                // Common phases
                NORM: begin
                    if (phase_done_7) begin
                        current_phase <= RESIDUAL;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                RESIDUAL: begin
                    current_phase <= NEXT_LAYER;
                end
                
                NEXT_LAYER: begin
                    if (current_layer >= N_LAYERS - 1) begin
                        current_phase <= DONE;
                    end else begin
                        current_layer <= current_layer + 1;
                        phase_cycle <= 8'd0;
                        if (LAYER_PATTERN[current_layer + 1])
                            current_phase <= MLA_LATENT;
                        else
                            current_phase <= KDA_PROJ_Q;
                    end
                end
                
                DONE: begin
                    output_valid <= 1'b1;
                    output_h <= h_reg;
                    busy <= 1'b0;
                    current_phase <= IDLE;
                    current_layer <= 4'd0;
                end
                
                default: current_phase <= IDLE;
            endcase
        end
    end

endmodule
