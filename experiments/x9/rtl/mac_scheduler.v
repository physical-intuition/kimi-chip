`timescale 1ns/1ps
// Routes an output row to the array assigned by the X9 row split.
// This does not invent the unspecified weight reorder/prefetch buffer needed
// to feed both arrays concurrently from the row-major SRAM stream.
module mac_scheduler(
    input  wire       row_valid,
    input  wire [6:0] row,
    output wire       mac0_valid,
    output wire       mac1_valid,
    output wire [5:0] local_row
);
    assign mac0_valid = row_valid && !row[6];
    assign mac1_valid = row_valid &&  row[6];
    assign local_row = row[5:0];
endmodule
