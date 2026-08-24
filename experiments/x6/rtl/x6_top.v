`timescale 1ns/1ps

// Complete, sequential one-head KDA dataflow chip. The external weight and
// state ports are macro-friendly; all arithmetic blocks are instantiated and
// exercised by the controller. Lane zero occupies the least-significant bits.
module x6_top (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          in_valid,
    output wire          in_ready,
    input  wire [127:0]  activation_in,
    input  wire [127:0]  skip_in,
    input  wire          in_last,
    output wire          out_valid,
    input  wire          out_ready,
    output wire [127:0]  activation_out,
    output wire          out_last,

    output reg  [5:0]    weight_bank_req,
    output wire [95:0]   weight_bank_addr,
    input  wire [5:0]    weight_bank_valid,
    input  wire [1535:0] weight_bank_rdata,

    input  wire [255:0]  conv_alpha_weights,
    input  wire [255:0]  conv_beta_weights,
    input  wire [255:0]  conv_alpha_bias,
    input  wire [255:0]  conv_beta_bias,

    output reg            state_read_req,
    output reg            state_write_req,
    output reg            state_read_bank,
    output reg            state_write_bank,
    output reg  [6:0]     state_read_addr,
    output reg  [6:0]     state_write_addr,
    input  wire           state_row_valid,
    input  wire [3071:0]  state_row_rdata,
    output wire [3071:0]  state_row_wdata,

    output wire           busy,
    output reg            fault
);
    localparam S_COLLECT    = 5'd0;
    localparam S_PROJ_CLEAR = 5'd1;
    localparam S_PROJ_LOAD  = 5'd2;
    localparam S_PROJ_ACT   = 5'd3;
    localparam S_PROJ_MAC   = 5'd4;
    localparam S_PROJ_WAIT  = 5'd5;
    localparam S_CONV       = 5'd6;
    localparam S_P1_START   = 5'd7;
    localparam S_P1_RUN     = 5'd8;
    localparam S_DELTA      = 5'd9;
    localparam S_P2_START   = 5'd10;
    localparam S_P2_RUN     = 5'd11;
    localparam S_NORM_START = 5'd12;
    localparam S_NORM_FEED  = 5'd13;
    localparam S_NORM_WAIT  = 5'd14;
    localparam S_RES_START  = 5'd15;
    localparam S_RES_FEED   = 5'd16;
    localparam S_RES_WAIT   = 5'd17;
    localparam S_OUTPUT     = 5'd18;
    localparam S_P2_CAPTURE = 5'd19;

    reg [4:0] phase;
    reg [3:0] input_beat;
    reg [1:0] projection;
    reg [1:0] tile_pair;
    reg [2:0] chunk;
    reg [2:0] load_beat;
    reg [3:0] conv_sent, conv_got;
    reg [7:0] issue_row, consume_row;
    reg [6:0] vector_index;
    reg read_outstanding;
    reg [3:0] norm_beat, norm_got, residual_beat, residual_got, output_beat;

    wire [1023:0] input_vector, skip_vector;
    wire [1023:0] k_vector, v_vector, q_vector, query_vector;
    wire [3071:0] o_vector_24;
    wire [1023:0] alpha_vector, beta_vector, norm_vector, final_vector;

    function signed [7:0] sat8_from24;
        input signed [23:0] value;
        begin
            if (value > 24'sd127) sat8_from24 = 8'sd127;
            else if (value < -24'sd128) sat8_from24 = -8'sd128;
            else sat8_from24 = value[7:0];
        end
    endfunction

    function signed [23:0] sat24_from32;
        input signed [31:0] value;
        begin
            if (value > 32'sd8388607) sat24_from32 = 24'sh7fffff;
            else if (value < -32'sd8388608) sat24_from32 = 24'sh800000;
            else sat24_from32 = value[23:0];
        end
    endfunction

    wire [1023:0] projection_activation = (projection == 2'd3) ? query_vector : input_vector;
    wire [127:0] mac_activation = projection_activation[chunk*128 +: 128];

    reg mac_weight_load, mac_activate, mac_clear, mac_valid;
    wire mac0_wready, mac1_wready, mac0_ready, mac1_ready;
    wire mac0_result_valid, mac1_result_valid;
    wire [383:0] mac0_result, mac1_result;

    mac_array_16x16 mac0 (
        .clk(clk), .rst_n(rst_n), .weight_load_valid((phase == S_PROJ_LOAD) && weight_bank_valid[0] && weight_bank_valid[1]),
        .weight_load_ready(mac0_wready), .weight_load_buffer(chunk[0]),
        .weight_load_beat(load_beat), .weight_load_data(weight_bank_rdata[255:0]),
        .weight_activate(phase == S_PROJ_ACT), .weight_activate_buffer(chunk[0]),
        .acc_clear(phase == S_PROJ_CLEAR), .mac_valid(phase == S_PROJ_MAC), .mac_ready(mac0_ready),
        .activation_data(mac_activation), .result_valid(mac0_result_valid),
        .result_data(mac0_result));
    mac_array_16x16 mac1 (
        .clk(clk), .rst_n(rst_n), .weight_load_valid((phase == S_PROJ_LOAD) && weight_bank_valid[0] && weight_bank_valid[1]),
        .weight_load_ready(mac1_wready), .weight_load_buffer(chunk[0]),
        .weight_load_beat(load_beat), .weight_load_data(weight_bank_rdata[511:256]),
        .weight_activate(phase == S_PROJ_ACT), .weight_activate_buffer(chunk[0]),
        .acc_clear(phase == S_PROJ_CLEAR), .mac_valid(phase == S_PROJ_MAC), .mac_ready(mac1_ready),
        .activation_data(mac_activation), .result_valid(mac1_result_valid),
        .result_data(mac1_result));

    reg conv_in_valid;
    wire conv_in_ready, conv_out_valid;
    wire [127:0] conv_alpha_out, conv_beta_out;
    reg [511:0] conv_history;
    integer ch, lane;
    always @* begin
        conv_history = 512'd0;
        for (ch = 0; ch < 16; ch = ch + 1) begin
            conv_history[(ch*4+0)*8 +: 8] = input_vector[(conv_sent*16+ch)*8 +: 8];
            conv_history[(ch*4+1)*8 +: 8] = input_vector[(conv_sent*16+ch)*8 +: 8];
            conv_history[(ch*4+2)*8 +: 8] = input_vector[(conv_sent*16+ch)*8 +: 8];
            conv_history[(ch*4+3)*8 +: 8] = input_vector[(conv_sent*16+ch)*8 +: 8];
        end
    end
    conv_unit gates (
        .clk(clk), .rst_n(rst_n), .in_valid((phase == S_CONV) && (conv_sent < 8)), .in_ready(conv_in_ready),
        .history_data(conv_history), .alpha_weights(conv_alpha_weights),
        .beta_weights(conv_beta_weights), .alpha_bias(conv_alpha_bias),
        .beta_bias(conv_beta_bias), .out_valid(conv_out_valid),
        .alpha_out(conv_alpha_out), .beta_out(conv_beta_out));

    reg state_start, state_pass;
    wire state_input_valid = state_row_valid &&
                             ((phase == S_P1_RUN) || (phase == S_P2_RUN));
    wire state_input_ready, state_output_valid, state_done;
    wire [6:0] state_output_index;
    wire [3071:0] state_output_row, state_reduction;
    wire [3071:0] delta_vector;
    function signed [23:0] make_delta;
        input signed [7:0] v_value;
        input signed [23:0] u_value;
        input signed [7:0] beta_value;
        reg signed [24:0] difference;
        reg signed [32:0] product;
        begin
            difference = {{17{v_value[7]}},v_value} - {u_value[23],u_value};
            product = difference * beta_value;
            make_delta = sat24_from32(product >>> 7);
        end
    endfunction

    state_update state_engine (
        .clk(clk), .rst_n(rst_n), .start(state_start), .pass_select(state_pass),
        .row_valid(state_input_valid), .row_ready(state_input_ready),
        .row_index(consume_row[6:0]), .state_row_in(state_row_rdata),
        .alpha_scalar(alpha_vector[consume_row*8 +: 8]),
        .k_scalar(k_vector[consume_row*8 +: 8]),
        .q_scalar(q_vector[consume_row*8 +: 8]), .delta_vector(delta_vector),
        .row_out_valid(state_output_valid), .row_out_index(state_output_index),
        .state_row_out(state_output_row), .done(state_done),
        .reduction_vector(state_reduction));
    assign state_row_wdata = state_output_row;

    reg norm_start, norm_in_valid;
    wire norm_in_ready, norm_out_valid, norm_done;
    wire [127:0] norm_out;
    norm_unit norm_engine (
        .clk(clk), .rst_n(rst_n), .start(norm_start), .in_valid(norm_in_valid),
        .in_ready(norm_in_ready), .in_data(o_vector_24[norm_beat*384 +: 384]),
        .out_valid(norm_out_valid), .out_ready(1'b1), .out_data(norm_out), .done(norm_done));

    reg residual_start, residual_in_valid;
    wire residual_in_ready, residual_out_valid, residual_done;
    wire [127:0] residual_out;
    residual_unit residual_engine (
        .clk(clk), .rst_n(rst_n), .start(residual_start),
        .in_valid(residual_in_valid), .in_ready(residual_in_ready),
        .main_data(norm_vector[residual_beat*128 +: 128]),
        .skip_data(skip_vector[residual_beat*128 +: 128]),
        .out_valid(residual_out_valid), .out_ready(1'b1),
        .out_data(residual_out), .done(residual_done));

    assign in_ready = (phase == S_COLLECT);
    assign out_valid = (phase == S_OUTPUT);
    assign activation_out = final_vector[output_beat*128 +: 128];
    assign out_last = (output_beat == 4'd7);
    assign busy = (phase != S_COLLECT) || (input_beat != 0);

    integer idx;
    reg [15:0] weight_address;
    always @* begin
        weight_address = projection * 16'd128 + tile_pair * 16'd32 +
                         chunk * 16'd4 + load_beat;
    end
    assign weight_bank_addr = {64'd0, weight_address, weight_address};

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= S_COLLECT; input_beat <= 0; projection <= 0; tile_pair <= 0;
            chunk <= 0; load_beat <= 0; conv_sent <= 0; conv_got <= 0;
            issue_row <= 0; consume_row <= 0; vector_index <= 0; read_outstanding <= 0; norm_beat <= 0; norm_got <= 0;
            residual_beat <= 0; residual_got <= 0; output_beat <= 0;
            weight_bank_req <= 0;
            state_read_req <= 0; state_write_req <= 0; state_read_bank <= 0;
            state_write_bank <= 1; state_read_addr <= 0; state_write_addr <= 0;
            mac_weight_load <= 0; mac_activate <= 0; mac_clear <= 0; mac_valid <= 0;
            conv_in_valid <= 0; state_start <= 0; state_pass <= 0;
            norm_start <= 0; norm_in_valid <= 0; residual_start <= 0;
            residual_in_valid <= 0; fault <= 0;
        end else begin
            weight_bank_req <= 0; mac_weight_load <= 0; mac_activate <= 0;
            mac_clear <= 0; mac_valid <= 0; conv_in_valid <= 0;
            state_start <= 0; state_read_req <= 0;
            state_write_req <= state_output_valid; state_write_addr <= state_output_index;
            norm_start <= 0; norm_in_valid <= 0; residual_start <= 0;
            residual_in_valid <= 0;
            if (residual_out_valid && ((phase == S_RES_FEED) || (phase == S_RES_WAIT))) begin
                residual_got <= residual_got + 1'b1;
                if (residual_got == 7) begin output_beat <= 0; phase <= S_OUTPUT; end
            end

            case (phase)
                S_COLLECT: if (in_valid && in_ready) begin
                    if ((input_beat == 7) != in_last) fault <= 1'b1;
                    if (input_beat == 7) begin
                        input_beat <= 0; projection <= 0; tile_pair <= 0; chunk <= 0;
                        phase <= S_PROJ_CLEAR;
                    end else input_beat <= input_beat + 1'b1;
                end

                S_PROJ_CLEAR: begin mac_clear <= 1; load_beat <= 0; phase <= S_PROJ_LOAD; end
                S_PROJ_LOAD: begin
                    weight_bank_req <= 6'b000011;
                    if (weight_bank_valid[0] && weight_bank_valid[1] && mac0_wready && mac1_wready) begin
                        mac_weight_load <= 1;
                        if (load_beat == 3) phase <= S_PROJ_ACT;
                        else load_beat <= load_beat + 1'b1;
                    end
                end
                S_PROJ_ACT: begin mac_activate <= 1; phase <= S_PROJ_MAC; end
                S_PROJ_MAC: if (mac0_ready && mac1_ready) begin mac_valid <= 1; phase <= S_PROJ_WAIT; end
                S_PROJ_WAIT: if (mac0_result_valid && mac1_result_valid) begin
                    if (chunk != 7) begin chunk <= chunk + 1'b1; load_beat <= 0; phase <= S_PROJ_LOAD; end
                    else if (tile_pair != 3) begin tile_pair <= tile_pair + 1'b1; chunk <= 0; phase <= S_PROJ_CLEAR; end
                    else if (projection == 2) begin conv_sent <= 0; conv_got <= 0; phase <= S_CONV; end
                    else if (projection == 3) begin norm_beat <= 0; phase <= S_NORM_START; end
                    else begin projection <= projection + 1'b1; tile_pair <= 0; chunk <= 0; phase <= S_PROJ_CLEAR; end
                end

                S_CONV: begin
                    if (conv_sent < 8 && conv_in_ready) begin conv_in_valid <= 1; conv_sent <= conv_sent + 1'b1; end
                    if (conv_out_valid) begin
                        conv_got <= conv_got + 1'b1;
                        if (conv_got == 7) phase <= S_P1_START;
                    end
                end

                S_P1_START: begin
                    state_pass <= 0; state_start <= 1; issue_row <= 0; consume_row <= 0; read_outstanding <= 0;
                    state_read_bank <= 0; state_write_bank <= 1; phase <= S_P1_RUN;
                end
                S_P1_RUN: begin
                    if (issue_row < 128 && state_input_ready && !read_outstanding) begin
                        state_read_req <= 1; state_read_addr <= issue_row[6:0]; issue_row <= issue_row + 1'b1; read_outstanding <= 1;
                    end
                    if (state_row_valid && state_input_ready) begin consume_row <= consume_row + 1'b1; read_outstanding <= 0; end
                    if (state_done) begin vector_index <= 0; phase <= S_DELTA; end
                end
                S_DELTA: begin
                    if (vector_index == 127) phase <= S_P2_START;
                    else vector_index <= vector_index + 1'b1;
                end
                S_P2_START: begin
                    state_pass <= 1; state_start <= 1; issue_row <= 0; consume_row <= 0; read_outstanding <= 0;
                    state_read_bank <= 1; state_write_bank <= 0; phase <= S_P2_RUN;
                end
                S_P2_RUN: begin
                    if (issue_row < 128 && state_input_ready && !read_outstanding) begin
                        state_read_req <= 1; state_read_addr <= issue_row[6:0]; issue_row <= issue_row + 1'b1; read_outstanding <= 1;
                    end
                    if (state_row_valid && state_input_ready) begin consume_row <= consume_row + 1'b1; read_outstanding <= 0; end
                    if (state_done) begin vector_index <= 0; phase <= S_P2_CAPTURE; end
                end
                S_P2_CAPTURE: begin
                    if (vector_index == 127) begin
                        projection <= 3; tile_pair <= 0; chunk <= 0; phase <= S_PROJ_CLEAR;
                    end else vector_index <= vector_index + 1'b1;
                end

                S_NORM_START: begin norm_start <= 1; norm_beat <= 0; norm_got <= 0; phase <= S_NORM_FEED; end
                S_NORM_FEED: if (norm_in_ready) begin
                    norm_in_valid <= 1;
                    if (norm_beat == 7) phase <= S_NORM_WAIT;
                    else norm_beat <= norm_beat + 1'b1;
                end
                S_NORM_WAIT: if (norm_out_valid) begin
                    norm_got <= norm_got + 1'b1;
                    if (norm_got == 7) phase <= S_RES_START;
                end
                S_RES_START: begin residual_start <= 1; residual_beat <= 0; residual_got <= 0; phase <= S_RES_FEED; end
                S_RES_FEED: if (residual_in_ready) begin
                    residual_in_valid <= 1;
                    if (residual_beat == 7) phase <= S_RES_WAIT;
                    else residual_beat <= residual_beat + 1'b1;
                end
                S_RES_WAIT: begin end
                S_OUTPUT: if (out_valid && out_ready) begin
                    if (output_beat == 7) begin output_beat <= 0; phase <= S_COLLECT; end
                    else output_beat <= output_beat + 1'b1;
                end
                default: begin fault <= 1; phase <= S_COLLECT; end
            endcase
        end
    end

    wire projection_capture = phase == S_PROJ_WAIT && mac0_result_valid &&
                              mac1_result_valid && chunk == 7;
    wire [127:0] mac0_sat, mac1_sat;
    genvar sv;
    generate for (sv=0; sv<16; sv=sv+1) begin : g_mac_sat
        assign mac0_sat[sv*8 +: 8] = sat8_from24(mac0_result[sv*24 +: 24]);
        assign mac1_sat[sv*8 +: 8] = sat8_from24(mac1_result[sv*24 +: 24]);
    end endgenerate

    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) input_store(
        .clk(clk),.write_en(phase==S_COLLECT && in_valid && in_ready),
        .write_addr(input_beat[2:0]),.write_data(activation_in),.packed_data(input_vector));
    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) skip_store(
        .clk(clk),.write_en(phase==S_COLLECT && in_valid && in_ready),
        .write_addr(input_beat[2:0]),.write_data(skip_in),.packed_data(skip_vector));

    wire [511:0] k_lo,k_hi,v_lo,v_hi,q_lo,q_hi;
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) k0_store(.clk(clk),.write_en(projection_capture&&projection==0),.write_addr(tile_pair),.write_data(mac0_sat),.packed_data(k_lo));
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) k1_store(.clk(clk),.write_en(projection_capture&&projection==0),.write_addr(tile_pair),.write_data(mac1_sat),.packed_data(k_hi));
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) v0_store(.clk(clk),.write_en(projection_capture&&projection==1),.write_addr(tile_pair),.write_data(mac0_sat),.packed_data(v_lo));
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) v1_store(.clk(clk),.write_en(projection_capture&&projection==1),.write_addr(tile_pair),.write_data(mac1_sat),.packed_data(v_hi));
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) q0_store(.clk(clk),.write_en(projection_capture&&projection==2),.write_addr(tile_pair),.write_data(mac0_sat),.packed_data(q_lo));
    vector_store #(.WORD_W(128),.DEPTH(4),.ADDR_W(2)) q1_store(.clk(clk),.write_en(projection_capture&&projection==2),.write_addr(tile_pair),.write_data(mac1_sat),.packed_data(q_hi));
    assign k_vector={k_hi,k_lo}; assign v_vector={v_hi,v_lo}; assign q_vector={q_hi,q_lo};

    wire [1535:0] o_lo,o_hi;
    vector_store #(.WORD_W(384),.DEPTH(4),.ADDR_W(2)) o0_store(.clk(clk),.write_en(projection_capture&&projection==3),.write_addr(tile_pair),.write_data(mac0_result),.packed_data(o_lo));
    vector_store #(.WORD_W(384),.DEPTH(4),.ADDR_W(2)) o1_store(.clk(clk),.write_en(projection_capture&&projection==3),.write_addr(tile_pair),.write_data(mac1_result),.packed_data(o_hi));
    assign o_vector_24={o_hi,o_lo};

    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) alpha_store(.clk(clk),.write_en(phase==S_CONV&&conv_out_valid),.write_addr(conv_got[2:0]),.write_data(conv_alpha_out),.packed_data(alpha_vector));
    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) beta_store(.clk(clk),.write_en(phase==S_CONV&&conv_out_valid),.write_addr(conv_got[2:0]),.write_data(conv_beta_out),.packed_data(beta_vector));
    vector_store #(.WORD_W(24),.DEPTH(128),.ADDR_W(7)) delta_store(.clk(clk),.write_en(phase==S_DELTA),.write_addr(vector_index),.write_data(make_delta(v_vector[vector_index*8 +: 8],state_reduction[vector_index*24 +: 24],beta_vector[vector_index*8 +: 8])),.packed_data(delta_vector));
    vector_store #(.WORD_W(8),.DEPTH(128),.ADDR_W(7)) query_store(.clk(clk),.write_en(phase==S_P2_CAPTURE),.write_addr(vector_index),.write_data(sat8_from24(state_reduction[vector_index*24 +: 24])),.packed_data(query_vector));
    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) norm_store(.clk(clk),.write_en(phase==S_NORM_WAIT&&norm_out_valid),.write_addr(norm_got[2:0]),.write_data(norm_out),.packed_data(norm_vector));
    vector_store #(.WORD_W(128),.DEPTH(8),.ADDR_W(3)) final_store(.clk(clk),.write_en(residual_out_valid&&((phase==S_RES_FEED)||(phase==S_RES_WAIT))),.write_addr(residual_got[2:0]),.write_data(residual_out),.packed_data(final_vector));
endmodule
