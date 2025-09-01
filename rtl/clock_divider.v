module clock_divider (
    input  wire        clk_14M,        // 14.318 MHz input clock
    input  wire        reset,          // Active high reset
    input  wire [7:0]  cyareg,          // Active high reset
    input wire [7:0] bank,             // CPU BANK
    input wire [7:0] shadow,           // SHADOW REG
    input wire [15:0] addr,            // CPU ADDR
    input wire IO,

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
    output reg         slowMem             // Slow mode indicator
);

// Clock divider counters
reg [3:0]  clk_14M_counter;    // 14M cycle counter
reg [3:0]  ph0_counter;        // PH0 cycle counter (0-13 for full cycle)
reg [3:0]  ph2_counter;        // PH2 cycle counter
reg [2:0]  refresh_counter;    // Refresh cycle counter (every 9th cycle)
reg        clk_7M_div;         // 7M divider flip-flop

// PH2 cycle state machine
localparam CYCLE_FAST         = 4'd0;  // Normal fast cycle (5 ticks: 2 low, 3 high)
localparam CYCLE_REFRESH      = 4'd1;  // Fast refresh cycle (10 ticks: 2 low, 8 high)
localparam CYCLE_SYNC         = 4'd2;  // Sync cycle (14-27 ticks: 2 low, 12-25 high)
localparam CYCLE_SYNC_STRETCH = 4'd3;  // Sync stretch cycle (16-29 ticks: 2 low, 14-27 high)

