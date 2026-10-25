`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// X4Y4: X4Y3 KDA + functional NoPE MLA (layer 1).
// MLA: latent compression h@wc + RMSNorm(knorm), queries h@wq_c / h@wq_r,
// shared key h@wk_r, decompression lat@wk_c / lat@wv, KV cache append in
// SRAM, scores q.k/sqrt(dk+dr) over the valid cache, LUT softmax, value
// weighted sum and output projection. MLA weights are the reference int4
// format (q, z, Q3.12 s per group/column, group = min(GROUP_SIZE, fan_in)),
// dequantized in the projection engine. Bit-exact model: mla_model.py.
// KDA changes vs X4Y3: f/z low rank 32 (was 8), gated-RMSNorm eps 1e-5.
// The MLA input h is STAGED (placeholder codes, see mla_model.h_u): the
// residual / norm / MoE path that produces it in the reference is X4Y5.
// Functional validation only (wide combinational helpers, not timing-clean).
//-----------------------------------------------------------------------------

module dataflow_top #(
    parameter D_MODEL     = 64,
    parameter N_LAYERS    = 2,
    parameter KDA_HEADS   = 2,
    parameter KDA_DIM     = 32,
    parameter MLA_HEADS   = 2,
    parameter MLA_DK      = 32,
    parameter MLA_DR      = 16,
    parameter MLA_DV      = 32,
    parameter MLA_DC      = 128,
    parameter MAX_SEQ     = 64,
    parameter CONV_KERNEL = 4,
    parameter GROUP_SIZE  = 128
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
    localparam MLA_PROJ_Q     = 5'd10;  // h projections: wc, wq_c, wq_r, wk_r
    localparam MLA_PROJ_KV    = 5'd11;  // latent decompression: wk_c, wv
    localparam MLA_KV_APPEND  = 5'd12;  // 72 SRAM words at entry mla_kv_count
    localparam MLA_ATTN_A     = 5'd13;  // scores over valid cache entries
    localparam MLA_ATTN_B     = 5'd14;  // softmax
    localparam MLA_OUTPUT     = 5'd15;  // ctx = p @ V
    localparam NORM           = 5'd16;
    localparam RESIDUAL       = 5'd17;
    localparam NEXT_LAYER     = 5'd18;
    localparam DONE           = 5'd19;
    localparam KDA_OPROJ      = 5'd20;
    localparam MLA_LAT_NORM   = 5'd21;  // RMSNorm(knorm) of the latent + INT8 codes
    localparam MLA_CTX_Q      = 5'd22;  // ctx INT8 codes
    localparam MLA_OPROJ      = 5'd23;  // output projection o

    // MLA cache geometry: kc (H*dk) + kr (dr) + v (H*dv) Q16.16 values per position
    localparam KV_WORDS  = (MLA_HEADS*MLA_DK + MLA_DR + MLA_HEADS*MLA_DV) / 2;   // 72
    localparam KR_WORD   = MLA_HEADS*MLA_DK/2;                                   // 32
    localparam V_WORD    = KR_WORD + MLA_DR/2;                                   // 40
    localparam QK_WORDS  = (MLA_DK + MLA_DR) / 2;                                // 24
    // Reference int4 weight ROM layout (mla_model.layout), engine matrices 9..15
    localparam G_D   = (GROUP_SIZE < D_MODEL) ? GROUP_SIZE : D_MODEL;
    localparam G_DC  = (GROUP_SIZE < MLA_DC) ? GROUP_SIZE : MLA_DC;
    localparam NG_D  = D_MODEL / G_D;
    localparam NG_DC = MLA_DC / G_DC;
    localparam MLA_NQ = 17920;
    localparam MLA_NS = (MLA_DC + 64 + 32 + 16 + 64) * NG_D + 2 * 64 * NG_DC;

    //-------------------------------------------------------------------------
    // Declarations
    //-------------------------------------------------------------------------
    reg [4:0]  current_phase;
    reg [7:0]  phase_cycle;
    reg [3:0]  current_layer;
    reg        busy_reg;
    reg [8:0]  argmax_reg;
    reg [7:0]  mla_kv_count;

    reg [KDA_HEADS*KDA_DIM*KDA_DIM*32-1:0] kda_state [0:N_LAYERS-1];
    reg [KDA_HEADS*KDA_DIM*32-1:0] kda_q, kda_k, kda_v;

    // KV cache SRAM macro, word-addressed: entry*72 + word
    reg  [12:0] kv_sram_addr;
    reg  [63:0] kv_sram_wdata;
    reg         kv_sram_we;
    reg         kv_sram_ce;
    wire [63:0] kv_sram_rdata;
    reg  [63:0] kv_word_r;      // last consumed SRAM read word

    // MAC array interface. The legacy X4Y2 pipe register is inert (always 0)
    // and only kept so the distributed weight-shift regression still applies.
    reg         mac_start;
    reg  [3:0]  mac_a, mac_b;
    wire [23:0] mac_acc;
    wire        mac_done;
    reg  [23:0] mac_pipe;
    reg         mac_pipe_v;

    // KDA operator state (X4Y3). kda_state[0] holds S: element (h,i,j) at word
    // {h,i[4:0],j[4:0]}, i = key channel, j = value channel.
    reg [7:0]  kx_u [0:63];           // KDA input codes, x = (code-128)/32 (placeholder embedding)
    reg [7:0]  kh_f [0:31];           // f low-rank intermediate codes
    reg [7:0]  kh_z [0:31];           // z low-rank intermediate codes
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

    // MLA operator state. Values signed Q16.16; *_u are INT8 codes with value
    // (code-128)*2^(e-16); h uses e = 10, lat/ctx carry their own e.
    reg [7:0]  mla_hu   [0:63];       // STAGED MLA input codes (placeholder)
    reg signed [31:0] mla_latr [0:127];  // h @ wc
    reg signed [31:0] mla_lat  [0:127];  // RMSNorm(h @ wc, knorm)
    reg [7:0]  mla_latu [0:127];
    reg [4:0]  mla_elat, mla_ectx;
    reg signed [31:0] mla_qc [0:63];     // [head*32 + d]
    reg signed [31:0] mla_qr [0:31];     // [head*16 + d]
    reg signed [31:0] mla_kr [0:15];     // shared by heads
    reg signed [31:0] mla_kc [0:63];
    reg signed [31:0] mla_v  [0:63];
    reg signed [31:0] mla_score [0:127]; // [head*64 + t]
    reg signed [31:0] mla_ex    [0:127]; // exp(score - max)
    reg signed [31:0] mla_p     [0:127]; // softmax probabilities, Q16
    reg signed [31:0] mla_ctx [0:63];
    reg [7:0]  mla_ctxu [0:63];
    reg signed [31:0] mla_out [0:63];    // MLA layer output (residual input `a`)
    reg [7:0]  mla_qrom [0:MLA_NQ-1];    // packed int4: w[2r] bits[3:0], w[2r+1] bits[7:4]
    reg [15:0] mla_srom [0:MLA_NS-1];    // Q3.12 scales
    reg [7:0]  mla_zrom [0:MLA_NS-1];    // zero points
    reg [15:0] mla_knorm [0:MLA_DC-1];   // Q2.13 offsets around 1
    reg [8*256-1:0] mla_wdir;

    // Projection engine (KDA m: 0 q,1 k,2 v,3 beta,4 f1,5 f2,6 z1,7 z2,8 o;
    // MLA m: 9 wc,10 wq_c,11 wq_r,12 wk_r,13 wk_c,14 wv,15 o)
    reg [3:0]  pj_m;
    reg [6:0]  pj_o, pj_i;
    reg [1:0]  pj_g;
    reg        pj_hi;
    reg [2:0]  pj_step, pj_drain;
    reg [23:0] pj_base, pj_dhi;
    reg [15:0] pj_sumx, pj_sumw;
    reg signed [63:0] pj_acc;
    reg        pj_wb;                 // one-cycle pulse per projection output
    reg [3:0]  pj_wb_m;
    reg [6:0]  pj_wb_o;
    reg [3:0]  mac_cnt_mirror;        // equals mac.cnt: starts sampled mod 16
    wire [3:0] mac_cnt_next = mac_cnt_mirror + {3'b0, mac_start};

    // Sequential operator counters and procedural temporaries
    reg [11:0] kc_idx;
    reg [6:0]  kc_j;
    reg [2:0]  kc_sub;
    reg signed [63:0] kc_acc;
    reg [31:0] kc_root;
    reg signed [31:0] kc_u;
    reg [7:0]  t_src;
    reg [3:0]  t_w;
    reg [23:0] t_dlo;
    reg signed [31:0] t_raw, t_a, t_b, t_c, t_d, t_y;
    reg [10:0] t_s;
    reg [5:0]  t_e;
    reg [7:0]  t_ii;
    reg [9:0]  t_si;
    reg [14:0] t_qa;
    reg signed [63:0] t_acc;
    reg signed [71:0] t_w72, t_l72;
    integer    ki;

    // MLA sequential state: 72-bit exact accumulators, SRAM streaming tags
    reg signed [71:0] ma_acc, ma_acc2;
    reg [31:0] ma_max;                // max |x| (unsigned)
    reg signed [31:0] ma_smax;        // max score
    reg [31:0] ma_sum;                // softmax denominator
    reg        ia_on, ia_h;           // SRAM read issue: head, entry, word
    reg [6:0]  ia_t;
    reg [4:0]  ia_w;
    reg        tg1_v, tg1_h, tg2_v, tg2_h;
    reg [6:0]  tg1_t, tg2_t;
    reg [4:0]  tg1_w, tg2_w;

    // Legacy distributed weight shift registers (X3), inert since mac_pipe_v = 0.
    localparam WEIGHT_BITS = D_MODEL*KDA_HEADS*KDA_DIM*4;
    localparam WEIGHT_SEG_BITS = 256;
    localparam WEIGHT_SEGMENTS = (WEIGHT_BITS+WEIGHT_SEG_BITS-1)/WEIGHT_SEG_BITS;
    reg [WEIGHT_BITS-1:0] weight_q_sr;
    reg [WEIGHT_BITS-1:0] weight_k_sr;
    reg [WEIGHT_BITS-1:0] weight_v_sr;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_q_pending;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_k_pending;
    (* keep = 1 *) reg [WEIGHT_SEGMENTS-1:0] weight_v_pending;
    wire [3:0] weight_q_head = weight_q_pending[0] ? weight_q_sr[7:4] : weight_q_sr[3:0];
    wire [3:0] weight_k_head = weight_k_pending[0] ? weight_k_sr[7:4] : weight_k_sr[3:0];
    wire [3:0] weight_v_head = weight_v_pending[0] ? weight_v_sr[7:4] : weight_v_sr[3:0];
    wire shift_q = mac_pipe_v && ((current_phase == KDA_PROJ_Q) || (current_phase == MLA_PROJ_Q));
    wire shift_k = mac_pipe_v && (current_phase == KDA_PROJ_K);
    wire shift_v = mac_pipe_v && (current_phase == KDA_PROJ_V);

    wire phase_done_7   = (phase_cycle == 8'd7);
    wire phase_done_15  = (phase_cycle == 8'd15);

    assign busy = busy_reg;
    assign argmax_id = argmax_reg;
    // No eviction contract exists: a full sequence must be restarted.
    assign token_ready = !busy_reg && (current_phase == IDLE) &&
                         (seq_start || mla_kv_count < MAX_SEQ);

    //-------------------------------------------------------------------------
    // Functions
    //-------------------------------------------------------------------------
    `include "kda_luts.vh"
    `include "mla_luts.vh"

    function signed [31:0] sat32; input signed [71:0] x; begin
        if (x > 72'sd2147483647) sat32 = 32'sh7fffffff;
        else if (x < -72'sd2147483648) sat32 = 32'sh80000000;
        else sat32 = x[31:0];
    end endfunction
    function signed [7:0] sat8; input signed [63:0] x; begin
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
    // Deterministic placeholder KDA parameters (identical formulas in kda_model.py)
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
        case (m) 3: kda_nout = 2; 4, 6: kda_nout = 32; default: kda_nout = 64; endcase
    end endfunction
    function integer kda_nin; input [3:0] m; begin kda_nin = (m == 5 || m == 7) ? 32 : 64; end endfunction
    function integer kda_pad; input [3:0] m; begin kda_pad = (m == 5 || m == 7) ? 32 : 64; end endfunction
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
    // STAGED placeholder MLA input codes (identical formula: mla_model.h_u)
    function [7:0] mla_hu_f; input integer t, i; integer s; begin
        s = t*89 + i*113 + ((t ^ (i*3)) & 63)*3 + 17; mla_hu_f = s[7:0];
    end endfunction
    // MLA matrix geometry: fan_in, fan_out, ROM bases (mla_model.MATS/layout)
    function integer mla_k; input [3:0] m; begin mla_k = (m == 13 || m == 14) ? MLA_DC : D_MODEL; end endfunction
    function integer mla_n; input [3:0] m; begin
        case (m) 9: mla_n = MLA_DC; 11: mla_n = MLA_HEADS*MLA_DR; 12: mla_n = MLA_DR; default: mla_n = 64; endcase
    end endfunction
    function integer mla_grp; input [3:0] m; begin mla_grp = (m == 13 || m == 14) ? G_DC : G_D; end endfunction
    function integer mla_qbase; input [3:0] m; begin
        case (m) 9: mla_qbase = 0; 10: mla_qbase = 4096; 11: mla_qbase = 6144; 12: mla_qbase = 7168;
                 13: mla_qbase = 7680; 14: mla_qbase = 11776; default: mla_qbase = 15872; endcase
    end endfunction
    function integer mla_sbase; input [3:0] m; begin
        case (m) 9: mla_sbase = 0; 10: mla_sbase = 128*NG_D; 11: mla_sbase = 192*NG_D; 12: mla_sbase = 224*NG_D;
                 13: mla_sbase = 240*NG_D; 14: mla_sbase = 240*NG_D + 64*NG_DC;
                 default: mla_sbase = 240*NG_D + 128*NG_DC; endcase
    end endfunction
    // Smallest e in [0,16] with max|x| >> e < 128
    function [4:0] choose_e; input [31:0] m; integer e; begin
        choose_e = 16;
        for (e = 16; e >= 0; e = e - 1) if ((m >> e) < 128) choose_e = e;
    end endfunction
    function [7:0] quant8; input signed [31:0] x; input [4:0] e; reg signed [63:0] y; begin
        y = x; if (e != 0) y = y + (64'sd1 <<< (e - 1));
        y = y >>> e; quant8 = sat8(y) + 8'd128;
    end endfunction
    function [31:0] abs32; input signed [31:0] x; reg signed [32:0] y; begin
        y = x; if (y < 0) y = -y; abs32 = y[31:0];
    end endfunction
    function signed [31:0] expn_q; input [32:0] d; integer i, fr, t0, t1; begin   // exp(-d), d >= 0 Q16
        if (d[32:11] >= 512) expn_q = 0;
        else begin
            i = d[20:11]; fr = d[10:0]; t0 = expn_tab(i); t1 = expn_tab(i+1);
            expn_q = t0 - (((t0 - t1) * fr) >>> 11);
        end
    end endfunction
    // query value d of head h: [qc_h, qr_h]
    function signed [31:0] mla_qval; input h; input [5:0] d; begin
        mla_qval = (d < MLA_DK) ? mla_qc[{h, d[4:0]}] : mla_qr[{h, d[3:0]}];
    end endfunction
    // cache word w of the head-h key [kc_h, kr]
    function [6:0] mla_kword; input h; input [4:0] w; begin
        mla_kword = (w < MLA_DK/2) ? {2'b0, h, w[3:0]} : KR_WORD + (w - MLA_DK/2);
    end endfunction
    function [63:0] mla_append_word; input [6:0] w; begin
        if (w < KR_WORD) mla_append_word = {mla_kc[{w[4:0], 1'b1}], mla_kc[{w[4:0], 1'b0}]};
        else if (w < V_WORD) mla_append_word = {mla_kr[{w[2:0], 1'b1}], mla_kr[{w[2:0], 1'b0}]};
        else mla_append_word = {mla_v[{w[4:0] - 5'd8, 1'b1}], mla_v[{w[4:0] - 5'd8, 1'b0}]};
    end endfunction

    //-------------------------------------------------------------------------
    // Instances
    //-------------------------------------------------------------------------
    kv_banked_4608x64 kv_sram (
        .clk(clk),
        .ce_in(kv_sram_ce),
        .we_in(kv_sram_we),
        .addr_in(kv_sram_addr),
        .wd_in(kv_sram_wdata),
        .w_mask_in(64'hFFFFFFFFFFFFFFFF),
        .rd_out(kv_sram_rdata)
    );

    mac_array mac (
        .clk(clk), .rst_n(rst_n),
        .start(mac_start),
        .a(mac_a), .b(mac_b),
        .acc(mac_acc), .done(mac_done)
    );

    // MLA weights: official seeded synthetic tensors (reference gen_weights),
    // ROM images written by mla_model.py gen_hex. +MLA_WDIR=<dir> overrides.
    initial begin
        if (!$value$plusargs("MLA_WDIR=%s", mla_wdir)) mla_wdir = "mla_weights";
        $readmemh({mla_wdir, "/q.hex"}, mla_qrom);
        $readmemh({mla_wdir, "/s.hex"}, mla_srom);
        $readmemh({mla_wdir, "/z.hex"}, mla_zrom);
        $readmemh({mla_wdir, "/knorm.hex"}, mla_knorm);
    end

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

    // Each 256-bit segment gets its own preserved enable register. The
    // one-cycle deferred shift cuts decode out of the high-fanout path.
    // Head bypass makes the externally consumed nibble cycle-equivalent.
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
    // Main FSM
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
            mac_pipe <= 24'd0;
            mac_pipe_v <= 1'b0;
            kda_q <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_k <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kda_v <= {(KDA_HEADS*KDA_DIM*32){1'b0}};
            kv_sram_addr <= 13'd0;
            kv_sram_wdata <= 64'd0;
            kv_sram_we <= 1'b0;
            kv_sram_ce <= 1'b0;
            kv_word_r <= 64'd0;
            pj_m <= 0; pj_o <= 0; pj_i <= 0; pj_g <= 0; pj_hi <= 1'b1; pj_step <= 0; pj_drain <= 0;
            pj_base <= 0; pj_dhi <= 0; pj_sumx <= 0; pj_sumw <= 0; pj_acc <= 0; mac_cnt_mirror <= 0;
            pj_wb <= 1'b0; pj_wb_m <= 0; pj_wb_o <= 0;
            kc_idx <= 0; kc_j <= 0; kc_sub <= 0; kc_acc <= 0; kc_root <= 0; kc_u <= 0;
            ma_acc <= 0; ma_acc2 <= 0; ma_max <= 0; ma_smax <= 0; ma_sum <= 0;
            mla_elat <= 0; mla_ectx <= 0;
            ia_on <= 0; ia_h <= 0; ia_t <= 0; ia_w <= 0;
            tg1_v <= 0; tg1_h <= 0; tg1_t <= 0; tg1_w <= 0;
            tg2_v <= 0; tg2_h <= 0; tg2_t <= 0; tg2_w <= 0;
            kda_state[0] <= 0;
            for (ki = 0; ki < 576; ki = ki + 1) conv_hist[ki] <= 0;
        end else begin
            output_valid <= 1'b0; // one-cycle completion pulse
            pj_wb <= 1'b0;
            kv_sram_ce <= 1'b0;   // SRAM idle unless a phase issues an access
            kv_sram_we <= 1'b0;
            if (mac_start) mac_cnt_mirror <= mac_cnt_mirror + 4'd1;
            case (current_phase)
                IDLE: begin
                    if (token_valid && token_ready) begin
                        if (seq_start) mla_kv_count <= 0;
                        busy_reg <= 1'b1;
                        current_layer <= 4'd0;
                        current_phase <= KDA_PROJ_Q;
                        phase_cycle <= 8'd0;
                        argmax_reg <= token_id + 9'd1;
                        mac_pipe_v <= 1'b0;
                        for (ki = 0; ki < 64; ki = ki + 1) begin
                            kx_u[ki] <= kda_xu(token_id, ki);
                            mla_hu[ki] <= mla_hu_f(token_id, ki);
                        end
                        if (seq_start) begin  // new sequence: clear conv history and S
                            kda_state[0] <= 0;
                            for (ki = 0; ki < 576; ki = ki + 1) conv_hist[ki] <= 0;
                        end
                        pj_m <= 0; pj_o <= 0; pj_i <= 0; pj_g <= 0; pj_hi <= 1'b1;
                        pj_step <= 0; pj_drain <= 0; pj_acc <= 0;
                    end
                end

                // Projection engine on the unsigned INT4 MAC. Signed dot
                // sum_i (xu_i-128)*(wu_i-z) over one group of G inputs is exactly
                // 16*sum(xu_hi*wu) + sum(xu_lo*wu) - z*sum(xu) - 128*sum(wu) + 128*z*G,
                // where each pass result is the persistent-accumulator delta.
                // KDA matrices: z = 8, fixed scale (X4Y3). MLA matrices: reference
                // int4 z/s per group, acc = sum_g s_g*raw_g, value = acc*2^(e-12).
                KDA_PROJ_Q, KDA_PROJ_K, KDA_PROJ_V, KDA_OPROJ, MLA_PROJ_Q, MLA_PROJ_KV, MLA_OPROJ: begin
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
                                end else if (pj_m <= 4'd8) begin
                                    t_dlo = mac_acc - pj_base;
                                    t_raw = $signed({8'b0, pj_dhi}) * 16 + $signed({8'b0, t_dlo})
                                          - 8 * $signed({16'b0, pj_sumx}) - 128 * $signed({16'b0, pj_sumw})
                                          + 1024 * kda_nin(pj_m);
                                    case (pj_m)
                                        4'd0: kda_q[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd1: kda_k[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd2: kda_v[pj_o*32 +: 32] <= t_raw * 32;
                                        4'd3: kda_beta_raw[pj_o[0]] <= t_raw;
                                        4'd4: kh_f[pj_o[4:0]] <= sat8(t_raw >>> 6) + 8'd128;
                                        4'd5: kda_f[pj_o[5:0]] <= t_raw * 32;
                                        4'd6: kh_z[pj_o[4:0]] <= sat8(t_raw >>> 6) + 8'd128;
                                        4'd7: kda_z[pj_o[5:0]] <= t_raw * 32;
                                        default: kda_out[pj_o[5:0]] <= t_raw * 32;
                                    endcase
                                    pj_wb <= 1'b1; pj_wb_m <= pj_m; pj_wb_o <= pj_o;
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
                                end else begin
                                    t_dlo = mac_acc - pj_base;
                                    t_si = mla_sbase(pj_m) + pj_g * mla_n(pj_m) + pj_o;
                                    t_raw = $signed({8'b0, pj_dhi}) * 16 + $signed({8'b0, t_dlo})
                                          - $signed({28'b0, mla_zrom[t_si][3:0]}) * $signed({16'b0, pj_sumx})
                                          - 128 * $signed({16'b0, pj_sumw})
                                          + 128 * mla_grp(pj_m) * $signed({28'b0, mla_zrom[t_si][3:0]});
                                    t_acc = $signed(mla_srom[t_si]);
                                    t_acc = pj_acc + t_acc * t_raw;
                                    pj_hi <= 1'b1; pj_sumx <= 0; pj_sumw <= 0; pj_step <= 3'd2;
                                    if ((pj_g + 1) * mla_grp(pj_m) < mla_k(pj_m)) begin
                                        pj_acc <= t_acc; pj_g <= pj_g + 2'd1;
                                    end else begin
                                        case (pj_m)
                                            4'd13, 4'd14: t_e = {1'b0, mla_elat};
                                            4'd15: t_e = {1'b0, mla_ectx};
                                            default: t_e = 6'd10;   // h codes: 2^-6 steps
                                        endcase
                                        if (t_e <= 12) t_y = sat32(t_acc >>> (12 - t_e));
                                        else t_y = sat32(t_acc <<< (t_e - 12));
                                        case (pj_m)
                                            4'd9:  mla_latr[pj_o] <= t_y;
                                            4'd10: mla_qc[pj_o[5:0]] <= t_y;
                                            4'd11: mla_qr[pj_o[4:0]] <= t_y;
                                            4'd12: mla_kr[pj_o[3:0]] <= t_y;
                                            4'd13: mla_kc[pj_o[5:0]] <= t_y;
                                            4'd14: mla_v[pj_o[5:0]] <= t_y;
                                            default: mla_out[pj_o[5:0]] <= t_y;
                                        endcase
                                        pj_wb <= 1'b1; pj_wb_m <= pj_m; pj_wb_o <= pj_o;
                                        pj_acc <= 0; pj_g <= 0;
                                        if (pj_o == mla_n(pj_m) - 1) begin
                                            pj_o <= 0;
                                            case (pj_m)
                                                4'd12: begin
                                                    current_phase <= MLA_LAT_NORM;
                                                    kc_idx <= 0; kc_sub <= 0; ma_acc <= 0; ma_max <= 0;
                                                end
                                                4'd14: begin current_phase <= MLA_KV_APPEND; phase_cycle <= 8'd0; end
                                                4'd15: begin current_phase <= NORM; phase_cycle <= 8'd0; end
                                                default: pj_m <= pj_m + 4'd1;
                                            endcase
                                        end else pj_o <= pj_o + 1;
                                    end
                                end
                            end else pj_drain <= pj_drain + 1;
                        end
                        default: begin // 2 / 4: issue one operand pair per cycle
                            mac_start <= 1'b1;
                            if (pj_m <= 4'd8) begin
                                case (pj_m)
                                    4'd5: t_src = kh_f[pj_i[4:0]];
                                    4'd7: t_src = kh_z[pj_i[4:0]];
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
                            end else begin
                                t_ii = pj_g * mla_grp(pj_m) + pj_i;
                                case (pj_m)
                                    4'd13, 4'd14: t_src = mla_latu[t_ii[6:0]];
                                    4'd15: t_src = mla_ctxu[t_ii[5:0]];
                                    default: t_src = mla_hu[t_ii[5:0]];
                                endcase
                                t_qa = mla_qbase(pj_m) + (t_ii >> 1) * mla_n(pj_m) + pj_o;
                                t_w = t_ii[0] ? mla_qrom[t_qa][7:4] : mla_qrom[t_qa][3:0];
                                mac_a <= pj_hi ? t_src[7:4] : t_src[3:0];
                                mac_b <= t_w;
                                if (pj_hi) begin
                                    pj_sumx <= pj_sumx + t_src;
                                    pj_sumw <= pj_sumw + t_w;
                                end
                                if (pj_i == mla_grp(pj_m) - 1) begin
                                    pj_step <= pj_step + 3'd1; pj_drain <= 0;
                                end else pj_i <= pj_i + 1;
                            end
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
                        3'd0: begin
                            kc_acc <= kc_acc + t_a * t_a;
                            if (kc_idx[4:0] == 5'd31) begin kc_sub <= 3'd1; kc_idx <= 0; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            kc_root <= isqrt64(kc_acc + 64'sd4295);  // L2 eps = 1e-6 in Q32
                            kc_sub <= 3'd2;
                        end
                        default: begin
                            if (kc_j[1]) kda_k[t_e*32 +: 32] <= qdiv(t_a, kc_root);
                            else         kda_q[t_e*32 +: 32] <= qdiv(t_a, kc_root);
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0; kc_sub <= 3'd0;
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
                        3'd0: begin
                            kda_state[0][kc_idx[10:0]*32 +: 32] <=
                                mulq(kda_state[0][kc_idx[10:0]*32 +: 32], kda_alpha[kc_idx[10:5]]);
                            if (kc_idx == 12'd2047) begin kc_idx <= 0; kc_j <= 0; kc_sub <= 3'd1; kc_acc <= 0; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            t_a = kda_k[t_e*32 +: 32];
                            t_b = kda_state[0][t_s*32 +: 32];
                            kc_acc <= kc_acc + t_a * t_b;
                            if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 3'd2; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd2: begin
                            kc_u <= ssub(kda_v[kc_j[5:0]*32 +: 32], sat32(kc_acc >>> 16));
                            kc_sub <= 3'd3;
                        end
                        default: begin
                            t_a = kda_k[t_e*32 +: 32];
                            t_b = kda_state[0][t_s*32 +: 32];
                            kda_state[0][t_s*32 +: 32] <= sadd(t_b, mulq(mulq(kda_beta[kc_j[5]], t_a), kc_u));
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0;
                                if (kc_j == 7'd63) begin current_phase <= KDA_STATE_WR; kc_j <= 0; kc_sub <= 3'd0; end
                                else begin kc_j <= kc_j + 1; kc_sub <= 3'd1; end
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Readout: attn_j = (q . S[:,j]) / sqrt(dh)
                KDA_STATE_WR: begin
                    t_s = {kc_j[5], kc_idx[4:0], kc_j[4:0]};
                    t_e = {kc_j[5], kc_idx[4:0]};
                    if (kc_sub == 3'd0) begin
                        t_a = kda_q[t_e*32 +: 32];
                        t_b = kda_state[0][t_s*32 +: 32];
                        kc_acc <= kc_acc + t_a * t_b;
                        if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 3'd1; end
                        else kc_idx <= kc_idx + 1;
                    end else begin
                        kda_attn[kc_j[5:0]] <= mulq(sat32(kc_acc >>> 16), 32'sd11585);
                        kc_acc <= 0; kc_sub <= 3'd0;
                        if (kc_j == 7'd63) begin current_phase <= KDA_OUTPUT; kc_j <= 0; end
                        else kc_j <= kc_j + 1;
                    end
                end

                // Gated RMSNorm per head: rmsnorm(attn)*onorm*sigmoid(z), then o_proj
                KDA_OUTPUT: begin
                    t_e = {kc_j[0], kc_idx[4:0]};
                    case (kc_sub)
                        3'd0: begin
                            t_a = kda_attn[t_e];
                            kc_acc <= kc_acc + t_a * t_a;
                            if (kc_idx[4:0] == 5'd31) begin kc_idx <= 0; kc_sub <= 3'd1; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            kc_root <= isqrt64((kc_acc >>> 5) + 64'sd42950);  // RMS eps = 1e-5 in Q32
                            kc_sub <= 3'd2;
                        end
                        default: begin
                            t_y = mulq(mulq(qdiv(kda_attn[t_e], kc_root), kda_onorm(kc_idx[4:0])),
                                       sigmoid_q(kda_z[t_e]));
                            kda_y[t_e] <= t_y;
                            ky_u[t_e] <= sat8(t_y >>> 11) + 8'd128;
                            if (kc_idx[4:0] == 5'd31) begin
                                kc_idx <= 0; kc_acc <= 0; kc_sub <= 3'd0;
                                if (kc_j[0]) begin
                                    current_phase <= KDA_OPROJ; kc_j <= 0;
                                    pj_m <= 4'd8; pj_o <= 0; pj_i <= 0; pj_step <= 0; pj_drain <= 0;
                                end else kc_j <= kc_j + 1;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Latent RMSNorm: lat = latr / sqrt(mean(latr^2) + 1e-5) * (1 + knorm),
                // then per-vector exponent e_lat and INT8 codes for wk_c / wv.
                MLA_LAT_NORM: begin
                    case (kc_sub)
                        3'd0: begin
                            t_a = mla_latr[kc_idx[6:0]];
                            ma_acc <= ma_acc + t_a * t_a;
                            if (kc_idx == MLA_DC-1) begin kc_idx <= 0; kc_sub <= 3'd1; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            t_l72 = (ma_acc >>> 7) + 72'sd42950;      // RMS eps = 1e-5 in Q32
                            kc_root <= isqrt64(t_l72[63:0]);
                            kc_sub <= 3'd2;
                        end
                        3'd2: begin
                            t_y = mulq(qdiv(mla_latr[kc_idx[6:0]], kc_root),
                                       32'sd65536 + 8 * $signed(mla_knorm[kc_idx[6:0]]));
                            mla_lat[kc_idx[6:0]] <= t_y;
                            if (abs32(t_y) > ma_max) ma_max <= abs32(t_y);
                            if (kc_idx == MLA_DC-1) begin kc_idx <= 0; kc_sub <= 3'd3; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd3: begin
                            mla_elat <= choose_e(ma_max);
                            kc_sub <= 3'd4;
                        end
                        default: begin
                            mla_latu[kc_idx[6:0]] <= quant8(mla_lat[kc_idx[6:0]], mla_elat);
                            if (kc_idx == MLA_DC-1) begin
                                kc_idx <= 0; kc_sub <= 3'd0;
                                current_phase <= MLA_PROJ_KV;
                                pj_m <= 4'd13; pj_o <= 0; pj_i <= 0; pj_g <= 0; pj_acc <= 0;
                                pj_step <= 0; pj_drain <= 0;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Append [kc, kr, v] at entry mla_kv_count (< MAX_SEQ by backpressure).
                MLA_KV_APPEND: begin
                    if (mla_kv_count < MAX_SEQ) begin
                        kv_sram_ce <= 1'b1;
                        kv_sram_we <= 1'b1;
                        kv_sram_addr <= mla_kv_count * KV_WORDS + phase_cycle;
                        kv_sram_wdata <= mla_append_word(phase_cycle[6:0]);
                    end
                    if (phase_cycle == KV_WORDS-1) begin
                        mla_kv_count <= mla_kv_count + 1;
                        current_phase <= MLA_ATTN_A;
                        phase_cycle <= 8'd0;
                        ia_on <= 1'b1; ia_h <= 0; ia_t <= 0; ia_w <= 0;
                        tg1_v <= 0; tg2_v <= 0;
                    end else phase_cycle <= phase_cycle + 1;
                end

                // Scores s[h,t] = ([qc_h,qr_h] . [kc_h,kr]_t) / sqrt(dk+dr) for t < count.
                // One cache word issued per cycle; data consumed two cycles later.
                MLA_ATTN_A: begin
                    if (ia_on) begin
                        kv_sram_ce <= 1'b1;
                        kv_sram_addr <= ia_t * KV_WORDS + mla_kword(ia_h, ia_w);
                        tg1_v <= 1'b1; tg1_h <= ia_h; tg1_t <= ia_t; tg1_w <= ia_w;
                        if (ia_w == QK_WORDS-1) begin
                            ia_w <= 0;
                            if (ia_t == mla_kv_count - 1) begin
                                ia_t <= 0;
                                if (ia_h) ia_on <= 1'b0; else ia_h <= 1'b1;
                            end else ia_t <= ia_t + 1;
                        end else ia_w <= ia_w + 1;
                    end else tg1_v <= 1'b0;
                    tg2_v <= tg1_v; tg2_h <= tg1_h; tg2_t <= tg1_t; tg2_w <= tg1_w;
                    if (tg2_v) begin
                        kv_word_r <= kv_sram_rdata;
                        t_w72 = mla_qval(tg2_h, {tg2_w, 1'b0}) * $signed(kv_sram_rdata[31:0]);
                        t_l72 = mla_qval(tg2_h, {tg2_w, 1'b1}) * $signed(kv_sram_rdata[63:32]);
                        t_w72 = ((tg2_w == 0) ? 72'sd0 : ma_acc) + t_w72 + t_l72;
                        ma_acc <= t_w72;
                        if (tg2_w == QK_WORDS-1) begin
                            mla_score[{tg2_h, tg2_t[5:0]}] <= mulq(sat32(t_w72 >>> 16), 32'sd9459);
                            if (tg2_h && tg2_t == mla_kv_count - 1) begin
                                current_phase <= MLA_ATTN_B;
                                kc_idx <= 0; kc_j <= 0; kc_sub <= 0;
                            end
                        end
                    end
                end

                // Softmax per head over the valid entries: max, exp LUT + sum, divide.
                MLA_ATTN_B: begin
                    t_si = {kc_j[0], kc_idx[5:0]};
                    case (kc_sub)
                        3'd0: begin
                            if (kc_idx == 0 || mla_score[t_si] > ma_smax) ma_smax <= mla_score[t_si];
                            if (kc_idx == mla_kv_count - 1) begin kc_idx <= 0; kc_sub <= 3'd1; ma_sum <= 0; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            t_y = expn_q($signed({ma_smax[31], ma_smax}) - $signed({mla_score[t_si][31], mla_score[t_si]}));
                            mla_ex[t_si] <= t_y;
                            ma_sum <= ma_sum + t_y;
                            if (kc_idx == mla_kv_count - 1) begin kc_idx <= 0; kc_sub <= 3'd2; end
                            else kc_idx <= kc_idx + 1;
                        end
                        default: begin
                            mla_p[t_si] <= ({32'b0, mla_ex[t_si]} << 16) / {32'b0, ma_sum};
                            if (kc_idx == mla_kv_count - 1) begin
                                kc_idx <= 0; kc_sub <= 3'd0;
                                if (kc_j[0]) begin
                                    current_phase <= MLA_OUTPUT; kc_j <= 0;
                                    ia_on <= 1'b1; ia_h <= 0; ia_t <= 0; ia_w <= 0;
                                    tg1_v <= 0; tg2_v <= 0;
                                end else kc_j <= kc_j + 1;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // ctx[h, 2w..2w+1] = sum_t p[h,t] * v_t[h, 2w..2w+1]; loop (h, w, t).
                MLA_OUTPUT: begin
                    if (ia_on) begin
                        kv_sram_ce <= 1'b1;
                        kv_sram_addr <= ia_t * KV_WORDS + V_WORD + {ia_h, ia_w[3:0]};
                        tg1_v <= 1'b1; tg1_h <= ia_h; tg1_t <= ia_t; tg1_w <= ia_w;
                        if (ia_t == mla_kv_count - 1) begin
                            ia_t <= 0;
                            if (ia_w == MLA_DV/2 - 1) begin
                                ia_w <= 0;
                                if (ia_h) ia_on <= 1'b0; else ia_h <= 1'b1;
                            end else ia_w <= ia_w + 1;
                        end else ia_t <= ia_t + 1;
                    end else tg1_v <= 1'b0;
                    tg2_v <= tg1_v; tg2_h <= tg1_h; tg2_t <= tg1_t; tg2_w <= tg1_w;
                    if (tg2_v) begin
                        kv_word_r <= kv_sram_rdata;
                        t_y = mla_p[{tg2_h, tg2_t[5:0]}];
                        t_w72 = ((tg2_t == 0) ? 72'sd0 : ma_acc) + t_y * $signed(kv_sram_rdata[31:0]);
                        t_l72 = ((tg2_t == 0) ? 72'sd0 : ma_acc2) + t_y * $signed(kv_sram_rdata[63:32]);
                        ma_acc <= t_w72; ma_acc2 <= t_l72;
                        if (tg2_t == mla_kv_count - 1) begin
                            mla_ctx[{tg2_h, tg2_w[3:0], 1'b0}] <= sat32(t_w72 >>> 16);
                            mla_ctx[{tg2_h, tg2_w[3:0], 1'b1}] <= sat32(t_l72 >>> 16);
                            if (tg2_h && tg2_w == MLA_DV/2 - 1) begin
                                current_phase <= MLA_CTX_Q;
                                kc_idx <= 0; kc_sub <= 0; ma_max <= 0;
                            end
                        end
                    end
                end

                // ctx INT8 codes with per-vector exponent, then output projection o.
                MLA_CTX_Q: begin
                    case (kc_sub)
                        3'd0: begin
                            if (abs32(mla_ctx[kc_idx[5:0]]) > ma_max) ma_max <= abs32(mla_ctx[kc_idx[5:0]]);
                            if (kc_idx == 63) begin kc_idx <= 0; kc_sub <= 3'd1; end
                            else kc_idx <= kc_idx + 1;
                        end
                        3'd1: begin
                            mla_ectx <= choose_e(ma_max);
                            kc_sub <= 3'd2;
                        end
                        default: begin
                            mla_ctxu[kc_idx[5:0]] <= quant8(mla_ctx[kc_idx[5:0]], mla_ectx);
                            if (kc_idx == 63) begin
                                kc_idx <= 0; kc_sub <= 3'd0;
                                current_phase <= MLA_OPROJ;
                                pj_m <= 4'd15; pj_o <= 0; pj_i <= 0; pj_g <= 0; pj_acc <= 0;
                                pj_step <= 0; pj_drain <= 0;
                            end else kc_idx <= kc_idx + 1;
                        end
                    endcase
                end

                // Placeholders: layer norm / MoE / residual mixing are X4Y5.
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
                        pj_m <= 4'd9; pj_o <= 0; pj_i <= 0; pj_g <= 0; pj_acc <= 0;
                        pj_step <= 0; pj_drain <= 0;
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
