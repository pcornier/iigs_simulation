// Define DEBUG_CLKDIV to enable verbose clock divider debug output
// `define DEBUG_CLKDIV

module clock_divider (
    input  wire        clk_14M,        // 14.318 MHz input clock
    input  wire        reset,          // Active high reset
    input  wire [7:0]  cyareg,          // Active high reset
    input wire [7:0] bank,             // CPU BANK
    input wire [7:0] shadow,           // SHADOW REG
    input wire [15:0] addr,            // CPU ADDR
    input wire IO,
    input wire we,                     // NEW: Write enable signal
    input wire floppy_motor_on,        // Floppy motor active (force slow mode)

    input  wire        stretch,        // Stretch signal for extended cycles
    
    // Clock enables (active high for one 14M cycle)
    output reg         clk_14M_en,     // 14M enable (always high)
    output reg         clk_7M_en,      // 7M enable (~7.159 MHz)
    output reg         ph0_en,         // PH0 enable (~1 MHz, compatible with Apple II)
    output reg         ph2_en,         // PH2 enable (variable rate for fast/sync cycles) (FAST CLK)
    output reg         q3_en,          // Q3 enable (quadrature timing)
    
    // Clock states for debugging/interfacing
    output reg         ph0_state,      // Current PH0 level
    output reg         slow,             // Slow mode indicator
    output reg         slowMem/*verilator public_flat*/             // Slow mode indicator
);

// Clock divider counters
reg [3:0]  clk_14M_counter;    // 14M cycle counter
reg [3:0]  ph0_counter;        // PH0 cycle counter (0-13 for full cycle)
reg [3:0]  ph2_counter;        // PH2 cycle counter
reg [3:0]  refresh_counter;    // Refresh cycle counter (every 9th cycle)
reg        clk_7M_div;         // 7M divider flip-flop
reg [3:0]  ph2_gap_count;      // Ticks since last ph2_en (for mode transition safety)

// PH2 cycle state machine
localparam CYCLE_FAST         = 4'd0;  // Normal fast cycle (5 ticks: 2 low, 3 high)
localparam CYCLE_REFRESH      = 4'd1;  // Fast refresh cycle (10 ticks: 2 low, 8 high)
localparam CYCLE_SYNC         = 4'd2;  // Sync cycle (14-27 ticks: 2 low, 12-25 high)
localparam CYCLE_SYNC_STRETCH = 4'd3;  // Sync stretch cycle (16-29 ticks: 2 low, 14-27 high)

reg [4:0] ph2_cycle_length;    // Current PH2 cycle length
reg       sync_requested;      // Flag to request sync cycle
reg       refresh_requested;   // Flag to request refresh cycle

// Pipeline registers for clean PH2/PH0 synchronization (Option 3)
reg [3:0] ph0_counter_prev;     // Previous cycle ph0_counter value
reg       ph0_en_prev;          // Previous cycle ph0_en value  
reg       ph0_state_prev;       // Previous cycle ph0_state value
reg [3:0] ph0_counter_next;     // Next cycle ph0_counter value (for enable calculation)
reg       slow_prev;            // Previous cycle slow state (to avoid assignment conflicts)  
reg       ph2_sync_pulse;       // Debug signal to show sync pulses in VCD
reg       ph2_en_prev;          // Proper variable to track ph2_en changes
reg       we_reg;              // Registered version of we signal to avoid timing races



// CYAREG:
//
// 0 - slot 4 disk motor-on detect
// 1 - slot 5 disk motor-on detect
// 2 - slot 6 disk motor-on detect
// 3 - slot 7 disk motor-on detect
// 4 - shadowing enabled all ram banks
// 5 - RESERVED DO NOT MODIFY
// 6 - POWER ON STATUS
// 7 - CPU Speed (0 - 1.024Mhz 1 - 2.8Mhz )
// 
//
// When bit 1 is set, on C0D9 access switch to 1.024Mhz on  C0D8 resume to 2.8Mhz
// C0C9 - slot 4
// C0D9 - slot 5
// C0E9 - slot 6
// C0F9 - slot 7

// Shadowed writes slow down processor

reg waitforC0C8;
reg waitforC0D8;
reg waitforC0E8;
reg waitforC0F8;
reg waitforC041;

reg [7:0]  cyareg_reg;
always @(posedge clk_14M) begin
    if (reset) begin
        cyareg_reg <= 8'h80;  // Start in fast mode
    end else begin
        cyareg_reg <= cyareg;
    end
end

