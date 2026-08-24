`timescale 1ns/1ps

// Six-bank to two-buffer registered weight router. Each selected 256-bit bank
// beat is placed into one of eight slices of a 2048-bit MAC-local line.
module weight_crossbar (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          route_valid,
    input  wire [2:0]    mac0_bank_select,
    input  wire [2:0]    mac1_bank_select,
    input  wire [2:0]    mac0_beat,
    input  wire [2:0]    mac1_beat,
    input  wire [1535:0] bank_data,
    input  wire [5:0]    bank_valid,
    output reg           mac0_valid,
    output reg           mac1_valid,
    output reg  [2047:0] mac0_weights,
    output reg  [2047:0] mac1_weights
);
    reg [255:0] selected0, selected1;

    always @* begin
        selected0 = 256'd0;
        selected1 = 256'd0;
        case (mac0_bank_select)
            3'd0: selected0 = bank_data[0*256 +: 256];
            3'd1: selected0 = bank_data[1*256 +: 256];
            3'd2: selected0 = bank_data[2*256 +: 256];
            3'd3: selected0 = bank_data[3*256 +: 256];
            3'd4: selected0 = bank_data[4*256 +: 256];
            3'd5: selected0 = bank_data[5*256 +: 256];
            default: selected0 = 256'd0;
        endcase
        case (mac1_bank_select)
            3'd0: selected1 = bank_data[0*256 +: 256];
            3'd1: selected1 = bank_data[1*256 +: 256];
            3'd2: selected1 = bank_data[2*256 +: 256];
            3'd3: selected1 = bank_data[3*256 +: 256];
            3'd4: selected1 = bank_data[4*256 +: 256];
            3'd5: selected1 = bank_data[5*256 +: 256];
            default: selected1 = 256'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac0_valid <= 1'b0;
            mac1_valid <= 1'b0;
            mac0_weights <= 2048'd0;
            mac1_weights <= 2048'd0;
        end else begin
            mac0_valid <= route_valid && (mac0_bank_select < 3'd6) && bank_valid[mac0_bank_select];
            mac1_valid <= route_valid && (mac1_bank_select < 3'd6) && bank_valid[mac1_bank_select];
            if (route_valid && (mac0_bank_select < 3'd6) && bank_valid[mac0_bank_select])
                mac0_weights[mac0_beat*256 +: 256] <= selected0;
            if (route_valid && (mac1_bank_select < 3'd6) && bank_valid[mac1_bank_select])
                mac1_weights[mac1_beat*256 +: 256] <= selected1;
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) if (rst_n && route_valid) begin
        assert (mac0_bank_select < 3'd6 && mac1_bank_select < 3'd6)
            else $error("weight crossbar selected nonexistent bank");
        assert (!(mac0_bank_select == mac1_bank_select &&
                  (!bank_valid[mac0_bank_select])))
            else $error("weight bank selected before data valid");
    end
`endif
endmodule
