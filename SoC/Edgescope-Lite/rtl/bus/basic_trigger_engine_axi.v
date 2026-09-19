`timescale 1 ns / 1 ps

//------------------------------------------------------------------------------
// Basic Trigger Engine AXI4-Lite Top Module
//
// Vivado AXI Peripheral의 최상위 Wrapper 역할만 수행한다.
// 실제 Register 설정과 basic_trigger_engine 인스턴스는
// basic_trigger_engine_axi_slave_lite_v1_0_S_AXI 내부에 위치한다.
//
// 최종 Hierarchy
// basic_trigger_engine_axi
// `-- u_axi_slave
//     `-- u_trigger_core
//------------------------------------------------------------------------------
module basic_trigger_engine_axi #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    // User ports
    input  wire [7:0] sample_data_i,
    input  wire       sample_valid_i,
    output wire       trigger_pulse_o,

    // AXI4-Lite Slave Interface
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready
);

    // Instantiation of AXI Bus Interface S_AXI
    // Register Bank와 Trigger Core를 모두 포함하는 유일한 하위 인스턴스
    basic_trigger_engine_axi_slave_lite_v1_0_S_AXI #(
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
    ) u_axi_slave (
        // User ports
        .sample_data_i   (sample_data_i),
        .sample_valid_i  (sample_valid_i),
        .trigger_pulse_o (trigger_pulse_o),

        // AXI4-Lite ports
        .S_AXI_ACLK      (s_axi_aclk),
        .S_AXI_ARESETN   (s_axi_aresetn),
        .S_AXI_AWADDR    (s_axi_awaddr),
        .S_AXI_AWPROT    (s_axi_awprot),
        .S_AXI_AWVALID   (s_axi_awvalid),
        .S_AXI_AWREADY   (s_axi_awready),
        .S_AXI_WDATA     (s_axi_wdata),
        .S_AXI_WSTRB     (s_axi_wstrb),
        .S_AXI_WVALID    (s_axi_wvalid),
        .S_AXI_WREADY    (s_axi_wready),
        .S_AXI_BRESP     (s_axi_bresp),
        .S_AXI_BVALID    (s_axi_bvalid),
        .S_AXI_BREADY    (s_axi_bready),
        .S_AXI_ARADDR    (s_axi_araddr),
        .S_AXI_ARPROT    (s_axi_arprot),
        .S_AXI_ARVALID   (s_axi_arvalid),
        .S_AXI_ARREADY   (s_axi_arready),
        .S_AXI_RDATA     (s_axi_rdata),
        .S_AXI_RRESP     (s_axi_rresp),
        .S_AXI_RVALID    (s_axi_rvalid),
        .S_AXI_RREADY    (s_axi_rready)
    );

endmodule
