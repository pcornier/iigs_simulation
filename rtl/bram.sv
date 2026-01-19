`timescale 1ns / 1ps

module bram #(
    parameter width_a = 8,
    parameter widthad_a = 10,
    parameter init_file= ""
) (
    // Port A
    input   wire                clock_a,
    input   wire                wren_a,
    input   wire    [widthad_a-1:0]  address_a,
    input   wire    [width_a-1:0]  data_a,
    output  reg     [width_a-1:0]  q_a,
     
    // Port B
    input   wire                clock_b,
    input   wire                wren_b,
    input   wire    [widthad_a-1:0]  address_b,
    input   wire    [width_a-1:0]  data_b,
    output  wire    [width_a-1:0]  q_b,  // Changed to wire for combinational read

    input wire byteena_a = 1'b1,
    input wire byteena_b = 1'b1,
    input wire enable_a = 1'b1,
    input wire enable_b = 1'b1
);

    initial begin
        $display("Loading rom.");
        $display(init_file);
        if (init_file>0)
        	$readmemh(init_file, mem);
    end

 
// Shared memory
reg [width_a-1:0] mem [(2**widthad_a)-1:0];

// Port A
always @(posedge clock_a) begin
    if(wren_a) begin
        mem[address_a] <= data_a;
        q_a      <= data_a;
    end else begin
        q_a      <= mem[address_a];
    end
end
 
// Port B - Combinational read for simulation (no latency)
// NOTE: Real FPGAs need registered BRAM. This is only for debugging the WOZ path.
always @(posedge clock_b) begin
    if(wren_b) begin
        mem[address_b] <= data_b;
    end
end
// Combinational read - output changes immediately with address
assign q_b = wren_b ? data_b : mem[address_b];
 
endmodule