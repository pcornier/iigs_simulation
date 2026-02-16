
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
    else begin
      ram[addr] <= din;
`ifdef SIMULATION
      // Watchpoint: E1:0F3A = curcyl[0] in firmware driver
      if (addr == 17'h10F3A)
        $display("SLOWRAM_WATCHPOINT: write E1:0F3A <= %02h (curcyl[0])", din);
`endif
    end
  end

endmodule
