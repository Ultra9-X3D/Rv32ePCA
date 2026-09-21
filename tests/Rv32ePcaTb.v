module Rv32ePcaTb;

  localparam integer IO_WIDTH = 66;
  localparam integer HALF_PERIOD = 5;

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

  reg   clock;
  reg   reset;
  reg   [IO_WIDTH-1:0] io_in;
  wire  [IO_WIDTH-1:0] io_out;
  wire  [IO_WIDTH-1:0] io_oe;

  reg [31:0] read_value;
  reg        bus_error;

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    io_in = {IO_WIDTH{1'b0}};
    read_value = 32'd0;
    bus_error = 1'b0;
  end

  always #(HALF_PERIOD) clock = ~clock;

  UserDesignDut #(.IO_WIDTH(IO_WIDTH)) dut (
    .clock(clock),
    .reset(reset),
    .io_in(io_in),
    .io_out(io_out),
    .io_oe(io_oe)
  );

  task automatic apb_write;
    input [5:0]  word_address;
    input [31:0] data;
    input [3:0]  strobes;
    output       error;
    begin
      @(negedge clock);
      io_in[31:0]  = data;
      io_in[37:32] = word_address;
      io_in[41:38] = strobes;
      io_in[42]    = 1'b1;
      io_in[43]    = 1'b0;
      io_in[44]    = 1'b1;

      @(negedge clock);
      io_in[43] = 1'b1;
      @(posedge clock);
      #1;
      if (io_out[45] !== 1'b1) begin
        $display("ERROR: APB write did not receive PREADY");
        $stop;
      end
      error = io_out[46];

      @(negedge clock);
      io_in[44:42] = 3'b000;
      io_in[41:38] = 4'b0000;
      io_in[37:32] = 6'd0;
      io_in[31:0]  = 32'd0;
    end
  endtask

  task automatic apb_read;
    input  [5:0]  word_address;
    output [31:0] data;
    output        error;
    begin
      @(negedge clock);
      io_in[37:32] = word_address;
      io_in[41:38] = 4'hF;
      io_in[42]    = 1'b1;
      io_in[43]    = 1'b0;
      io_in[44]    = 1'b0;
      @(negedge clock);
      io_in[43] = 1'b1;
      @(posedge clock);
      #1;
      if (io_out[45] !== 1'b1) begin
        $display("ERROR: APB read did not receive PREADY");
        $stop;
      end
      if (io_oe[31:0] !== 32'hFFFF_FFFF) begin
        $display("ERROR: read data bus was not driven");
        $stop;
      end
      data  = io_out[31:0];
      error = io_out[46];

      @(negedge clock);
      io_in[44:42] = 3'b000;
      io_in[41:38] = 4'b0000;
      io_in[37:32] = 6'd0;
    end
  endtask

  task automatic write_ok;
    input [5:0]  word_address;
    input [31:0] data;
    reg error;
    begin
      apb_write(word_address, data, 4'hF, error);
      if (error !== 1'b0) begin
        $display("ERROR: unexpected APB error on write to word 0x%0h",
                 word_address);
        $stop;
      end
    end
  endtask

  task automatic read_ok;
    input  [5:0]  word_address;
    output [31:0] data;
    reg error;
    begin
      apb_read(word_address, data, error);
      if (error !== 1'b0) begin
        $display("ERROR: unexpected APB error on read from word 0x%0h",
                 word_address);
        $stop;
      end
    end
  endtask

  task automatic run_operation;
    input [3:0]  opcode;
    input [31:0] operand_a;
    input [31:0] operand_b;
    input [31:0] accumulator;
    input [31:0] expected;
    reg [31:0] status;
    reg [31:0] actual;
    reg [31:0] perf;
    integer poll;
    begin
      write_ok(REG_OPERAND_A, operand_a);
      write_ok(REG_OPERAND_B, operand_b);
      write_ok(REG_ACC, accumulator);
      // bit 8 starts the operation; bit 4 enables the completion IRQ.
      write_ok(REG_CTRL, 32'h0000_0110 | {28'd0, opcode});

      status = 32'd0;
      poll = 0;
      while ((poll < 8) && !status[1]) begin
        read_ok(REG_STATUS, status);
        poll = poll + 1;
      end
      if (!status[1]) begin
        $display("ERROR: operation 0x%0h did not complete", opcode);
        $stop;
      end
      if (status[3]) begin
        $display("ERROR: operation 0x%0h set the error flag", opcode);
        $stop;
      end
      if (status[2] !== 1'b1 || io_out[47] !== 1'b1) begin
        $display("ERROR: operation 0x%0h did not assert IRQ", opcode);
        $stop;
      end

      read_ok(REG_RESULT, actual);
      if (actual !== expected) begin
        $display("ERROR: op 0x%0h result 0x%08h, expected 0x%08h",
                 opcode, actual, expected);
        $stop;
      end

      read_ok(REG_PERF, perf);
      if (perf[7:0] !== 8'd1) begin
        $display("ERROR: op 0x%0h latency was %0d, expected 1",
                 opcode, perf[7:0]);
        $stop;
      end

      write_ok(REG_IRQ_CLEAR, 32'h0000_0001);
      read_ok(REG_STATUS, status);
      if (status[2:1] !== 2'b00 || io_out[47] !== 1'b0) begin
        $display("ERROR: IRQ/done clear failed for op 0x%0h", opcode);
        $stop;
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clock);
    #1;
    if (io_oe[47:45] !== 3'b111 || io_oe[44:0] !== 45'b0) begin
      $display("ERROR: reset output-enable state is incorrect");
      $stop;
    end

    @(negedge clock);
    reset = 1'b0;

    read_ok(REG_ID, read_value);
    if (read_value !== 32'h5043_4134) begin
      $display("ERROR: bad accelerator ID 0x%08h", read_value);
      $stop;
    end
    read_ok(REG_CAPS, read_value);
    if (read_value !== 32'h010A_0804) begin
      $display("ERROR: bad capability word 0x%08h", read_value);
      $stop;
    end

    // Verify byte strobes before the functional sweep.
    write_ok(REG_OPERAND_A, 32'h1122_3344);
    apb_write(REG_OPERAND_A, 32'hAA00_00BB, 4'b1001, bus_error);
    if (bus_error) begin
      $display("ERROR: partial write unexpectedly failed");
      $stop;
    end
    read_ok(REG_OPERAND_A, read_value);
    if (read_value !== 32'hAA22_33BB) begin
      $display("ERROR: PSTRB merge failed: 0x%08h", read_value);
      $stop;
    end

    // A lanes (MSB..LSB): 127, -128, -1, 1
    // B lanes (MSB..LSB):   1,    1,  1,-1
    run_operation(4'h0, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h8081_0000);
    run_operation(4'h1, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h7E7F_FE02);
    run_operation(4'h2, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h7E7F_FEFE);
    run_operation(4'h3, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h7E81_FEFE);
    run_operation(4'h4, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'hFFFF_FFFD);
    run_operation(4'h5, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h0000_0007);
    run_operation(4'h6, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h0000_0303);
    run_operation(4'h7, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h0100_0101);
    run_operation(4'h8, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h7F81_FFFF);
    run_operation(4'h9, 32'h7F80_FF01, 32'h0101_01FF, 32'd10, 32'h7F80_FF01);

    // Writes to read-only registers are rejected.
    apb_write(REG_ID, 32'hDEAD_BEEF, 4'hF, bus_error);
    if (bus_error !== 1'b1) begin
      $display("ERROR: write to read-only ID register was not rejected");
      $stop;
    end

    $display("RV32E PCA UNIT TEST PASS");
    $finish;
  end

endmodule
