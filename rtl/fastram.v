
module fastram(
  input clk,
  input [22:0] addr,
  input [7:0] din,
  output reg [7:0] dout,
  input wr,
  input ce
);

reg [7:0] ram[(1<<23)-1:0];

wire [7:0] dbg = ram[addr];

always @(posedge clk)
  if (ce) begin
    if (wr)
      dout <= ram[addr];
    else
      ram[addr] <= din;
  end

endmodule
