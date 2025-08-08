`timescale 1ns / 1ps

module tb_clock_divider;

// Parameters
parameter CLK_PERIOD = 69.84; // 14.318 MHz = 69.84ns period

// Testbench signals
reg clk_14M;
reg reset;
reg stretch;
reg [7:0] cyareg;
reg [7:0] bank;
reg [7:0] shadow;
reg [15:0] addr;
reg IO;

// DUT outputs
wire clk_14M_en;
wire clk_7M_en;
wire ph0_en;
wire ph2_en;
wire q3_en;
wire ph0_state;
wire slow;

// Instantiate DUT
clock_divider dut (
    .clk_14M(clk_14M),
    .reset(reset),
    .stretch(stretch),
    .cyareg(cyareg),
    .bank(bank),
    .shadow(shadow),
    .addr(addr),
    .IO(IO),
    .clk_14M_en(clk_14M_en),
    .clk_7M_en(clk_7M_en),
    .ph0_en(ph0_en),
    .ph2_en(ph2_en),
    .q3_en(q3_en),
    .ph0_state(ph0_state),
    .slow(slow)
);

// Clock generation
initial begin
    clk_14M = 0;
    forever #(CLK_PERIOD/2) clk_14M = ~clk_14M;
end

// Test stimulus
initial begin
    // Initialize VCD dump
    $dumpfile("clock_divider.vcd");
    $dumpvars(0, tb_clock_divider);
    
    // Initialize signals
    reset = 1;
    stretch = 0;
    cyareg = 8'h80;  // Start in fast mode (bit 7 = 1)
    bank = 8'h00;
    shadow = 8'hFF;
    addr = 16'h0000;
    IO = 0;
    
    // Wait a few clock cycles then release reset
    #(CLK_PERIOD * 5);
    reset = 0;
    
    $display("Starting clock divider test...");
    $display("Time\t\t14M_en\t7M_en\tPH0_en\tPH2_en\tQ3_en\tPH0\tSlw\tCyareg");
    $monitor("%t\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%h", 
             $time, clk_14M_en, clk_7M_en, ph0_en, ph2_en, q3_en, 
             ph0_state, slow, cyareg);
    
    // Run for several complete PH0 cycles to observe behavior in fast mode
    #(CLK_PERIOD * 14 * 8); // 8 complete PH0 cycles (14 clocks per cycle now)
    
    // Test slow mode functionality with cyareg=FF and C0E9 access
    $display("\n--- Testing slow mode with cyareg=FF and C0E9 access ---");
    cyareg = 8'hFF;  // Set cyareg to FF (enables slot 6 slow mode detection)
    #(CLK_PERIOD * 2);  // Wait a couple cycles
    
    // Access C0E9 to trigger slow mode
    IO = 1;
    addr = 16'hC0E9;
    #(CLK_PERIOD * 2);  // Hold for 2 clock cycles
    IO = 0;
    addr = 16'h0000;
    
    // Run in slow mode for several cycles
    #(CLK_PERIOD * 14 * 8); // 8 complete PH0 cycles in slow mode
    
    // Test returning to fast mode by accessing C0E8
    $display("\n--- Testing return to fast mode with C0E8 access ---");
    IO = 1;
    addr = 16'hC0E8;
    #(CLK_PERIOD * 2);  // Hold for 2 clock cycles
    IO = 0;
    addr = 16'h0000;
    
    // Run in fast mode again
    #(CLK_PERIOD * 14 * 4); // 4 more PH0 cycles in fast mode
    
    // Test stretch functionality
    $display("\n--- Testing stretch functionality ---");
    stretch = 1;
    #(CLK_PERIOD * 14 * 2); // 2 more PH0 cycles with stretch
    stretch = 0;
    
    // Run a bit longer to see return to normal operation
    #(CLK_PERIOD * 14 * 3);
    
    $display("\nTest completed successfully!");
    $finish;
end

// Additional monitoring for debugging
always @(posedge clk_14M) begin
    if (ph0_en) begin
        $display("PH0 edge at time %t, state: %b", $time, ph0_state);
    end
    if (q3_en) begin
        $display("Q3 edge at time %t", $time);
    end
end

// Performance counters
integer ph0_count = 0;
integer ph2_count = 0;
integer clk_7m_count = 0;

always @(posedge ph0_en) ph0_count = ph0_count + 1;
always @(posedge ph2_en) ph2_count = ph2_count + 1;
always @(posedge clk_7M_en) clk_7m_count = clk_7m_count + 1;

initial begin
    #(CLK_PERIOD * 14 * 30 + 100); // Wait until near end of simulation
    $display("\n=== Final Statistics ===");
    $display("PH0 pulses: %d", ph0_count);
    $display("PH2 pulses: %d", ph2_count);
    $display("7M pulses: %d", clk_7m_count);
end

endmodule
