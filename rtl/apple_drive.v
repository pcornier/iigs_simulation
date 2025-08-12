//
// apple_drive.v: A generic module for Apple II / IIGS disk drives.
//
// **REVISION 2**
// - Added FAST_MODE input to select data rate.
// - Data rate timing logic is now implemented in the read/write process,
//   based on the IWM's specified 32µs/16µs per nibble data rate.
//
module apple_drive(
    // Configuration
    IS_35_INCH, FAST_MODE,
    // Global Clocks and Signals
    CLK_14M, Q3, PH0, RESET,
    // Status and Data Bus
    DISK_READY, D_IN, D_OUT,
    // Control Lines from IWM
    DISK_ACTIVE, MOTOR_PHASE, WRITE_MODE, READ_DISK, WRITE_REG, READ_STROBE,
    // Track Memory Interface
    TRACK, TRACK_ADDR, TRACK_DI, TRACK_DO, TRACK_WE, TRACK_BUSY
);
    // --- I/O Port Declarations ---
    input           IS_35_INCH;
    input           FAST_MODE;      // New input for speed control
    input           CLK_14M;
    input           Q3;         // 2MHz clock for timing
    input           PH0;
    input           RESET;
    input           DISK_READY;
    input [7:0]     D_IN;
    output [7:0]    D_OUT;
    input           DISK_ACTIVE;
    input [3:0]     MOTOR_PHASE;
    input           WRITE_MODE;
    input           READ_DISK;
    input           WRITE_REG;
    input           READ_STROBE;
    output [6:0]    TRACK;
    output [12:0]   TRACK_ADDR;
    output [7:0]    TRACK_DI;
    input [7:0]     TRACK_DO;
    output          TRACK_WE;
    input           TRACK_BUSY;

    // --- Internal Registers ---
    reg             TRACK_WE;
    reg             Q3_D;
    reg [8:0]       phase;
    reg [12:0]      track_byte_addr;
    reg [7:0]       data_reg;
    reg             reset_data_reg;
