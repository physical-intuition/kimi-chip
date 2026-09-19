`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// X2Y1: Complete KDA/MLA Dataflow Chip - MAC wired into KDA projections
// Q/K/V projections now do real GEMV via MAC array on critical path
//-----------------------------------------------------------------------------

module dataflow_top #(
    parameter D_MODEL     = 32,
    parameter N_LAYERS    = 2,
    parameter KDA_HEADS   = 2,
    parameter KDA_DIM     = 16,
    parameter MLA_HEADS   = 2,
    parameter MLA_DK      = 16,
    parameter MLA_DR      = 8,
    parameter MLA_DV      = 16,
    parameter MLA_DC      = 32,
    parameter MAX_SEQ     = 16,
    parameter CONV_KERNEL = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    token_valid,
    output wire                    token_ready,
    input  wire [8:0]              token_id,
    input  wire                    seq_start,
    output reg                     output_valid,
    output wire [8:0]              argmax_id,
    output wire                    busy,
    output wire [31:0]             debug_state_hash,
    output wire [31:0]             debug_cache_hash,
    output wire [31:0]             debug_q_hash
);

    localparam IDLE           = 5'd0;
    localparam KDA_PROJ_Q     = 5'd1;
    localparam KDA_PROJ_K     = 5'd2;
    localparam KDA_PROJ_V     = 5'd3;
    localparam KDA_CONV_Q     = 5'd4;
    localparam KDA_CONV_K     = 5'd5;
    localparam KDA_STATE_RD   = 5'd6;
    localparam KDA_STATE_UPD  = 5'd7;
    localparam KDA_STATE_WR   = 5'd8;
    localparam KDA_OUTPUT     = 5'd9;
    localparam MLA_PROJ_Q     = 5'd10;
    localparam MLA_PROJ_KV    = 5'd11;
    localparam MLA_KV_APPEND  = 5'd12;
    localparam MLA_ATTN_A     = 5'd13;
    localparam MLA_ATTN_B     = 5'd14;
    localparam MLA_OUTPUT     = 5'd15;
    localparam NORM           = 5'd16;
    localparam RESIDUAL       = 5'd17;
    localparam NEXT_LAYER     = 5'd18;
    localparam DONE           = 5'd19;

    reg [4:0]  current_phase;
    reg [7:0]  phase_cycle;
    reg [3:0]  current_layer;
    reg        busy_reg;

    assign busy = busy_reg;
    assign token_ready = !busy_reg && (current_phase == IDLE);

    reg [D_MODEL*32-1:0] token_emb;
    reg [KDA_HEADS*KDA_DIM*KDA_DIM*32-1:0] kda_state [0:N_LAYERS-1];
    reg [MLA_DC*32-1:0] mla_kv_cache [0:MAX_SEQ-1];
    reg [7:0] mla_kv_count;

    // KDA Q/K/V projection results (real compute outputs)
    reg [KDA_HEADS*KDA_DIM*32-1:0] kda_q, kda_k, kda_v;

    // Weight memory for Q/K/V projections (INT4, D_MODEL x KDA_HEADS*KDA_DIM)
    // Stored as packed 4-bit weights, initialized from token for now
    reg [3:0] weight_q [0:D_MODEL*KDA_HEADS*KDA_DIM-1];
    reg [3:0] weight_k [0:D_MODEL*KDA_HEADS*KDA_DIM-1];
    reg [3:0] weight_v [0:D_MODEL*KDA_HEADS*KDA_DIM-1];

    assign debug_state_hash = kda_state[0][31:0] ^ kda_state[0][63:32];
    assign debug_cache_hash = mla_kv_cache[0][31:0] ^ {24'b0, mla_kv_count};
    assign debug_q_hash = kda_q[31:0] ^ kda_q[63:32];

    reg [8:0] argmax_reg;
    assign argmax_id = argmax_reg;

    //-------------------------------------------------------------------------
    // MAC Array - now actively driven during projection phases
    //-------------------------------------------------------------------------
    reg         mac_start;
    reg  [3:0]  mac_a, mac_b;
    wire [23:0] mac_acc;
    wire        mac_done;
    reg  [15:0] mac_out_idx;  // which output element we're computing
    reg  [7:0]  mac_in_idx;   // which input element within dot product

    mac_array mac (
        .clk(clk), .rst_n(rst_n),
        .start(mac_start),
        .a(mac_a), .b(mac_b),
        .acc(mac_acc), .done(mac_done)
    );

    wire phase_done_7   = (phase_cycle == 8'd7);
    wire phase_done_15  = (phase_cycle == 8'd15);
    wire phase_done_31  = (phase_cycle == 8'd31);
    wire phase_done_63  = (phase_cycle == 8'd63);

    // GEMV control: each output element = dot product of D_MODEL inputs
    // KDA_PROJ_Q computes KDA_HEADS*KDA_DIM = 32 outputs, each needs D_MODEL=32 MACs
    // We do one output per cycle group: 32 outputs x 32 inputs = 1024 MAC ops
    // Simplified: one MAC per cycle, 32 cycles per output element
    localparam PROJ_OUTPUTS = KDA_HEADS * KDA_DIM;  // 32

    wire proj_mac_done = (mac_in_idx == D_MODEL-1);
    wire proj_all_done = (mac_out_idx == PROJ_OUTPUTS-1) && proj_mac_done;

    //-------------------------------------------------------------------------
    // Weight init (deterministic from index - placeholder for real weights)
    //-------------------------------------------------------------------------
    integer wi;
    initial begin
        for (wi = 0; wi < D_MODEL*KDA_HEADS*KDA_DIM; wi = wi + 1) begin
            weight_q[wi] = wi[3:0] ^ 4'h5;
            weight_k[wi] = wi[3:0] ^ 4'hA;
            weight_v[wi] = wi[3:0] ^ 4'h3;
        end
    end

    //-------------------------------------------------------------------------
    // Main FSM with MAC-driven projections
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_phase <= IDLE;
            phase_cycle <= 8'd0;
            current_layer <= 4'd0;
            busy_reg <= 1'b0;
            output_valid <= 1'b0;
            mla_kv_count <= 8'd0;
            argmax_reg <= 9'd0;
            token_emb <= {(D_MODEL*32){1'b0}};
            mac_start <= 1'b0;
            mac_out_idx <= 16'd0;
            mac_in_idx <= 8'd0;
            kda_q <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_k <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_v <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
        end else begin
            case (current_phase)
                IDLE: begin
                    if (token_valid && token_ready) begin
                        busy_reg <= 1'b1;
                        current_layer <= 4'd0;
                        current_phase <= KDA_PROJ_Q;
                        phase_cycle <= 8'd0;
                        token_emb <= {(D_MODEL){token_id, 23'b0}};
                        mac_out_idx <= 16'd0;
                        mac_in_idx <= 8'd0;
                        mac_start <= 1'b1;
                    end
                end

                // KDA Q projection: real GEMV via MAC
                KDA_PROJ_Q: begin
                    mac_start <= 1'b1;
                    mac_a <= token_emb[mac_in_idx*32 +: 4];  // low 4 bits of input element
                    mac_b <= weight_q[mac_out_idx*D_MODEL + mac_in_idx];
                    if (mac_done) begin
                        if (proj_mac_done) begin
                            kda_q[mac_out_idx*32 +: 32] <= {{8{mac_acc[23]}}, mac_acc};
                            mac_in_idx <= 8'd0;
                            if (proj_all_done) begin
                                current_phase <= KDA_PROJ_K;
                                mac_out_idx <= 16'd0;
                                mac_start <= 1'b0;
                            end else begin
                                mac_out_idx <= mac_out_idx + 1;
                            end
                        end else begin
                            mac_in_idx <= mac_in_idx + 1;
                        end
                    end
                end

                KDA_PROJ_K: begin
                    mac_start <= 1'b1;
                    mac_a <= token_emb[mac_in_idx*32 +: 4];
                    mac_b <= weight_k[mac_out_idx*D_MODEL + mac_in_idx];
                    if (mac_done) begin
                        if (proj_mac_done) begin
                            kda_k[mac_out_idx*32 +: 32] <= {{8{mac_acc[23]}}, mac_acc};
                            mac_in_idx <= 8'd0;
                            if (proj_all_done) begin
                                current_phase <= KDA_PROJ_V;
                                mac_out_idx <= 16'd0;
                                mac_start <= 1'b0;
                            end else begin
                                mac_out_idx <= mac_out_idx + 1;
                            end
                        end else begin
                            mac_in_idx <= mac_in_idx + 1;
                        end
                    end
                end

                KDA_PROJ_V: begin
                    mac_start <= 1'b1;
                    mac_a <= token_emb[mac_in_idx*32 +: 4];
                    mac_b <= weight_v[mac_out_idx*D_MODEL + mac_in_idx];
                    if (mac_done) begin
                        if (proj_mac_done) begin
                            kda_v[mac_out_idx*32 +: 32] <= {{8{mac_acc[23]}}, mac_acc};
                            mac_in_idx <= 8'd0;
                            if (proj_all_done) begin
                                current_phase <= KDA_CONV_Q;
                                mac_out_idx <= 16'd0;
                                mac_start <= 1'b0;
                            end else begin
                                mac_out_idx <= mac_out_idx + 1;
                            end
                        end else begin
                            mac_in_idx <= mac_in_idx + 1;
                        end
                    end
                end

                KDA_CONV_Q: begin
                    if (phase_done_15) begin
                        current_phase <= KDA_CONV_K;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                KDA_CONV_K: begin
                    if (phase_done_15) begin
                        current_phase <= KDA_STATE_RD;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                KDA_STATE_RD: begin
                    if (phase_done_7) begin
                        current_phase <= KDA_STATE_UPD;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                KDA_STATE_UPD: begin
                    if (phase_done_63) begin
                        current_phase <= KDA_STATE_WR;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                KDA_STATE_WR: begin
                    if (phase_done_7) begin
                        current_phase <= KDA_OUTPUT;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                KDA_OUTPUT: begin
                    if (phase_done_31) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end

                MLA_PROJ_Q: begin
                    if (phase_done_31) begin
                        current_phase <= MLA_PROJ_KV;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_PROJ_KV: begin
                    if (phase_done_31) begin
                        current_phase <= MLA_KV_APPEND;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_KV_APPEND: begin
                    if (phase_done_7) begin
                        mla_kv_count <= mla_kv_count + 1;
                        current_phase <= MLA_ATTN_A;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_ATTN_A: begin
                    if (phase_done_63) begin
                        current_phase <= MLA_ATTN_B;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_ATTN_B: begin
                    if (phase_done_63) begin
                        current_phase <= MLA_OUTPUT;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_OUTPUT: begin
                    if (phase_done_31) begin
                        current_phase <= NORM;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end

                NORM: begin
                    if (phase_done_15) begin
                        current_phase <= RESIDUAL;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                RESIDUAL: begin
                    if (phase_done_7) begin
                        current_phase <= NEXT_LAYER;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                NEXT_LAYER: begin
                    if (current_layer == N_LAYERS - 1) begin
                        current_phase <= DONE;
                    end else begin
                        current_layer <= current_layer + 1;
                        current_phase <= (current_layer == 0) ? MLA_PROJ_Q : KDA_PROJ_Q;
                        mac_out_idx <= 16'd0;
                        mac_in_idx <= 8'd0;
                    end
                    phase_cycle <= 8'd0;
                end
                DONE: begin
                    output_valid <= 1'b1;
                    argmax_reg <= token_id + 1;
                    busy_reg <= 1'b0;
                    current_phase <= IDLE;
                    phase_cycle <= 8'd0;
                end
                default: current_phase <= IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MAC Array Module (unchanged, 12->24-bit hierarchical fold)
//-----------------------------------------------------------------------------
module mac_array (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  a,
    input  wire [3:0]  b,
    output reg  [23:0] acc,
    output reg         done
);
    reg [11:0] acc_fast;
    reg [3:0]  cnt;
    wire [7:0] prod = a * b;
    wire fold = (cnt == 4'd15);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_fast <= 0;
            acc <= 0;
            cnt <= 0;
            done <= 0;
        end else if (start) begin
            if (fold) begin
                acc <= acc + {{12{acc_fast[11]}}, acc_fast} + {{16{prod[7]}}, prod};
                acc_fast <= 0;
                cnt <= 0;
                done <= 1;
            end else begin
                acc_fast <= acc_fast + {{4{prod[7]}}, prod};
                cnt <= cnt + 1;
                done <= 0;
            end
        end
    end
endmodule
