`timescale 1ns/1ps

// Sixteen-lane saturating residual add. Eight accepted beats cover 128 values.
module residual_unit (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire          in_valid,
    output wire          in_ready,
    input  wire [127:0]  main_data,
    input  wire [127:0]  skip_data,
    output reg           out_valid,
    input  wire          out_ready,
    output reg  [127:0]  out_data,
    output reg           done
);
    reg busy;
    reg [3:0] beat_count;
    integer lane;
    reg signed [8:0] add_temp;

    assign in_ready = busy && (!out_valid || out_ready);

    function signed [7:0] sat8;
        input signed [8:0] value;
        begin
            if (value > 9'sd127) sat8 = 8'sd127;
            else if (value < -9'sd128) sat8 = -8'sd128;
            else sat8 = value[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            beat_count <= 4'd0;
            out_valid <= 1'b0;
            out_data <= 128'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (out_valid && out_ready)
                out_valid <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                beat_count <= 4'd0;
            end
            if (in_valid && in_ready) begin
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    add_temp = $signed(main_data[lane*8 +: 8]) +
                               $signed(skip_data[lane*8 +: 8]);
                    out_data[lane*8 +: 8] <= sat8(add_temp);
                end
                out_valid <= 1'b1;
                if (beat_count == 4'd7) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else beat_count <= beat_count + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && start)
            assert (!busy) else $error("residual start while busy");
        if (rst_n && in_valid)
            assert (in_ready) else $error("residual input dropped by backpressure");
    end
`endif
endmodule
