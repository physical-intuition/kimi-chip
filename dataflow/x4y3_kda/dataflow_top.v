`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// X4Y3: X4Y2 bounds fixes + functional KDA (Kimi Delta Attention) operators.
// KDA layer (layer 0): q/k/v/beta/f/z projections on the unsigned INT4 MAC
// (signed operands via offset decomposition), causal depthwise conv k=4 + SiLU,
// per-head L2 norm, sigmoid/exp gates, delta-rule state update, gated RMSNorm
// and output projection. Fixed point Q16.16; bit-exact model: kda_model.py.
// Functional validation only (wide combinational helpers, not timing-clean).
//-----------------------------------------------------------------------------

module dataflow_top #(
    parameter D_MODEL     = 64,
    parameter N_LAYERS    = 2,
    parameter KDA_HEADS   = 2,
    parameter KDA_DIM     = 32,
    parameter MLA_HEADS   = 2,
    parameter MLA_DK      = 16,
    parameter MLA_DR      = 8,
    parameter MLA_DV      = 32,
    parameter MLA_DC      = 128,
    parameter MAX_SEQ     = 64,
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
    output reg  [31:0]             debug_state_hash,
    output reg  [31:0]             debug_cache_hash,
    output reg  [31:0]             debug_q_hash
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
    localparam KDA_OPROJ      = 5'd20;  // X4Y3: KDA output projection
    // X4Y3 phase meaning: 1/2/3 project q / k / (v,beta,f,z), 4 conv+SiLU,
    // 5 L2 norm q,k, 6 gates, 7 decay+delta update, 8 q.S, 9 gated RMSNorm.

    reg [4:0]  current_phase;
    reg [7:0]  phase_cycle;
    reg [3:0]  current_layer;
    reg        busy_reg;

    assign busy = busy_reg;
    // No eviction contract exists: a full sequence must be restarted.
    assign token_ready = !busy_reg && (current_phase == IDLE) &&
                         (seq_start || mla_kv_count < MAX_SEQ);

    reg [D_MODEL*32-1:0] token_emb;
    reg [KDA_HEADS*KDA_DIM*KDA_DIM*32-1:0] kda_state [0:N_LAYERS-1];
    // X4: KV cache lives in SRAM macro; word-addressed (entry*32 + word)
    reg  [10:0] kv_sram_addr;
    reg  [63:0] kv_sram_wdata;
    reg         kv_sram_we;
    reg         kv_sram_ce;
    wire [63:0] kv_sram_rdata;
    reg  [63:0] kv_word_r;      // 1-cycle staged SRAM read word

    kv_banked_2048x64 kv_sram (
        .clk(clk),
        .ce_in(kv_sram_ce),
        .we_in(kv_sram_we),
        .addr_in(kv_sram_addr),
        .wd_in(kv_sram_wdata),
        .w_mask_in(64'hFFFFFFFFFFFFFFFF),
        .rd_out(kv_sram_rdata)
    );
    reg [3:0] q_nib_r, kv_nib_r;
    reg [4:0] kv_word_off;
    reg [7:0] mla_kv_count;

    // KDA Q/K/V projection results (real compute outputs)
    reg [KDA_HEADS*KDA_DIM*32-1:0] kda_q, kda_k, kda_v;

    //-------------------------------------------------------------------------
    // X4Y3 KDA operator state. Values are signed Q16.16 unless noted.
    // kda_state[0] holds S: element (h,i,j) at word {h,i[4:0],j[4:0]}, i = key
    // channel, j = value channel. kda_state[1] unused (layer 1 is MLA).
    //-------------------------------------------------------------------------
    reg [7:0]  kx_u [0:63];           // KDA input codes, x = (code-128)/32 (placeholder embedding)
    reg [7:0]  kh_f [0:7];            // f low-rank intermediate codes
    reg [7:0]  kh_z [0:7];            // z low-rank intermediate codes
    reg [7:0]  ky_u [0:63];           // gated-norm output codes feeding o_proj
    reg signed [31:0] kda_f     [0:63];
    reg signed [31:0] kda_z     [0:63];
    reg signed [31:0] kda_alpha [0:63];
    reg signed [31:0] kda_attn  [0:63]; // q.S/sqrt(dh), before gated norm
    reg signed [31:0] kda_y     [0:63]; // gated RMSNorm output
    reg signed [31:0] kda_out   [0:63]; // output projection (KDA layer output)
    reg signed [31:0] kda_beta_raw [0:1];
    reg signed [31:0] kda_beta  [0:1];
    reg signed [31:0] conv_hist [0:575]; // [tap*192 + stream*64 + ch], tap0 = t-1

    // Projection engine (matrix 0 q,1 k,2 v,3 beta,4 f1,5 f2,6 z1,7 z2,8 o)
    reg [3:0]  pj_m;
    reg [6:0]  pj_o, pj_i;
    reg        pj_hi;
    reg [2:0]  pj_step, pj_drain;
    reg [23:0] pj_base, pj_dhi;
    reg [15:0] pj_sumx, pj_sumw;
    reg [3:0]  mac_cnt_mirror;        // equals mac.cnt: starts sampled mod 16
    wire [3:0] mac_cnt_next = mac_cnt_mirror + {3'b0, mac_start};

    // Sequential operator counters and procedural temporaries
    reg [11:0] kc_idx;
    reg [6:0]  kc_j;
    reg [1:0]  kc_sub;
    reg signed [63:0] kc_acc;
    reg [31:0] kc_root;
    reg signed [31:0] kc_u;
    reg [7:0]  t_src;
    reg [3:0]  t_w;
    reg [23:0] t_dlo;
    reg signed [31:0] t_raw, t_a, t_b, t_c, t_d, t_y;
    reg [10:0] t_s;
    reg [5:0]  t_e;
    integer    ki;

    `include "kda_luts.vh"

    function signed [31:0] sat32; input signed [63:0] x; begin
        if (x > 64'sd2147483647) sat32 = 32'sh7fffffff;
        else if (x < -64'sd2147483648) sat32 = 32'sh80000000;
        else sat32 = x[31:0];
    end endfunction
    function signed [7:0] sat8; input signed [31:0] x; begin
        if (x > 127) sat8 = 8'sd127; else if (x < -128) sat8 = -8'sd128; else sat8 = x[7:0];
    end endfunction
    function signed [31:0] mulq; input signed [31:0] a, b; reg signed [63:0] p; begin
        p = a; p = p * b; mulq = sat32(p >>> 16);
    end endfunction
    function signed [31:0] sadd; input signed [31:0] a, b; reg signed [63:0] p; begin
        p = a; p = p + b; sadd = sat32(p);
    end endfunction
    function signed [31:0] ssub; input signed [31:0] a, b; reg signed [63:0] p; begin
        p = a; p = p - b; ssub = sat32(p);
    end endfunction
    function signed [31:0] sigmoid_q; input signed [31:0] x; integer off, i, fr, t0, t1; begin
        if (x < -32'sd524288) off = 0; else if (x > 32'sd524287) off = 1048575; else off = x + 524288;
        i = off >>> 12; fr = off & 4095; t0 = sig_tab(i); t1 = sig_tab(i+1);
        sigmoid_q = t0 + (((t1 - t0) * fr) >>> 12);
    end endfunction
    function signed [31:0] exp5_q; input signed [31:0] s; integer i, fr, t0, t1; begin
        i = s >>> 8; fr = s & 255;
        if (i >= 256) exp5_q = exp5_tab(256);
        else begin t0 = exp5_tab(i); t1 = exp5_tab(i+1); exp5_q = t0 + (((t1 - t0) * fr) >>> 8); end
    end endfunction
    function [31:0] isqrt64; input [63:0] n; reg [63:0] rem, root, b; integer it; begin
        rem = n; root = 0; b = 64'h4000000000000000;
        for (it = 0; it < 32; it = it + 1) begin
            if (rem >= root + b) begin rem = rem - root - b; root = (root >> 1) + b; end
            else root = root >> 1;
            b = b >> 2;
        end
        isqrt64 = root[31:0];
    end endfunction
    function signed [31:0] qdiv; input signed [31:0] x; input [31:0] r; reg signed [63:0] num, den; begin
        num = x; num = num <<< 16; den = {32'b0, r}; qdiv = sat32(num / den);
    end endfunction
    // Deterministic placeholder parameters (identical formulas in kda_model.py)
    function [3:0] kda_w; input integer m, o, i; integer t; begin
        t = m*131 + o*67 + i*29 + ((o*i) % 13)*7; kda_w = t[3:0];
    end endfunction
    function [7:0] kda_xu; input integer t, i; integer s; begin
        s = t*73 + i*151 + ((t ^ i) & 31)*5; kda_xu = s[7:0];
    end endfunction
    function signed [31:0] kda_cw; input integer c, j; begin
        kda_cw = (((c*7 + j*3) % 9) - 4) * 8192;
    end endfunction
    function signed [31:0] kda_dtb; input integer c; begin kda_dtb = (((c*13) % 17) - 8) * 4096; end endfunction
    function signed [31:0] kda_onorm; input integer j; begin kda_onorm = 65536 + (((j*5) % 7) - 3) * 4096; end endfunction
    function integer kda_nout; input [3:0] m; begin
        case (m) 3: kda_nout = 2; 4, 6: kda_nout = 8; default: kda_nout = 64; endcase
    end endfunction
    function integer kda_nin; input [3:0] m; begin kda_nin = (m == 5 || m == 7) ? 8 : 64; end endfunction
    function integer kda_pad; input [3:0] m; begin kda_pad = (m == 5 || m == 7) ? 16 : 64; end endfunction
    function signed [31:0] conv_cell; input integer c; input signed [31:0] x0, x1, x2, x3; reg signed [63:0] s; begin
        s = mulq(kda_cw(c,0), x0); s = s + mulq(kda_cw(c,1), x1);
        s = s + mulq(kda_cw(c,2), x2); s = s + mulq(kda_cw(c,3), x3);
        conv_cell = sat32(s);
    end endfunction
    function signed [31:0] gate_alpha; input integer c; input signed [31:0] f; reg signed [63:0] t; reg signed [31:0] fb; begin
        t = f; t = t + kda_dtb(c); fb = sat32(t);
        t = fb; t = t * ((c < 32) ? 256 : 384); t = t >>> 8;   // A_h Q8.8 = 1.0, 1.5
        gate_alpha = exp5_q(sigmoid_q(sat32(t)));
    end endfunction

    // MLA query + attention scores (X3: real MAC compute)
    reg [MLA_HEADS*MLA_DK*32-1:0] mla_q;
    reg [MAX_SEQ*32-1:0] attn_scores;
    reg [7:0] attn_kv_idx;   // which KV cache entry
    reg [7:0] attn_dim_idx;  // which dim within dc

    // Weight memory for Q/K/V projections (INT4, D_MODEL x KDA_HEADS*KDA_DIM)
    // Stored as packed 4-bit weights, initialized from token for now
    reg [D_MODEL*KDA_HEADS*KDA_DIM*4-1:0] weight_q_sr;
    reg [D_MODEL*KDA_HEADS*KDA_DIM*4-1:0] weight_k_sr;
    reg [D_MODEL*KDA_HEADS*KDA_DIM*4-1:0] weight_v_sr;
    wire [3:0] weight_q_head = weight_q_pending[0] ? weight_q_sr[7:4] : weight_q_sr[3:0];
    wire [3:0] weight_k_head = weight_k_pending[0] ? weight_k_sr[7:4] : weight_k_sr[3:0];
    wire [3:0] weight_v_head = weight_v_pending[0] ? weight_v_sr[7:4] : weight_v_sr[3:0];

    // All debug hashes are sampled together, one cycle behind internal state.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_state_hash <= 0;
            debug_cache_hash <= 0;
            debug_q_hash <= 0;
        end else begin
            debug_state_hash <= kda_state[0][31:0] ^ kda_state[0][63:32];
            debug_cache_hash <= kv_word_r[31:0] ^ {24'b0, mla_kv_count};
            debug_q_hash <= kda_q[31:0] ^ kda_q[63:32];
        end
    end

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
    reg  [23:0] mac_pipe;     // pipeline stage: MAC output captured before writeback
    reg         mac_pipe_v;   // pipeline valid

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
    // KDA_PROJ_Q computes KDA_HEADS*KDA_DIM = 32 outputs, each needs D_MODEL=64 MACs
    // We do one output per cycle group: 32 outputs x 32 inputs = 1024 MAC ops
    // Simplified: one MAC per cycle, 32 cycles per output element
    localparam PROJ_OUTPUTS = KDA_HEADS * KDA_DIM;  // 32

    wire proj_mac_done = (mac_in_idx == D_MODEL-1);
    // MLA query and KDA projection have different output dimensions.
    wire [15:0] projection_outputs =
        (current_phase == MLA_PROJ_Q) ? MLA_HEADS*MLA_DK : PROJ_OUTPUTS;
    wire proj_all_done = (mac_out_idx == projection_outputs-1) && proj_mac_done;


    // Each 256-bit segment gets its own preserved enable register. The
    // one-cycle deferred shift cuts decode out of the high-fanout path.
    // Head bypass makes the externally consumed nibble cycle-equivalent.
    localparam WEIGHT_BITS = D_MODEL*KDA_HEADS*KDA_DIM*4;
    localparam WEIGHT_SEG_BITS = 256;
    localparam WEIGHT_SEGMENTS = (WEIGHT_BITS+WEIGHT_SEG_BITS-1)/WEIGHT_SEG_BITS;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_q_pending;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_k_pending;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_v_pending;
    wire shift_q = mac_pipe_v && ((current_phase == KDA_PROJ_Q) || (current_phase == MLA_PROJ_Q));
    wire shift_k = mac_pipe_v && (current_phase == KDA_PROJ_K);
    wire shift_v = mac_pipe_v && (current_phase == KDA_PROJ_V);
    genvar seg;
    generate for (seg=0; seg<WEIGHT_SEGMENTS; seg=seg+1) begin: weight_segment
        localparam LO = seg*WEIGHT_SEG_BITS;
        localparam WIDTH = (WEIGHT_BITS-LO < WEIGHT_SEG_BITS) ? WEIGHT_BITS-LO : WEIGHT_SEG_BITS;
        integer nib;
        initial begin
            for(nib=0; nib<WIDTH/4; nib=nib+1) begin
                weight_q_sr[LO+nib*4 +: 4] = ((LO/4+nib)%16) ^ 4'h5;
                weight_k_sr[LO+nib*4 +: 4] = ((LO/4+nib)%16) ^ 4'hA;
                weight_v_sr[LO+nib*4 +: 4] = ((LO/4+nib)%16) ^ 4'h3;
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                weight_q_pending[seg] <= 0;
                weight_k_pending[seg] <= 0;
                weight_v_pending[seg] <= 0;
            end else begin
                weight_q_pending[seg] <= shift_q;
                weight_k_pending[seg] <= shift_k;
                weight_v_pending[seg] <= shift_v;
            end
        end
        if(LO+WIDTH == WEIGHT_BITS) begin: last
            always @(posedge clk) begin
                if(weight_q_pending[seg]) weight_q_sr[LO +: WIDTH] <= {4'b0,weight_q_sr[LO+4 +: WIDTH-4]};
                if(weight_k_pending[seg]) weight_k_sr[LO +: WIDTH] <= {4'b0,weight_k_sr[LO+4 +: WIDTH-4]};
                if(weight_v_pending[seg]) weight_v_sr[LO +: WIDTH] <= {4'b0,weight_v_sr[LO+4 +: WIDTH-4]};
            end
        end else begin: middle
            always @(posedge clk) begin
                if(weight_q_pending[seg]) weight_q_sr[LO +: WIDTH] <= weight_q_sr[LO+4 +: WIDTH];
                if(weight_k_pending[seg]) weight_k_sr[LO +: WIDTH] <= weight_k_sr[LO+4 +: WIDTH];
                if(weight_v_pending[seg]) weight_v_sr[LO +: WIDTH] <= weight_v_sr[LO+4 +: WIDTH];
            end
        end
    end endgenerate

    //-------------------------------------------------------------------------
    // Weight init (deterministic from index - placeholder for real weights)
    //-------------------------------------------------------------------------
    integer wi;
    initial begin



        for (wi = 0; wi < D_MODEL*KDA_HEADS*KDA_DIM; wi = wi + 1) begin



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
            mac_start <= 1'b0;
            mac_out_idx <= 16'd0;
            mac_in_idx <= 8'd0;
            mac_pipe <= 24'd0;
            mac_pipe_v <= 1'b0;
            kda_q <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_k <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_v <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            mla_q <= {(MLA_HEADS*MLA_DK*32){1'b0}};
            attn_scores <= {(MAX_SEQ*32){1'b0}};
            attn_kv_idx <= 8'd0;
            attn_dim_idx <= 8'd0;
            kv_sram_addr <= 11'd0;
            kv_sram_wdata <= 64'd0;
            kv_sram_we <= 1'b0;
            kv_sram_ce <= 1'b0;
            kv_word_r <= 64'd0;
            kv_word_off <= 5'd0;
            q_nib_r <= 0;
            kv_nib_r <= 0;
            pj_m <= 0; pj_o <= 0; pj_i <= 0; pj_hi <= 1'b1; pj_step <= 0; pj_drain <= 0;
            pj_base <= 0; pj_dhi <= 0; pj_sumx <= 0; pj_sumw <= 0; mac_cnt_mirror <= 0;
            kc_idx <= 0; kc_j <= 0; kc_sub <= 0; kc_acc <= 0; kc_root <= 0; kc_u <= 0;
            kda_state[0] <= 0;
            for (ki = 0; ki < 576; ki = ki + 1) conv_hist[ki] <= 0;
        end else begin
            output_valid <= 1'b0; // one-cycle completion pulse
            if (mac_start) mac_cnt_mirror <= mac_cnt_mirror + 4'd1;
            case (current_phase)
                IDLE: begin
                    if (token_valid && token_ready) begin
                        if (seq_start) mla_kv_count <= 0;
                        busy_reg <= 1'b1;
                        current_layer <= 4'd0;
                        current_phase <= KDA_PROJ_Q;
                        phase_cycle <= 8'd0;
                        token_emb[511:0] <= {(16){token_id, 23'b0}};
                        token_emb[1535:512] <= 0;
                        token_emb[2047:1536] <= 0;
                        argmax_reg <= token_id + 9'd1;
                        mac_out_idx <= 16'd0;
                        mac_in_idx <= 8'd0;
                        mac_pipe_v <= 1'b0;
                        for (ki = 0; ki < 64; ki = ki + 1) kx_u[ki] <= kda_xu(token_id, ki);
                        if (seq_start) begin  // new sequence: clear conv history and S
                            kda_state[0] <= 0;
                            for (ki = 0; ki < 576; ki = ki + 1) conv_hist[ki] <= 0;
                        end
                        pj_m <= 0; pj_o <= 0; pj_i <= 0; pj_hi <= 1'b1;
                        pj_step <= 0; pj_drain <= 0;
                    end
                end

                // X4Y3 projection engine on the unsigned INT4 MAC. Signed dot
                // sum_i x_i*w_i with x=xu-128, w=wu-8 is computed exactly as
                // 16*sum(xu_hi*wu) + sum(xu_lo*wu) - 8*sum(xu) - 128*sum(wu) + 1024*N,
                // where each pass result is the persistent-accumulator delta.
                KDA_PROJ_Q, KDA_PROJ_K, KDA_PROJ_V, KDA_OPROJ: begin
                    mac_pipe_v <= 1'b0;
                    case (pj_step)
                        3'd0: begin // align MAC fold counter with zero operands
                            mac_a <= 4'd0; mac_b <= 4'd0;
                            if (mac_cnt_next == 4'd0) begin
                                mac_start <= 1'b0; pj_step <= 3'd1; pj_drain <= 0;
                            end else mac_start <= 1'b1;
                        end
                        3'd1, 3'd3, 3'd5: begin // drain MAC pipeline
                            mac_start <= 1'b0;
                            if (pj_drain == 3'd5) begin
                                pj_drain <= 0; pj_i <= 0;
                                pj_base <= mac_acc;
                                if (pj_step == 3'd1) begin
                                    pj_hi <= 1'b1; pj_sumx <= 0; pj_sumw <= 0; pj_step <= 3'd2;
                                end else if (pj_step == 3'd3) begin
                                    pj_dhi <= mac_acc - pj_base; pj_hi <= 1'b0; pj_step <= 3'd4;
                                end else begin
                                    t_dlo = mac_acc - pj_base;
                                    t_raw = $signed({8'b0, pj_dhi}) * 16 + $signed({8'b0, t_dlo})
                                          - 8 * $signed({16'b0, pj_sumx}) - 128 * $signed({16'b0, pj_sumw})
                                          + 1024 * kda_nin(pj_m);
                                    case (pj_m)
                                        4'd0: kda_q[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd1: kda_k[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd2: kda_v[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd3: kda_beta_raw[pj_o[0]] <= t_raw;
                                        4'd4: kh_f[pj_o[2:0]] <= sat8(t_raw >>> 6) + 8'd128;
                                        4'd5: kda_f[pj_o[5:0]] <= t_raw * 32;
                                        4'd6: kh_z[pj_o[2:0]] <= sat8(t_raw >>> 6) + 8'd128;
                                        4'd7: kda_z[pj_o[5:0]] <= t_raw * 32;
                                        default: kda_out[pj_o[5:0]] <= t_raw * 32;
                                    endcase
                                    pj_hi <= 1'b1; pj_sumx <= 0; pj_sumw <= 0; pj_step <= 3'd2;
                                    if (pj_o == kda_nout(pj_m) - 1) begin
                                        pj_o <= 0;
                                        case (pj_m)
                                            4'd0: begin pj_m <= 4'd1; current_phase <= KDA_PROJ_K; end
                                            4'd1: begin pj_m <= 4'd2; current_phase <= KDA_PROJ_V; end
                                            4'd7: begin current_phase <= KDA_CONV_Q; kc_idx <= 0; end
                                            4'd8: begin current_phase <= NORM; phase_cycle <= 8'd0; end
                                            default: pj_m <= pj_m + 4'd1;
                                        endcase
                                    end else pj_o <= pj_o + 1;
                                end
                            end else pj_drain <= pj_drain + 1;
                        end
                        default: begin // 2 / 4: issue one operand pair per cycle
                            mac_start <= 1'b1;
                            case (pj_m)
                                4'd5: t_src = kh_f[pj_i[2:0]];
                                4'd7: t_src = kh_z[pj_i[2:0]];
                                4'd8: t_src = ky_u[pj_i[5:0]];
                                default: t_src = kx_u[pj_i[5:0]];
                            endcase
                            t_w = kda_w(pj_m, pj_o, pj_i);
                            if (pj_i < kda_nin(pj_m)) begin
                                mac_a <= pj_hi ? t_src[7:4] : t_src[3:0];
                                mac_b <= t_w;
                                if (pj_hi) begin
                                    pj_sumx <= pj_sumx + t_src;
                                    pj_sumw <= pj_sumw + t_w;
                                end
                            end else begin
                                mac_a <= 4'd0; mac_b <= 4'd0;
                            end
                            if (pj_i == kda_pad(pj_m) - 1) begin
                                pj_step <= pj_step + 3'd1; pj_drain <= 0;
                            end else pj_i <= pj_i + 1;
                        end
                    endcase
                end

                // Causal depthwise conv (kernel 4) + SiLU, one channel per cycle
                KDA_CONV_Q: begin
                    case (kc_idx[7:6])
                        2'd0: t_a = kda_q[kc_idx[5:0]*32 +: 32];
                        2'd1: t_a = kda_k[kc_idx[5:0]*32 +: 32];
                        default: t_a = kda_v[kc_idx[5:0]*32 +: 32];
                    endcase
                    t_b = conv_hist[kc_idx]; t_c = conv_hist[192 + kc_idx]; t_d = conv_hist[384 + kc_idx];
                    t_y = conv_cell(kc_idx, t_a, t_b, t_c, t_d);
                    t_y = mulq(t_y, sigmoid_q(t_y));
                    case (kc_idx[7:6])
                        2'd0: kda_q[kc_idx[5:0]*32 +: 32] <= t_y;
                        2'd1: kda_k[kc_idx[5:0]*32 +: 32] <= t_y;
                        default: kda_v[kc_idx[5:0]*32 +: 32] <= t_y;
                    endcase
                    conv_hist[384 + kc_idx] <= t_c;
                    conv_hist[192 + kc_idx] <= t_b;
                    conv_hist[kc_idx] <= t_a;
                    if (kc_idx == 12'd191) begin
                        current_phase <= KDA_CONV_K;
                        kc_idx <= 0; kc_j <= 0; kc_sub <= 0; kc_acc <= 0;
                    end else kc_idx <= kc_idx + 1;
                end

                // Per-head L2 norm of q (groups 0,1) and k (groups 2,3)
                KDA_CONV_K: begin
                    t_e = {kc_j[0], kc_idx[4:0]};
                    t_a = kc_j[1] ? kda_k[t_e*32 +: 32] : kda_q[t_e*32 +: 32];
                    case (kc_sub)
                        2'd0: begin
                            kc_acc <= kc_acc + t_a * t_a;
                            if (kc_idx[4:0] == 5'd31) begin kc_sub <= 2'd1; kc_idx <= 0; end
                            else kc_idx <= kc_idx + 1;
                        end
                        2'd1: begin
                            kc_root <= isqrt64(kc_acc + 64'sd4295);  // eps = 1e-6 in Q32
                            kc_sub <= 2'd2;
                        end
                        default: begin
                            if (kc_j[1]) kda_k[t_e*32 +: 32] <= qdiv(t_a, kc_root);
                            else         kda_q[t_e*32 +: 32] <= qdiv(t_a, kc_root);
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0; kc_sub <= 2'd0;
                                if (kc_j[1:0] == 2'd3) begin current_phase <= KDA_STATE_RD; kc_j <= 0; end
                                else kc_j <= kc_j + 1;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Gates: beta = sigmoid(beta_in), alpha = exp(-5*sigmoid(A_h*(f+dt_bias)))
                KDA_STATE_RD: begin
                    if (kc_idx == 0) begin
                        kda_beta[0] <= sigmoid_q(kda_beta_raw[0] * 32);
                        kda_beta[1] <= sigmoid_q(kda_beta_raw[1] * 32);
                    end
                    kda_alpha[kc_idx[5:0]] <= gate_alpha(kc_idx[5:0], kda_f[kc_idx[5:0]]);
                    if (kc_idx == 12'd63) begin
                        current_phase <= KDA_STATE_UPD;
                        kc_idx <= 0; kc_j <= 0; kc_sub <= 0; kc_acc <= 0;
                    end else kc_idx <= kc_idx + 1;
                end

                // S = diag(alpha) S; per column j: u = v - k.S; S += outer(beta*k, u)
                KDA_STATE_UPD: begin
                    t_s = {kc_j[5], kc_idx[4:0], kc_j[4:0]};
                    t_e = {kc_j[5], kc_idx[4:0]};
                    case (kc_sub)
                        2'd0: begin
                            kda_state[0][kc_idx[10:0]*32 +: 32] <=
                                mulq(kda_state[0][kc_idx[10:0]*32 +: 32], kda_alpha[kc_idx[10:5]]);
                            if (kc_idx == 12'd2047) begin kc_idx <= 0; kc_j <= 0; kc_sub <= 2'd1; kc_acc <= 0; end
                            else kc_idx <= kc_idx + 1;
                        end
                        2'd1: begin
                            t_a = kda_k[t_e*32 +: 32];
                            t_b = kda_state[0][t_s*32 +: 32];
                            kc_acc <= kc_acc + t_a * t_b;
                            if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 2'd2; end
                            else kc_idx <= kc_idx + 1;
                        end
                        2'd2: begin
                            kc_u <= ssub(kda_v[kc_j[5:0]*32 +: 32], sat32(kc_acc >>> 16));
                            kc_sub <= 2'd3;
                        end
                        default: begin
                            t_a = kda_k[t_e*32 +: 32];
                            t_b = kda_state[0][t_s*32 +: 32];
                            kda_state[0][t_s*32 +: 32] <= sadd(t_b, mulq(mulq(kda_beta[kc_j[5]], t_a), kc_u));
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0;
                                if (kc_j == 7'd63) begin current_phase <= KDA_STATE_WR; kc_j <= 0; kc_sub <= 2'd0; end
                                else begin kc_j <= kc_j + 1; kc_sub <= 2'd1; end
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Readout: attn_j = (q . S[:,j]) / sqrt(dh)
                KDA_STATE_WR: begin
                    t_s = {kc_j[5], kc_idx[4:0], kc_j[4:0]};
                    t_e = {kc_j[5], kc_idx[4:0]};
                    if (kc_sub == 2'd0) begin
                        t_a = kda_q[t_e*32 +: 32];
                        t_b = kda_state[0][t_s*32 +: 32];
                        kc_acc <= kc_acc + t_a * t_b;
                        if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 2'd1; end
                        else kc_idx <= kc_idx + 1;
                    end else begin
                        kda_attn[kc_j[5:0]] <= mulq(sat32(kc_acc >>> 16), 32'sd11585);
                        kc_acc <= 0; kc_sub <= 2'd0;
                        if (kc_j == 7'd63) begin current_phase <= KDA_OUTPUT; kc_j <= 0; end
                        else kc_j <= kc_j + 1;
                    end
                end

                // Gated RMSNorm per head: rmsnorm(attn)*onorm*sigmoid(z), then o_proj
                KDA_OUTPUT: begin
                    t_e = {kc_j[0], kc_idx[4:0]};
                    case (kc_sub)
                        2'd0: begin
                            t_a = kda_attn[t_e];
                            kc_acc <= kc_acc + t_a * t_a;
                            if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 2'd1; end
                            else kc_idx <= kc_idx + 1;
                        end
                        2'd1: begin
                            kc_root <= isqrt64((kc_acc >>> 5) + 64'sd4295);
                            kc_sub <= 2'd2;
                        end
                        default: begin
                            t_y = mulq(mulq(qdiv(kda_attn[t_e], kc_root), kda_onorm(kc_idx[4:0])),
                                       sigmoid_q(kda_z[t_e]));
                            kda_y[t_e] <= t_y;
                            ky_u[t_e] <= sat8(t_y >>> 11) + 8'd128;
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0; kc_sub <= 2'd0;
                                if (kc_j[0]) begin
                                    current_phase <= KDA_OPROJ; kc_j <= 0;
                                    pj_m <= 4'd8; pj_o <= 0; pj_i <= 0; pj_step <= 0; pj_drain <= 0;
                                end else kc_j <= kc_j + 1;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                MLA_PROJ_Q: begin
                    // real GEMV: mla_q[i] = sum_j token_emb[j] * w[i,j], 32 outputs x 32 MACs
                    mac_start <= 1'b1;
                    mac_a <= token_emb[mac_in_idx*32 +: 4];
                    mac_b <= weight_q_head;
                    mac_pipe_v <= mac_done;
                    if (mac_done) mac_pipe <= mac_acc;
                    if (mac_pipe_v) begin
                        if (proj_mac_done) begin
                            mla_q[mac_out_idx*32 +: 32] <= {{8{mac_pipe[23]}}, mac_pipe};
                            mac_in_idx <= 8'd0;
                            if (proj_all_done) begin
                                current_phase <= MLA_PROJ_KV;
                                mac_out_idx <= 16'd0;
                                mac_start <= 1'b0;
                            end else begin
                                mac_out_idx <= mac_out_idx + 1;
                            end
                        end else begin
                            mac_in_idx <= mac_in_idx + 1;
                        end
                        // Weight storage commits through distributed delayed enables.
                    end
                end
                MLA_PROJ_KV: begin
                    if (phase_done_31) begin
                        current_phase <= MLA_KV_APPEND;
                        phase_cycle <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_KV_APPEND: begin
                    // X4: stream 32 x 32b words into SRAM over 32 cycles
                    kv_sram_ce <= 1'b1;
                    kv_sram_we <= 1'b1;
                    kv_sram_addr <= {mla_kv_count[5:0], 5'b00000} + phase_cycle[4:0];  // entry*32 + word_idx
                    kv_sram_wdata <= token_emb[phase_cycle[4:0]*64 +: 64];
                    if (phase_done_31) begin
                        mla_kv_count <= mla_kv_count + 1;
                        current_phase <= MLA_ATTN_A;
                        phase_cycle <= 8'd0;
                        attn_kv_idx <= 8'd0;
                        attn_dim_idx <= 8'd0;
                    end else phase_cycle <= phase_cycle + 1;
                end
                MLA_ATTN_A: begin
                    // X4Y4: operands staged one cycle ahead (q_nib_r/kv_nib_r) so MAC inputs
                    // come from registers, not array muxes
                    kv_sram_ce <= 1'b1;
                    kv_sram_we <= 1'b0;
                    kv_sram_addr <= {attn_kv_idx[5:0], 5'b00000} + (attn_dim_idx[7:3] + 1);
                    mac_start <= 1'b1;
                    mac_a <= q_nib_r;
                    mac_b <= kv_nib_r;
                    // X4Y3: mla_q has 32 entries (no up-projection yet); dims >= 32 are
                    // explicit zeros instead of out-of-range X that poisoned the shared
                    // persistent MAC accumulator used by the KDA projections.
                    q_nib_r  <= (attn_dim_idx < MLA_HEADS*MLA_DK) ? mla_q[attn_dim_idx*32 +: 4] : 4'd0;
                    kv_nib_r <= kv_word_r[attn_dim_idx[3:0]*4 +: 4];
                    mac_pipe_v <= mac_done;
                    if (mac_done) mac_pipe <= mac_acc;
                    if (mac_pipe_v) begin
                        if (attn_dim_idx[4:0] == 5'd31) kv_word_r <= kv_sram_rdata;
                        if (attn_dim_idx == MLA_DC-1) begin
                            attn_scores[attn_kv_idx*32 +: 32] <= {{8{mac_pipe[23]}}, mac_pipe};
                            attn_dim_idx <= 8'd0;
                            if (attn_kv_idx == mla_kv_count-1) begin
                                current_phase <= MLA_ATTN_B;
                                attn_kv_idx <= 8'd0;
                                mac_start <= 1'b0;
                            end else begin
                                attn_kv_idx <= attn_kv_idx + 1;
                            end
                        end else begin
                            attn_dim_idx <= attn_dim_idx + 1;
                        end
                    end
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
    // X3Y4: partial products -> product reduction -> accumulation.
    // Throughput stays one operand/cycle; done gains one cycle of latency.
    reg [5:0] partial_lo, partial_hi;
    reg partial_v, partial_fold;
    reg [7:0]  prod_r;
    reg        prod_v;
    reg [11:0] acc_fast;
    reg [3:0]  cnt;
    reg        fold_r;

    wire [5:0] low_c = {2'b0, a & {4{b[0]}}} +
                               {1'b0, a & {4{b[1]}} , 1'b0};
    wire [5:0] high_c = {2'b0, a & {4{b[2]}}} +
                                {1'b0, a & {4{b[3]}} , 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_lo <= 0; partial_hi <= 0;
            partial_v <= 0; partial_fold <= 0;
            prod_r <= 0; prod_v <= 0; fold_r <= 0;
            acc_fast <= 0; acc <= 0; cnt <= 0; done <= 0;
        end else begin
            // Stage 1: independent two-bit partial products.
            partial_v <= start;
            partial_fold <= start && (cnt == 4'd15);
            if (start) begin
                partial_lo <= low_c;
                partial_hi <= high_c;
                cnt <= (cnt == 4'd15) ? 4'd0 : cnt + 1;
            end
            // Stage 2: reduce the two partial products.
            prod_v <= partial_v;
            fold_r <= partial_fold;
            if (partial_v) prod_r <= {2'b0, partial_lo} + {partial_hi, 2'b0};
            // Stage 3: accumulate
            done <= 0;
            if (prod_v) begin
                if (fold_r) begin
                    acc <= acc + {12'b0, acc_fast} + {16'b0, prod_r};
                    acc_fast <= 0;
                    done <= 1;
                end else begin
                    acc_fast <= acc_fast + {4'b0, prod_r};
                end
            end
        end
    end
endmodule
