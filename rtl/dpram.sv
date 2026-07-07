`timescale 1ns / 1ps

module dpram #(
    parameter width_a = 8,
    parameter widthad_a = 10,
    parameter init_file= "",
    parameter prefix= "",
    parameter p= "",
    // Simulation-only combinational mirror of port A's read (q_a_comb).
    // Models the FPGA accelerator's comb hit port (sdram_cache cpu_data_now),
    // which delivers read data within the SAME CLK_14M tick -- the registered
    // q_a is one tick late, which breaks the 1-tick (14.32 MHz) CPU cycle.
    // MUST stay 0 on synthesized instances: an async read port on the same
    // array defeats BRAM inference.
    parameter sim_async_a = 0
) (
    // Port A
    input   wire                clock_a,
    input   wire                wren_a,
    input   wire    [widthad_a-1:0]  address_a,
    input   wire    [width_a-1:0]  data_a,
    output  reg     [width_a-1:0]  q_a,
    output  wire    [width_a-1:0]  q_a_comb,

    // Port B
    input   wire                clock_b,
    input   wire                wren_b,
    input   wire    [widthad_a-1:0]  address_b,
    input   wire    [width_a-1:0]  data_b,
    output  reg     [width_a-1:0]  q_b,

    input wire byteena_a,
    input wire byteena_b,
    input wire ce_a,
    input wire enable_b
);

    initial begin
        $display("Loading rom.");
        $display(init_file);
        if (init_file>0)
                $readmemh(init_file, ram);
    end


// Shared ramory
reg [width_a-1:0] ram [(2**widthad_a)-1:0];

generate if (sim_async_a) begin : g_async_a
    assign q_a_comb = ram[address_a];
end else begin : g_async_a
    assign q_a_comb = {width_a{1'b0}};
end endgenerate

// Port A - Synchronous read/write
always @(posedge clock_a) begin
  if (ce_a) begin
    if(wren_a) begin
        ram[address_a] <= data_a;
        q_a      <= data_a;
`ifdef DEBUG_VERBOSE
        if (p == " e" && address_a == 17'h10F3A)
            $display("DPRAM_CURCYL: addr=%05h data=%02h t=%0t", address_a, data_a, $time);
`endif
    end else begin
        q_a      <= ram[address_a];
    end
  end
end

// Port B
always @(posedge clock_b) begin
    if(wren_b) begin
        ram[address_b] <= data_b;
        q_b      <= data_b;
        $display("writingb: %x %x",address_b,data_b);
    end else begin
        q_b      <= ram[address_b];
    end
end

endmodule
