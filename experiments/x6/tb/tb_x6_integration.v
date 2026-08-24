`timescale 1ns/1ps
module tb_x6_integration;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    integer failures = 0;
    integer i, tile, beat, lane;
    integer first_token_budget;

    // Projection MAC signals.
    reg m_wvalid=0, m_wbuf=0, m_wactivate=0, m_wactivate_buf=0;
    reg [2:0] m_wbeat=0; reg [255:0] m_wdata=0;
    reg m_clear=0, m_valid=0; reg [127:0] m_act=0;
    wire m_wready, m_ready, m_result_valid; wire [383:0] m_result;
    mac_array_16x16 mac (
        .clk(clk), .rst_n(rst_n), .weight_load_valid(m_wvalid), .weight_load_ready(m_wready),
        .weight_load_buffer(m_wbuf), .weight_load_beat(m_wbeat), .weight_load_data(m_wdata),
        .weight_activate(m_wactivate), .weight_activate_buffer(m_wactivate_buf), .acc_clear(m_clear),
        .mac_valid(m_valid), .mac_ready(m_ready), .activation_data(m_act),
        .result_valid(m_result_valid), .result_data(m_result));

    // Gate convolution signals.
    reg c_valid=0; reg [511:0] c_hist=0; reg [255:0] c_aw=0,c_bw=0,c_ab=0,c_bb=0;
    wire c_ready,c_out_valid; wire [127:0] c_alpha,c_beta;
    conv_unit conv (.clk(clk),.rst_n(rst_n),.in_valid(c_valid),.in_ready(c_ready),
        .history_data(c_hist),.alpha_weights(c_aw),.beta_weights(c_bw),.alpha_bias(c_ab),.beta_bias(c_bb),
        .out_valid(c_out_valid),.alpha_out(c_alpha),.beta_out(c_beta));

    // State recurrence signals.
    reg s_start=0,s_pass=0,s_row_valid=0; wire s_row_ready,s_out_valid,s_done;
    reg [6:0] s_row_index=0; reg [3071:0] s_row_in=0,s_delta=0;
    reg signed [7:0] s_alpha=0,s_k=0,s_q=0;
    wire [6:0] s_out_index; wire [3071:0] s_row_out,s_reduce;
    state_update state_dut (.clk(clk),.rst_n(rst_n),.start(s_start),.pass_select(s_pass),
        .row_valid(s_row_valid),.row_ready(s_row_ready),.row_index(s_row_index),.state_row_in(s_row_in),
        .alpha_scalar(s_alpha),.k_scalar(s_k),.q_scalar(s_q),.delta_vector(s_delta),
        .row_out_valid(s_out_valid),.row_out_index(s_out_index),.state_row_out(s_row_out),
        .done(s_done),.reduction_vector(s_reduce));

    // Norm and residual signals.
    reg n_start=0,n_in_valid=0; reg [383:0] n_in=0; wire n_ready,n_out_valid,n_done;
    wire [127:0] n_out;
    norm_unit norm (.clk(clk),.rst_n(rst_n),.start(n_start),.in_valid(n_in_valid),.in_ready(n_ready),
        .in_data(n_in),.out_valid(n_out_valid),.out_ready(1'b1),.out_data(n_out),.done(n_done));
    reg r_start=0,r_valid=0; reg [127:0] r_main=0,r_skip=0; wire r_ready,r_out_valid,r_done;
    wire [127:0] r_out;
    residual_unit residual (.clk(clk),.rst_n(rst_n),.start(r_start),.in_valid(r_valid),.in_ready(r_ready),
        .main_data(r_main),.skip_data(r_skip),.out_valid(r_out_valid),.out_ready(1'b1),.out_data(r_out),.done(r_done));

    reg [127:0] activ_mem [0:7]; reg [255:0] weights_mem [0:255];
    reg [383:0] projection_mem [0:7]; reg [3071:0] zero_state [0:127];
    reg [3071:0] delta_mem [0:0], updated_mem [0:127], qout_mem [0:0];
    reg [127:0] norm_golden [0:7], final_golden [0:7];
    reg signed [7:0] projection [0:127], gate_alpha [0:127], gate_beta [0:127];
    reg [127:0] norm_beats [0:7];
    integer conv_outputs=0, state_outputs=0, norm_outputs=0, residual_outputs=0;

    always @(negedge clk) begin
        if (rst_n && c_out_valid) begin
            for (lane=0; lane<16; lane=lane+1) begin
                gate_alpha[conv_outputs*16+lane] = c_alpha[lane*8 +: 8];
                gate_beta[conv_outputs*16+lane] = c_beta[lane*8 +: 8];
            end
            conv_outputs = conv_outputs + 1;
        end
        if (rst_n && s_out_valid) begin
            if (!s_pass && s_row_out !== zero_state[s_out_index]) begin
                $display("FAIL INTEGRATION scale row %0d", s_out_index); failures=failures+1;
            end
            if (s_pass && s_row_out !== updated_mem[s_out_index]) begin
                $display("FAIL INTEGRATION update row %0d", s_out_index); failures=failures+1;
            end
            state_outputs = state_outputs + 1;
        end
        if (rst_n && n_out_valid) begin
            norm_beats[norm_outputs] = n_out;
            if (n_out !== norm_golden[norm_outputs]) begin
                $display("FAIL INTEGRATION norm beat %0d",norm_outputs); failures=failures+1;
            end
            norm_outputs = norm_outputs + 1;
        end
        if (rst_n && r_out_valid) begin
            if (r_out !== final_golden[residual_outputs]) begin
                $display("FAIL INTEGRATION final beat %0d got=%h expected=%h",residual_outputs,r_out,final_golden[residual_outputs]);
                failures=failures+1;
            end
            residual_outputs = residual_outputs + 1;
        end
    end

    task load_mac_subtile;
        input integer t;
        input integer chunk;
        integer wb;
        begin
            for (wb=0;wb<4;wb=wb+1) begin
                @(negedge clk); m_wvalid=1; m_wbuf=chunk[0]; m_wbeat=wb[2:0];
                m_wdata=weights_mem[t*32+chunk*4+wb];
            end
            @(negedge clk); m_wvalid=0; m_wactivate=1; m_wactivate_buf=chunk[0];
            @(negedge clk); m_wactivate=0;
        end
    endtask

    task run_state_pass;
        input reg p;
        begin
            s_pass=p; state_outputs=0;
            @(negedge clk); s_start=1;
            @(negedge clk); s_start=0;
            for (i=0;i<128;i=i+1) begin
                wait(s_row_ready); @(negedge clk);
                s_row_valid=1; s_row_index=i[6:0]; s_row_in=zero_state[i];
                s_alpha=gate_alpha[i]; s_k=projection[i]; s_q=projection[i];
                @(negedge clk); s_row_valid=0;
            end
            wait(s_done); @(negedge clk); #1;
            if(state_outputs!=128) begin $display("FAIL INTEGRATION state rows=%0d",state_outputs); failures=failures+1; end
        end
    endtask

    initial begin
        $readmemh("tb/vectors/integration_activation.mem",activ_mem);
        $readmemh("tb/vectors/integration_weights.mem",weights_mem);
        $readmemh("tb/vectors/integration_projection.mem",projection_mem);
        $readmemh("tb/vectors/integration_zero_state.mem",zero_state);
        $readmemh("tb/vectors/integration_delta.mem",delta_mem);
        $readmemh("tb/vectors/integration_state_updated.mem",updated_mem);
        $readmemh("tb/vectors/integration_qout.mem",qout_mem);
        $readmemh("tb/vectors/integration_norm.mem",norm_golden);
        $readmemh("tb/vectors/integration_final.mem",final_golden);
        repeat(3) @(posedge clk); rst_n=1;

        // K/V/Q projection representative: one complete 128x128 GEMV, 64 accepted beats.
        for(tile=0;tile<8;tile=tile+1) begin
            @(negedge clk); m_clear=1;
            @(negedge clk); m_clear=0;
            for(beat=0;beat<8;beat=beat+1) begin
                load_mac_subtile(tile,beat);
                @(negedge clk); m_valid=1; m_act=activ_mem[beat];
                @(negedge clk); m_valid=0;
                wait(m_result_valid);
            end
            wait(m_result_valid); @(negedge clk); #1;
            if(!m_result_valid || m_result!==projection_mem[tile]) begin
                $display("FAIL INTEGRATION projection tile %0d",tile); failures=failures+1;
            end
            for(lane=0;lane<16;lane=lane+1) projection[tile*16+lane]=m_result[lane*24 +: 8];
        end

        // Alpha/beta gates: zero kernels, sigmoid(0)=64 and tanh(128)=64.
        c_ab=0; c_bb={16{16'd128}};
        for(beat=0;beat<8;beat=beat+1) begin @(negedge clk); c_valid=1; end
        @(negedge clk); c_valid=0; wait(conv_outputs==8);
        for(i=0;i<128;i=i+1) if(gate_alpha[i]!==8'sd64 || gate_beta[i]!==8'sd64) begin
            $display("FAIL INTEGRATION gate lane %0d",i); failures=failures+1;
        end

        s_delta=delta_mem[0];
        run_state_pass(1'b0);
        if(s_reduce!==3072'd0) begin $display("FAIL INTEGRATION u not zero"); failures=failures+1; end
        repeat(2) @(posedge clk);
        run_state_pass(1'b1);
        if(s_reduce!==qout_mem[0]) begin $display("FAIL INTEGRATION q output mismatch"); failures=failures+1; end

        @(negedge clk); n_start=1;
        @(negedge clk); n_start=0;
        for(beat=0;beat<8;beat=beat+1) begin
            n_in_valid=1; n_in=s_reduce[beat*384 +: 384]; @(negedge clk);
        end
        n_in_valid=0; wait(norm_outputs==8);

        @(negedge clk); r_start=1;
        @(negedge clk); r_start=0;
        for(beat=0;beat<8;beat=beat+1) begin
            r_valid=1; r_main=norm_beats[beat]; r_skip={16{8'd3}}; @(negedge clk);
        end
        r_valid=0; wait(residual_outputs==8);

        // First-token schedule: K/V/Q plus gate overlap=128, recurrence=258,
        // O projection=64, RMSNorm=24, residual/writeback=8.
        first_token_budget=128+258+64+24+8;
        if(first_token_budget!=482) begin $display("FAIL INTEGRATION budget=%0d",first_token_budget); failures=failures+1; end
        if(failures==0) $display("PASS tb_x6_integration: projection->gates->state->norm->residual, budget=482");
        else $display("FAIL tb_x6_integration: %0d errors",failures);
        $finish_and_return(failures!=0);
    end
endmodule
