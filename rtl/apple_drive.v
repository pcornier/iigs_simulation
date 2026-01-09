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
    IS_35_INCH, FAST_MODE, DRIVE_ID,
    // Global Clocks and Signals
    CLK_14M, Q3, PH0, RESET,
    // Status and Data Bus
    DISK_READY, D_IN, D_OUT,
    // Control Lines from IWM
    DISK_ACTIVE, MOTOR_ON, MOTOR_PHASE, WRITE_MODE, READ_DISK, WRITE_REG, READ_STROBE, DATA_REG_READ,
    // Motor state output (for per-drive motor tracking)
    MOTOR_SPINNING,
    // Track Memory Interface
    TRACK, TRACK_ADDR, TRACK_DI, TRACK_DO, TRACK_WE, TRACK_BUSY
);
    // --- I/O Port Declarations ---
    input           IS_35_INCH;
    input           FAST_MODE;      // New input for speed control
    input [1:0]     DRIVE_ID;       // Drive instance identifier (1-4) for debug
    input           CLK_14M;
    input           Q3;         // 2MHz clock for timing
    input           PH0;
    input           RESET;
    input           DISK_READY;
    input [7:0]     D_IN;
    output [7:0]    D_OUT;
    input           DISK_ACTIVE;    // True when THIS drive is selected and motor on
    input           MOTOR_ON;       // True when motor is on (regardless of drive selection)
    input [3:0]     MOTOR_PHASE;
    input           WRITE_MODE;
    input           READ_DISK;
    input           WRITE_REG;
    input           READ_STROBE;
    input           DATA_REG_READ;   // Any data register read (Q6=Q7=0, any even address)
    output          MOTOR_SPINNING;  // Physical motor state for this drive
    output [6:0]    TRACK;
    output [13:0]   TRACK_ADDR;    // 14-bit for 3.5" drives (up to 10240 bytes)
    output [7:0]    TRACK_DI;
    input [7:0]     TRACK_DO;
    output          TRACK_WE;
    input           TRACK_BUSY;

    // --- Internal Registers ---
    reg             TRACK_WE;
    reg             Q3_D;
    reg [8:0]       phase;
    reg [13:0]      track_byte_addr;  // 14-bit for 3.5" drives
    reg [7:0]       data_reg;
    reg             reset_data_reg;
    // BRAM read latency compensation: track_byte_addr is one ahead of what we're outputting
    // When we first start or after address changes, we need to wait for BRAM to provide data
    reg             bram_data_valid;  // Set after BRAM has had time to respond to address
    // Data ready flag for CPU byte synchronization
    // SET when a new byte loads into data_reg (disk has delivered fresh data)
    // CLEARED on the SECOND read after byte arrival (not the first)
    // When clear, D_OUT bit 7 is cleared so CPU knows to wait for next byte
    reg             data_ready;
    reg             prev_read_strobe;  // Delayed READ_STROBE for proper clearing
    reg             prev_read_strobe2; // Extra delay for slow-mode CPU timing
    reg             prev_read_strobe3; // 3rd stage delay for reliable data latching
    // Tracks whether current byte has been read at least once
    // This is needed because in slow mode, a CPU read spans ~14 14MHz cycles.
    // We must NOT clear data_ready on the first read - only on subsequent reads.
    reg             byte_was_read;
    // Spindown inertia: disk keeps rotating for a while after MOTOR_ON goes low
    // This is critical for proper boot because the ROM scans multiple drives
    // and the disk must keep spinning while other drives are being probed.
    // Spindown time ~100ms at 14MHz = 1,400,000 cycles
    reg [20:0]      spindown_counter;  // 21 bits for up to 2M cycles
    reg             motor_spinning;     // True when disk is physically rotating
    // Spin-up delay counter: for 3.5" drives, wait before starting rotation
    reg [13:0]      spinup_counter;     // 14 bits for up to 16K cycles
    // Write pending flag: set when WRITE_REG fires, cleared after write completes
    // This prevents spurious writes when Q6=0, Q7=1 but no data was written
    reg             write_pending;
    // Byte timing counter - counts Q3 cycles between disk bytes
    // (moved to module level for new_byte_arriving wire access)
    reg [7:0]       byte_delay;
    // Timer to enforce minimum data_ready duration (prevent race condition clearing)
    reg [4:0]       data_ready_timer;
    // LATCH MODE TIMER (2025-12-22):
    // For 3.5" drives in latch mode, this timer clears bit 7 after ~14 clocks post-read.
    // This allows the ROM to detect new byte arrival even when consecutive bytes have
    // the same value (e.g., 0x96 at both taddr=0015 and taddr=0016).
    // Reference: MacPlus iwm.v line 289: readLatchClearTimer <= 4'hD (13 clocks)
    // At 14MHz, 24 clocks = ~1.7µs, similar to MacPlus 14 clocks at 8MHz = 1.75µs
    reg [5:0]       latch_clear_timer;  // 6 bits for up to 63 cycle timer
    // Strict byte consumption tracking for debug
    reg             byte_consumed;
    reg             prev_data_reg_read;  // Tracks DATA_REG_READ for edge detection
    reg             first_byte_loaded;
    reg             ever_loaded_byte;

    // Local tracking registers (moved to module level for Verilator compatibility)
    reg             disk_ready_d;
    reg             disk_active_d;
    reg             disk_active_latched;  // Latched DISK_ACTIVE at READ_STROBE rising edge
    reg [15:0]      sample_count;
    reg             track_busy_d;
