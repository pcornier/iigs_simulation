
module rom #(parameter memfile="")
(
  input clk,
  input [15:0] addr,
  output [7:0] dout,
  input ce
);

reg [7:0] q;
reg [7:0] mem[65535:0];

assign dout = ce ? q : 8'd0;

initial begin
  $readmemh(memfile, mem);
end

always @(posedge clk)
  q <= mem[addr];

endmodule
