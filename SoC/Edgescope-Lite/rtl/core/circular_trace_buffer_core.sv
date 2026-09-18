`timescale 1ns/1ps

module circular_trace_buffer_core (
  input  logic                                           clk_i,
  input  logic                                           rst_ni,

  input  logic [logic_analyzer_pkg::PROBE_WIDTH-1:0]     sample_data_i,
  input  logic                                           sample_valid_i,
  input  logic                                           trigger_pulse_i,

  input  logic                                           arm_i,
  input  logic                                           clear_done_i,
  input  logic                                           abort_i,

  output logic                                           busy_o,
  output logic                                           pre_ready_o,
  output logic                                           triggered_o,
  output logic                                           capture_done_o,
  output logic                                           irq_o,

  output logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] start_addr_o,
  output logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] trigger_addr_o,
  output logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] write_addr_o,

  output logic                                           bram_en_o,
  output logic [3:0]                                     bram_we_o,
  output logic [logic_analyzer_pkg::BRAM_ADDR_WIDTH-1:0] bram_addr_o,
  output logic [logic_analyzer_pkg::BRAM_DATA_WIDTH-1:0] bram_wdata_o
);
  import logic_analyzer_pkg::*;

  typedef enum logic [2:0] {
    IDLE,
    PREFILL,
    ARMED,
    POST_CAPTURE,
    DONE
  } state_e;

  state_e state_q;

  // write_ptr_q always points to the BRAM word used by the next valid sample.
  logic [BRAM_ADDR_WIDTH-1:0] write_ptr_q;
  logic [BRAM_ADDR_WIDTH-1:0] last_write_addr_q;
  logic [BRAM_ADDR_WIDTH-1:0] start_addr_q;
  logic [BRAM_ADDR_WIDTH-1:0] trigger_addr_q;

  // Both counters represent the number of samples already stored.
  logic [BRAM_ADDR_WIDTH-1:0] prefill_count_q;
  logic [BRAM_ADDR_WIDTH-1:0] post_count_q;

  logic triggered_q;
  logic done_q;
  logic capture_write_active;

  assign capture_write_active =
      (state_q == PREFILL) ||
      (state_q == ARMED) ||
      (state_q == POST_CAPTURE);

  assign busy_o         = capture_write_active;
  assign pre_ready_o    = (state_q == ARMED) ||
                          (state_q == POST_CAPTURE) ||
                          (state_q == DONE);
  assign triggered_o    = triggered_q;
  assign capture_done_o = done_q;
  assign irq_o          = done_q;

  assign start_addr_o   = start_addr_q;
  assign trigger_addr_o = trigger_addr_q;
  assign write_addr_o   = last_write_addr_q;

  // The BMG Port A writes one complete 32-bit word for every valid sample.
  // abort_i gates the write so an abort edge cannot commit another sample.
  assign bram_en_o    = rst_ni && !abort_i &&
                        capture_write_active && sample_valid_i;
  assign bram_we_o    = bram_en_o ? 4'b1111 : 4'b0000;
  assign bram_addr_o  = write_ptr_q;
  assign bram_wdata_o = {
    {(BRAM_DATA_WIDTH-PROBE_WIDTH){1'b0}},
    sample_data_i
  };

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q           <= IDLE;
      write_ptr_q       <= '0;
      last_write_addr_q <= '0;
      start_addr_q      <= '0;
      trigger_addr_q    <= '0;
      prefill_count_q   <= '0;
      post_count_q      <= '0;
      triggered_q       <= 1'b0;
      done_q            <= 1'b0;
    end else if (abort_i) begin
      state_q           <= IDLE;
      write_ptr_q       <= '0;
      last_write_addr_q <= '0;
      start_addr_q      <= '0;
      trigger_addr_q    <= '0;
      prefill_count_q   <= '0;
      post_count_q      <= '0;
      triggered_q       <= 1'b0;
      done_q            <= 1'b0;
    end else if (clear_done_i && (state_q == DONE)) begin
      state_q           <= IDLE;
      triggered_q       <= 1'b0;
      done_q            <= 1'b0;
    end else if (arm_i && ((state_q == IDLE) || (state_q == DONE))) begin
      state_q           <= PREFILL;
      write_ptr_q       <= '0;
      last_write_addr_q <= '0;
      start_addr_q      <= '0;
      trigger_addr_q    <= '0;
      prefill_count_q   <= '0;
      post_count_q      <= '0;
      triggered_q       <= 1'b0;
      done_q            <= 1'b0;
    end else begin
      case (state_q)
        IDLE: begin
          // Wait for arm_i.
        end

        PREFILL: begin
          if (sample_valid_i) begin
            last_write_addr_q <= write_ptr_q;
            write_ptr_q       <= write_ptr_q + 1'b1;

            if (prefill_count_q == PRE_TRIGGER_SAMPLES-1) begin
              prefill_count_q <= PRE_TRIGGER_SAMPLES;
              state_q         <= ARMED;
            end else begin
              prefill_count_q <= prefill_count_q + 1'b1;
            end
          end
        end

        ARMED: begin
          if (sample_valid_i) begin
            last_write_addr_q <= write_ptr_q;
            write_ptr_q       <= write_ptr_q + 1'b1;

            if (trigger_pulse_i) begin
              trigger_addr_q <= write_ptr_q;
              post_count_q   <= 1;
              triggered_q    <= 1'b1;
              state_q        <= POST_CAPTURE;
            end
          end
        end

        POST_CAPTURE: begin
          if (sample_valid_i) begin
            last_write_addr_q <= write_ptr_q;
            write_ptr_q       <= write_ptr_q + 1'b1;

            // The trigger sample was post sample #1. When 511 samples
            // are already counted, this write is post sample #512.
            if (post_count_q == POST_TRIGGER_SAMPLES-1) begin
              post_count_q <= POST_TRIGGER_SAMPLES;
              start_addr_q <= write_ptr_q + 1'b1;
              done_q       <= 1'b1;
              state_q      <= DONE;
            end else begin
              post_count_q <= post_count_q + 1'b1;
            end
          end
        end

        DONE: begin
          // Hold memory, addresses, done and IRQ until clear or re-arm.
        end

        default: begin
          state_q           <= IDLE;
          write_ptr_q       <= '0;
          last_write_addr_q <= '0;
          start_addr_q      <= '0;
          trigger_addr_q    <= '0;
          prefill_count_q   <= '0;
          post_count_q      <= '0;
          triggered_q       <= 1'b0;
          done_q            <= 1'b0;
        end
      endcase
    end
  end

endmodule
