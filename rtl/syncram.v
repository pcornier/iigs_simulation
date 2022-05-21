module syncram
  (input	      clk,
   input	      we,
   input [7:0]	      data_in,
   input [15:0]	      addr,
   output reg [7:0]   data_out
   );

   reg [7:0]	      ram [65535:0];

   always @(posedge clk) begin
      if (we) ram[addr] <= data_in;
      data_out <= ram[addr];
   end
endmodule // syncram
