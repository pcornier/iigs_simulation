module singlesteptests
  (
   input  reset,
   input  clk,
   input[7:0]  cpu_din,
   output[7:0] cpu_dout,
   output[23:0] cpu_addr,
   output cpu_we_n,
   output ready_out,
   output cpu_vpa,
   output cpu_vda,
   output cpu_mlb,
   output cpu_vpb
   );

   initial begin
      $dumpfile("singlesteptests.vcd");
      $dumpvars(0);
   end   

P65C816 cpu(
            .CLK(clk),
            .RST_N(~reset),
            .CE(1'b1),
            .RDY_IN(1'b1),
            .NMI_N(1'b1),
            .IRQ_N(1'b1),
            .ABORT_N(1'b1),
            .D_IN(cpu_din),
            .D_OUT(cpu_dout),
            .A_OUT(cpu_addr),
            .WE(cpu_we_n), // This signal is active low at this point
            .RDY_OUT(ready_out),
            .VPA(cpu_vpa),
            .VDA(cpu_vda),
            .MLB(cpu_mlb),
            .VPB(cpu_vpb)
            );
endmodule; // singlesteptests