// Slow mode: CYAREG bit 7 = 0, OR waiting for slot motor-on detect
// Note: 3.5" floppy motor does NOT force slow mode - only 5.25" slot-based detection does
wire slow_request = (cyareg[7] == 1'b0) || waitforC0C8 || waitforC0D8 || waitforC0E8 || waitforC0F8 || waitforC041;

`ifdef SIMULATION
// Debug: track previous states and counters (module scope to avoid
// procedural declarations errors in Verilog-2001 tools)
reg        prev_slow;
reg        prev_slowMem;
reg [31:0] slow_ph2_cnt;
reg [31:0] fast_ph2_cnt;
reg [31:0] slow_14m_cycles;
reg [31:0] fast_14m_cycles;
reg [3:0]  last_event; // 0:none 1:C0C9 2:C0D9 3:C0E9 4:C0F9 5:C042 6:slowMem
`endif
	
always @(posedge clk_14M) begin
    if (reset) begin
        waitforC0C8 <= 1'b0;
        waitforC0D8 <= 1'b0;
        waitforC0E8 <= 1'b0;
        waitforC0F8 <= 1'b0;
        waitforC041 <= 1'b0;
    end else begin
        if (cyareg[0] == 1'b1 && IO && addr == 16'hC0C9) waitforC0C8 <= 1;
        if (cyareg[1] == 1'b1 && IO && addr == 16'hC0D9) waitforC0D8 <= 1;
        if (cyareg[2] == 1'b1 && IO && addr == 16'hC0E9) waitforC0E8 <= 1;
        if (cyareg[3] == 1'b1 && IO && addr == 16'hC0F9) waitforC0F8 <= 1;
        if (IO && addr == 16'hC042) waitforC041 <= 1;

        if (waitforC0C8 && IO && addr == 16'hC0C8) waitforC0C8 <= 0;
        if (waitforC0D8 && IO && addr == 16'hC0D8) waitforC0D8 <= 0;
        if (waitforC0E8 && IO && addr == 16'hC0E8) waitforC0E8 <= 0;
        if (waitforC0F8 && IO && addr == 16'hC0F8) waitforC0F8 <= 0;
        if (waitforC041 && IO && addr == 16'hC041) waitforC041 <= 0;
    end
end

always @(posedge clk_14M) begin
    if (reset) begin
        // Reset all counters and states
        clk_14M_counter <= 4'd0;
        ph0_counter <= 4'd0;
        ph2_counter <= 4'd0;
        refresh_counter <= 4'd0;
        clk_7M_div <= 1'b0;
        
        // Reset enables
        clk_14M_en <= 1'b0;
        clk_7M_en <= 1'b0;
        ph0_en <= 1'b0;
        ph2_en <= 1'b0;
        q3_en <= 1'b0;
        
        // Reset states
        ph0_state <= 1'b0;
        slow <= 1'b0;
        slowMem <= 1'b0;
        slow_prev <= 1'b0;
        
        // Reset pipeline registers
        ph0_counter_prev <= 4'd0;
        ph0_en_prev <= 1'b0;
        ph0_state_prev <= 1'b0;
        ph2_sync_pulse <= 1'b0;
        ph2_en_prev <= 1'b0;
        we_reg <= 1'b0;
        ph2_gap_count <= 4'd6;  // Start with gap satisfied
`ifdef SIMULATION
        prev_slow <= 1'b0;
        prev_slowMem <= 1'b0;
        slow_ph2_cnt <= 32'd0;
        fast_ph2_cnt <= 32'd0;
        slow_14m_cycles <= 32'd0;
        fast_14m_cycles <= 32'd0;
        last_event <= 4'd0;
`endif
        
        // Reset cycle control
        ph2_cycle_length <= 5'd5;  // Default to fast cycle
        sync_requested <= 1'b0;
        refresh_requested <= 1'b0;
        
        // Reset pipeline registers
        ph0_counter_prev <= 4'd0;
        ph0_en_prev <= 1'b0;
        ph0_state_prev <= 1'b0;
    end else begin
        // --- Refactored Logic ---
        slow <= slow_request;

        // Register write enable to avoid timing races
        we_reg <= we;

        // 4. Determine slowMem (unconditionally)
        slowMem <= 1'b0;
        if ( (bank == 8'hE0 || bank == 8'hE1) ||
             ( (bank == 8'h00 || bank == 8'h01) && addr[15:12] == 4'hC &&
               !(
                 (addr == 16'hC02D) || (addr == 16'hC035) || (addr == 16'hC036) ||
                 (addr == 16'hC037) || (addr == 16'hC068) || (addr == 16'hC069) ||
                 (addr >= 16'hC071 && addr <= 16'hC07F)
               )
             ) ||
             (we_reg && (bank == 8'h00 || bank == 8'h01) &&
                (
                    // Shadow bits are "inhibit" flags: bit=0 means shadow ENABLED (slow access)
                    // bit=1 means shadow DISABLED (fast access). Use inverted bits for slowMem.
                    (addr >= 16'h0400 && addr <= 16'h07FF && ~shadow[0]) ||
                    (addr >= 16'h0800 && addr <= 16'h0BFF && ~shadow[5]) ||
                    (addr >= 16'h2000 && addr <= 16'h3FFF && ~shadow[1]) ||
                    (addr >= 16'h4000 && addr <= 16'h5FFF && ~shadow[2])
                )
             )
           )
        begin
            slowMem <= 1;
        end

        // --- Original Clock Generation Logic (unchanged) ---

        // 14M is always enabled
        clk_14M_en <= 1'b1;
        
        // Increment master counter
        clk_14M_counter <= clk_14M_counter + 1'b1;
        
        // Generate 7M enable (every other 14M cycle)
        clk_7M_div <= ~clk_7M_div;
        clk_7M_en <= ~clk_7M_div;  // Enable on rising edge of 7M
        
        // PH0 generation (Apple II compatible 1MHz clock)
        ph0_counter_next = ph0_counter + 1'b1;
        if (ph0_counter == 4'd13) begin
            ph0_counter_next = 4'd0;
        end
        ph0_counter <= ph0_counter_next;
        
        if (ph0_counter_next < 4'd7) begin
            ph0_state <= 1'b0;
            ph0_en <= (ph0_counter_next == 4'd0);
        end else begin
            ph0_state <= 1'b1;
            ph0_en <= 1'b0;
        end
        
        q3_en <= (ph0_counter_next == 4'd0) || (ph0_counter_next == 4'd7);
        
        ph0_counter_prev <= ph0_counter;
        ph0_en_prev <= ph0_en;
        ph0_state_prev <= ph0_state;
        slow_prev <= slow;

        // Track gap since last ph2_en (for mode transition safety)
        if (ph2_en)
            ph2_gap_count <= 4'd0;
        else if (ph2_gap_count < 4'd14)
            ph2_gap_count <= ph2_gap_count + 4'd1;

	if (slow==1'b1 || slowMem==1'b1) begin
		// Sync cycle: ph2_en pulses once per ph0 cycle (every 14 ticks)
		// Check gap to prevent back-to-back pulses on fast->slow transition
		if (ph0_counter_next == 4'd0 && ph2_gap_count >= 4'd5) begin
			ph2_en <= 1'b1;  // Single enable pulse
			ph2_counter <= 4'd1;
			ph2_sync_pulse <= 1'b1;
		end else begin
			ph2_en <= 1'b0;  // Stay low for rest of ph0 cycle
			if (ph2_counter < 4'd13) begin
				ph2_counter <= ph2_counter + 1'b1;
			end
			ph2_sync_pulse <= 1'b0;
		end
	end else if (slow==1'b0 && slowMem==1'b0) begin
        // Fast mode: 5-tick cycles (2.86 MHz) matching standard IIgs timing
        ph2_counter <= ph2_counter + 1'b1;
        if (ph2_counter >= 4'd4) begin
            ph2_counter <= 4'd0;
        end

        ph2_en <= (ph2_counter == 4'd0);  // Single tick enable at start of cycle
        ph2_sync_pulse <= 1'b0;
    end else begin
`ifdef DEBUG_CLK_TIMING
        $display("CLKDIV: IMPOSSIBLE BRANCH - neither slow nor fast conditions met! slow=%0b slowMem=%0b t=%0t", slow, slowMem, $time);
`endif
    end
        
`ifdef SIMULATION
        if ((slow != prev_slow) || (slowMem != prev_slowMem)) begin
`ifdef DEBUG_CLKDIV
            $display("CLKDIV: slow=%0d slowMem=%0d -> slow=%0d slowMem=%0d ph0_cnt=%0d ph2_cnt=%0d t=%0t", prev_slow, prev_slowMem, slow, slowMem, ph0_counter, ph2_counter, $time);
`endif
            if (!slow && !slowMem) begin
                slow_ph2_cnt <= 0;
                slow_14m_cycles <= 0;
                last_event <= 0;
            end
            prev_slow <= slow;
            prev_slowMem <= slowMem;
        end
        ph2_en_prev <= ph2_en;
`endif
    end
end


endmodule