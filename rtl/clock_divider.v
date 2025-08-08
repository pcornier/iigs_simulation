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
    output reg         slow             // Slow mode indicator
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
	waitforC0C8<=1'b0;
	waitforC0D8<=1'b0;
	waitforC0E8<=1'b0;
	waitforC0F8<=1'b0;
        
        // Reset cycle control
        ph2_cycle_length <= 5'd5;  // Default to fast cycle
        sync_requested <= 1'b0;
        refresh_requested <= 1'b0;
    end else begin

	//
	// logic to determine if we should be in slow mode
	//
	if (cyareg[7] == 1'b0) begin
		slow <= 1;
	end else begin
		// Check for slot-specific slow mode triggers (can be multiple slots enabled)
		if (cyareg[0] == 1'b1 && IO && addr == 16'hC0C9) begin
			slow <= 1;
			waitforC0C8 <= 1;
		end
		if (cyareg[1] == 1'b1 && IO && addr == 16'hC0D9) begin
			slow <= 1;
			waitforC0D8 <= 1;
		end
		if (cyareg[2] == 1'b1 && IO && addr == 16'hC0E9) begin
			slow <= 1;
			waitforC0E8 <= 1;
		end
		if (cyareg[3] == 1'b1 && IO && addr == 16'hC0F9) begin
			slow <= 1;
			waitforC0F8 <= 1;
		end
		
		// Check for return to fast mode
		if (waitforC0C8 && IO && addr == 16'hC0C8) begin
			slow <= 0;
			waitforC0C8 <= 0;
		end
		if (waitforC0D8 && IO && addr == 16'hC0D8) begin
			slow <= 0;
			waitforC0D8 <= 0;
		end
		if (waitforC0E8 && IO && addr == 16'hC0E8) begin
			slow <= 0;
			waitforC0E8 <= 0;
		end
		if (waitforC0F8 && IO && addr == 16'hC0F8) begin
			slow <= 0;
			waitforC0F8 <= 0;
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
	if (slow==1'b1) begin
		if (ph2_counter==4'd4 && ph0_en == 1'b1)
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
		end
	end else begin	

        // PH2 generation (simplified 5 clock cycle)
        ph2_counter <= ph2_counter + 1'b1;
        if (ph2_counter == 4'd4) begin
            ph2_counter <= 4'd0;
        end
        
        // PH2 enable generation (5 clock cycles long)
        ph2_en <= (ph2_counter == 4'd0);
end
        
    end
end


endmodule
