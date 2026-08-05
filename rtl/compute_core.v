// Compute Core - MAC Array + Controller (no SRAM)
// For P&R with black-boxed memory interfaces
// Target: Demonstrate compute throughput separate from memory
module compute_core #(
    parameter TILE_SIZE = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface  
    input  wire        start,
    input  wire [7:0]  m_dim,
    input  wire [7:0]  n_dim,
    input  wire [7:0]  k_dim,
    output wire        busy,
    output wire        done,
    
    // Weight memory interface (to external SRAM macro)
    output wire        wgt_cs,
    output wire [11:0] wgt_addr,
    input  wire [63:0] wgt_rdata,
    
    // Activation memory interface (to external SRAM macro)
    output wire        act_cs,
    output wire [11:0] act_addr,
    input  wire [63:0] act_rdata,
    
    // Output interface
    output wire        out_valid,
    output wire [7:0]  out_row,
    output wire [7:0]  out_col,
    output wire [TILE_SIZE*TILE_SIZE*32-1:0] acc_out
);

    // Controller signals
    wire mac_en, mac_clear;
    
    // Data unpacking for MAC array
    wire [TILE_SIZE*4-1:0] act_to_mac = act_rdata[TILE_SIZE*4-1:0];
    wire [TILE_SIZE*4-1:0] wgt_to_mac = wgt_rdata[TILE_SIZE*4-1:0];

    // Matrix multiply controller FSM
    mm_controller #(
        .TILE_SIZE(TILE_SIZE)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .m_dim     (m_dim),
        .n_dim     (n_dim),
        .k_dim     (k_dim),
        .busy      (busy),
        .done      (done),
        .wgt_cs    (wgt_cs),
        .wgt_addr  (wgt_addr),
        .act_cs    (act_cs),
        .act_addr  (act_addr),
        .mac_en    (mac_en),
        .mac_clear (mac_clear),
        .out_valid (out_valid),
        .out_row   (out_row),
        .out_col   (out_col)
    );

    // 16x16 INT4 MAC array (256 parallel MACs)
    mac_array #(
        .ROWS(TILE_SIZE),
        .COLS(TILE_SIZE)
    ) u_mac (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (mac_en),
        .clear   (mac_clear),
        .act_in  (act_to_mac),
        .wgt_in  (wgt_to_mac),
        .acc_out (acc_out)
    );

endmodule
