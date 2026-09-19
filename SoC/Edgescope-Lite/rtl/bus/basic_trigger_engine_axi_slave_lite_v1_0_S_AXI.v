`timescale 1 ns / 1 ps

//------------------------------------------------------------------------------
// Basic Trigger Engine AXI4-Lite Slave Module
//
// Vivado AXI4-Lite Peripheral Template의 구조를 유지하면서,
// 5개 User Register와 DAY1 basic_trigger_engine 코어를 연결한다.
//
// Offset  slv_reg   Register       Access  Bit Definition
// 0x00    slv_reg0  CONTROL        W1P     [0] ARM, [1] CLEAR
// 0x04    slv_reg1  CONFIG         RW      [1:0] MODE, [10:8] EDGE_CHANNEL
// 0x08    slv_reg2  PATTERN        RW      [7:0] VALUE, [15:8] MASK
// 0x0C    slv_reg3  STATUS         RO      [0] ARMED, [1] TRIGGERED
// 0x10    slv_reg4  TRIGGER_COUNT  RO      [31:0] 누적 Trigger 횟수
//
// CONTROL은 Write transaction에서만 1 Clock Pulse를 생성하며 Read 값은 0이다.
// Reserved bit는 Write 시 무시하고 Read 시 0을 반환한다.
//------------------------------------------------------------------------------
module basic_trigger_engine_axi_slave_lite_v1_0_S_AXI #
(
    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    // Width of S_AXI address bus
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    // User ports
    input  wire [7:0] sample_data_i,
    input  wire       sample_valid_i,
    output wire       trigger_pulse_o,

    // Global Clock Signal
    input  wire                              S_AXI_ACLK,
    // Global Reset Signal. This Signal is Active LOW
    input  wire                              S_AXI_ARESETN,
    // Write address
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    // Write channel Protection type
    input  wire [2:0]                        S_AXI_AWPROT,
    // Write address valid
    input  wire                              S_AXI_AWVALID,
    // Write address ready
    output wire                              S_AXI_AWREADY,
    // Write data
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    // Write strobes
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    // Write valid
    input  wire                              S_AXI_WVALID,
    // Write ready
    output wire                              S_AXI_WREADY,
    // Write response
    output wire [1:0]                        S_AXI_BRESP,
    // Write response valid
    output wire                              S_AXI_BVALID,
    // Response ready
    input  wire                              S_AXI_BREADY,
    // Read address
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    // Protection type
    input  wire [2:0]                        S_AXI_ARPROT,
    // Read address valid
    input  wire                              S_AXI_ARVALID,
    // Read address ready
    output wire                              S_AXI_ARREADY,
    // Read data
    output wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    // Read response
    output wire [1:0]                        S_AXI_RRESP,
    // Read valid
    output wire                              S_AXI_RVALID,
    // Read ready
    input  wire                              S_AXI_RREADY
);

    // AXI4-Lite internal signals
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready;
    reg                          axi_wready;
    reg [1:0]                    axi_bresp;
    reg                          axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                    axi_rresp;
    reg                          axi_rvalid;

    // 32-bit Data Bus에서 Address [1:0]은 Word 내부 Byte 선택에 사용된다.
    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;

    // Decode the full word address, including bit 5, to avoid address aliases.
    localparam integer OPT_MEM_ADDR_BITS = C_S_AXI_ADDR_WIDTH - ADDR_LSB - 1;

    // User Registers
    // slv_reg0: CONTROL, slv_reg1: CONFIG, slv_reg2: PATTERN
    reg  [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg  [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg  [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;

    // slv_reg3/4는 코어 상태를 Read하는 RO Register View이다.
    wire [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;
    wire [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;

    wire                          slv_reg_rden;
    wire                          slv_reg_wren;
    reg  [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    reg                           aw_en;

    // Trigger Core status signals
    wire        armed_status;
    wire        triggered_status;
    wire [31:0] trigger_count_status;

    // AXI output assignments
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    //------------------------------------------------------------------------------
    // AXI Write Address Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                // Vivado Template 방식: AWVALID와 WVALID가 모두 확인되면 수락
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // Write Address Latch
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
            axi_awaddr <= S_AXI_AWADDR;
        end
    end

    //------------------------------------------------------------------------------
    // AXI Write Data Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
        end else begin
            if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    // Write는 Address와 Data handshake가 동시에 완료될 때 한 번만 수행한다.
    assign slv_reg_wren = axi_wready && S_AXI_WVALID &&
                          axi_awready && S_AXI_AWVALID;

    //------------------------------------------------------------------------------
    // User Register Write Logic
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            slv_reg0 <= {C_S_AXI_DATA_WIDTH{1'b0}};
            slv_reg1 <= {C_S_AXI_DATA_WIDTH{1'b0}};
            slv_reg2 <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else begin
            // CONTROL은 저장형 Register가 아니라 W1P이므로 매 Clock 0으로 복귀
            slv_reg0 <= {C_S_AXI_DATA_WIDTH{1'b0}};

            if (slv_reg_wren) begin
                case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    3'h0: begin
                        // CONTROL: Byte Lane 0의 ARM/CLEAR만 유효
                        if (S_AXI_WSTRB[0])
                            slv_reg0[1:0] <= S_AXI_WDATA[1:0];
                    end

                    3'h1: begin
                        // CONFIG.MODE
                        if (S_AXI_WSTRB[0])
                            slv_reg1[1:0] <= S_AXI_WDATA[1:0];

                        // CONFIG.EDGE_CHANNEL
                        if (S_AXI_WSTRB[1])
                            slv_reg1[10:8] <= S_AXI_WDATA[10:8];
                    end

                    3'h2: begin
                        // PATTERN.VALUE
                        if (S_AXI_WSTRB[0])
                            slv_reg2[7:0] <= S_AXI_WDATA[7:0];

                        // PATTERN.MASK
                        if (S_AXI_WSTRB[1])
                            slv_reg2[15:8] <= S_AXI_WDATA[15:8];
                    end

                    // 0x0C STATUS와 0x10 TRIGGER_COUNT는 Read-Only
                    3'h3,
                    3'h4: begin
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

    //------------------------------------------------------------------------------
    // AXI Write Response Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && S_AXI_AWVALID &&
                !axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------------
    // AXI Read Address Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_arready && !axi_rvalid && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------------
    // AXI Read Data/Response Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Read-Only Register View
    assign slv_reg3 = {{(C_S_AXI_DATA_WIDTH-2){1'b0}},
                       triggered_status, armed_status};
    assign slv_reg4 = trigger_count_status;

    // Register Read Enable
    assign slv_reg_rden = axi_arready && S_AXI_ARVALID && !axi_rvalid;

    // Register Read MUX
    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            3'h0:   reg_data_out = {C_S_AXI_DATA_WIDTH{1'b0}}; // CONTROL Read=0
            3'h1:   reg_data_out = slv_reg1;                    // CONFIG
            3'h2:   reg_data_out = slv_reg2;                    // PATTERN
            3'h3:   reg_data_out = slv_reg3;                    // STATUS
            3'h4:   reg_data_out = slv_reg4;                    // TRIGGER_COUNT
            default: reg_data_out = {C_S_AXI_DATA_WIDTH{1'b0}};
        endcase
    end

    // Read Data Register
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else if (slv_reg_rden) begin
            axi_rdata <= reg_data_out;
        end
    end

    //------------------------------------------------------------------------------
    // Add user logic here
    //------------------------------------------------------------------------------
    // Register와 Core 연결
    //
    // slv_reg0[0]    -> ARM 1-Clock Pulse
    // slv_reg0[1]    -> CLEAR 1-Clock Pulse
    // slv_reg1[1:0]  -> Trigger Mode
    // slv_reg1[10:8] -> Edge Channel
    // slv_reg2[7:0]  -> Pattern Value
    // slv_reg2[15:8] -> Pattern Mask
    //
    // Vivado Sources에서는 u_trigger_core가 u_axi_slave 아래에 표시된다.
    basic_trigger_engine u_trigger_core (
        .clk_i           (S_AXI_ACLK),
        .rst_ni          (S_AXI_ARESETN),
        .sample_data_i   (sample_data_i),
        .sample_valid_i  (sample_valid_i),
        .arm_i           (slv_reg0[0]),
        .clear_i         (slv_reg0[1]),
        .mode_i          (slv_reg1[1:0]),
        .edge_channel_i  (slv_reg1[10:8]),
        .pattern_value_i (slv_reg2[7:0]),
        .pattern_mask_i  (slv_reg2[15:8]),
        .trigger_pulse_o (trigger_pulse_o),
        .armed_o         (armed_status),
        .triggered_o     (triggered_status),
        .trigger_count_o (trigger_count_status)
    );

    // User logic ends

    // S_AXI_AWPROT와 S_AXI_ARPROT는 이 Register Bank에서 사용하지 않는다.

endmodule
