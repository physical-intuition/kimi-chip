// compute_core v9 - corrected control + hierarchical accumulation.
//
// Fixes vs v4:
//   1. SINGLE-ADD SEMANTICS. v4 held mac_en across both FETCH and COMPUTE
//      while addr and the SRAM read are each registered, so every element
//      except the last was accumulated twice (verified in sim: K=4 of all
//      ones yields 7, not 4). Here en is asserted for exactly the one cycle
//      in which that element's rdata is valid.
//   2. UNLIMITED K. Per-MAC fast 12-bit chunk accumulators fold into 24-bit
//      wide accumulators every CHUNK adds (and once more before DONE).
//      CHUNK=16: 16 adds x |prod|<=64 = 1024, provably safe in 12 bits
//      signed. 24-bit wide covers K up to 131072.
//   3. Drains pulse only on non-add cycles, so the wide 24-bit add is never
//      in series with the multiply path.
//
// Timing of one element k (steady state, 2 cycles/element like v4):
//   FETCH_k   : addr <= k            (registered)
//   COMPUTE_k : SRAM samples addr    (rdata registered at end)
//   FETCH_k+1 : rdata_k valid, en=1  -> exactly one add of element k
module compute_core_v9 (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [15:0] k_dim,
    output reg wgt_cs,
    output reg [15:0] wgt_addr,
    input wire [63:0] wgt_rdata,
    output reg act_cs,
    output reg [15:0] act_addr,
    input wire [63:0] act_rdata,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam CHUNK = 16;
    localparam IDLE=0, CLEAR=1, FETCH=2, COMPUTE=3, FLUSH=4, FLUSH2=5, DONE=6;
    reg [2:0] state;
    reg [15:0] k_cnt;
    reg [3:0] addcnt;
    reg mac_en, mac_clear, mac_drain;

    mac_array_v9 #(.ROWS(16), .COLS(16)) array (
        .clk(clk), .rst_n(rst_n),
        .en(mac_en), .clear(mac_clear), .drain(mac_drain),
        .activations(act_rdata),
        .weights(wgt_rdata),
        .acc_out(acc_out)
    );

    // Chunk bookkeeping: adds happen on mac_en cycles; the fold is pulsed on
    // the following (non-add) cycle. The FLUSH-state fold catches the tail.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addcnt <= 0; mac_drain <= 0;
        end else if (mac_clear) begin
            addcnt <= 0; mac_drain <= 0;
        end else begin
            mac_drain <= (mac_en && addcnt == CHUNK-1) || (state == FLUSH);
            if (mac_en) addcnt <= (addcnt == CHUNK-1) ? 4'd0 : addcnt + 4'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; k_cnt <= 0; done <= 0;
            mac_en <= 0; mac_clear <= 0;
            wgt_cs <= 0; act_cs <= 0;
            wgt_addr <= 0; act_addr <= 0;
        end else case (state)
            IDLE: if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
            CLEAR: begin mac_clear <= 0; state <= FETCH; k_cnt <= 0; end
            FETCH: begin
                wgt_cs <= 1; act_cs <= 1;
                wgt_addr <= k_cnt; act_addr <= k_cnt;
                mac_en <= 0;                 // COMPUTE cycles never add
                state <= COMPUTE;
            end
            COMPUTE: begin
                mac_en <= 1;                 // add during the NEXT cycle,
                                             // when rdata for k_cnt is valid
                if (k_cnt == k_dim - 1) state <= FLUSH;
                else begin k_cnt <= k_cnt + 1; state <= FETCH; end
            end
            FLUSH: begin                     // last element adds THIS cycle
                mac_en <= 0;                 // (drain pulses next, via addcnt block)
                state <= FLUSH2;
            end
            FLUSH2: begin                    // final fold lands here
                state <= DONE;
            end
            DONE: begin
                done <= 1; wgt_cs <= 0; act_cs <= 0;
                if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
            end
        endcase
    end
endmodule
