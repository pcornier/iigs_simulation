`timescale 1ns / 1ps

module bram #(
    parameter width_a = 8,
    parameter widthad_a = 10,
    parameter init_file= "",
    // BRAM_LATENCY controls Port B read behavior:
    //   0 = Combinational read (simulation-friendly, no latency)
    //   1 = Registered read (FPGA-friendly, 1-cycle latency)
    parameter BRAM_LATENCY = 0
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
    output  wire    [width_a-1:0]  q_b,

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

// Port A - Always registered (standard BRAM behavior)
always @(posedge clock_a) begin
    if(wren_a) begin
        mem[address_a] <= data_a;
        q_a      <= data_a;
    end else begin
        q_a      <= mem[address_a];
    end
end

// Port B - Latency controlled by BRAM_LATENCY parameter
generate
    if (BRAM_LATENCY == 0) begin : gen_combinational
        // Combinational read - output changes immediately with address
        // This is for simulation only; real FPGAs need registered BRAM.
        always @(posedge clock_b) begin
            if(wren_b) begin
                mem[address_b] <= data_b;
            end
        end
        assign q_b = wren_b ? data_b : mem[address_b];
    end else begin : gen_registered
        // Registered read - standard FPGA BRAM behavior with 1-cycle latency
        // Address is registered, data appears on the next clock edge.
        reg [width_a-1:0] q_b_reg;
        always @(posedge clock_b) begin
            if(wren_b) begin
                mem[address_b] <= data_b;
                q_b_reg <= data_b;
            end else begin
                q_b_reg <= mem[address_b];
            end
        end
        assign q_b = q_b_reg;
    end
endgenerate

endmodule
