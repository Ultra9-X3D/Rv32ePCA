// Flat APB4 slave wrapper. The register aperture is 256 bytes.

`default_nettype none

module Apb4Rv32ePca (
  input  wire        apb4_pclk,
  input  wire        apb4_presetn,
  input  wire        apb4_psel,
  input  wire        apb4_penable,
  input  wire        apb4_pwrite,
  input  wire [31:0] apb4_paddr,
  input  wire [2:0]  apb4_pprot,
  input  wire [31:0] apb4_pwdata,
  input  wire [3:0]  apb4_pstrb,
  output wire        apb4_pready,
  output wire        apb4_pslverr,
  output reg  [31:0] apb4_prdata,
  output wire        irq_o
);

  localparam [5:0] REG_ID        = 6'h00;
  localparam [5:0] REG_CAPS      = 6'h01;
  localparam [5:0] REG_CTRL      = 6'h02;
  localparam [5:0] REG_STATUS    = 6'h03;
  localparam [5:0] REG_OPERAND_A = 6'h04;
  localparam [5:0] REG_OPERAND_B = 6'h05;
  localparam [5:0] REG_ACC       = 6'h06;
  localparam [5:0] REG_RESULT    = 6'h07;
  localparam [5:0] REG_PERF      = 6'h08;
  localparam [5:0] REG_IRQ_CLEAR = 6'h09;

  localparam [31:0] PCA_ID   = 32'h5043_4134; // ASCII "PCA4"
  localparam [31:0] PCA_CAPS = 32'h010A_0804; // v1, 10 ops, 8-bit, 4 lanes

  reg [4:0]  ctrl_q;
  reg [31:0] operand_a_q;
  reg [31:0] operand_b_q;
  reg [31:0] accumulator_q;
  reg        done_sticky_q;
  reg        error_sticky_q;

  wire [5:0]  reg_addr;
  wire        apb_access;
  wire        apb_write;
  reg         reg_valid;
  reg         reg_writable;
  wire [31:0] ctrl_merged;
  wire        start_request;
  wire        start_accept;

  wire        dp_ready;
  wire        dp_busy;
  wire        dp_done;
  wire [31:0] dp_result;
  wire [7:0]  dp_cycles;

  wire unused_inputs;

  function [31:0] merge_wstrb;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0]  strobes;
    reg [31:0] merged;
    integer byte_index;
    begin
      merged = old_value;
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        if (strobes[byte_index])
          merged[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
      end
      merge_wstrb = merged;
    end
  endfunction

  assign reg_addr   = apb4_paddr[7:2];
  assign apb_access = apb4_psel && apb4_penable;
  assign apb_write  = apb_access && apb4_pwrite;

  always @* begin
    case (reg_addr)
      REG_ID, REG_CAPS, REG_CTRL, REG_STATUS, REG_OPERAND_A,
      REG_OPERAND_B, REG_ACC, REG_RESULT, REG_PERF, REG_IRQ_CLEAR:
        reg_valid = 1'b1;
      default: reg_valid = 1'b0;
    endcase

    case (reg_addr)
      REG_CTRL, REG_OPERAND_A, REG_OPERAND_B, REG_ACC, REG_IRQ_CLEAR:
        reg_writable = 1'b1;
      default: reg_writable = 1'b0;
    endcase
  end

  assign ctrl_merged  = merge_wstrb({23'd0, 4'd0, ctrl_q},
                                    apb4_pwdata, apb4_pstrb);
  assign start_request = apb_write && (reg_addr == REG_CTRL) &&
                         ctrl_merged[8];
  assign start_accept  = start_request && dp_ready;

  PcaDatapath u_datapath (
    .clock         (apb4_pclk),
    .reset         (!apb4_presetn),
    .start_i       (start_accept),
    .opcode_i      (ctrl_merged[3:0]),
    .operand_a_i   (operand_a_q),
    .operand_b_i   (operand_b_q),
    .accumulator_i (accumulator_q),
    .ready_o       (dp_ready),
    .busy_o        (dp_busy),
    .done_o        (dp_done),
    .result_o      (dp_result),
    .cycles_o      (dp_cycles)
  );

  always @(posedge apb4_pclk or negedge apb4_presetn) begin
    if (!apb4_presetn) begin
      ctrl_q         <= 5'd0;
      operand_a_q    <= 32'd0;
      operand_b_q    <= 32'd0;
      accumulator_q  <= 32'd0;
      done_sticky_q  <= 1'b0;
      error_sticky_q <= 1'b0;
    end else begin
      if (apb_write && reg_valid && reg_writable) begin
        case (reg_addr)
          REG_CTRL: begin
            if (!(start_request && !dp_ready))
              ctrl_q <= ctrl_merged[4:0];
          end
          REG_OPERAND_A:
            operand_a_q <= merge_wstrb(operand_a_q, apb4_pwdata, apb4_pstrb);
          REG_OPERAND_B:
            operand_b_q <= merge_wstrb(operand_b_q, apb4_pwdata, apb4_pstrb);
          REG_ACC:
            accumulator_q <= merge_wstrb(accumulator_q, apb4_pwdata, apb4_pstrb);
          REG_IRQ_CLEAR: begin
            if (apb4_pwdata[0] && apb4_pstrb[0])
              done_sticky_q <= 1'b0;
            if (apb4_pwdata[1] && apb4_pstrb[0])
              error_sticky_q <= 1'b0;
          end
          default: begin
          end
        endcase
      end

      if (start_accept) begin
        done_sticky_q  <= 1'b0;
        error_sticky_q <= 1'b0;
      end else if (start_request && !dp_ready) begin
        error_sticky_q <= 1'b1;
      end

      if (dp_done)
        done_sticky_q <= 1'b1;
    end
  end

  always @* begin
    apb4_prdata = 32'd0;
    case (reg_addr)
      REG_ID:        apb4_prdata = PCA_ID;
      REG_CAPS:      apb4_prdata = PCA_CAPS;
      REG_CTRL:      apb4_prdata = {27'd0, ctrl_q};
      REG_STATUS: begin
        apb4_prdata[0]    = dp_busy;
        apb4_prdata[1]    = done_sticky_q;
        apb4_prdata[2]    = irq_o;
        apb4_prdata[3]    = error_sticky_q;
        apb4_prdata[15:8] = dp_cycles;
      end
      REG_OPERAND_A: apb4_prdata = operand_a_q;
      REG_OPERAND_B: apb4_prdata = operand_b_q;
      REG_ACC:       apb4_prdata = accumulator_q;
      REG_RESULT:    apb4_prdata = dp_result;
      REG_PERF:      apb4_prdata = {24'd0, dp_cycles};
      REG_IRQ_CLEAR: apb4_prdata = 32'd0;
      default:       apb4_prdata = 32'd0;
    endcase
  end

  assign apb4_pready  = 1'b1;
  assign apb4_pslverr = apb_access &&
                        ((apb4_paddr[1:0] != 2'b00) ||
                         !reg_valid ||
                         (apb4_pwrite && !reg_writable));
  assign irq_o = ctrl_q[4] && done_sticky_q;

  // The page decode is performed by the SoC and CTRL reserved bits read as 0.
  // Keep intentionally ignored inputs visible to strict standalone lint.
  assign unused_inputs = ^{apb4_pprot, apb4_paddr[31:8],
                           ctrl_merged[31:9], ctrl_merged[7:5]};

endmodule

`default_nettype wire
