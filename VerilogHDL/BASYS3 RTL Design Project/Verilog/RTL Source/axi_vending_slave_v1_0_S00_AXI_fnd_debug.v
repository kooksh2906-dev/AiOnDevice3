`timescale 1ns / 1ps

// Compact debug-only AXI4-Lite slave with the same six-register map as the
// final slave. It binds exclusively to slave_inventory_fnd_debug.
module axi_vending_slave_v1_0_S00_AXI_fnd_debug #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
) (
    input  wire S_AXI_ACLK,
    input  wire S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0] S_AXI_AWPROT,
    input  wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input  wire S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0] S_AXI_ARPROT,
    input  wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input  wire S_AXI_RREADY
);
    reg axi_awready;
    reg axi_wready;
    reg axi_bvalid;
    reg axi_arready;
    reg axi_rvalid;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;

    reg [31:0] reg_order;
    reg [31:0] reg_money;
    reg ctrl_trigger;
    integer byte_index;

    wire [31:0] w_db_status;
    wire [31:0] w_db_inventory;
    wire [31:0] w_db_change;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    // The project master presents AW and W together. Accept one combined
    // write and hold BVALID until BREADY.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            reg_order   <= 32'd0;
            reg_money   <= 32'd0;
            ctrl_trigger <= 1'b0;
        end
        else begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            ctrl_trigger <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_WVALID && !axi_bvalid) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
                axi_bvalid  <= 1'b1;

                case (S_AXI_AWADDR[4:2])
                    3'h0: ctrl_trigger <= S_AXI_WDATA[0];
                    3'h1: begin
                        for (byte_index = 0; byte_index < 4;
                             byte_index = byte_index + 1)
                            if (S_AXI_WSTRB[byte_index])
                                reg_order[byte_index*8 +: 8] <=
                                    S_AXI_WDATA[byte_index*8 +: 8];
                    end
                    3'h2: begin
                        for (byte_index = 0; byte_index < 4;
                             byte_index = byte_index + 1)
                            if (S_AXI_WSTRB[byte_index])
                                reg_money[byte_index*8 +: 8] <=
                                    S_AXI_WDATA[byte_index*8 +: 8];
                    end
                    default: begin end
                endcase
            end
            else if (axi_bvalid && S_AXI_BREADY)
                axi_bvalid <= 1'b0;
        end
    end

    // One outstanding read at a time. RDATA is selected from the same map:
    // 0x0C=status, 0x10=inventory, 0x14=change.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end
        else begin
            axi_arready <= 1'b0;

            if (S_AXI_ARVALID && !axi_rvalid) begin
                axi_arready <= 1'b1;
                axi_rvalid  <= 1'b1;
                case (S_AXI_ARADDR[4:2])
                    3'h1: axi_rdata <= reg_order;
                    3'h2: axi_rdata <= reg_money;
                    3'h3: axi_rdata <= w_db_status;
                    3'h4: axi_rdata <= w_db_inventory;
                    3'h5: axi_rdata <= w_db_change;
                    default: axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
                endcase
            end
            else if (axi_rvalid && S_AXI_RREADY)
                axi_rvalid <= 1'b0;
        end
    end

    // Protection attributes are intentionally unused, as in the final slave.
    wire unused_prot;
    assign unused_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};

    slave_inventory_fnd_debug u_inventory_core (
        .clk           (S_AXI_ACLK),
        .arst          (~S_AXI_ARESETN),
        .i_ctrl_trigger(ctrl_trigger),
        .i_order_info  (reg_order),
        .i_money_in    (reg_money),
        .o_status      (w_db_status),
        .o_inventory   (w_db_inventory),
        .o_change      (w_db_change)
    );
endmodule
