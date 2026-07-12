`timescale 1ns / 1ps

//-------------------------------------------------------------------------------------------------
module rom
//-------------------------------------------------------------------------------------------------
#
(
	parameter AW = 16,
	parameter DW = 8,
	parameter memfile = "rom8x16K.hex"
) (
	input  wire         clock,
	input  wire         ce,
	output reg [DW-1:0] q,
	input  wire[AW-1:0] address
);
//-------------------------------------------------------------------------------------------------

    initial begin
        $display("rom Loading rom: %s", memfile);
        $readmemh(memfile, d);
    end

reg[DW-1:0] d[(2**AW)-1:0];

// Synchronous read (FPGA compatible - 1 cycle latency)
// VGC must pre-fetch ROM data to compensate for this latency
always @(posedge clock) if(ce) q <= d[address];

// Debug chr.mem reads (commented out for production)
// always @(posedge clock) if(ce) begin
//     if (memfile == "chr.mem" && address >= 12'h2F0 && address <= 12'h300)
//         $display("CHRROM: addr=%h data_out=%h", address, d[address]);
// end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
