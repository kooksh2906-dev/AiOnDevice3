`timescale 1ns/1ps

// AXI4-Lite wrapper for probe_sampler.  Register offsets and semantics follow
// docs/day1_common_spec.md Frozen v2.1.
module probe_sampler_axi (
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

    input  logic [7:0]  probe_i,
    output logic [7:0]  sample_data_o,
    output logic        sample_valid_o
);
    import logic_analyzer_pkg::*;

    logic        aw_valid_q;
    logic [5:0]  awaddr_q;
    logic        w_valid_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        bvalid_q;
    logic        write_commit;

    logic        enable_q;
    logic        soft_clear_pulse_q;
    logic [1:0]  divider_sel_q;
    logic [7:0]  channel_mask_q;
    logic [31:0] sample_count;

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
            enable_q           <= 1'b0;
            soft_clear_pulse_q <= 1'b0;
            divider_sel_q      <= 2'b00;
            channel_mask_q     <= 8'hff;
        end else begin
            soft_clear_pulse_q <= 1'b0;
            if (write_commit && awaddr_q == SAMPLER_REG_CONTROL &&
                wstrb_q[0]) begin
                enable_q           <= wdata_q[0];
                soft_clear_pulse_q <= wdata_q[1];
            end
            if (write_commit && awaddr_q == SAMPLER_REG_CONFIG) begin
                if (wstrb_q[0])
                    divider_sel_q <= wdata_q[1:0];
                if (wstrb_q[1])
                    channel_mask_q <= wdata_q[15:8];
            end
        end
    end

    probe_sampler u_sampler (
        .clk_i          (s_axi_aclk),
        .rst_ni         (s_axi_aresetn),
        .probe_i,
        .enable_i       (enable_q),
        .soft_clear_i   (soft_clear_pulse_q),
        .divider_sel_i  (divider_sel_q),
        .channel_mask_i (channel_mask_q),
        .sample_data_o,
        .sample_valid_o,
        .sample_count_o (sample_count)
    );

    always_comb begin
        read_data = 32'h0000_0000;
        case (s_axi_araddr)
            SAMPLER_REG_CONTROL:
                read_data[0] = enable_q;
            SAMPLER_REG_CONFIG: begin
                read_data[1:0]  = divider_sel_q;
                read_data[15:8] = channel_mask_q;
            end
            SAMPLER_REG_LAST_SAMPLE:
                read_data[7:0] = sample_data_o;
            SAMPLER_REG_SAMPLE_COUNT:
                read_data = sample_count;
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
