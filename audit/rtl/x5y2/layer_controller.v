`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Layer Controller for Hybrid KDA/MLA Architecture
// X5Y2: Registered next_phase to break FSM combinational path
//
// Key optimization: compute next_phase combinationally, register it
// Breaks critical path from phase_done -> case -> current_phase
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

    // FSM states
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
    localparam MLA_ATTN     = 5'd17;
    localparam MLA_OUTPUT   = 5'd18;
    localparam NORM         = 5'd19;
    localparam RESIDUAL     = 5'd20;
    localparam NEXT_LAYER   = 5'd21;
    localparam DONE         = 5'd22;
    
    // Phase cycle counter
    reg [7:0] phase_cycle;
    
    // PRE-COMPUTED phase done signals (registered, one cycle ahead)
    reg phase_done_7;
    reg phase_done_15;
    reg phase_done_31;
    reg phase_done_63;
    reg phase_done_127;
    
    // X5Y2: next_phase computed combinationally, then registered
    reg [4:0] next_phase;
    reg phase_transition;
    
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
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_done_7   <= 1'b0;
            phase_done_15  <= 1'b0;
            phase_done_31  <= 1'b0;
            phase_done_63  <= 1'b0;
            phase_done_127 <= 1'b0;
        end else begin
            phase_done_7   <= (phase_cycle == 8'd6);
            phase_done_15  <= (phase_cycle == 8'd14);
            phase_done_31  <= (phase_cycle == 8'd30);
            phase_done_63  <= (phase_cycle == 8'd62);
            phase_done_127 <= (phase_cycle == 8'd126);
        end
    end
    
    // X5Y2: Combinational next_phase computation
    always @(*) begin
        next_phase = current_phase;
        phase_transition = 1'b0;
        
        case (current_phase)
            IDLE: begin
                if (token_valid) begin
                    if (LAYER_PATTERN[0])
                        next_phase = MLA_LATENT;
                    else
                        next_phase = KDA_PROJ_Q;
                    phase_transition = 1'b1;
                end
            end
            
            KDA_PROJ_Q: if (phase_done_15) begin
                next_phase = KDA_PROJ_K;
                phase_transition = 1'b1;
            end
            
            KDA_PROJ_K: if (phase_done_15) begin
                next_phase = KDA_PROJ_V;
                phase_transition = 1'b1;
            end
            
            KDA_PROJ_V: if (phase_done_15) begin
                next_phase = KDA_CONV_Q;
                phase_transition = 1'b1;
            end
            
            KDA_CONV_Q: begin
                next_phase = KDA_CONV_K;
                phase_transition = 1'b1;
            end
            
            KDA_CONV_K: begin
                next_phase = KDA_CONV_V;
                phase_transition = 1'b1;
            end
            
            KDA_CONV_V: begin
                next_phase = KDA_GATES;
                phase_transition = 1'b1;
            end
            
            KDA_GATES: if (phase_done_7) begin
                next_phase = KDA_STATE_RD;
                phase_transition = 1'b1;
            end
            
            KDA_STATE_RD: begin
                next_phase = KDA_STATE_UP;
                phase_transition = 1'b1;
            end
            
            KDA_STATE_UP: if (phase_done_63) begin
                next_phase = KDA_STATE_WR;
                phase_transition = 1'b1;
            end
            
            KDA_STATE_WR: begin
                next_phase = KDA_OUTPUT;
                phase_transition = 1'b1;
            end
            
            KDA_OUTPUT: if (phase_done_31) begin
                next_phase = NORM;
                phase_transition = 1'b1;
            end
            
            MLA_LATENT: if (phase_done_31) begin
                next_phase = MLA_PROJ_Q;
                phase_transition = 1'b1;
            end
            
            MLA_PROJ_Q: if (phase_done_15) begin
                next_phase = MLA_PROJ_K;
                phase_transition = 1'b1;
            end
            
            MLA_PROJ_K: if (phase_done_15) begin
                next_phase = MLA_PROJ_V;
                phase_transition = 1'b1;
            end
            
            MLA_PROJ_V: if (phase_done_15) begin
                next_phase = MLA_KV_STORE;
                phase_transition = 1'b1;
            end
            
            MLA_KV_STORE: begin
                next_phase = MLA_ATTN;
                phase_transition = 1'b1;
            end
            
            MLA_ATTN: if (phase_done_127) begin
                next_phase = MLA_OUTPUT;
                phase_transition = 1'b1;
            end
            
            MLA_OUTPUT: if (phase_done_15) begin
                next_phase = NORM;
                phase_transition = 1'b1;
            end
            
            NORM: if (phase_done_7) begin
                next_phase = RESIDUAL;
                phase_transition = 1'b1;
            end
            
            RESIDUAL: begin
                next_phase = NEXT_LAYER;
                phase_transition = 1'b1;
            end
            
            NEXT_LAYER: begin
                if (current_layer >= N_LAYERS - 1) begin
                    next_phase = DONE;
                end else begin
                    if (LAYER_PATTERN[current_layer + 1])
                        next_phase = MLA_LATENT;
                    else
                        next_phase = KDA_PROJ_Q;
                end
                phase_transition = 1'b1;
            end
            
            DONE: begin
                next_phase = IDLE;
                phase_transition = 1'b1;
            end
            
            default: next_phase = IDLE;
        endcase
    end
    
    // X5Y2: Registered state update
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
            // Register the next phase
            current_phase <= next_phase;
            
            // Phase cycle counter
            if (phase_transition) begin
                phase_cycle <= 8'd0;
            end else begin
                phase_cycle <= phase_cycle + 1;
            end
            
            // Default control signals
            output_valid <= 1'b0;
            conv_push_valid <= 1'b0;
            kda_state_rd_en <= 1'b0;
            kda_state_wr_en <= 1'b0;
            mla_kv_append <= 1'b0;
            mla_cache_reset <= 1'b0;
            
            // Control signal generation based on NEXT phase (1 cycle ahead)
            case (next_phase)
                IDLE: begin
                    if (current_phase == DONE) begin
                        busy <= 1'b0;
                        current_layer <= 4'd0;
                    end
                    if (seq_start) begin
                        mla_cache_reset <= 1'b1;
                        current_layer <= 4'd0;
                    end
                end
                
                KDA_PROJ_Q: begin
                    if (current_phase == IDLE && token_valid) begin
                        busy <= 1'b1;
                        h_reg <= token_emb;
                        current_layer <= 4'd0;
                    end
                end
                
                MLA_LATENT: begin
                    if (current_phase == IDLE && token_valid) begin
                        busy <= 1'b1;
                        h_reg <= token_emb;
                        current_layer <= 4'd0;
                    end
                end
                
                KDA_CONV_Q: begin
                    conv_stream_sel <= 2'd0;
                    conv_push_valid <= 1'b1;
                end
                
                KDA_CONV_K: begin
                    conv_stream_sel <= 2'd1;
                    conv_push_valid <= 1'b1;
                end
                
                KDA_CONV_V: begin
                    conv_stream_sel <= 2'd2;
                    conv_push_valid <= 1'b1;
                end
                
                KDA_STATE_RD: begin
                    kda_state_rd_en <= 1'b1;
                end
                
                KDA_STATE_WR: begin
                    kda_state_wr_en <= 1'b1;
                end
                
                MLA_KV_STORE: begin
                    mla_kv_append <= 1'b1;
                end
                
                NEXT_LAYER: begin
                    if (current_layer < N_LAYERS - 1) begin
                        current_layer <= current_layer + 1;
                    end
                end
                
                DONE: begin
                    output_valid <= 1'b1;
                    output_h <= h_reg;
                end
                
                default: begin
                    // No control signals
                end
            endcase
        end
    end

endmodule
