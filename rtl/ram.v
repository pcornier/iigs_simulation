`timescale 1ns / 1ps
module ram 
  #(
    parameter AW=16, 
    parameter DW=8) (
    input [(DW-1):0]  d,
    input [(AW-1):0]  addr,
    input	       we, clk,
    output [(DW-1):0] q
    );

   reg [DW-1:0] ram[2**AW-1:0];

   reg [AW-1:0]	addr_reg;

   always @ (posedge clk)
     begin
	// Write
	if (we)
	  ram[addr] <= d;

	addr_reg <= addr;
     end
   assign q = ram[addr_reg];
endmodule
