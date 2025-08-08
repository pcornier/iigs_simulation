module iwm(
  input CLK_14M,
  input cen/*verilator public_flat*/,
  input reset,
  input [7:0] addr/*verilator public_flat*/,
  input rw/*verilator public_flat*/,
  input [7:0] din/*verilator public_flat*/,
  output reg [7:0] dout/*verilator public_flat*/,
  output irq/*verilator public_flat*/,
  input strobe/*verilator public_flat*/,
  input [7:0] DISK35/*verilator public_flat*/
);


endmodule