reg [4:0] ph2_cycle_length;    // Current PH2 cycle length
reg       sync_requested;      // Flag to request sync cycle
reg       refresh_requested;   // Flag to request refresh cycle



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
        // Reset all counters and states
        clk_14M_counter <= 4'd0;
        ph0_counter <= 4'd0;
        ph2_counter <= 4'd0;
        refresh_counter <= 3'd0;
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
	waitforC0C8<=1'b0;
	waitforC0D8<=1'b0;
	waitforC0E8<=1'b0;
	waitforC0F8<=1'b0;
        waitforC041<= 1'b0;
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
    end else begin
        slowMem <= 1'b0;


	//
	// logic to determine if we should be in slow mode
	//
	if (cyareg[7] == 1'b0) begin
		slow <= 1;
	end else begin
		// Default to fast mode when CYAREG[7]=1 (unless overridden by slot conditions)
		slow <= 0;
		
		// Check for slot-specific slow mode triggers (can be multiple slots enabled)
        if (cyareg[0] == 1'b1 && IO && addr == 16'hC0C9) begin
            slow <= 1;
            waitforC0C8 <= 1;
`ifdef SIMULATION
            last_event <= 4'd1;
            $display("CLKDIV: slow enter due C0C9 (slot4) cyareg=%02h bank=%02h addr=%04h IO=%0d t=%0t", cyareg, bank, addr, IO, $time);
`endif
        end
        if (cyareg[1] == 1'b1 && IO && addr == 16'hC0D9) begin
            slow <= 1;
            waitforC0D8 <= 1;
`ifdef SIMULATION
            last_event <= 4'd2;
            $display("CLKDIV: slow enter due C0D9 (slot5) cyareg=%02h bank=%02h addr=%04h IO=%0d t=%0t", cyareg, bank, addr, IO, $time);
`endif
        end
        if (cyareg[2] == 1'b1 && IO && addr == 16'hC0E9) begin
            slow <= 1;
            waitforC0E8 <= 1;
`ifdef SIMULATION
            last_event <= 4'd3;
            $display("CLKDIV: slow enter due C0E9 (slot6) cyareg=%02h bank=%02h addr=%04h IO=%0d t=%0t", cyareg, bank, addr, IO, $time);
`endif
        end
        if (cyareg[3] == 1'b1 && IO && addr == 16'hC0F9) begin
            slow <= 1;
            waitforC0F8 <= 1;
`ifdef SIMULATION
            last_event <= 4'd4;
            $display("CLKDIV: slow enter due C0F9 (slot7) cyareg=%02h bank=%02h addr=%04h IO=%0d t=%0t", cyareg, bank, addr, IO, $time);
`endif
        end
        if (IO && addr == 16'hC042) begin
            slow <= 1;
            waitforC041<= 1;
`ifdef SIMULATION
            last_event <= 4'd5;
            $display("CLKDIV: slow enter due C042 (keyboard) bank=%02h addr=%04h IO=%0d t=%0t", bank, addr, IO, $time);
`endif
        end
		
		// Keep slow mode active if any waitfor flags are set
		if (waitforC0C8 || waitforC0D8 || waitforC0E8 || waitforC0F8 || waitforC041) begin
			slow <= 1;
		end
		
		// Check for return to fast mode
        if (waitforC0C8 && IO && addr == 16'hC0C8) begin
            waitforC0C8 <= 0;
`ifdef SIMULATION
            $display("CLKDIV: slow exit via C0C8 (slot4) t=%0t", $time);
`endif
        end
        if (waitforC0D8 && IO && addr == 16'hC0D8) begin
            waitforC0D8 <= 0;
`ifdef SIMULATION
            $display("CLKDIV: slow exit via C0D8 (slot5) t=%0t", $time);
`endif
        end
        if (waitforC0E8 && IO && addr == 16'hC0E8) begin
            waitforC0E8 <= 0;
`ifdef SIMULATION
            $display("CLKDIV: slow exit via C0E8 (slot6) t=%0t", $time);
`endif
        end
        if (waitforC0F8 && IO && addr == 16'hC0F8) begin
            waitforC0F8 <= 0;
`ifdef SIMULATION
            $display("CLKDIV: slow exit via C0F8 (slot7) t=%0t", $time);
`endif
        end
        if (waitforC041 && IO && addr == 16'hC041) begin
            waitforC041<= 0;

`ifdef SIMULATION
            $display("CLKDIV: slow exit via C041 (keyboard) t=%0t", $time);
`endif
        end
        

	
	   
    // --- 1. Entire banks $E0 and $E1: always slow ---
        if ((bank == 8'hE0 || bank == 8'hE1) ||

    // --- 2. I/O space $C000-$CFFF in bank $00 or $01 ---
    ((bank == 8'h00 || bank == 8'h01) && addr[15:12] == 4'hC) ||

    // --- 3. Bank $00: $E000-$FFFF (ROM/softswitch region) ---
    (bank == 8'h00 && addr[15:13] == 3'b111) ||

    // --- 4. Slot ROM space: banks $C1-$CF, $C8-$CF
    //     (Accesses to slot firmware are slow)
    ((bank >= 8'hC1 && bank <= 8'hCF)) ||

    // --- 5. Peripheral slow mapping (shadowed video memory) ---
    // Bank $00/$01: $0400-$07FF (text page 1)
    ((bank == 8'h00 || bank == 8'h01) &&
        (addr >= 16'h0400 && addr <= 16'h07FF)) ||

    // Bank $00/$01: $0800-$0BFF (text page 2 / hi-res page 1)
    ((bank == 8'h00 || bank == 8'h01) &&
        (addr >= 16'h0800 && addr <= 16'h0BFF)) ||

    // Bank $00/$01: $2000-$3FFF (hi-res page 2)
    ((bank == 8'h00 || bank == 8'h01) &&
        (addr >= 16'h2000 && addr <= 16'h3FFF)) )
            begin
                slowMem<=1;
`ifdef SIMULATION
                if (!prev_slow && !prev_slowMem) begin
                    last_event <= 4'd6;
                    $display("CLKDIV: slowMem active (shadowed/slow region) bank=%02h addr=%04h t=%0t", bank, addr, $time);
                end
`endif
            end
        end

        // 14M is always enabled
        clk_14M_en <= 1'b1;
        
        // Increment master counter
        clk_14M_counter <= clk_14M_counter + 1'b1;
        
        // Generate 7M enable (every other 14M cycle)
        clk_7M_div <= ~clk_7M_div;
        clk_7M_en <= ~clk_7M_div;  // Enable on rising edge of 7M
        
        // PH0 generation (Apple II compatible 1MHz clock)
        // PH0 cycle: 7 ticks high, 7 ticks low (14 total = ~1MHz from 14MHz)
        ph0_counter <= ph0_counter + 1'b1;
        if (ph0_counter == 4'd13) begin
            ph0_counter <= 4'd0;
        end
        
        // PH0 state and enable generation
        if (ph0_counter < 4'd7) begin
            ph0_state <= 1'b0;  // PH0 low phase
            ph0_en <= (ph0_counter == 4'd0);  // Enable at start of low phase
        end else begin
            ph0_state <= 1'b1;  // PH0 high phase  
        //    ph0_en <= (ph0_counter == 4'd7); // Enable at start of high phase
        end
        
        // Q3 generation 
        q3_en <= (ph0_counter == 4'd0) || (ph0_counter == 4'd7);
      
	// If we are in slow -- we need to change the PH2 clock to be 1.024
	// Mhz, and sync it up with the PH0 clock
	//
	if (slow==1'b1 || slowMem==1'b1) begin
		// BUG - THIS MAKES PH2 one cycle after ph0_en
		//if (ph2_counter==4'd4 && ph0_en == 1'b1)
      if (ph2_counter==4'd4 && ph0_counter == 4'd0)		
		begin
			ph2_en <= 1'b1;
			ph2_counter <= 4'd0;
		end else if (ph2_counter==4'd4 && ph0_en == 1'b0)
		begin
			ph2_en <= 1'b0;
			// don't increment the counter, wait
		end else
		begin
			ph2_en <= 1'b0;
        		ph2_counter <= ph2_counter + 1'b1;
        		// Safety clamp to prevent counter from exceeding 4 in slow mode
        		if (ph2_counter >= 4'd4) begin
        		    ph2_counter <= 4'd4;  // Hold at waiting state
        		end
		end
	end else begin	

        // PH2 generation (simplified 5 clock cycle)
        ph2_counter <= ph2_counter + 1'b1;
        if (ph2_counter >= 4'd4) begin  // Fix: handle counter overflow from slow mode
            ph2_counter <= 4'd0;
        end
        
        // PH2 enable generation (5 clock cycles long)
        ph2_en <= (ph2_counter == 4'd0);
end
        
`ifdef SIMULATION
        // Accumulate simple stats about PH2 pulses while slow/fast
        if (ph2_en) begin
            if (slow || slowMem) slow_ph2_cnt <= slow_ph2_cnt + 1; else fast_ph2_cnt <= fast_ph2_cnt + 1;
        end
        if (slow || slowMem) slow_14m_cycles <= slow_14m_cycles + 1; else fast_14m_cycles <= fast_14m_cycles + 1;
        // Report transitions of slow/slowMem
        if ((slow != prev_slow) || (slowMem != prev_slowMem)) begin
            $display("CLKDIV: slow=%0d slowMem=%0d -> slow=%0d slowMem=%0d ph0_cnt=%0d ph2_cnt=%0d t=%0t", prev_slow, prev_slowMem, slow, slowMem, ph0_counter, ph2_counter, $time);
            if (!slow && !slowMem) begin
                // exiting slow state: dump mini-stats
                $display("CLKDIV: slow phase stats: ph2=%0d 14Mcy=%0d; fast so far: ph2=%0d 14Mcy=%0d (last_event=%0d)", slow_ph2_cnt, slow_14m_cycles, fast_ph2_cnt, fast_14m_cycles, last_event);
                slow_ph2_cnt <= 0;
                slow_14m_cycles <= 0;
                last_event <= 0;
            end
            prev_slow <= slow;
            prev_slowMem <= slowMem;
        end
`endif
    end
end


endmodule