`ifdef SIMULATION
    reg [31:0]      q3_edge_counter;
    reg [31:0]      data_update_counter;
    reg [7:0]       last_data_output;
    reg [31:0]      cycles_since_strobe;
    reg [31:0]      clear_count;  // Counter for data_ready CLEARs
    reg [31:0]      all_q3_edges;  // Counts ALL Q3 edges regardless of conditions
`endif

    // --- Drive Geometry and Timing Parameters ---
    localparam MAX_PHASE_525 = 139; // 35 tracks * 4 steps/track - 1
    localparam MAX_PHASE_35  = 319; // 80 tracks * 4 steps/track - 1
    // Data rate for 5.25" disks at 300 RPM:
    // Track = 6656 bytes, rotation = 200ms, so 30µs per byte
    // Q3 runs at ~2MHz (pulses at counter 0 and 7 in 14-cycle period = 7 CLK_14M per Q3)
    // Target: 30µs / 0.489µs = 61 Q3 cycles per byte
    // For 3.5" disks in fast mode (variable speed zones), halve the period.
    //
    // BUG FIX: Increased from 61 to 72 Q3 cycles to give the CPU more margin to catch
    // each byte. At 61 cycles, the IIgs ROM's prolog detection code (which processes
    // D5 AA before reading the next byte) sometimes misses the third byte (96 or AD)
    // because the disk rotates past it. Real Apple II timing had tolerances that
    // allowed for some variation. 72 cycles = ~17% slower rotation, within tolerance.
    localparam SLOW_BYTE_PERIOD = 8'd72;
    // 3.5" byte period: Balance between giving ROM enough time to process each byte
    // and delivering the next byte before the ROM times out.
    //
    // - Theoretical: 2µs/bit × 8 = 16µs = 32 Q3 cycles (224 14MHz cycles)
    // - ROM timeout: After reading a byte, the ROM expects the next byte within
    //   a certain number of cycles. If bit7 doesn't return to 1, ROM gives up.
    // - ROM processing: ROM needs time to read and process each byte.
    //
    // Testing (2026-01-04): ROM needs D5 AA 96 prolog, then address field, then data prolog.
    // After reading address epilogue (DE AA), ROM looks for data prolog (D5 AA AD).
    //
    // At 24 Q3 (~168 cycles), disk reaches taddr=0x00f (D9) but ROM times out before 0x010 (DE).
    // Try 20 Q3 (~140 cycles) for faster rotation to reach DE before ROM times out.
    // Trade-off: faster rotation risks missing bytes between prolog detection and reading.
    // BOOT FIX (2026-01-05): Use fastest possible byte rate for 3.5" drives.
    // The ROM polls in a tight loop expecting bytes every ~7 cycles.
    // At 2 Q3 cycles (~14 14MHz cycles), the ROM times out waiting for 96 after seeing AA.
    // Using 1 Q3 cycle (~7 14MHz cycles) lets the ROM see D5 AA 96 in sequence before timeout.
    // TODO: This is faster than real hardware - may need proper IWM handshaking instead.
    localparam FAST_BYTE_PERIOD = 8'd1;  // 1 Q3 cycle = ~7 14MHz cycles (fastest boot mode)
    // Spindown inertia time: ~100ms at 14MHz is enough time for ROM to scan other drives
    localparam SPINDOWN_TIME = 21'd1400000;
    // Spin-up delay for 3.5" drives: ~10000 cycles to allow ROM to complete initialization
    // before disk starts rotating. The ROM has a ~9000 cycle gap after initial probe reads
    // where it does other setup. If disk starts rotating immediately, it rotates past
    // the D5 AA 96 address prolog before ROM starts continuous reading.
    // 5.25" drives don't need this because they use slower rotation timing.
    localparam SPINUP_DELAY_35 = 14'd10000;  // ~700µs at 14MHz

    wire [9:0] max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    // 5.25" drives ALWAYS use slow mode (300 RPM, ~30µs/byte = 60-72 Q3 cycles)
    // 3.5" drives ALWAYS use fast mode (~400 RPM variable, ~15µs/byte = 31 Q3 cycles)
    // The IWM FAST_MODE bit affects CPU timing expectations, not disk rotation.
    // 3.5" drive motors are designed to deliver data at ~2MHz regardless of zone.
    wire [7:0] byte_period = IS_35_INCH ? FAST_BYTE_PERIOD[7:0] : SLOW_BYTE_PERIOD[7:0];

    // ROTATION FIX (2026-01-04): Use motor_spinning for BOTH drive types.
    // Previously tried to pause 3.5" rotation when DISK_ACTIVE went false, but this
    // caused the disk to stop mid-address-field when the ROM read from phase registers
    // or when eff_drive35 momentarily went false. The ROM would read D5 AA 96 + track
    // but then the disk would stop before reading sector/side/format/checksum.
    //
    // The byte_consumed logic now correctly handles sync detection - the ROM sees
    // bit7=0 between bytes and waits for the next byte to arrive. No need to pause
    // rotation during probe; the ROM simply won't find valid data on empty drives.
    //
    // BUG FIX (2026-01-05): For 3.5" drives, pause rotation when not reading data register.
    // The ROM does ~9000 cycles of processing after reading D5 AA 96. During this gap,
    // the disk rotates at FAST_BYTE_PERIOD=1 (every 7 cycles), advancing ~1280 bytes.
    // When the ROM returns to read track/sector/format/checksum, it's at the wrong
    // position and misses the address field data.
    //
    // On real hardware, bytes arrive every ~280 14MHz cycles, so the ROM has plenty
    // of time for processing between bytes. Our accelerated timing breaks this.
    //
    // Fix: For 3.5" drives, only rotate when DATA_REG_READ is high (ROM reading $C0EC).
    // DISK_ACTIVE stays high during processing gaps because ROM accesses other IWM regs.
    // DATA_REG_READ only goes high when actually reading the data register.
    // 5.25" drives continue to rotate continuously for compatibility.
    wire should_rotate = IS_35_INCH ? (motor_spinning && DATA_REG_READ) : motor_spinning;

    // BUG FIX: Detect when a new byte is arriving this cycle.
    // This is needed to prevent a race condition: if a READ_STROBE edge happens on
    // the same cycle as a new byte arrives, both `data_ready <= 1` (from byte arrival)
    // and `data_ready <= 0` (from READ_STROBE handler) would be scheduled. In Verilog,
    // the LAST non-blocking assignment wins, so we must ensure the SET comes after the CLEAR.
    // By checking this condition, we can skip the CLEAR when a new byte is arriving.
    wire new_byte_arriving = Q3 && ~Q3_D && DISK_READY && should_rotate && ~TRACK_BUSY && (byte_delay == 1);

    // BUG FIX (2026-01-04): Detect when a data register read is happening RIGHT NOW.
    // This is needed because byte_consumed uses non-blocking assignment, so D_OUT would
    // still see byte_consumed=0 during the clock cycle when byte_consumed <= 1 is scheduled.
    // By detecting the read COMBINATIONALLY, we can mask bit 7 immediately without waiting
    // for the register to update. This ensures the CPU sees bit 7 = 0 on the SAME read cycle.
    wire reading_data_now = DATA_REG_READ && !prev_data_reg_read && data_ready && !byte_consumed;

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
    assign MOTOR_SPINNING = motor_spinning;  // Expose internal motor state

