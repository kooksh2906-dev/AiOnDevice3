`timescale 1ns/1ps

// AXI4-Lite wrapper for basic_trigger_engine.  CONTROL commands are W1P;
// configuration registers retain their values until reset or another write.
module basic_trigger_engine_axi (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [5:0]  s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [5:0]  s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input  logic [7:0]  sample_data_i,
    input  logic        sample_valid_i,
    output logic        trigger_pulse_o
);
    import logic_analyzer_pkg::*;

    logic        aw_valid_q;
    logic [5:0]  awaddr_q;
    logic        w_valid_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        bvalid_q;
    logic        write_commit;

    logic        arm_pulse_q;
    logic        clear_pulse_q;
    logic [1:0]  mode_q;
    logic [2:0]  edge_channel_q;
    logic [7:0]  pattern_value_q;
    logic [7:0]  pattern_mask_q;
    logic        armed;
    logic        triggered;
    logic [31:0] trigger_count;

    logic [31:0] read_data;
    logic [31:0] rdata_q;
    logic        rvalid_q;
    logic        unused_prot;

    assign s_axi_awready = !aw_valid_q && !bvalid_q;
    assign s_axi_wready  = !w_valid_q && !bvalid_q;
    assign write_commit  = aw_valid_q && w_valid_q && !bvalid_q;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_q;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_valid_q <= 1'b0;
            awaddr_q   <= '0;
            w_valid_q  <= 1'b0;
            wdata_q    <= '0;
            wstrb_q    <= '0;
            bvalid_q   <= 1'b0;
        end else begin
            if (s_axi_awready && s_axi_awvalid) begin
                aw_valid_q <= 1'b1;
                awaddr_q   <= s_axi_awaddr;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                w_valid_q <= 1'b1;
                wdata_q   <= s_axi_wdata;
                wstrb_q   <= s_axi_wstrb;
            end
            if (write_commit) begin
                aw_valid_q <= 1'b0;
                w_valid_q  <= 1'b0;
                bvalid_q   <= 1'b1;
            end else if (bvalid_q && s_axi_bready) begin
                bvalid_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            arm_pulse_q     <= 1'b0;
            clear_pulse_q   <= 1'b0;
            mode_q          <= 2'b00;
            edge_channel_q  <= 3'b000;
            pattern_value_q <= 8'ha0;
            pattern_mask_q  <= 8'hf0;
        end else begin
            arm_pulse_q   <= 1'b0;
            clear_pulse_q <= 1'b0;
            if (write_commit && awaddr_q == TRIGGER_REG_CONTROL &&
                wstrb_q[0]) begin
                arm_pulse_q   <= wdata_q[0];
                clear_pulse_q <= wdata_q[1];
            end
            if (write_commit && awaddr_q == TRIGGER_REG_CONFIG) begin
                if (wstrb_q[0])
                    mode_q <= wdata_q[1:0];
                if (wstrb_q[1])
                    edge_channel_q <= wdata_q[10:8];
            end
            if (write_commit && awaddr_q == TRIGGER_REG_PATTERN) begin
                if (wstrb_q[0])
                    pattern_value_q <= wdata_q[7:0];
                if (wstrb_q[1])
                    pattern_mask_q <= wdata_q[15:8];
            end
        end
    end

    basic_trigger_engine u_trigger (
        .clk_i           (s_axi_aclk),
        .rst_ni          (s_axi_aresetn),
        .sample_data_i,
        .sample_valid_i,
        .arm_i           (arm_pulse_q),
        .clear_i         (clear_pulse_q),
        .mode_i          (mode_q),
        .edge_channel_i  (edge_channel_q),
        .pattern_value_i (pattern_value_q),
        .pattern_mask_i  (pattern_mask_q),
        .trigger_pulse_o,
        .armed_o         (armed),
        .triggered_o     (triggered),
        .trigger_count_o (trigger_count)
    );

    always_comb begin
        read_data = 32'h0000_0000;
        case (s_axi_araddr)
            TRIGGER_REG_CONTROL:
                read_data = 32'h0000_0000;
            TRIGGER_REG_CONFIG: begin
                read_data[1:0]  = mode_q;
                read_data[10:8] = edge_channel_q;
            end
            TRIGGER_REG_PATTERN: begin
                read_data[7:0]  = pattern_value_q;
                read_data[15:8] = pattern_mask_q;
            end
            TRIGGER_REG_STATUS: begin
                read_data[0] = armed;
                read_data[1] = triggered;
            end
            TRIGGER_REG_TRIGGER_COUNT:
                read_data = trigger_count;
            default:
                read_data = 32'h0000_0000;
        endcase
    end

    assign s_axi_arready = !rvalid_q;
    assign s_axi_rdata   = rdata_q;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_q;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            rdata_q  <= '0;
            rvalid_q <= 1'b0;
        end else begin
            if (s_axi_arready && s_axi_arvalid) begin
                rdata_q  <= read_data;
                rvalid_q <= 1'b1;
            end else if (rvalid_q && s_axi_rready) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    assign unused_prot = ^{s_axi_awprot, s_axi_arprot};
endmodule
