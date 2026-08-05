// AXI-Lite Slave Interface
// Register map for accelerator control
module axi_lite_slave #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // AXI-Lite Write Address Channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,
    
    // AXI-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [3:0]              s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,
    
    // AXI-Lite Write Response Channel
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,
    
    // AXI-Lite Read Address Channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,
    
    // AXI-Lite Read Data Channel
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,
    
    // Control registers output
    output reg                     ctrl_start,
    output reg  [7:0]              ctrl_m_dim,
    output reg  [7:0]              ctrl_n_dim,
    output reg  [7:0]              ctrl_k_dim,
    input  wire                    status_busy,
    input  wire                    status_done,
    
    // DMA-style data interface
    output reg                     dma_wgt_we,
    output reg  [11:0]             dma_wgt_addr,
    output reg  [63:0]             dma_wgt_data,
    output reg                     dma_act_we,
    output reg  [11:0]             dma_act_addr,
    output reg  [63:0]             dma_act_data
);

    // Register addresses
    localparam REG_CTRL    = 8'h00;  // Control: bit0=start
    localparam REG_STATUS  = 8'h04;  // Status: bit0=busy, bit1=done
    localparam REG_M_DIM   = 8'h08;  // M dimension
    localparam REG_N_DIM   = 8'h0C;  // N dimension
    localparam REG_K_DIM   = 8'h10;  // K dimension
    localparam REG_WGT_ADR = 8'h20;  // Weight address
    localparam REG_WGT_DAT = 8'h24;  // Weight data (low)
    localparam REG_WGT_DAH = 8'h28;  // Weight data (high)
    localparam REG_ACT_ADR = 8'h30;  // Activation address
    localparam REG_ACT_DAT = 8'h34;  // Activation data (low)
    localparam REG_ACT_DAH = 8'h38;  // Activation data (high)

    reg [ADDR_WIDTH-1:0] aw_addr;
    reg [ADDR_WIDTH-1:0] ar_addr;
    reg [31:0] wgt_data_low, wgt_data_high;
    reg [31:0] act_data_low, act_data_high;

    // Write state machine
    localparam W_IDLE = 2'b00;
    localparam W_DATA = 2'b01;
    localparam W_RESP = 2'b10;
    reg [1:0] w_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            aw_addr <= 0;
            ctrl_start <= 1'b0;
            ctrl_m_dim <= 8'd16;
            ctrl_n_dim <= 8'd16;
            ctrl_k_dim <= 8'd16;
            dma_wgt_we <= 1'b0;
            dma_wgt_addr <= 12'd0;
            dma_wgt_data <= 64'd0;
            dma_act_we <= 1'b0;
            dma_act_addr <= 12'd0;
            dma_act_data <= 64'd0;
            wgt_data_low <= 32'd0;
            wgt_data_high <= 32'd0;
            act_data_low <= 32'd0;
            act_data_high <= 32'd0;
        end else begin
            // Auto-clear start signal
            ctrl_start <= 1'b0;
            dma_wgt_we <= 1'b0;
            dma_act_we <= 1'b0;

            case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        aw_addr <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        s_axi_wready <= 1'b1;
                        w_state <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        // Decode register write
                        case (aw_addr)
                            REG_CTRL:    ctrl_start <= s_axi_wdata[0];
                            REG_M_DIM:   ctrl_m_dim <= s_axi_wdata[7:0];
                            REG_N_DIM:   ctrl_n_dim <= s_axi_wdata[7:0];
                            REG_K_DIM:   ctrl_k_dim <= s_axi_wdata[7:0];
                            REG_WGT_ADR: dma_wgt_addr <= s_axi_wdata[11:0];
                            REG_WGT_DAT: wgt_data_low <= s_axi_wdata;
                            REG_WGT_DAH: begin
                                wgt_data_high <= s_axi_wdata;
                                dma_wgt_data <= {s_axi_wdata, wgt_data_low};
                                dma_wgt_we <= 1'b1;
                            end
                            REG_ACT_ADR: dma_act_addr <= s_axi_wdata[11:0];
                            REG_ACT_DAT: act_data_low <= s_axi_wdata;
                            REG_ACT_DAH: begin
                                act_data_high <= s_axi_wdata;
                                dma_act_data <= {s_axi_wdata, act_data_low};
                                dma_act_we <= 1'b1;
                            end
                        endcase
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp <= 2'b00;
                        w_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        w_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // Read state machine
    localparam R_IDLE = 2'b00;
    localparam R_DATA = 2'b01;
    reg [1:0] r_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            ar_addr <= 0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        ar_addr <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        // Decode register read
                        case (s_axi_araddr)
                            REG_STATUS:  s_axi_rdata <= {30'd0, status_done, status_busy};
                            REG_M_DIM:   s_axi_rdata <= {24'd0, ctrl_m_dim};
                            REG_N_DIM:   s_axi_rdata <= {24'd0, ctrl_n_dim};
                            REG_K_DIM:   s_axi_rdata <= {24'd0, ctrl_k_dim};
                            default:     s_axi_rdata <= 32'd0;
                        endcase
                        s_axi_rvalid <= 1'b1;
                        s_axi_rresp <= 2'b00;
                        r_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (s_axi_rready && s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b0;
                        r_state <= R_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