`ifdef SIMULATION
    reg [8:0] prev_phase;
    always @(posedge CLK_14M) begin
        if (phase != prev_phase) begin
            $display("DRIVE%0s: phase changed %0d -> %0d (TRACK=%0d -> %0d) MOTOR_PHASE=%b ACTIVE=%0d",
                     IS_35_INCH?"(3.5)":"(5.25)", prev_phase, phase, prev_phase[8:2], phase[8:2], MOTOR_PHASE, DISK_ACTIVE);
        end
        prev_phase <= phase;
    end
`endif

    // Read/Write logic with corrected timing
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            // BRAM READ LATENCY COMPENSATION:
            // Start byte_delay at 2 to allow 1 cycle for BRAM latency before first load.
            // Sequence: Q3#1: byte_delay 2->1 (BRAM fetches data[N])
            //           Q3#2: byte_delay==1 triggers load, TRACK_DO has data[N]
            //
            // D5 SYNC BYTE FIX: Start position depends on drive type.
            //
            // 5.25" drives: Start at address 1 (near beginning of track).
            // The ~9000 cycle gap between ROM reads causes disk rotation.
            // At byte_period=72, 9000/504 = ~18 bytes rotation.
            //
            // 3.5" drives: ROM needs to find SECTOR 0 for boot block.
            // After the ROM's initial probe (~11 reads), it switches to probe other drives
            // for ~9000 cycles. During this gap, the disk rotates.
            // At byte_period=20 Q3 = ~140 14MHz cycles: 9000 / 140 = ~64 bytes rotation.
            // Sector 0's D5 AA 96 address prolog is at position 8 in the track.
            //
            // To land at position 8 after 64 bytes rotation:
            //   Starting position = 8 - 64 = -56 → wrap to 10240 - 56 = 10184 (0x27C8)
            //
            // 3.5" drives: Start at position 7 so TRACK_ADDR (prefetch) = 8 points to D5.
            // The motor spinup pre-loads data_reg from TRACK_DO at the prefetch address.
            // D5 is at position 8 (after 8 sync bytes), so starting at 7 means the ROM's
            // first read sees D5 immediately.
            // ROM burst-reads ~11 times before the disk advances (byte_delay=31 Q3 cycles),
            // so we need D5 visible from the very first read.
            track_byte_addr <= IS_35_INCH ? 14'h0007 : 14'h0001;
            byte_delay <= 8'd2;  // Extra cycle for BRAM latency before first load
            reset_data_reg <= 1'b0;
            data_reg <= 8'h00;
            disk_ready_d <= 1'b0;
            disk_active_d <= 1'b0;
            disk_active_latched <= 1'b0;
            sample_count <= 16'd0;
            track_busy_d <= 1'b0;
            bram_data_valid <= 1'b0;  // Need to wait for BRAM data after reset
            data_ready <= 1'b0;  // No data ready after reset
            prev_read_strobe <= 1'b0;  // Initialize strobe tracking
            prev_read_strobe2 <= 1'b0; // Initialize second delay register
            prev_read_strobe3 <= 1'b0; // Initialize third delay register
            byte_was_read <= 1'b0;    // No byte has been read yet
            spindown_counter <= 21'd0;  // No spindown in progress
            motor_spinning <= 1'b0;     // Not spinning at reset
            spinup_counter <= 14'd0;    // No spinup in progress
            write_pending <= 1'b0;      // No write pending at reset
            data_ready_timer <= 5'd0;   // Initialize timer
            latch_clear_timer <= 6'd0;  // Initialize latch clear timer
            byte_consumed <= 1'b0;
            prev_data_reg_read <= 1'b0;  // Initialize data reg read tracking
            first_byte_loaded <= 1'b0;
            ever_loaded_byte <= 1'b0;
`ifdef SIMULATION
            q3_edge_counter <= 0;
            data_update_counter <= 0;
            last_data_output <= 8'h00;
            cycles_since_strobe <= 0;
            clear_count <= 0;
            all_q3_edges <= 0;
`endif
        end else begin
            TRACK_WE <= 1'b0;
            Q3_D <= Q3;
            // Decrement data_ready_timer
            if (data_ready_timer > 0) data_ready_timer <= data_ready_timer - 1'b1;

            // LATCH CLEAR TIMER (3.5" and 5.25" drives):
            // After a valid byte read, the timer counts down and clears bit 7.
            // This signals to the ROM "you read this byte, wait for the next one."
            // Without this, the ROM sees bit 7=1 continuously and thinks the SAME
            // byte is still valid, causing it to process the same byte repeatedly.
            //
            // Timing requirements:
            // - Timer must expire BEFORE the ROM's next poll (typically ~50 cycles after read)
            // - Timer must expire AFTER the CPU has latched the data (~10 cycles)
            // - Next byte arrives at byte_period (238 cycles for 3.5"), setting bit 7=1 again
            //
            // Sequence: Read at N → bit7=1 → timer expires at N+40 → bit7=0 →
            //           ROM polls at N+55 → sees bit7=0, loops →
            //           next byte at N+238 → bit7=1 → ROM reads new byte
            if (latch_clear_timer > 0) begin
                latch_clear_timer <= latch_clear_timer - 1'b1;
                // When timer expires, clear data_ready (bit 7)
                if (latch_clear_timer == 1) begin
                    data_ready <= 1'b0;
                end
            end
            
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

            // Spindown inertia management:
            // When MOTOR_ON is high, the motor is physically spinning (regardless of drive selection).
            // When MOTOR_ON goes low, the physical disk keeps rotating due to inertia.
            // NOTE: We use MOTOR_ON (not DISK_ACTIVE) because the ROM may switch between
            // drives during boot, but the motor should keep running for all drives.
            if (MOTOR_ON) begin
                // Motor is on - keep spinning
                // BUG FIX (2025-01-03): When motor first starts, pre-load data_reg from TRACK_DO
                // so the ROM's first probe read sees valid data. Otherwise, data_reg is 0x00
                // and the ROM sees bit7=0, thinking there's no disk.
                // We only do this when DISK_READY is true (track loaded) and not busy.
                if (!motor_spinning && DISK_READY && ~TRACK_BUSY) begin
