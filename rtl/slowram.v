
module slowram(
  input clk,
  input [16:0] addr,
  input [7:0] din,
  output reg [7:0] dout,
  input wr,
  input ce
);

reg [7:0] ram[(1<<17)-1:0];

always @(posedge clk)
  if (ce) begin
    if (wr)
      dout <= ram[addr];
    else
      ram[addr] <= din;
  end

endmodule
