// Define DEBUG_CLKDIV to enable verbose clock divider debug output
//`define DEBUG_CLKDIV
// Define DEBUG_SLOWMEM to enable slowMem access tracking (very verbose)
//`define DEBUG_SLOWMEM

module clock_divider (
    input  wire        clk_14M,        // 14.318 MHz input clock
    input  wire        reset,          // Active high reset
    input  wire [7:0]  cyareg,          // Active high reset
    input wire [7:0] bank,             // CPU BANK
    input wire [7:0] shadow,           // SHADOW REG
    input wire [15:0] addr,            // CPU ADDR
    input wire IO,
    input wire we,                     // Write enable signal
    input wire valid,                  // VPA|VDA: bus cycle is valid (address bus meaningful)
    input wire is_rom_access,          // True when accessing ROM (refresh hidden)

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
reg        cycle_is_refresh;   // Next cycle is a refresh (10-tick) cycle
reg        clk_7M_div;         // 7M divider flip-flop
reg [3:0]  ph2_gap_count;      // Ticks since last ph2_en (for debug tracking)
reg        sync_aligned;       // First PHI0 boundary seen during sync wait

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

reg [7:0]  cyareg_reg;
always @(posedge clk_14M) begin
    if (reset) begin
        cyareg_reg <= 8'h80;  // Start in fast mode
    end else begin
        cyareg_reg <= cyareg;
    end
end

// Slow mode: CYAREG bit 7 = 0, OR waiting for slot motor-on detect WITH cyareg bit enabled
// Note: 3.5" floppy motor does NOT force slow mode - only 5.25" slot-based detection does
// MAME gates slow mode by (m_motors_active & (m_speed & 0x0f)), so we do the same:
// - waitforC0XY tracks motor state unconditionally
// - cyareg[N] bit gates whether that motor forces slow mode
wire slow_request = (cyareg[7] == 1'b0) ||
                   (waitforC0C8 && cyareg[0]) ||
                   (waitforC0D8 && cyareg[1]) ||
                   (waitforC0E8 && cyareg[2]) ||
                   (waitforC0F8 && cyareg[3]);

// I/O bank check for motor detection - banks that have I/O mirrored at $C0xx
// Banks 00, 01, E0, E1, FC, FD, FE, FF all have I/O at $C0xx
// IMPORTANT: Can't use IO signal because IO=0 for ROM bank reads
wire io_bank = (bank == 8'h00 || bank == 8'h01 || bank == 8'he0 || bank == 8'he1 ||
               bank == 8'hfc || bank == 8'hfd || bank == 8'hfe || bank == 8'hff);

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
// Track previous motor flag states for edge detection
reg        prev_waitforC0C8;
reg        prev_waitforC0D8;
reg        prev_waitforC0E8;
reg        prev_waitforC0F8;
reg [15:0] iwm_slow_log_count;
`endif
	
always @(posedge clk_14M) begin
    if (reset) begin
        waitforC0C8 <= 1'b0;
        waitforC0D8 <= 1'b0;
        waitforC0E8 <= 1'b0;
        waitforC0F8 <= 1'b0;
`ifdef SIMULATION
        prev_waitforC0C8 <= 1'b0;
        prev_waitforC0D8 <= 1'b0;
        prev_waitforC0E8 <= 1'b0;
        prev_waitforC0F8 <= 1'b0;
`endif
    end else begin
        // Track motor state UNCONDITIONALLY (like MAME does)
        // The cyareg bits gate whether motor forces slow mode (in slow_request), not tracking
        // Use io_bank wire (defined above) to check for I/O-mirrored banks

        if (io_bank && addr == 16'hC0C9) begin
            waitforC0C8 <= 1;
        end
        if (io_bank && addr == 16'hC0D9) begin
            waitforC0D8 <= 1;
        end
        if (io_bank && addr == 16'hC0E9) begin
            waitforC0E8 <= 1;
        end
        if (io_bank && addr == 16'hC0F9) begin
            waitforC0F8 <= 1;
        end

        if (waitforC0C8 && io_bank && addr == 16'hC0C8) begin
            waitforC0C8 <= 0;
        end
        if (waitforC0D8 && io_bank && addr == 16'hC0D8) begin
            waitforC0D8 <= 0;
        end
        if (waitforC0E8 && io_bank && addr == 16'hC0E8) begin
            waitforC0E8 <= 0;
        end
        if (waitforC0F8 && io_bank && addr == 16'hC0F8) begin
            waitforC0F8 <= 0;
        end

`ifdef SIMULATION
        // Edge-detected debug output for motor state changes
`ifdef DEBUG_CLKDIV
        if (waitforC0C8 && !prev_waitforC0C8)
            $display("VSIM_MOTOR: slot=4 motor=ON  (waitforC0C8=0->1) cyareg[0]=%0d t=%0t", cyareg[0], $time);
        if (!waitforC0C8 && prev_waitforC0C8)
            $display("VSIM_MOTOR: slot=4 motor=OFF (waitforC0C8=1->0) cyareg[0]=%0d t=%0t", cyareg[0], $time);
        if (waitforC0D8 && !prev_waitforC0D8)
            $display("VSIM_MOTOR: slot=5 motor=ON  (waitforC0D8=0->1) cyareg[1]=%0d t=%0t", cyareg[1], $time);
        if (!waitforC0D8 && prev_waitforC0D8)
            $display("VSIM_MOTOR: slot=5 motor=OFF (waitforC0D8=1->0) cyareg[1]=%0d t=%0t", cyareg[1], $time);
        if (waitforC0E8 && !prev_waitforC0E8)
            $display("VSIM_MOTOR: slot=6 motor=ON  (waitforC0E8=0->1) cyareg[2]=%0d t=%0t", cyareg[2], $time);
        if (!waitforC0E8 && prev_waitforC0E8)
            $display("VSIM_MOTOR: slot=6 motor=OFF (waitforC0E8=1->0) cyareg[2]=%0d t=%0t", cyareg[2], $time);
        if (waitforC0F8 && !prev_waitforC0F8)
            $display("VSIM_MOTOR: slot=7 motor=ON  (waitforC0F8=0->1) cyareg[3]=%0d t=%0t", cyareg[3], $time);
        if (!waitforC0F8 && prev_waitforC0F8)
            $display("VSIM_MOTOR: slot=7 motor=OFF (waitforC0F8=1->0) cyareg[3]=%0d t=%0t", cyareg[3], $time);
`endif
        prev_waitforC0C8 <= waitforC0C8;
        prev_waitforC0D8 <= waitforC0D8;
        prev_waitforC0E8 <= waitforC0E8;
        prev_waitforC0F8 <= waitforC0F8;
`endif
    end
end

always @(posedge clk_14M) begin
    if (reset) begin
        // Reset all counters and states
        clk_14M_counter <= 4'd0;
        ph0_counter <= 4'd0;
        ph2_counter <= 4'd0;
        refresh_counter <= 4'd0;
        cycle_is_refresh <= 1'b0;
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
        ph2_gap_count <= 4'd0;
        sync_aligned <= 1'b0;
`ifdef SIMULATION
        prev_slow <= 1'b0;
        prev_slowMem <= 1'b0;
        slow_ph2_cnt <= 32'd0;
        fast_ph2_cnt <= 32'd0;
        slow_14m_cycles <= 32'd0;
        fast_14m_cycles <= 32'd0;
        last_event <= 4'd0;
        iwm_slow_log_count <= 16'd0;
`endif
        
        // Reset pipeline registers (duplicate for safety)
        ph0_counter_prev <= 4'd0;
        ph0_en_prev <= 1'b0;
        ph0_state_prev <= 1'b0;
    end else begin
        // --- Refactored Logic ---
        slow <= slow_request;

        // Register write enable to avoid timing races
        we_reg <= we;

        // 4. Determine slowMem (only when bus cycle is valid)
        // During internal CPU cycles (VPA=VDA=0), address bus is invalid;
        // internal cycles are always fast (no memory access occurring).
        slowMem <= 1'b0;
        if ( valid && (
             (bank == 8'hE0 || bank == 8'hE1) ||
             ( (bank == 8'h00 || bank == 8'h01) && addr[15:8] == 8'hC0 &&
               !(
                 (addr == 16'hC02D && !we_reg) ||   // Slot ROM Select: read-fast, write-slow
                 (addr == 16'hC035) ||               // Shadow register: always fast
                 (addr == 16'hC036) ||               // Speed register: always fast
                 (addr == 16'hC037) ||               // DMA register: always fast
                 (addr == 16'hC068 && !we_reg) ||    // State register: read-fast, write-slow
                 (addr >= 16'hC071 && addr <= 16'hC07F)  // Interrupt ROM: always fast
               )
             ) ||
             (we_reg && (bank == 8'h00 || bank == 8'h01) &&
                (
                    // Shadow bits are "inhibit" flags: bit=0 means shadow ENABLED (slow access)
                    // bit=1 means shadow DISABLED (fast access). Use inverted bits for slowMem.
                    (addr >= 16'h0400 && addr <= 16'h07FF && ~shadow[0]) ||                              // Text 1
                    (addr >= 16'h0800 && addr <= 16'h0BFF && ~shadow[5]) ||                              // Text 2
                    (addr >= 16'h2000 && addr <= 16'h3FFF && ~shadow[1] && !(bank == 8'h01 && shadow[4])) || // HiRes 1
                    (addr >= 16'h4000 && addr <= 16'h5FFF && ~shadow[2] && !(bank == 8'h01 && shadow[4])) || // HiRes 2
                    (addr >= 16'h2000 && addr <= 16'h9FFF && bank == 8'h01 && ~shadow[3])                // SHR (bank 01)
                )
             )
           ))
        begin
            slowMem <= 1;
`ifdef DEBUG_SLOWMEM
            if (bank == 8'hE0 || bank == 8'hE1)
                $display("SLOWMEM: bank_E0E1 bank=%02x addr=%04x t=%0t", bank, addr, $time);
            else if ((bank == 8'h00 || bank == 8'h01) && addr[15:12] == 4'hC)
                $display("SLOWMEM: IO_space bank=%02x addr=%04x t=%0t", bank, addr, $time);
            else if (we_reg)
                $display("SLOWMEM: shadow_wr bank=%02x addr=%04x shadow=%02x t=%0t", bank, addr, shadow, $time);
`endif
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

	if (slow==1'b1) begin
		// Pure slow mode (C036[7]=0): every cycle runs at PHI0 rate (1.023 MHz)
		// Fire ph2_en on every PHI0 boundary.
		sync_aligned <= 1'b0;  // Keep clean for fast+sync transitions
		if (ph0_counter_next == 4'd0) begin
			ph2_en <= 1'b1;
			ph2_counter <= 4'd0;
			ph2_sync_pulse <= 1'b1;
			refresh_counter <= 4'd0;
			cycle_is_refresh <= 1'b0;
		end else begin
			ph2_en <= 1'b0;
			ph2_counter <= 4'd0;
			ph2_sync_pulse <= 1'b0;
		end
	end else if (slowMem==1'b1) begin
		// Sync cycle per krue FPI doc: extend PH2 to overlap one full PH0 cycle.
		// Total cycle = 14-27 ticks (2 low + 12-25 high).
		// Fire ph2_en at first PH0 falling edge where total cycle >= 14 ticks,
		// ensuring one complete PH0 period is contained within PH2 high.
		// ph2_counter tracks elapsed ticks since cycle start (inherited from
		// fast path, keeps counting through sync).
		sync_aligned <= 1'b0;
		if (ph2_counter < 4'd15)
			ph2_counter <= ph2_counter + 4'd1;

		if (ph0_counter_next == 4'd0 && ph2_counter >= 4'd13) begin
			ph2_en <= 1'b1;
			ph2_counter <= 4'd0;
			ph2_sync_pulse <= 1'b1;
			refresh_counter <= 4'd0;
			cycle_is_refresh <= 1'b0;
		end else begin
			ph2_en <= 1'b0;
			ph2_sync_pulse <= 1'b0;
		end
	end else begin
        // Fast mode with RAM refresh penalty:
        // Every 9th fast RAM cycle takes 10 ticks instead of 5.
        // ROM access hides refresh (stays at full 2.8636 MHz).
        sync_aligned <= 1'b0;  // Ensure clean state when entering sync
        ph2_counter <= ph2_counter + 1'b1;

        if (cycle_is_refresh) begin
            // Refresh cycle: 10 ticks
            if (ph2_counter >= 4'd9) begin
                ph2_counter <= 4'd0;
                ph2_en <= 1'b1;
                cycle_is_refresh <= 1'b0;
                refresh_counter <= 4'd0;
            end else begin
                ph2_en <= 1'b0;
            end
        end else begin
            // Normal fast cycle: 5 ticks
            if (ph2_counter >= 4'd4) begin
                ph2_counter <= 4'd0;
                ph2_en <= 1'b1;
                // Decide next cycle:
                if (is_rom_access) begin
                    refresh_counter <= 4'd0;    // ROM hides refresh
                    cycle_is_refresh <= 1'b0;
                end else if (refresh_counter >= 4'd8) begin
                    cycle_is_refresh <= 1'b1;   // Next is refresh (10-tick)
                    refresh_counter <= 4'd0;
                end else begin
                    refresh_counter <= refresh_counter + 4'd1;
                    cycle_is_refresh <= 1'b0;
                end
            end else begin
                ph2_en <= 1'b0;
            end
        end
        ph2_sync_pulse <= 1'b0;
    end
        
`ifdef SIMULATION
        if ((slow != prev_slow) || (slowMem != prev_slowMem)) begin
`ifdef DEBUG_CLKDIV
            // Match MAME format for easy comparison
            $display("VSIM_SPEED: %s -> %s (cyareg=%02x cyareg7=%0d motors=%04b wC0C8=%0d wC0D8=%0d wC0E8=%0d wC0F8=%0d) t=%0t",
                     prev_slow ? "SLOW" : "FAST",
                     slow ? "SLOW" : "FAST",
                     cyareg, cyareg[7],
                     {waitforC0F8, waitforC0E8, waitforC0D8, waitforC0C8},
                     waitforC0C8, waitforC0D8, waitforC0E8, waitforC0F8, $time);
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

        if (ph2_en && io_bank && addr == 16'hC0EC && iwm_slow_log_count < 16'd5000) begin
            $display("CLKDIV_IWM_SLOW: addr=%04x bank=%02x IO=%0d we=%0d slow=%0d slowMem=%0d slow_req=%0d cyareg=%02x slot_gate=%01x wC0C8=%0d wC0D8=%0d wC0E8=%0d wC0F8=%0d",
                     addr, bank, IO, we_reg, slow, slowMem, slow_request, cyareg, cyareg[3:0],
                     waitforC0C8, waitforC0D8, waitforC0E8, waitforC0F8);
            iwm_slow_log_count <= iwm_slow_log_count + 1'd1;
        end
`endif
    end
end


endmodule