`ifdef SIMULATION
    reg [31:0]      q3_edge_counter;
    reg [31:0]      data_update_counter;
    reg [7:0]       last_data_output;
    reg [31:0]      cycles_since_strobe;
`endif

    // --- Drive Geometry and Timing Parameters ---
    localparam MAX_PHASE_525 = 139; // 35 tracks * 4 steps/track - 1
    localparam MAX_PHASE_35  = 319; // 80 tracks * 4 steps/track - 1
    // Data rate: 1 nibble per 32µs (slow) or 16µs (fast)
    // 1 byte = 64µs (slow) or 32µs (fast)
    // With a 2MHz clock (500ns period), we need 128 cycles for slow and 64 for fast.
    localparam SLOW_BYTE_PERIOD = 8'd128;
    localparam FAST_BYTE_PERIOD = 8'd64;

    wire [9:0] max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    wire [7:0] byte_period = FAST_MODE ? FAST_BYTE_PERIOD[7:0] : SLOW_BYTE_PERIOD[7:0];

    // Head Stepper Motor Logic (unchanged)
    always @(posedge CLK_14M or posedge RESET) begin
        // ... (this logic is identical to the previous version) ...
        integer phase_change;
        integer new_phase;
        reg [3:0] rel_phase;
        if (RESET) begin
            phase <= 0;
        end else if (DISK_ACTIVE) begin
            phase_change = 0;
            new_phase = phase;
            rel_phase = MOTOR_PHASE;
            case (phase[2:1])
               2'b00: rel_phase = {rel_phase[1:0], rel_phase[3:2]};
               2'b01: rel_phase = {rel_phase[2:0], rel_phase[3]};
               2'b10: ;
               2'b11: rel_phase = {rel_phase[0], rel_phase[3:1]};
               default: ;
            endcase
            if (phase[0] == 1'b1) case (rel_phase)
                4'b0001: phase_change = -3; 4'b0010: phase_change = -1;
                4'b0011: phase_change = -2; 4'b0100: phase_change = 1;
                4'b0101: phase_change = -1; 4'b0110: phase_change = 0;
                4'b0111: phase_change = -1; 4'b1000: phase_change = 3;
                4'b1001: phase_change = 0;  4'b1010: phase_change = 1;
                4'b1011: phase_change = -3;
                default: phase_change = 0;
            endcase else case (rel_phase)
                4'b0001: phase_change = -2; 4'b0011: phase_change = -1;
                4'b0100: phase_change = 2;  4'b0110: phase_change = 1;
                4'b1001: phase_change = 1;  4'b1010: phase_change = 2;
                4'b1011: phase_change = -2;
                default: phase_change = 0;
            endcase
            new_phase = phase + phase_change;
            if (new_phase < 0) phase <= 0;
            else if (new_phase > max_phase) phase <= max_phase;
            else phase <= new_phase;
        end
    end

    assign TRACK = phase[8:2];

    // Read/Write logic with corrected timing
    always @(posedge CLK_14M or posedge RESET) begin
        reg [7:0] byte_delay;
        reg        disk_ready_d;
        reg        disk_active_d;
        reg [15:0] sample_count;
        reg        track_busy_d;
        if (RESET) begin
            track_byte_addr <= 13'b0;
            byte_delay <= 8'd128;  // Initialize to proper delay (SLOW_BYTE_PERIOD)
            reset_data_reg <= 1'b0;
            data_reg <= 8'h00;
            disk_ready_d <= 1'b0;
            disk_active_d <= 1'b0;
            sample_count <= 16'd0;
            track_busy_d <= 1'b0;
`ifdef SIMULATION
            q3_edge_counter <= 0;
            data_update_counter <= 0;
            last_data_output <= 8'h00;
            cycles_since_strobe <= 0;
`endif
        end else begin
            TRACK_WE <= 1'b0;
            Q3_D <= Q3;
`ifdef SIMULATION
            // Monitor D_OUT changes
            if (data_reg != last_data_output && sample_count < 16'd50) begin
                $display("DRIVE%0s: D_OUT changed %02h -> %02h (data_reg updated)", IS_35_INCH?"(3.5)":"(5.25)", last_data_output, data_reg);
            end
            last_data_output <= data_reg;
`endif
            if (DISK_READY != disk_ready_d) begin
`ifdef SIMULATION
                $display("DRIVE%0s: DISK_READY %0d -> %0d", IS_35_INCH?"(3.5)":"(5.25)", disk_ready_d, DISK_READY);
`endif
                disk_ready_d <= DISK_READY;
            end
            if (DISK_ACTIVE != disk_active_d) begin
`ifdef SIMULATION
                $display("DRIVE%0s: DISK_ACTIVE %0d -> %0d (phase=%0d)", IS_35_INCH?"(3.5)":"(5.25)", disk_active_d, DISK_ACTIVE, phase);
`endif
                disk_active_d <= DISK_ACTIVE;
                sample_count <= 16'd0;
            end
            if (TRACK_BUSY != track_busy_d) begin
`ifdef SIMULATION
                $display("DRIVE%0s: TRACK_BUSY %0d -> %0d", IS_35_INCH?"(3.5)":"(5.25)", track_busy_d, TRACK_BUSY);
`endif
                track_busy_d <= TRACK_BUSY;
            end
            // For reads: advance on Q3 clock like reference implementation. For writes: on Q3 tick.
`ifdef SIMULATION
            if (Q3 && ~Q3_D && DISK_READY && DISK_ACTIVE && sample_count < 16'd20) begin
                $display("DRIVE%0s: Q3 tick (ready=%0d active=%0d busy=%0d delay=%0d)", IS_35_INCH?"(3.5)":"(5.25)", DISK_READY, DISK_ACTIVE, TRACK_BUSY, byte_delay);
            end
            // Track READ_STROBE activity  
            if (READ_STROBE && (WRITE_MODE == 1'b0)) begin
                cycles_since_strobe <= 0;  // Reset counter when strobe received
                if (sample_count < 16'd20) begin
                    $display("DRIVE%0s: READ_STROBE received (ready=%0d active=%0d busy=%0d data_reg=%02h addr=%04h)", 
                             IS_35_INCH?"(3.5)":"(5.25)", DISK_READY, DISK_ACTIVE, TRACK_BUSY, data_reg, track_byte_addr);
                end
                // Enhanced debugging: check why advancement might fail
                if (data_update_counter >= 360) begin
                    $display("DRIVE%0s: READ_STROBE conditions: STROBE=%0d WRITE_MODE=%0d READY=%0d ACTIVE=%0d ~BUSY=%0d (count=%0d)", 
                             IS_35_INCH?"(3.5)":"(5.25)", READ_STROBE, WRITE_MODE, DISK_READY, DISK_ACTIVE, ~TRACK_BUSY, data_update_counter);
                end
            end else if (DISK_ACTIVE && data_update_counter >= 360) begin
                cycles_since_strobe <= cycles_since_strobe + 1;
                // Report when READ_STROBE stops coming for extended periods
                if (cycles_since_strobe == 32'd1000) begin
                    $display("DRIVE%0s: WARNING - No READ_STROBE for 1000 cycles after count %0d", 
                             IS_35_INCH?"(3.5)":"(5.25)", data_update_counter);
                end else if (cycles_since_strobe == 32'd10000) begin
                    $display("DRIVE%0s: ERROR - No READ_STROBE for 10000 cycles after count %0d", 
                             IS_35_INCH?"(3.5)":"(5.25)", data_update_counter);
                end
            end
`endif
            // Primary timing: advance on CPU reads via READ_STROBE for responsive disk access
            // Secondary timing: Q3 clock provides maximum rate limit and timing fallback
            
`ifdef SIMULATION
            // Debug why advancement might be failing after count 360
            if (READ_STROBE && (WRITE_MODE == 1'b0) && data_update_counter >= 360) begin
                if (!(DISK_READY && DISK_ACTIVE && ~TRACK_BUSY)) begin
                    $display("DRIVE%0s: CPU READ BLOCKED - conditions failed: READY=%0d ACTIVE=%0d ~BUSY=%0d (count=%0d)", 
                             IS_35_INCH?"(3.5)":"(5.25)", DISK_READY, DISK_ACTIVE, ~TRACK_BUSY, data_update_counter);
                end
            end
`endif
            
            // CPU-driven advancement: advance immediately when CPU reads the data register
            if (READ_STROBE && (WRITE_MODE == 1'b0) && DISK_READY && DISK_ACTIVE && ~TRACK_BUSY) begin
`ifdef SIMULATION
                $display("DRIVE%0s: CPU READ detected - advancing track immediately", IS_35_INCH?"(3.5)":"(5.25)");
`endif
                // Handle data clearing first if needed
                if (reset_data_reg) begin
                    data_reg <= 8'b0;
                    reset_data_reg <= 1'b0;
`ifdef SIMULATION
                    $display("DRIVE%0s: DATA_REG cleared to 00 (was %02h) [CPU-driven]", IS_35_INCH?"(3.5)":"(5.25)", data_reg);
`endif
                end else begin
                    // Load new data and advance
                    data_reg <= TRACK_DO;
                    // Advance track address
                    if (track_byte_addr == 13'h19FF) track_byte_addr <= 13'b0;
                    else track_byte_addr <= track_byte_addr + 1;
`ifdef SIMULATION
                    data_update_counter <= data_update_counter + 1;
                    $display("DRIVE%0s: CPU_READ_UPDATE #%0d - data_reg<=%02h track_byte_addr<=%04h (advancing to %04h)", IS_35_INCH?"(3.5)":"(5.25)", 
                             data_update_counter + 1, TRACK_DO, track_byte_addr, 
                             (track_byte_addr == 13'h19FF) ? 13'b0 : track_byte_addr + 1);
                    // Check for potential counter overflow
                    if (data_update_counter == 32'hFFFFFFFE) begin
                        $display("DRIVE%0s: WARNING - data_update_counter about to overflow!", IS_35_INCH?"(3.5)":"(5.25)");
                    end
`endif
                end
                // Reset byte_delay to provide maximum rate limiting
                byte_delay <= byte_period;
            end
            // OLD Q3 timing disabled for now - CPU-driven timing should be sufficient
            else if (Q3 && ~Q3_D && DISK_READY && DISK_ACTIVE && ~TRACK_BUSY && 1'b0) begin  // disabled
                byte_delay <= byte_delay - 1;
`ifdef SIMULATION
                q3_edge_counter <= q3_edge_counter + 1;
                if (sample_count < 16'd20) begin
                    $display("DRIVE%0s: Q3 edge #%0d - byte_delay %0d -> %0d (period=%0d) active=%0d ready=%0d busy=%0d", 
                             IS_35_INCH?"(3.5)":"(5.25)", q3_edge_counter + 1, byte_delay, 
                             (byte_delay > 0) ? byte_delay-1 : byte_period, 
                             byte_period, DISK_ACTIVE, DISK_READY, TRACK_BUSY);
                end
`endif
                if (byte_delay > 0) begin
                    // Still counting down
`ifdef SIMULATION
                    if (sample_count < 16'd10) begin
                        $display("DRIVE%0s: counting down byte_delay=%0d", IS_35_INCH?"(3.5)":"(5.25)", byte_delay-1);
                    end
`endif
                end else begin
                    // Timer expired, perform a byte operation and reset timer
                    byte_delay <= byte_period;
`ifdef SIMULATION
                    if (sample_count < 16'd10) begin
                        $display("DRIVE%0s: byte_delay RESET to %0d (was 0)", IS_35_INCH?"(3.5)":"(5.25)", byte_period);
                    end
`endif

                    if (WRITE_MODE == 1'b0) begin // Read Mode
                        // Handle data_reg clearing FIRST (like reference implementation)
                        if (reset_data_reg) begin
                            data_reg <= 8'b0;
                            reset_data_reg <= 1'b0;
`ifdef SIMULATION
                            $display("DRIVE%0s: DATA_REG cleared to 00 (was %02h) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", data_reg, sample_count);
`endif
                        end
                        
                        // Load new data when byte_delay expires 
                        if (byte_delay == 0) begin
                            byte_delay <= byte_period;  // Reset the timer
`ifdef SIMULATION
                            $display("DRIVE%0s: BYTE_DELAY EXPIRED - loading new data and advancing", IS_35_INCH?"(3.5)":"(5.25)");
                            $display("DRIVE%0s: BEFORE - data_reg=%02h track_byte_addr=%04h TRACK_DO=%02h", IS_35_INCH?"(3.5)":"(5.25)", data_reg, track_byte_addr, TRACK_DO);
`endif
                            data_reg <= TRACK_DO;
                            // Advance track address
                            if (track_byte_addr == 13'h19FF) track_byte_addr <= 13'b0;
                            else track_byte_addr <= track_byte_addr + 1;
`ifdef SIMULATION
                            data_update_counter <= data_update_counter + 1;
                            $display("DRIVE%0s: DATA_UPDATE #%0d - data_reg<=%02h track_byte_addr<=%04h (advancing to %04h) Q3_edge=#%0d", IS_35_INCH?"(3.5)":"(5.25)", 
                                     data_update_counter + 1, TRACK_DO, track_byte_addr, 
                                     (track_byte_addr == 13'h19FF) ? 13'b0 : track_byte_addr + 1, q3_edge_counter + 1);
                            if (sample_count < 16'd64 || (sample_count % 16'd100) == 0) begin
                                $display("DRIVE%0s RD: track=%0d addr=%04h data=%02h (from TRACK_DO) -> data_reg -> D_OUT [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", TRACK, track_byte_addr, TRACK_DO, sample_count);
                            end
`endif
`ifdef SIMULATION
                            if (sample_count < 16'd64) begin
                                sample_count <= sample_count + 1;
                            end
`endif
                        end
                        
                        // Request data clearing for next cycle if needed
                        if (READ_DISK && PH0) begin
                            reset_data_reg <= 1'b1;
`ifdef SIMULATION
                            $display("DRIVE%0s: DATA_REG clear requested (read_disk=%0d PH0=%0d) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", READ_DISK, PH0, sample_count);
`endif
                        end
                    end else begin // Write Mode
                        if (WRITE_REG) begin
                            data_reg <= D_IN;
                        end
                        // A real write happens on the sync signal
                        if (READ_DISK && PH0) begin
                            TRACK_WE <= ~TRACK_BUSY;
                        end
                    end
                    // Advance track address after every operation
                    if (track_byte_addr == 13'h19FF) track_byte_addr <= 13'b0;
                    else track_byte_addr <= track_byte_addr + 1;
`ifdef SIMULATION
                    if (sample_count < 16'd20) begin
                        $display("DRIVE%0s: ADVANCE addr %04h -> %04h (TRACK_ADDR will be %04h)", IS_35_INCH?"(3.5)":"(5.25)", track_byte_addr, 
                                 (track_byte_addr == 13'h19FF) ? 13'b0 : track_byte_addr + 1,
                                 (track_byte_addr == 13'h19FF) ? 13'b0 : track_byte_addr + 1);
                    end
`endif
                end
                
                // OLD Latch clearing logic (from reference implementation) - COMMENTED OUT, now handled in read mode
                /*if (reset_data_reg) begin
                    data_reg <= 8'b0;
                    reset_data_reg <= 1'b0;
`ifdef SIMULATION
                    $display("DRIVE%0s: DATA_REG cleared to 00 (was %02h) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", data_reg, sample_count);
`endif
                end
                if (READ_DISK && PH0) begin
                    reset_data_reg <= 1'b1;
`ifdef SIMULATION
                    $display("DRIVE%0s: DATA_REG clear requested (read_disk=%0d PH0=%0d) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", READ_DISK, PH0, sample_count);
`endif
                end*/
            end
        end
    end

    assign D_OUT = data_reg;
    assign TRACK_ADDR = track_byte_addr;
    assign TRACK_DI = data_reg;

endmodule
