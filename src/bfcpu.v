module bfcpu (
  input wire clk,
  input wire rst,
);

  // BF program pointer, max size 16MB
  reg [23:0] pc;

  // Classic BF pointer and data registers.
  reg [14:0] pointer;
  reg  [7:0] data;

  // True if the data register is dirty and needs to be written back, we avoid
  // writing it to memory until the pointer changes.
  reg dirty;

endmodule