`ifdef SIMULATION
                    $display("DRIVE%0s: MOTOR SPINUP - pre-loading data_reg=%02h from TRACK_DO at addr=%04h",
                             IS_35_INCH?"(3.5)":"(5.25)", TRACK_DO, track_byte_addr);
`endif
                    data_reg <= TRACK_DO;
                    data_ready <= 1'b1;  // Mark as valid so bit7 is set
                    // BUG FIX (2026-01-05): For 3.5" drives, use short byte_delay so the next
                    // byte (AA after D5) arrives quickly. The ROM only polls for ~10 cycles
                    // before giving up, but byte_period=31 means AA wouldn't arrive for ~217
                    // cycles. Setting byte_delay=1 makes AA arrive on the next Q3 edge (~7 cycles).
                    // For 5.25" drives, keep normal timing.
                    byte_delay <= IS_35_INCH ? 8'd1 : byte_period;
                    // BUG FIX (2026-01-05): Also advance track_byte_addr during spinup!
                    // The spinup loads data_reg from TRACK_DO (which reads via prefetch_addr).
                    // Without advancing track_byte_addr, the NEXT byte_delay expiry loads from
                    // the SAME prefetch address, giving D5 twice in a row instead of D5 then AA.
                    // The ROM sees D5, waits for AA, but gets D5 again and restarts search.
                    // Fix: advance track_byte_addr so next DATA_UPDATE prefetches the NEXT byte.
                    if (IS_35_INCH) begin
                        if (track_byte_addr == 14'h27FF) track_byte_addr <= 14'b0;
                        else track_byte_addr <= track_byte_addr + 1;
                    end else begin
                        if (track_byte_addr == 14'h19FF) track_byte_addr <= 14'b0;
                        else track_byte_addr <= track_byte_addr + 1;
                    end
                end
`ifdef SIMULATION
                if (!motor_spinning) begin
                    $display("DRIVE%0s: motor_spinning 0->1 (MOTOR_ON=%0d) track_byte_addr=%04h byte_delay=%0d",
                             IS_35_INCH?"(3.5)":"(5.25)", MOTOR_ON, track_byte_addr, byte_delay);
                end
`endif
                motor_spinning <= 1'b1;
                spindown_counter <= SPINDOWN_TIME;
            end else if (spindown_counter > 0) begin
                // Motor was on but now off - spindown in progress
                spindown_counter <= spindown_counter - 1'd1;
                // motor_spinning stays true
            end else begin
                // Spindown complete
                motor_spinning <= 1'b0;
`ifdef SIMULATION
                if (motor_spinning) begin
                    $display("DRIVE%0s: MOTOR SPINDOWN COMPLETE - motor_spinning going FALSE", IS_35_INCH?"(3.5)":"(5.25)");
                end
`endif
            end

            // For reads: advance on Q3 clock like reference implementation. For writes: on Q3 tick.

            // Track strobe for falling edge detection with extra delay for slow-mode CPU timing.
            prev_read_strobe3 <= prev_read_strobe2;
            prev_read_strobe2 <= prev_read_strobe;
            prev_read_strobe <= READ_STROBE;

            // BUG FIX (2025-12-21): Latch DISK_ACTIVE at rising edge of READ_STROBE.
            // Problem: When ROM reads D5 (@C0EC) then immediately accesses drive select (@C0EB),
            // DISK_ACTIVE changes DURING the read cycle (between rising and falling edges).
            // This caused byte_consumed to NOT be set for D5, leaving bit7=1 on subsequent reads.
            // The ROM then saw D5 again instead of waiting for AA, breaking prolog detection.
            // Solution: Latch DISK_ACTIVE when read starts, use latched value for byte_consumed.
            if (READ_STROBE && !prev_read_strobe) begin
                disk_active_latched <= DISK_ACTIVE;  // Latch at rising edge
            end

            // Track DATA_REG_READ for edge detection
            prev_data_reg_read <= DATA_REG_READ;

            // Mark byte as consumed on FALLING edge of DATA_REG_READ (after CPU has latched data)
            // BUG FIX (2026-01-04): Previously used READ_STROBE which only triggers for $C0EC.
            // But the ROM reads from multiple even addresses (@e0, @e2, @e4, @e6, @e8, @ea, @ec)
            // while in Q6=Q7=0 mode. All these reads should consume the byte, not just $C0EC.
            // Using DATA_REG_READ (which fires on ANY even address when Q6=Q7=0) ensures
            // byte_consumed is set regardless of which IWM address the ROM reads from.
            //
            // This fixes 3.5" boot where the ROM reads D5 AA 96 address prolog but then
            // doesn't see bit 7 clear when polling for the next byte from addresses like @e0.
            //
            // We only check if data_ready is true (meaning we have valid disk data
            // that the CPU just read). This works because:
            // 1. data_ready is only set when the motor is spinning AND disk is ready
            // 2. The motor_just_starting bypass handles the very first read
            // 3. For subsequent reads, data_ready correctly reflects disk state
            // BUG FIX (2026-01-05): Don't use rising edge detection!
            // The ROM reads the IWM in a tight loop (LDA $C0EC; BPL loop). DATA_REG_READ
            // stays high continuously across multiple 14MHz cycles because DEVICE_SELECT
            // doesn't toggle between CPU instructions.
            //
            // Problem with rising edge: When a new byte arrives (byte_consumed cleared by
            // byte_delay expiry), there's no rising edge of DATA_REG_READ if the ROM is
            // still polling. So byte_consumed never gets set again, and bit7 stays 1.
            //
            // Fix: Set byte_consumed whenever DATA_REG_READ is high AND byte_consumed is 0.
            // This ensures byte_consumed gets set on the FIRST cycle after a new byte
            // arrives, regardless of DATA_REG_READ's edge state.
            //
            // Also trigger when motor_just_starting to handle the very first byte during
            // motor spinup (before data_ready is set).
            if (DATA_REG_READ && (data_ready || motor_just_starting) && !byte_consumed) begin
                byte_consumed <= 1'b1;
                $display("BYTE_SEQ[%0d]: %02h (taddr=%04h)", DRIVE_ID+1, data_reg, track_byte_addr);
            end

            // BUG FIX (2026-01-05): For 3.5" drives, load next byte on DATA_REG_READ falling edge.
            // Problem: With should_rotate = motor_spinning && DATA_REG_READ, byte_delay can't
            // count down after the read completes (DATA_REG_READ drops). The next byte never
            // loads, and the ROM reads stale data.
            //
            // Fix: On falling edge of DATA_REG_READ (ROM just finished reading), immediately
            // load the next byte. This makes disk access "demand-driven" - disk advances one
            // byte per read. Works because:
            // 1. ROM reads current byte (DATA_REG_READ high, byte_consumed set)
            // 2. DATA_REG_READ drops (ROM done reading)
            // 3. We immediately load next byte and clear byte_consumed
            // 4. ROM comes back, sees bit7=1 (new byte ready), reads it
            if (IS_35_INCH && !DATA_REG_READ && prev_data_reg_read && byte_consumed &&
                DISK_READY && ~TRACK_BUSY && motor_spinning) begin
                // Falling edge of DATA_REG_READ with byte already consumed
                // Load next byte from disk (TRACK_DO has prefetched the next byte)
                data_reg <= TRACK_DO;
                data_ready <= 1'b1;
                byte_consumed <= 1'b0;  // New byte is ready, not consumed yet

                // Advance track address for next prefetch
                if (track_byte_addr == 14'h27FF) track_byte_addr <= 14'b0;
                else track_byte_addr <= track_byte_addr + 1;

                $display("DRIVE(3.5): IMMEDIATE LOAD on READ falling edge - data_reg<=%02h next_addr=%04h",
                         TRACK_DO, (track_byte_addr == 14'h27FF) ? 14'b0 : track_byte_addr + 1);
            end

            // START LATCH CLEAR TIMER on DATA_REG_READ rising edge (any data register read)
            // BUG FIX (2026-01-04): Same issue - must use rising edge.
            // This handles the case where ROM reads from addresses other than $C0EC
            // (e.g., $C0E0-$C0EA) while in Q6=Q7=0 mode. The timer-based approach clears
            // data_ready after a delay, signaling to the ROM "wait for next byte."
            //
            // CRITICAL for 3.5" drives: The address field for track 0, sector 0 contains:
            //   D5 AA 96 (prolog) + 96 96 96 DA DA (track, sector, side, format, checksum)
            // The first 3 address bytes are ALL 0x96! Without bit7 clearing, the ROM
            // can't distinguish "still reading same byte" from "new byte arrived with
            // same value". The ROM times out and gives up on the drive.
            //
            // Timer value: 40 cycles gives the CPU enough time to latch the data,
            // then clears bit7 so the ROM waits for the next byte arrival (~238 cycles).
            // Use longer timer for 3.5" (40) than 5.25" (14) because 3.5" has faster
            // byte arrival rate and ROM needs more margin.
            if (DATA_REG_READ && !prev_data_reg_read && data_ready) begin
                latch_clear_timer <= IS_35_INCH ? 6'd40 : 6'd14;
            end

            // BUG FIX (2025-12-19): Do NOT clear data_ready on READ_STROBE falling edge.
            // This contradicts the policy at lines 519-527 which says:
            // "data_ready policy: keep bit7 asserted until next byte arrives."
            // Clearing here causes the ROM to see bit7=0 (e.g., 0x55 instead of 0xD5)
            // when polling for sync bytes, preventing disk boot.
            // The correct behavior is to keep data_ready=1 until the next byte arrives,
            // which is handled by the byte arrival logic at line 405.
            //
            // OLD BUGGY CODE (removed):
            // if (!READ_STROBE && prev_read_strobe && data_ready && !new_byte_arriving) begin
            //     data_ready <= 1'b0;
            // end

`ifdef SIMULATION
            // Debug: trace READ_STROBE edges
            if (sample_count < 16'd100) begin
                if (READ_STROBE && !prev_read_strobe) begin
                    $display("DRIVE%0s: READ_STROBE RISING (data_ready=%0d data_reg=%02h)", IS_35_INCH?"(3.5)":"(5.25)", data_ready, data_reg);
                end
                if (!READ_STROBE && prev_read_strobe) begin
                    $display("DRIVE%0s: READ_STROBE FALLING (data_ready=%0d data_reg=%02h) -> keeping data_ready", IS_35_INCH?"(3.5)":"(5.25)", data_ready, data_reg);
                end
            end
`endif

`ifdef SIMULATION
            if (Q3 && ~Q3_D && DISK_READY && motor_spinning && sample_count < 16'd20) begin
                $display("DRIVE%0s: Q3 tick (ready=%0d spinning=%0d active=%0d busy=%0d delay=%0d)", IS_35_INCH?"(3.5)":"(5.25)", DISK_READY, motor_spinning, DISK_ACTIVE, TRACK_BUSY, byte_delay);
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
            // Disk rotation is driven ONLY by Q3 timing, NOT by CPU reads!
            // The CPU reads whatever data is currently in data_reg at the disk's rotation rate.
            // This is critical for proper GCR sync detection - the disk rotates at a fixed rate
            // regardless of how fast the CPU polls it.

            // Q3 timing simulates disk rotation - data advances at disk speed, not CPU speed
            // This is essential for proper disk operation
            // BUG FIX: Use motor_spinning instead of DISK_ACTIVE so disk keeps rotating
            // even when deselected (due to physical inertia). This is critical for boot
            // because the ROM scans multiple drives and the disk must keep spinning.
`ifdef SIMULATION
            // Debug: Track ALL Q3 edges (not just when conditions pass)
            if (Q3 && ~Q3_D) begin
                all_q3_edges <= all_q3_edges + 1;
                // Print every 100,000th Q3 edge to verify clock is still running
                if ((all_q3_edges > 14500000) && ((all_q3_edges % 100000) == 0)) begin
                    $display("DRIVE%0d Q3_HEARTBEAT: edge#%0d READY=%0d spinning=%0d BUSY=%0d count=%0d byte_delay=%0d",
                             DRIVE_ID+1, all_q3_edges, DISK_READY, motor_spinning, TRACK_BUSY, data_update_counter, byte_delay);
                end
            end
`endif
            // Use should_rotate which is defined as a wire above - pauses 3.5" disk when deselected
            if (Q3 && ~Q3_D && DISK_READY && should_rotate && ~TRACK_BUSY) begin
`ifdef SIMULATION
                q3_edge_counter <= q3_edge_counter + 1;
                if (sample_count < 16'd20) begin
                    $display("DRIVE%0s: Q3 edge #%0d - byte_delay %0d (period=%0d) spinning=%0d active=%0d ready=%0d busy=%0d",
                             IS_35_INCH?"(3.5)":"(5.25)", q3_edge_counter + 1, byte_delay,
                             byte_period, motor_spinning, DISK_ACTIVE, DISK_READY, TRACK_BUSY);
                end
`endif
                // BUG FIX: Check byte_delay == 1 BEFORE decrementing to avoid off-by-one due
                // to non-blocking assignment. When byte_delay=1, it's about to become 0, so
                // this is when we should load new data.
                if (byte_delay == 1) begin
                    // Timer expired, perform a byte operation and reset timer
                    byte_delay <= byte_period;
`ifdef SIMULATION
                    if (sample_count < 16'd10) begin
                        $display("DRIVE%0s: byte_delay RESET to %0d (was 0)", IS_35_INCH?"(3.5)":"(5.25)", byte_period);
                    end
`endif

                    // BUG FIX: Always load data_reg from TRACK_DO regardless of WRITE_MODE.
                    // The disk keeps spinning and provides data continuously. Previously, when
                    // WRITE_MODE was high (Q7=1 from mode register access), data_reg wasn't
                    // updated, causing stale bytes to be returned to the CPU.
                    //
                    // Handle data_reg clearing FIRST (like reference implementation)
                    if (reset_data_reg) begin
                        data_reg <= 8'b0;
                        reset_data_reg <= 1'b0;
`ifdef SIMULATION
                        $display("DRIVE%0s: DATA_REG cleared to 00 (was %02h) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", data_reg, sample_count);
`endif
                    end

                    // Load new data from disk - always happens as disk rotates
                    // BRAM READ LATENCY FIX:
                    // BRAM has 1-cycle read latency. TRACK_DO contains data from the address
                    // we set on the PREVIOUS cycle. So we need to:
                    // 1. Output current TRACK_DO (which is data for current track_byte_addr)
                    // 2. Advance track_byte_addr (to fetch NEXT byte for next iteration)
                    //
                    // The key insight: track_byte_addr is "one ahead" - it's fetching the
                    // NEXT byte while we output the CURRENT byte from TRACK_DO.
`ifdef SIMULATION
                    $display("DRIVE%0s: BYTE_DELAY EXPIRED - loading new data and advancing", IS_35_INCH?"(3.5)":"(5.25)");
                    $display("DRIVE%0s: BEFORE - data_reg=%02h track_byte_addr=%04h TRACK_DO=%02h", IS_35_INCH?"(3.5)":"(5.25)", data_reg, track_byte_addr, TRACK_DO);
`endif
                    data_reg <= TRACK_DO;
                    data_ready <= 1'b1;  // SET: New byte is now available for CPU
                    data_ready_timer <= 5'd20; // Ensure data_ready stays high for 20 cycles
                    byte_was_read <= 1'b0;  // New byte has not been read yet
                    
                    // Byte consumption tracking
                    if (!byte_consumed && first_byte_loaded) begin
                        $display("ERROR: MISSED BYTE %02h at track_addr %04h", data_reg, track_byte_addr);
                    end
                    byte_consumed <= 1'b0;
                    first_byte_loaded <= 1'b1;
                    ever_loaded_byte <= 1'b1;

`ifdef SIMULATION
                    if (sample_count < 16'd50 || (sample_count % 16'd5000) == 0) begin
                        $display("DRIVE%0s: data_ready=1 SET byte=%02h D_OUT=%02h (new_byte_arriving should be 1) at Q3#%0d", IS_35_INCH?"(3.5)":"(5.25)", TRACK_DO, D_OUT, q3_edge_counter);
                    end
`endif
                    // Advance track address to fetch NEXT byte (BRAM will have it ready next time)
                    // Track sizes: 5.25" = 6656 bytes (0x1A00), 3.5" = 10240 bytes (0x2800)
                    if (IS_35_INCH) begin
                        if (track_byte_addr == 14'h27FF) track_byte_addr <= 14'b0;
                        else track_byte_addr <= track_byte_addr + 1;
                    end else begin
                        if (track_byte_addr == 14'h19FF) track_byte_addr <= 14'b0;
                        else track_byte_addr <= track_byte_addr + 1;
                    end
`ifdef SIMULATION
                    data_update_counter <= data_update_counter + 1;
                    $display("DRIVE%0d%0s: DATA_UPDATE #%0d - data_reg<=%02h track_byte_addr<=%04h TRACK_ADDR=%04h (advancing to %04h) Q3_edge=#%0d", DRIVE_ID+1, IS_35_INCH?"(3.5)":"(5.25)",
                             data_update_counter + 1, TRACK_DO, track_byte_addr, TRACK_ADDR,
                             IS_35_INCH ? ((track_byte_addr == 14'h27FF) ? 14'b0 : track_byte_addr + 1)
                                        : ((track_byte_addr == 14'h19FF) ? 14'b0 : track_byte_addr + 1),
                             q3_edge_counter + 1);
                    if (sample_count < 16'd64 || (sample_count % 16'd100) == 0) begin
                        $display("DRIVE%0s RD: track=%0d addr=%04h data=%02h (from TRACK_DO) -> data_reg -> D_OUT [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", TRACK, track_byte_addr, TRACK_DO, sample_count);
                    end
                    if (sample_count < 16'd64) begin
                        sample_count <= sample_count + 1;
                    end
`endif

                    // Request data clearing for next cycle if needed
                    if (READ_DISK && PH0) begin
                        reset_data_reg <= 1'b1;
`ifdef SIMULATION
                        $display("DRIVE%0s: DATA_REG clear requested (read_disk=%0d PH0=%0d) [count=%0d]", IS_35_INCH?"(3.5)":"(5.25)", READ_DISK, PH0, sample_count);
`endif
                    end

                    // Handle write operations (only when actually writing, not just Q7=1)
                    if (WRITE_MODE) begin
                        // NOTE: For IWM, write_mode = q7 && ~q6, but even with that check,
                        // we need write_pending because the ROM can briefly read $C0EC (Q6=0)
                        // while Q7 is still 1 from a previous mode register access.
                        if (WRITE_REG) begin
                            data_reg <= D_IN;  // Override disk data with CPU write data
                            write_pending <= 1'b1;  // Arm the write
`ifdef SIMULATION
                            $display("DRIVE%0s: WRITE_MODE override - data_reg<=%02h (D_IN) instead of %02h (TRACK_DO) at addr=%04h", IS_35_INCH?"(3.5)":"(5.25)", D_IN, TRACK_DO, track_byte_addr);
`endif
                        end
                        // A real write happens on the sync signal, but ONLY if data was written
                        if (READ_DISK && PH0 && write_pending) begin
                            TRACK_WE <= ~TRACK_BUSY;
                            write_pending <= 1'b0;  // Clear after write
`ifdef SIMULATION
                            if (~TRACK_BUSY) begin
                                $display("DRIVE%s: TRACK_WE SET! addr=%04h data=%02h (WRITE_MODE=%0d READ_DISK=%0d PH0=%0d)", IS_35_INCH?"(3.5)":"(5.25)", track_byte_addr, data_reg, WRITE_MODE, READ_DISK, PH0);
                            end
`endif
                        end
                    end
                    // NOTE: Track address is advanced in both read and write blocks above.
                    // DO NOT add another increment here - that was causing double advancement!
                end else begin
                    // Still counting down - just decrement byte_delay
                    byte_delay <= byte_delay - 1;
`ifdef SIMULATION
                    if (sample_count < 16'd10) begin
                        $display("DRIVE%0s: counting down byte_delay %0d -> %0d", IS_35_INCH?"(3.5)":"(5.25)", byte_delay, byte_delay-1);
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

            // Final step: Handle READ_STROBE falling edge for data_ready clearing
            //
            // The data_ready flag controls bit 7 of D_OUT:
            // - data_ready=1: D_OUT = data_reg (full 8 bits, bit 7 from disk data)
            // - data_ready=0: D_OUT = data_reg with bit 7 forced to 0
            //
            // GCR disk bytes always have bit 7=1. The ROM uses this to detect "new data":
            // - Poll $C0EC until bit 7=1 (new byte ready)
            // - Read and process the byte
            // - Continue polling - should see bit 7=0 until next byte arrives
            //
            // BUG FIX: Clear data_ready on FALLING edge of FIRST read, not rising edge of second.
            // The ROM expects:
            //   1. Read $C0EC, see bit 7=1 (data ready)
            //   2. Load byte into Y register
            //   3. BPL not taken (bit 7=1), proceed to EOR
            //   4. Next read of $C0EC should see bit 7=0 until new byte arrives
            //
            // Previous bug: data_ready stayed 1 for TWO reads, causing the ROM to process
            // the same GCR byte twice. XORing the same decode value twice cancels out,
            // effectively MISSING that byte in the checksum calculation.
            //
            // BUG FIX 2 (REVISED): Keep data_ready=1 until the NEXT byte arrives.
            //
            // Previous approach: Clear data_ready on READ_STROBE falling edge to tell ROM
            // "you already read this byte". But this caused a race condition - the ROM's
            // tight ASL $C08C,X / BCC loop would clear data_ready before the CPU could
            // reliably sample the value. The CPU would see bit 7=0 (0x55 instead of 0xD5).
            //
            // data_ready policy: keep bit7 asserted until next byte arrives.
            // Clear only when the motor stops or disk becomes not ready.
            // BUG FIX: Use MOTOR_ON instead of motor_spinning because motor_spinning
            // is set with non-blocking assignment and won't be true until next cycle.
            // This prevents clearing data_ready on the same cycle as motor spinup.
            if (!MOTOR_ON || !DISK_READY) begin
                data_ready <= 1'b0;
            end
        end
    end

    // BUG FIX: Q3 and PH2 fire on the same clock edge (ph0_counter=0).
    // When a new byte arrives (new_byte_arriving), data_ready <= 1 is scheduled
    // via non-blocking assignment, but won't take effect until the NEXT clock.
    // The CPU read happens on the SAME clock edge (via PH2), seeing the OLD
    // data_ready value (0), causing bit 7 to be 0 and the CPU to miss the byte.
    //
    // Fix: When new_byte_arriving is true, use TRACK_DO directly (the BRAM output
    // that will be loaded into data_reg this cycle). This ensures the CPU sees
    // the new byte with bit 7 set on the same clock edge it arrives.
    // Bit 7 now reflects data_ready to prevent the CPU from seeing a ready byte
    // until the first real nibble has actually arrived.
    //
    // BUG FIX (2025-12-21): USE byte_consumed to mask bit7 for proper sync detection.
    // The ROM's polling loop (BPL loop) relies on bit 7 transitioning 0→1 to detect
    // each NEW byte from disk. Without this:
    //   - CPU reads D5 (bit7=1), accepts it
    //   - CPU reads again expecting AA, but gets D5 again (bit7 still 1!)
    //   - CPU thinks D5 is fresh, sees D5≠AA, loops back to find D5
    //   - CPU stuck reading same D5 until disk rotates past AA and 96
    // With byte_consumed masking:
    //   - CPU reads D5 (bit7=1, byte_consumed=0), accepts it
    //   - READ_STROBE falling edge sets byte_consumed=1
    //   - CPU reads again: bit7=0 (byte_consumed=1), waits in BPL loop
    //   - Next byte arrives: byte_consumed=0, bit7=1
    //   - CPU reads AA (bit7=1), accepts it
    // - data_ready=1 && byte_consumed=0 → bit7=1 (fresh byte ready)
    // - data_ready=1 && byte_consumed=1 → bit7=0 (byte already consumed, wait) [5.25" only]
    // - data_ready=0 → bit7=0 (no data, motor off)
    //
    // LATCH MODE FIX (2025-12-22):
    // 3.5" drives use latch mode by default (IWM mode bit 0 = 1). In latch mode, the
    // byte stays valid (bit 7 = 1) until the NEXT byte arrives. The ROM may read the
    // same byte multiple times and expects bit 7 to remain 1 each time.
    // For 5.25" drives (non-latch mode), bit 7 is cleared after first read so the ROM
    // knows to wait for the next byte.
    // Reference: Clemens clem_iwm.c lines 565-569, MacPlus floppy.v line 218-220
    //
    // MOTOR SPINUP FIX (2025-01-03):
    // When motor first turns on, data_reg is preloaded via non-blocking assignment,
    // which takes effect NEXT cycle. But the ROM may read in the SAME cycle as motor
    // turn-on, seeing stale data (00) instead of track data (ff). This causes the ROM
    // to think no disk is present (bit 7 = 0). Fix: return TRACK_DO directly when
    // motor is just starting up, bypassing the registered data_reg.
    //
    // BYTE CONSUMPTION FIX (2026-01-03):
    // Previously, 3.5" drives used "latch mode" where bit 7 stayed high until the next
    // byte arrived (via latch_clear_timer). But the ROM's prolog detection reads multiple
    // times in quick succession expecting D5, AA, 96 in sequence. With latch mode, the ROM
    // sees D5, D5, D5... because bit 7 stays high and the disk hasn't rotated yet.
    // The ROM thinks each read is a new byte, checks if D5==AA, fails, and restarts.
    //
    // Fix: Use byte_consumed for ALL drive types (not just 5.25"). After the first read,
    // byte_consumed=1, bit 7 becomes 0 immediately. The ROM sees bit 7=0 on subsequent
    // reads and waits in its BPL loop until the next byte arrives (byte_consumed cleared,
    // data_ready=1, bit 7=1 again).
    wire motor_just_starting = MOTOR_ON && !motor_spinning && DISK_READY && !TRACK_BUSY;
    // D_OUT logic:
    // - motor_just_starting: Bypass data_reg, use TRACK_DO directly during motor spinup
    // - new_byte_arriving: Use TRACK_DO for the arriving byte
    // - Otherwise: Use data_reg
    //
    // ASYNC MODE FIX (2026-01-04): Match MAME's async mode behavior.
    // In MAME's async mode (3.5" drives), bit 7 stays HIGH for multiple reads
    // until either: (1) the next byte arrives, or (2) ~14 cycles pass after a read.
    //
    // BYTE CONSUMPTION FIX (2026-01-04):
    // Use byte_consumed to mask bit7 IMMEDIATELY after first read.
    // This provides instant feedback to the ROM that the byte was consumed.
    //
    // The ROM's algorithm:
    // 1. Poll until bit7=1 (new byte available)
    // 2. Read and process the byte
    // 3. Continue polling - expects bit7=0 to signal "wait for next byte"
    //
    // Previous approach (latch_clear_timer) caused bit7=0 for ~200 cycles between
    // bytes, which made the ROM think the drive had no more data and give up.
    //
    // New approach: bit7=1 on FIRST read (data_ready=1, byte_consumed=0), then
    // bit7=0 on subsequent reads (byte_consumed=1) until next byte arrives.
    // This is critical for 3.5" drives where consecutive address bytes may have
    // the same value (0x96 for track 0, sector 0, side 0).
    //
    // IMMEDIATE LOAD BYPASS (2026-01-05): When IMMEDIATE LOAD is about to fire
    // (falling edge of DATA_REG_READ with byte_consumed=1), bypass D_OUT directly
    // to TRACK_DO. This provides the next byte immediately without waiting for
    // the registered update, eliminating the 1-cycle glitch where bit7=0.
    wire immediate_load_pending = IS_35_INCH && !DATA_REG_READ && prev_data_reg_read &&
                                  byte_consumed && DISK_READY && ~TRACK_BUSY && motor_spinning;
    assign D_OUT = motor_just_starting ? TRACK_DO :
                   immediate_load_pending ? TRACK_DO :  // Bypass during immediate load
                   new_byte_arriving ? TRACK_DO :
                   ((data_ready && !byte_consumed) ? data_reg : {1'b0, data_reg[6:0]});
    // BRAM LATENCY FIX (2026-01-04): TRACK_ADDR must be 1 ahead of track_byte_addr
    // to compensate for BRAM's 1-cycle read latency. When DATA_UPDATE loads data_reg
    // from TRACK_DO, the BRAM needs to already be outputting the NEXT byte's data.
    // Without this, data_reg gets the PREVIOUS byte, causing D5 AA 96 to show as FF.
    wire [13:0] prefetch_addr = IS_35_INCH
        ? (track_byte_addr == 14'h27FF ? 14'b0 : track_byte_addr + 1)
        : (track_byte_addr == 14'h19FF ? 14'b0 : track_byte_addr + 1);
    assign TRACK_ADDR = prefetch_addr;
    assign TRACK_DI = data_reg;

`ifdef SIMULATION
    // Debug: trace D_OUT calculation on READ_STROBE
    reg prev_read_strobe_debug;
    reg [15:0] reading_now_debug_count;
    always @(posedge CLK_14M) begin
        prev_read_strobe_debug <= READ_STROBE;
        if (READ_STROBE && !prev_read_strobe_debug && DISK_ACTIVE && (data_update_counter < 100 || (data_update_counter % 1000 == 0))) begin
            $display("DRIVE%0d D_OUT_CALC: new_byte=%0d TRACK_DO=%02h data_ready=%0d byte_consumed=%0d data_reg=%02h -> D_OUT=%02h (addr=%04h)",
                     DRIVE_ID+1, new_byte_arriving, TRACK_DO, data_ready, byte_consumed, data_reg, D_OUT, track_byte_addr);
        end
        // Debug reading_data_now on rising edge of DATA_REG_READ
        if (DATA_REG_READ && !prev_data_reg_read && DISK_ACTIVE && reading_now_debug_count < 50) begin
            reading_now_debug_count <= reading_now_debug_count + 1;
            $display("DRIVE%0d READING_NOW: DATA_REG_READ=%d prev=%d data_ready=%d byte_consumed=%d reading_data_now=%d D_OUT=%02h",
                     DRIVE_ID+1, DATA_REG_READ, prev_data_reg_read, data_ready, byte_consumed, reading_data_now, D_OUT);
        end
    end
`endif

endmodule
