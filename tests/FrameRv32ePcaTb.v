module FrameRv32ePcaTb;

`ifndef FRAME_TEST_DESIGN_ID
  initial begin
    $display("ERROR: FRAME_TEST_DESIGN_ID must be provided by the build tool");
    $stop;
  end
`endif

  localparam integer IO_WIDTH = 73;
  localparam integer DESIGN_ID_WIDTH = 7;
  localparam integer PAYLOAD_BASE = DESIGN_ID_WIDTH;
  localparam [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
  localparam integer HALF_PERIOD = 5;

  localparam [5:0] REG_ID        = 6'h00;
  localparam [5:0] REG_CTRL      = 6'h02;
  localparam [5:0] REG_STATUS    = 6'h03;
  localparam [5:0] REG_OPERAND_A = 6'h04;
  localparam [5:0] REG_OPERAND_B = 6'h05;
  localparam [5:0] REG_ACC       = 6'h06;
  localparam [5:0] REG_RESULT    = 6'h07;

  reg   clock;
  reg   reset;
  reg   [IO_WIDTH-1:0] test_io_out;
  reg   [IO_WIDTH-1:0] test_io_oe;
  tri   [IO_WIDTH-1:0] user_io;

  reg [31:0] read_value;
  reg [31:0] status;
  reg        bus_error;
  integer    poll;

  always #(HALF_PERIOD) clock = ~clock;

  genvar io_index;
  generate
    for (io_index = 0; io_index < IO_WIDTH; io_index = io_index + 1) begin : gen_test_io
      assign user_io[io_index] = test_io_oe[io_index]
        ? test_io_out[io_index]
        : 1'bz;
    end
  endgenerate

  FrameTop dut (
    .clock(clock),
    .reset(reset),
    .user_io(user_io)
  );

  task automatic drive_request_common;
    input [5:0] word_address;
    input       write_enable;
    begin
      test_io_oe[PAYLOAD_BASE+44:PAYLOAD_BASE+32] = {13{1'b1}};
      test_io_out[PAYLOAD_BASE+37:PAYLOAD_BASE+32] = word_address;
      test_io_out[PAYLOAD_BASE+41:PAYLOAD_BASE+38] = 4'hF;
      test_io_out[PAYLOAD_BASE+42] = 1'b1;
      test_io_out[PAYLOAD_BASE+43] = 1'b0;
      test_io_out[PAYLOAD_BASE+44] = write_enable;
    end
  endtask

  task automatic release_request;
    begin
      test_io_oe[PAYLOAD_BASE+44:PAYLOAD_BASE] = {45{1'b0}};
      test_io_out[PAYLOAD_BASE+44:PAYLOAD_BASE] = {45{1'b0}};
    end
  endtask

  task automatic apb_write;
    input [5:0]  word_address;
    input [31:0] data;
    output       error;
    begin
      @(negedge clock);
      drive_request_common(word_address, 1'b1);
      test_io_oe[PAYLOAD_BASE+31:PAYLOAD_BASE] = 32'hFFFF_FFFF;
      test_io_out[PAYLOAD_BASE+31:PAYLOAD_BASE] = data;
      @(negedge clock);
      test_io_out[PAYLOAD_BASE+43] = 1'b1;
      @(posedge clock);
      #1;
      if (user_io[PAYLOAD_BASE+45] !== 1'b1) begin
        $display("ERROR: Frame APB write did not receive PREADY");
        $stop;
      end
      error = user_io[PAYLOAD_BASE+46];
      @(negedge clock);
      release_request;
    end
  endtask

  task automatic apb_read;
    input  [5:0]  word_address;
    output [31:0] data;
    output        error;
    begin
      @(negedge clock);
      drive_request_common(word_address, 1'b0);
      test_io_oe[PAYLOAD_BASE+31:PAYLOAD_BASE] = 32'd0;
      @(negedge clock);
      test_io_out[PAYLOAD_BASE+43] = 1'b1;
      @(posedge clock);
      #1;
      if (user_io[PAYLOAD_BASE+45] !== 1'b1) begin
        $display("ERROR: Frame APB read did not receive PREADY");
        $stop;
      end
      data = user_io[PAYLOAD_BASE+31:PAYLOAD_BASE];
      error = user_io[PAYLOAD_BASE+46];
      @(negedge clock);
      release_request;
    end
  endtask

  task automatic write_ok;
    input [5:0]  word_address;
    input [31:0] data;
    reg error;
    begin
      apb_write(word_address, data, error);
      if (error) begin
        $display("ERROR: Frame APB write failed at word 0x%0h", word_address);
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
      if (error) begin
        $display("ERROR: Frame APB read failed at word 0x%0h", word_address);
        $stop;
      end
    end
  endtask

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    test_io_out = {IO_WIDTH{1'b0}};
    test_io_oe = {IO_WIDTH{1'b0}};
    read_value = 32'd0;
    status = 32'd0;
    bus_error = 1'b0;
    poll = 0;

    test_io_oe[DESIGN_ID_WIDTH-1:0] = {DESIGN_ID_WIDTH{1'b1}};
    test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
    repeat (20) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;
    repeat (4) @(posedge clock);
    #1;

    if (!dut.selection_valid || !dut.design_selected[DESIGN_ID]) begin
      $display("ERROR: PCA design was not selected through FrameTop");
      $stop;
    end

    read_ok(REG_ID, read_value);
    if (read_value !== 32'h5043_4134) begin
      $display("ERROR: PCA ID did not cross FrameTop: 0x%08h", read_value);
      $stop;
    end

    write_ok(REG_OPERAND_A, 32'h0403_0201);
    write_ok(REG_OPERAND_B, 32'h0807_0605);
    write_ok(REG_ACC, 32'd10);
    write_ok(REG_CTRL, 32'h0000_0115); // signed DOT4 + ACC, IRQ enabled

    status = 32'd0;
    poll = 0;
    while ((poll < 8) && !status[1]) begin
      read_ok(REG_STATUS, status);
      poll = poll + 1;
    end
    if (!status[1] || !status[2]) begin
      $display("ERROR: PCA did not complete through FrameTop, status=0x%08h",
               status);
      $stop;
    end
    if (user_io[PAYLOAD_BASE+47] !== 1'b1) begin
      $display("ERROR: PCA IRQ did not reach its FrameTop pad");
      $stop;
    end

    read_ok(REG_RESULT, read_value);
    // 1*5 + 2*6 + 3*7 + 4*8 + 10 = 80
    if (read_value !== 32'd80) begin
      $display("ERROR: PCA Frame result was %0d, expected 80", read_value);
      $stop;
    end

    // An unimplemented word address must return PSLVERR.
    apb_read(6'h3F, read_value, bus_error);
    if (bus_error !== 1'b1) begin
      $display("ERROR: invalid Frame register read was not rejected");
      $stop;
    end

    $display("RV32E PCA FRAME TEST PASS");
    $finish;
  end

endmodule
