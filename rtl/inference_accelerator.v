// Inference Accelerator Top Module
// Complete INT4 inference engine with SRAM, MAC array, and AXI-Lite interface
// Target: Beat Kimi K3 specs (4mm², 100MHz, 8700 tok/s)
module inference_accelerator #(
    parameter TILE_SIZE = 16,
    parameter WGT_SRAM_DEPTH = 4096,   // 4K x 64b = 32KB weight SRAM
    parameter ACT_SRAM_DEPTH = 4096,   // 4K x 64b = 32KB activation SRAM
    parameter OUT_SRAM_DEPTH = 1024    // 1K x 256b = 32KB output buffer
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // AXI-Lite Slave Interface
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    
    // Output stream interface
    output wire        o_valid,
    output wire [7:0]  o_row,
    output wire [7:0]  o_col,
    output wire [TILE_SIZE*TILE_SIZE*32-1:0] o_data,
    input  wire        o_ready,
    
    // Status
    output wire        busy,
    output wire        done
);

    // Internal signals
    wire        ctrl_start;
    wire [7:0]  ctrl_m_dim, ctrl_n_dim, ctrl_k_dim;
    wire        status_busy, status_done;
    
    // DMA interface
    wire        dma_wgt_we, dma_act_we;
    wire [11:0] dma_wgt_addr, dma_act_addr;
    wire [63:0] dma_wgt_data, dma_act_data;
    
    // Controller to SRAM
    wire        wgt_cs, act_cs;
    wire [11:0] wgt_addr, act_addr;
    
    // SRAM data outputs
    wire [63:0] wgt_rdata, act_rdata;
    
    // MAC array control
    wire        mac_en, mac_clear;
    wire [TILE_SIZE*4-1:0]  act_to_mac;
    wire [TILE_SIZE*4-1:0]  wgt_to_mac;
    wire [TILE_SIZE*TILE_SIZE*32-1:0] mac_acc;
    
    // Output control
    wire        out_valid;
    wire [7:0]  out_row, out_col;

    // AXI-Lite Slave
    axi_lite_slave u_axi (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .ctrl_start     (ctrl_start),
        .ctrl_m_dim     (ctrl_m_dim),
        .ctrl_n_dim     (ctrl_n_dim),
        .ctrl_k_dim     (ctrl_k_dim),
        .status_busy    (status_busy),
        .status_done    (status_done),
        .dma_wgt_we     (dma_wgt_we),
        .dma_wgt_addr   (dma_wgt_addr),
        .dma_wgt_data   (dma_wgt_data),
        .dma_act_we     (dma_act_we),
        .dma_act_addr   (dma_act_addr),
        .dma_act_data   (dma_act_data)
    );

    // Matrix Multiply Controller
    mm_controller #(
        .TILE_SIZE (TILE_SIZE),
        .MAX_DIM   (256)
    ) u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (ctrl_start),
        .m_dim      (ctrl_m_dim),
        .n_dim      (ctrl_n_dim),
        .k_dim      (ctrl_k_dim),
        .busy       (status_busy),
        .done       (status_done),
        .wgt_cs     (wgt_cs),
        .wgt_addr   (wgt_addr),
        .act_cs     (act_cs),
        .act_addr   (act_addr),
        .mac_en     (mac_en),
        .mac_clear  (mac_clear),
        .out_valid  (out_valid),
        .out_row    (out_row),
        .out_col    (out_col)
    );

    // Weight SRAM - dual port for DMA write and controller read
    // Using simple arbitration: DMA has priority
    wire        wgt_sram_cs = dma_wgt_we ? 1'b1 : wgt_cs;
    wire        wgt_sram_we = dma_wgt_we;
    wire [11:0] wgt_sram_addr = dma_wgt_we ? dma_wgt_addr : wgt_addr;
    
    sram_sp #(
        .DEPTH  (WGT_SRAM_DEPTH),
        .WIDTH  (64)
    ) u_wgt_sram (
        .clk    (clk),
        .cs     (wgt_sram_cs),
        .we     (wgt_sram_we),
        .addr   (wgt_sram_addr),
        .wdata  (dma_wgt_data),
        .rdata  (wgt_rdata)
    );

    // Activation SRAM
    wire        act_sram_cs = dma_act_we ? 1'b1 : act_cs;
    wire        act_sram_we = dma_act_we;
    wire [11:0] act_sram_addr = dma_act_we ? dma_act_addr : act_addr;
    
    sram_sp #(
        .DEPTH  (ACT_SRAM_DEPTH),
        .WIDTH  (64)
    ) u_act_sram (
        .clk    (clk),
        .cs     (act_sram_cs),
        .we     (act_sram_we),
        .addr   (act_sram_addr),
        .wdata  (dma_act_data),
        .rdata  (act_rdata)
    );

    // Data formatting: 64-bit SRAM word -> 16 INT4 values
    assign wgt_to_mac = wgt_rdata[TILE_SIZE*4-1:0];
    assign act_to_mac = act_rdata[TILE_SIZE*4-1:0];

    // MAC Array
    mac_array #(
        .ROWS   (TILE_SIZE),
        .COLS   (TILE_SIZE)
    ) u_mac (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (mac_en),
        .clear   (mac_clear),
        .act_in  (act_to_mac),
        .wgt_in  (wgt_to_mac),
        .acc_out (mac_acc)
    );

    // Output interface
    assign o_valid = out_valid;
    assign o_row   = out_row;
    assign o_col   = out_col;
    assign o_data  = mac_acc;
    assign busy    = status_busy;
    assign done    = status_done;

endmodule
