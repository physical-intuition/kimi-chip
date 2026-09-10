`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Layer Controller for Hybrid KDA/MLA Architecture
//
// Handles the layer_pattern from nano-kpu config.py:
//   layer_pattern="LF"  # L=KDA (linear attention), F=MLA (full attention)
//   n_layers=2          # So pattern is [KDA, MLA]
//
// Each layer type has different dataflow:
//
// KDA Layer (type="L"):
//   1. Q/K/V projections: h @ W_q, h @ W_k, h @ W_v
//   2. Conv on Q/K/V: depthwise causal conv with history
//   3. Beta/alpha gates: sigmoid(h @ W_b), exp(bound * sigmoid(...))
//   4. State update: S = α·S + β·k·(v - k·S)ᵀ (read-modify-write)
//   5. Output: (q @ S) through norm and output proj
//
// MLA Layer (type="F"):
//   1. Latent projection: lat = rmsnorm(h @ W_c)
//   2. Q/K projections from h and lat
//   3. V projection from lat
//   4. Append K,V to cache
//   5. Attention: softmax(Q @ K.T / sqrt(d)) @ V over all cached positions
//   6. Output projection
//
// This controller sequences through layers and dispatches to correct units.
//-----------------------------------------------------------------------------
module layer_controller #(
    parameter N_LAYERS      = 2,
    parameter LAYER_PATTERN = 2'b01,  // bit i: 0=KDA(L), 1=MLA(F). nano: "LF" = 01
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
    
    // Token input
    input  wire                    token_valid,
    output wire                    token_ready,
    input  wire [D_MODEL*32-1:0]   token_emb,    // embedded token, FP32
    
    // Sequence control
    input  wire                    seq_start,     // reset all state/cache
    
    // Output
    output reg                     output_valid,
    output reg  [D_MODEL*32-1:0]   output_h,
    
    // Status
    output reg                     busy,
    output reg  [3:0]              current_layer,
    output reg  [4:0]              current_phase
);

    // Layer type decode
    wire is_mla_layer = LAYER_PATTERN[current_layer];
    
    // FSM states
    localparam IDLE         = 5'd0;
    // KDA phases
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
    // MLA phases
    localparam MLA_LATENT   = 5'd12;
    localparam MLA_PROJ_Q   = 5'd13;
    localparam MLA_PROJ_K   = 5'd14;
    localparam MLA_PROJ_V   = 5'd15;
    localparam MLA_KV_STORE = 5'd16;
    localparam MLA_ATTN     = 5'd17;
    localparam MLA_OUTPUT   = 5'd18;
    // Common
    localparam NORM         = 5'd19;
    localparam RESIDUAL     = 5'd20;
    localparam NEXT_LAYER   = 5'd21;
    localparam DONE         = 5'd22;
    
    // Phase cycle counter
    reg [7:0] phase_cycle;
    
    // Internal signals for submodule control
    reg  conv_push_valid;
    reg  [1:0] conv_stream_sel;
    reg  kda_state_rd_en;
    reg  kda_state_wr_en;
    reg  mla_kv_append;
    reg  mla_cache_reset;
    
    // Activation register
    reg [D_MODEL*32-1:0] h_reg;
    
    assign token_ready = !busy && (current_phase == IDLE);
    
    // Main FSM
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
            // Default: clear one-cycle signals
            output_valid <= 1'b0;
            conv_push_valid <= 1'b0;
            kda_state_rd_en <= 1'b0;
            kda_state_wr_en <= 1'b0;
            mla_kv_append <= 1'b0;
            mla_cache_reset <= 1'b0;
            
            case (current_phase)
                IDLE: begin
                    if (seq_start) begin
                        // Reset all state for new sequence
                        mla_cache_reset <= 1'b1;
                        current_layer <= 4'd0;
                    end else if (token_valid) begin
                        busy <= 1'b1;
                        h_reg <= token_emb;
                        current_layer <= 4'd0;
                        phase_cycle <= 8'd0;
                        // Dispatch to first layer type
                        if (LAYER_PATTERN[0])
                            current_phase <= MLA_LATENT;
                        else
                            current_phase <= KDA_PROJ_Q;
                    end
                end
                
                //------------------------------------------
                // KDA Layer Phases
                //------------------------------------------
                KDA_PROJ_Q: begin
                    // GEMV: q = h @ W_q, takes multiple cycles
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= KDA_PROJ_K;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_PROJ_K: begin
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= KDA_PROJ_V;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_PROJ_V: begin
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= KDA_CONV_Q;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_CONV_Q: begin
                    // Push Q projection into conv history, compute conv output
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
                    // Compute alpha, beta gates
                    if (phase_cycle >= 8'd7) begin
                        current_phase <= KDA_STATE_RD;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_STATE_RD: begin
                    // Read S matrix from SRAM
                    kda_state_rd_en <= 1'b1;
                    current_phase <= KDA_STATE_UP;
                    phase_cycle <= 8'd0;
                end
                
                KDA_STATE_UP: begin
                    // Compute S' = alpha * S + beta * k * (v - k @ S)^T
                    // This is the expensive part: matrix-vector, outer product
                    if (phase_cycle >= 8'd63) begin  // 32×32 = 1024 ops
                        current_phase <= KDA_STATE_WR;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                KDA_STATE_WR: begin
                    // Write updated S back
                    kda_state_wr_en <= 1'b1;
                    current_phase <= KDA_OUTPUT;
                end
                
                KDA_OUTPUT: begin
                    // o = q @ S, then output projection
                    if (phase_cycle >= 8'd31) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                //------------------------------------------
                // MLA Layer Phases
                //------------------------------------------
                MLA_LATENT: begin
                    // lat = rmsnorm(h @ W_c)
                    if (phase_cycle >= 8'd31) begin
                        current_phase <= MLA_PROJ_Q;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_Q: begin
                    // qc = h @ W_qc, qr = h @ W_qr
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= MLA_PROJ_K;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_K: begin
                    // kc = lat @ W_kc, kr = h @ W_kr (shared across heads)
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= MLA_PROJ_V;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_PROJ_V: begin
                    // v = lat @ W_v
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= MLA_KV_STORE;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_KV_STORE: begin
                    // Append K, V to cache
                    mla_kv_append <= 1'b1;
                    current_phase <= MLA_ATTN;
                    phase_cycle <= 8'd0;
                end
                
                MLA_ATTN: begin
                    // softmax(Q @ K.T / sqrt(d)) @ V for each head
                    // Cycles scale with seq_len
                    if (phase_cycle >= 8'd127) begin  // worst case max_seq
                        current_phase <= MLA_OUTPUT;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                MLA_OUTPUT: begin
                    // Output projection
                    if (phase_cycle >= 8'd15) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                //------------------------------------------
                // Common Phases
                //------------------------------------------
                NORM: begin
                    if (phase_cycle >= 8'd7) begin
                        current_phase <= RESIDUAL;
                        phase_cycle <= 8'd0;
                    end else begin
                        phase_cycle <= phase_cycle + 1;
                    end
                end
                
                RESIDUAL: begin
                    // h = h + attention_output (already in h_reg update path)
                    current_phase <= NEXT_LAYER;
                end
                
                NEXT_LAYER: begin
                    if (current_layer >= N_LAYERS - 1) begin
                        current_phase <= DONE;
                    end else begin
                        current_layer <= current_layer + 1;
                        phase_cycle <= 8'd0;
                        // Dispatch to next layer type
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
