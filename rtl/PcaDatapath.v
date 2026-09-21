// Four-lane INT8 SIMD/MAC datapath for a small RV32E companion accelerator.

`default_nettype none

module PcaDatapath (
  input  wire        clock,
  input  wire        reset,
  input  wire        start_i,
  input  wire [3:0]  opcode_i,
  input  wire [31:0] operand_a_i,
  input  wire [31:0] operand_b_i,
  input  wire [31:0] accumulator_i,
  output wire        ready_o,
  output wire        busy_o,
  output wire        done_o,
  output wire [31:0] result_o,
  output wire [7:0]  cycles_o
);

  localparam [3:0] OP_ADD4_WRAP   = 4'h0;
  localparam [3:0] OP_SUB4_WRAP   = 4'h1;
  localparam [3:0] OP_ABSDIFF4_U  = 4'h2;
  localparam [3:0] OP_XOR32       = 4'h3;
  localparam [3:0] OP_DOT4_S      = 4'h4;
  localparam [3:0] OP_DOT4_S_ACC  = 4'h5;
  localparam [3:0] OP_SAD4_U_ACC  = 4'h6;
  localparam [3:0] OP_AND32       = 4'h7;
  localparam [3:0] OP_OR32        = 4'h8;
  localparam [3:0] OP_COPY_A      = 4'h9;

  reg        busy_q;
  reg [3:0]  opcode_q;
  reg [31:0] operand_a_q;
  reg [31:0] operand_b_q;
  reg [31:0] accumulator_q;
  reg [31:0] result_q;
  reg [7:0]  cycles_q;

  wire signed [7:0]  mul_a0;
  wire signed [7:0]  mul_a1;
  wire signed [7:0]  mul_a2;
  wire signed [7:0]  mul_a3;
  wire signed [7:0]  mul_b0;
  wire signed [7:0]  mul_b1;
  wire signed [7:0]  mul_b2;
  wire signed [7:0]  mul_b3;
  wire signed [15:0] mul_product0;
  wire signed [15:0] mul_product1;
  wire signed [15:0] mul_product2;
  wire signed [15:0] mul_product3;
  wire signed [31:0] mul_product0_ext;
  wire signed [31:0] mul_product1_ext;
  wire signed [31:0] mul_product2_ext;
  wire signed [31:0] mul_product3_ext;
  wire signed [31:0] dot_sum;
  wire [7:0] absdiff0;
  wire [7:0] absdiff1;
  wire [7:0] absdiff2;
  wire [7:0] absdiff3;
  wire [31:0] sad_sum;
  reg [31:0] result_next;

  assign mul_a0 = operand_a_q[7:0];
  assign mul_a1 = operand_a_q[15:8];
  assign mul_a2 = operand_a_q[23:16];
  assign mul_a3 = operand_a_q[31:24];
  assign mul_b0 = operand_b_q[7:0];
  assign mul_b1 = operand_b_q[15:8];
  assign mul_b2 = operand_b_q[23:16];
  assign mul_b3 = operand_b_q[31:24];

  assign mul_product0 = mul_a0 * mul_b0;
  assign mul_product1 = mul_a1 * mul_b1;
  assign mul_product2 = mul_a2 * mul_b2;
  assign mul_product3 = mul_a3 * mul_b3;

  assign mul_product0_ext = {{16{mul_product0[15]}}, mul_product0};
  assign mul_product1_ext = {{16{mul_product1[15]}}, mul_product1};
  assign mul_product2_ext = {{16{mul_product2[15]}}, mul_product2};
  assign mul_product3_ext = {{16{mul_product3[15]}}, mul_product3};
  assign dot_sum = mul_product0_ext + mul_product1_ext +
                   mul_product2_ext + mul_product3_ext;

  assign absdiff0 = (operand_a_q[7:0] >= operand_b_q[7:0])
                  ? (operand_a_q[7:0] - operand_b_q[7:0])
                  : (operand_b_q[7:0] - operand_a_q[7:0]);
  assign absdiff1 = (operand_a_q[15:8] >= operand_b_q[15:8])
                  ? (operand_a_q[15:8] - operand_b_q[15:8])
                  : (operand_b_q[15:8] - operand_a_q[15:8]);
  assign absdiff2 = (operand_a_q[23:16] >= operand_b_q[23:16])
                  ? (operand_a_q[23:16] - operand_b_q[23:16])
                  : (operand_b_q[23:16] - operand_a_q[23:16]);
  assign absdiff3 = (operand_a_q[31:24] >= operand_b_q[31:24])
                  ? (operand_a_q[31:24] - operand_b_q[31:24])
                  : (operand_b_q[31:24] - operand_a_q[31:24]);
  assign sad_sum = {24'd0, absdiff0} + {24'd0, absdiff1} +
                   {24'd0, absdiff2} + {24'd0, absdiff3};

  always @* begin
    result_next = 32'd0;
    case (opcode_q)
      OP_ADD4_WRAP: begin
        result_next[7:0]   = operand_a_q[7:0] + operand_b_q[7:0];
        result_next[15:8]  = operand_a_q[15:8] + operand_b_q[15:8];
        result_next[23:16] = operand_a_q[23:16] + operand_b_q[23:16];
        result_next[31:24] = operand_a_q[31:24] + operand_b_q[31:24];
      end
      OP_SUB4_WRAP: begin
        result_next[7:0]   = operand_a_q[7:0] - operand_b_q[7:0];
        result_next[15:8]  = operand_a_q[15:8] - operand_b_q[15:8];
        result_next[23:16] = operand_a_q[23:16] - operand_b_q[23:16];
        result_next[31:24] = operand_a_q[31:24] - operand_b_q[31:24];
      end
      OP_ABSDIFF4_U: begin
        result_next[7:0]   = absdiff0;
        result_next[15:8]  = absdiff1;
        result_next[23:16] = absdiff2;
        result_next[31:24] = absdiff3;
      end
      OP_XOR32:      result_next = operand_a_q ^ operand_b_q;
      OP_DOT4_S:     result_next = dot_sum;
      OP_DOT4_S_ACC: result_next = accumulator_q + dot_sum;
      OP_SAD4_U_ACC: result_next = accumulator_q + sad_sum;
      OP_AND32:      result_next = operand_a_q & operand_b_q;
      OP_OR32:       result_next = operand_a_q | operand_b_q;
      OP_COPY_A:     result_next = operand_a_q;
      default:       result_next = 32'd0;
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      busy_q        <= 1'b0;
      opcode_q      <= OP_COPY_A;
      operand_a_q   <= 32'd0;
      operand_b_q   <= 32'd0;
      accumulator_q <= 32'd0;
      result_q      <= 32'd0;
      cycles_q      <= 8'd0;
    end else begin
      if (start_i && !busy_q) begin
        busy_q        <= 1'b1;
        opcode_q      <= opcode_i;
        operand_a_q   <= operand_a_i;
        operand_b_q   <= operand_b_i;
        accumulator_q <= accumulator_i;
        cycles_q      <= 8'd0;
      end else if (busy_q) begin
        busy_q   <= 1'b0;
        result_q <= result_next;
        cycles_q <= 8'd1;
      end
    end
  end

  assign ready_o  = !busy_q;
  assign busy_o   = busy_q;
  // A one-cycle completion pulse sampled by the register wrapper on the edge
  // that also commits result_q.
  assign done_o   = busy_q;
  assign result_o = result_q;
  assign cycles_o = cycles_q;

endmodule

`default_nettype wire
