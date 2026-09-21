// mpc-frame wrapper. A 32-bit bidirectional data bus keeps the APB-style link
// within the 66 payload pads available to each user design.

`default_nettype none

module Rv32ePca #(
  parameter integer IO_WIDTH = 66
) (
  input  wire                clock,
  input  wire                reset,
  input  wire [IO_WIDTH-1:0] io_in,
  output reg  [IO_WIDTH-1:0] io_out,
  output reg  [IO_WIDTH-1:0] io_oe
);

  wire [31:0] apb_paddr;
  wire [31:0] apb_prdata;
  wire        apb_pready;
  wire        apb_pslverr;
  wire        irq;
  wire        read_transfer;

  assign apb_paddr = {24'd0, io_in[37:32], 2'b00};
  assign read_transfer = io_in[42] && !io_in[44];

  Apb4Rv32ePca u_apb4_pca (
    .apb4_pclk    (clock),
    .apb4_presetn (!reset),
    .apb4_psel    (io_in[42]),
    .apb4_penable (io_in[43]),
    .apb4_pwrite  (io_in[44]),
    .apb4_paddr   (apb_paddr),
    .apb4_pprot   (3'b000),
    .apb4_pwdata  (io_in[31:0]),
    .apb4_pstrb   (io_in[41:38]),
    .apb4_pready  (apb_pready),
    .apb4_pslverr (apb_pslverr),
    .apb4_prdata  (apb_prdata),
    .irq_o        (irq)
  );

  always @* begin
    io_out = {IO_WIDTH{1'b0}};
    io_oe  = {IO_WIDTH{1'b0}};

    io_out[31:0] = apb_prdata;
    io_oe[31:0]  = {32{read_transfer}};

    io_out[45] = apb_pready;
    io_out[46] = apb_pslverr;
    io_out[47] = irq;
    io_oe[47:45] = 3'b111;
  end

endmodule

`default_nettype wire
