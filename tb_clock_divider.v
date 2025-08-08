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
wire slowMem;

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
    .slow(slow),
    .slowMem(slowMem)
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
    $display("Time\t\t14M_en\t7M_en\tPH0_en\tPH2_en\tQ3_en\tPH0\tSlw\tSlwMem\tBank\tAddr\tCyareg");
    $monitor("%t\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%b\t%h\t%h\t%h", 
             $time, clk_14M_en, clk_7M_en, ph0_en, ph2_en, q3_en, 
             ph0_state, slow, slowMem, bank, addr, cyareg);
    
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
    
    // === MEMORY ACCESS TESTS ===
    $display("\n=== Testing Memory Access Slow Mode ===");
    
    // Reset to fast mode and disable IO slow triggers
    cyareg = 8'h80;  // Fast mode, no slot slow triggers
    IO = 0;
    addr = 16'h0000;
    bank = 8'h00;
    
    // Test 1: I/O space C000-CFFF in bank 00/01 should trigger slowMem
    $display("\n--- Test 1: I/O Space C000-CFFF ---");
    bank = 8'h00;
    addr = 16'hC000;  // I/O space start
    #(CLK_PERIOD * 4);
    addr = 16'hC123;  // Random I/O address
    #(CLK_PERIOD * 4);
    addr = 16'hCFFF;  // I/O space end
    #(CLK_PERIOD * 4);
    
    // Test same addresses in bank 01
    bank = 8'h01;
    addr = 16'hC000;
    #(CLK_PERIOD * 4);
    addr = 16'hCFFF;
    #(CLK_PERIOD * 4);
    
    // Verify it doesn't trigger in other banks
    bank = 8'h02;
    addr = 16'hC000;
    #(CLK_PERIOD * 4);
    
    // Test 2: ROM space E000-FFFF in bank 00
    $display("\n--- Test 2: ROM Space E000-FFFF ---");
    bank = 8'h00;
    addr = 16'hE000;  // ROM space start
    #(CLK_PERIOD * 4);
    addr = 16'hF000;  // Mid ROM
    #(CLK_PERIOD * 4);
    addr = 16'hFFFF;  // ROM space end
    #(CLK_PERIOD * 4);
    
    // Verify it doesn't trigger in other banks
    bank = 8'h01;
    addr = 16'hE000;
    #(CLK_PERIOD * 4);
    
    // Test 3: Slot ROM banks C1-CF
    $display("\n--- Test 3: Slot ROM Banks C1-CF ---");
    bank = 8'hC1;
    addr = 16'h1000;  // Any address in slot ROM bank
    #(CLK_PERIOD * 4);
    
    bank = 8'hC8;     // Slot 0
    addr = 16'h2000;
    #(CLK_PERIOD * 4);
    
    bank = 8'hCF;     // Last slot ROM bank
    addr = 16'h3000;
    #(CLK_PERIOD * 4);
    
    // Verify non-slot ROM banks don't trigger
    bank = 8'hC0;     // Not a slot ROM bank
    addr = 16'h1000;
    #(CLK_PERIOD * 4);
    
    bank = 8'hD0;     // Beyond slot ROM range
    addr = 16'h1000;
    #(CLK_PERIOD * 4);
    
    // Test 4: Shadowed video memory ranges
    $display("\n--- Test 4: Shadowed Video Memory ---");
    
    // Text page 1: 0400-07FF in bank 00/01
    bank = 8'h00;
    addr = 16'h0400;  // Text page 1 start
    #(CLK_PERIOD * 4);
    addr = 16'h07FF;  // Text page 1 end
    #(CLK_PERIOD * 4);
    
    bank = 8'h01;
    addr = 16'h0400;
    #(CLK_PERIOD * 4);
    
    // Text page 2 / Hi-res page 1: 0800-0BFF in bank 00/01
    bank = 8'h00;
    addr = 16'h0800;  // Text page 2 start
    #(CLK_PERIOD * 4);
    addr = 16'h0BFF;  // Text page 2 end
    #(CLK_PERIOD * 4);
    
    // Hi-res page 2: 2000-3FFF in bank 00/01
    bank = 8'h00;
    addr = 16'h2000;  // Hi-res page 2 start
    #(CLK_PERIOD * 4);
    addr = 16'h3FFF;  // Hi-res page 2 end
    #(CLK_PERIOD * 4);
    
    bank = 8'h01;
    addr = 16'h2000;
    #(CLK_PERIOD * 4);
    
    // Verify these ranges don't trigger in other banks
    bank = 8'h02;
    addr = 16'h0400;
    #(CLK_PERIOD * 4);
    addr = 16'h2000;
    #(CLK_PERIOD * 4);
    
    // Test 5: Entire banks E0 and E1 - always slow
    $display("\n--- Test 5: Banks E0/E1 Always Slow ---");
    bank = 8'hE0;
    addr = 16'h0000;  // Any address in E0
    #(CLK_PERIOD * 4);
    addr = 16'h8000;
    #(CLK_PERIOD * 4);
    addr = 16'hFFFF;
    #(CLK_PERIOD * 4);
    
    bank = 8'hE1;
    addr = 16'h0000;  // Any address in E1
    #(CLK_PERIOD * 4);
    addr = 16'hFFFF;
    #(CLK_PERIOD * 4);
    
    // Test 6: C042/C041 special addresses
    $display("\n--- Test 6: C042/C041 Special Addresses ---");
    bank = 8'h00;
    cyareg = 8'h80;  // Fast mode
    IO = 1;
    addr = 16'hC042;  // Should trigger slow mode
    #(CLK_PERIOD * 4);
    IO = 0;
    addr = 16'h0000;
    #(CLK_PERIOD * 4);
    
    // Return to fast mode with C041
    IO = 1;
    addr = 16'hC041;
    #(CLK_PERIOD * 4);
    IO = 0;
    addr = 16'h0000;
    #(CLK_PERIOD * 4);
    
    // Test 7: Normal memory ranges should be fast
    $display("\n--- Test 7: Normal Memory - Should be Fast ---");
    bank = 8'h00;
    addr = 16'h1000;  // Normal RAM
    #(CLK_PERIOD * 4);
    
    bank = 8'h10;     // Extended memory bank
    addr = 16'h5000;
    #(CLK_PERIOD * 4);
    
    addr = 16'hD000;  // Just below ROM
    #(CLK_PERIOD * 4);
    
    $display("\n=== Memory Access Tests Completed ===");
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
