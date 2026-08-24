`timescale 1ns/1ps

// Y2 area/synthesis fix: sixteen arithmetic lanes process one 128-element
// state row in eight cycles. This preserves the complete two-pass recurrence
// while avoiding 128 replicated multipliers and Yosys's >1 GiB process cone.
module state_update (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,
    input  wire           pass_select,
    input  wire           row_valid,
    output wire           row_ready,
    input  wire [6:0]     row_index,
    input  wire [3071:0]  state_row_in,
    input  wire signed [7:0] alpha_scalar,
    input  wire signed [7:0] k_scalar,
    input  wire signed [7:0] q_scalar,
    input  wire [3071:0]  delta_vector,
    output reg            row_out_valid,
    output reg  [6:0]     row_out_index,
    output wire [3071:0]  state_row_out,
    output reg            done,
    output wire [3071:0]  reduction_vector
);
    reg busy, row_busy, active_pass;
    reg [7:0] rows_accepted, rows_completed;
    reg [6:0] chunk;
    reg [6:0] row_index_q;
    reg signed [7:0] alpha_q, k_q, q_q;
    reg [3071:0] row_q, delta_q;
    reg signed [23:0] reduction [0:127];
    reg signed [23:0] row_out_mem [0:127];
    integer j, index;
    reg signed [23:0] state_value, delta_value, lane_value;
    reg signed [31:0] mult_temp, add_temp;

    assign row_ready = busy && !row_busy;
    generate
        genvar g;
        for (g=0; g<128; g=g+1) begin : g_reduction
            assign reduction_vector[g*24 +: 24] = reduction[g];
            assign state_row_out[g*24 +: 24] = row_out_mem[g];
        end
    endgenerate

    function signed [23:0] sat24;
        input signed [31:0] value;
        begin
            if (value > 32'sd8388607) sat24 = 24'sh7fffff;
            else if (value < -32'sd8388608) sat24 = 24'sh800000;
            else sat24 = value[23:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0; row_busy <= 0; active_pass <= 0; rows_accepted <= 0;
            rows_completed <= 0; chunk <= 0; row_index_q <= 0;
            alpha_q <= 0; k_q <= 0; q_q <= 0; row_q <= 0; delta_q <= 0;
            row_out_valid <= 0; row_out_index <= 0; done <= 0;
            for (j=0; j<128; j=j+1) reduction[j] <= 0;
        end else begin
            row_out_valid <= 0;
            done <= 0;
            if (start && !busy) begin
                busy <= 1; row_busy <= 0; active_pass <= pass_select;
                rows_accepted <= 0; rows_completed <= 0; chunk <= 0;
                for (j=0; j<128; j=j+1) reduction[j] <= 0;
            end
            if (row_valid && row_ready) begin
                row_busy <= 1; chunk <= 0; row_index_q <= row_index;
                alpha_q <= alpha_scalar; k_q <= k_scalar; q_q <= q_scalar;
                row_q <= state_row_in; delta_q <= delta_vector;
                rows_accepted <= rows_accepted + 1'b1;
            end
            if (row_busy) begin
                index = chunk;
                state_value = row_q[index*24 +: 24];
                if (!active_pass) begin
                    mult_temp = state_value * alpha_q;
                    lane_value = sat24(mult_temp >>> 7);
                    row_out_mem[index] <= lane_value;
                    mult_temp = lane_value * k_q;
                    add_temp = $signed({{8{reduction[index][23]}},reduction[index]}) + (mult_temp >>> 7);
                    reduction[index] <= sat24(add_temp);
                end else begin
                    delta_value = delta_q[index*24 +: 24];
                    mult_temp = delta_value * k_q;
                    add_temp = $signed({{8{state_value[23]}},state_value}) + (mult_temp >>> 7);
                    lane_value = sat24(add_temp);
                    row_out_mem[index] <= lane_value;
                    mult_temp = lane_value * q_q;
                    add_temp = $signed({{8{reduction[index][23]}},reduction[index]}) + (mult_temp >>> 7);
                    reduction[index] <= sat24(add_temp);
                end
                if (chunk == 127) begin
                    row_busy <= 0; row_out_valid <= 1; row_out_index <= row_index_q;
                    rows_completed <= rows_completed + 1'b1;
                    if (rows_completed == 127) begin busy <= 0; done <= 1; end
                end else chunk <= chunk + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && start) assert (!busy) else $error("state_update start while busy");
        if (rst_n && row_valid) assert (row_ready) else $error("state row supplied while not ready");
        if (rst_n && row_valid && row_ready)
            assert (row_index == rows_accepted[6:0]) else $error("state rows must be ascending");
    end
`endif
endmodule
