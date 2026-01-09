//
// flux_drive.v: Hardware-accurate floppy drive module with flux transition interface
//
// This module implements the physical drive state that was implicit in real hardware:
// - Motor state (spinning with spindown inertia)
// - Head position (quarter-track from stepper phases)
// - Disk rotation (bit position within track)
// - Flux transition generation from track bits
//
// All state is maintained in this module; the IWM chip just samples flux transitions.
//
// Reference: MAME iwm.cpp, real Apple IIgs drive architecture
//

module flux_drive (
    // Configuration
    input  wire        IS_35_INCH,      // 1 = 3.5" drive, 0 = 5.25" drive
    input  wire [1:0]  DRIVE_ID,        // Drive instance identifier for debug

    // Global clocks and reset
    input  wire        CLK_14M,         // 14MHz master clock
    input  wire        RESET,

    // Control from IWM
    input  wire [3:0]  PHASES,          // Head stepper phases (PH0-PH3) - registered value
    input  wire [3:0]  IMMEDIATE_PHASES,// Immediate phase value (for sense calculation)
    input  wire [2:0]  LATCHED_SENSE_REG, // MAME-style latched sense register index
    input  wire        MOTOR_ON,        // Motor enable from IWM (with spinup inertia)
    input  wire        SW_MOTOR_ON,     // Software motor on state (immediate, from $C0E9)
    input  wire        DISKREG_SEL,     // SEL line from $C031 bit 7 (for 3.5" status)
    input  wire        DRIVE_SELECT,    // Drive selection (0=drive1, 1=drive2)
    input  wire        DRIVE_SLOT,      // Which slot this drive is (0 or 1)

    // Per-drive configuration (from C++/simulation)
    input  wire        DISK_MOUNTED,    // Disk is inserted in this drive
    input  wire        DISK_WP,         // Disk write protect status
    input  wire        DOUBLE_SIDED,    // Drive is double-sided (3.5" = 1)

    // Flux interface to IWM
    output reg         FLUX_TRANSITION, // Pulse when flux transition occurs
    output wire        WRITE_PROTECT,   // Write protect status (directly from DISK_WP)

    // Status sense output (computed per-drive)
    output wire        SENSE,           // Status sense line to IWM

    // Status outputs
    output wire        MOTOR_SPINNING,  // Physical motor state (includes spindown)
    output wire [6:0]  TRACK,           // Current track number (head position)

    // Track data interface (SD block or BRAM)
    // For initial testing, uses direct BRAM interface like apple_drive.v
    output wire [16:0] BIT_POSITION,    // Current bit position within track (for debug)
    input  wire [31:0] TRACK_BIT_COUNT, // Total bits in current track
    input  wire        TRACK_LOADED,    // Track data is available

    // BRAM interface for track bits
    output wire [13:0] BRAM_ADDR,       // Byte address in track buffer
    input  wire [7:0]  BRAM_DATA,       // Byte data from track buffer

    // SD block interface for track loading (optional, for WOZ support)
    output reg  [7:0]  SD_TRACK_REQ,    // Track number to load (pulsed)
    output reg         SD_TRACK_STROBE, // Request new track load
    input  wire        SD_TRACK_ACK     // Track load complete
);

    //=========================================================================
    // Parameters
    //=========================================================================

    // Drive geometry
    localparam MAX_PHASE_525 = 139;     // 35 tracks * 4 steps/track - 1
    localparam MAX_PHASE_35  = 319;     // 80 tracks * 4 steps/track - 1

    // Bit cell timing in 14MHz cycles
    // 5.25": 4µs per bit = 56 cycles
    // 3.5":  2µs per bit = 28 cycles
    localparam BIT_CELL_525 = 6'd56;
    localparam BIT_CELL_35  = 6'd28;

    //=========================================================================
    // Internal State
    //=========================================================================

    // Motor state
    reg         motor_spinning;         // Physical motor rotation state
    reg         prev_motor_spinning;    // For edge detection on motor state

    // Drive ready state (MAME m_ready equivalent)
    // MAME: m_ready=true means NOT ready, m_ready=false means ready (active-low)
    // After motor turns on, drive needs 2 rotations to become ready
    reg [1:0]   spinup_counter;         // Count rotations for spin-up (starts at 2)
    reg         drive_ready;            // True when drive is spun up and ready
    reg         rotation_complete;      // Pulse when disk completes one rotation

    // Head position (quarter-track)
    reg [8:0]   head_phase;             // 0-319 for 80 tracks (3.5") or 0-139 for 35 tracks (5.25")

    // Disk rotation
    reg [16:0]  bit_position;           // Current bit position within track (0 to bit_count-1)
    reg [5:0]   bit_timer;              // Countdown for bit cell timing

    // Track loading state
    reg [7:0]   current_track;          // Track currently in buffer
    reg         track_valid;            // Track data is valid

    // Flux generation state
    reg         prev_flux;              // Previous flux state for edge detection

    // Step direction tracking (MAME's m_dir equivalent)
    // Sony 3.5" drives use a command interface:
    //   - phases[3] = strobe (rising edge triggers command)
    //   - phases[2:0] = command code (0 = step dir +1, 4 = step dir -1)
    //   - Command 0: step toward higher tracks → m_dir = 0
    //   - Command 4: step toward track 0 → m_dir = 1
    // Track per drive slot since MAME tracks m_dir per physical drive
    reg [1:0]   step_direction_slot;    // One per drive slot (0 and 1)
    wire        step_direction = step_direction_slot[DRIVE_SELECT]; // Use current drive's direction
    reg [1:0]   prev_strobe_slot;       // Previous strobe state per drive slot

    // Internal motor state for 3.5" Sony drives (controlled by commands)
    reg         sony_motor_on;

    // Motor sense signal - for sense register 0x2 (MAME m_mon equivalent)
    // This follows the Sony command state, NOT the IWM motor bit
    // Decoupled from motor_spinning which controls flux generation
    wire        motor_on_sense = sony_motor_on;

`ifdef SIMULATION
    reg [3:0]   prev_imm_phases_debug;  // For tracking phase changes
`endif

    // Sony 3.5" drive command interface (MAME floppy.cpp mac_floppy_device::seek_phase_w)
    // Commands execute on rising edge of strobe (phases[3])
    // MAME computes: m_reg = (phases & 7) | (m_actual_ss ? 8 : 0)
    // where m_actual_ss is set from DISKREG_SEL (bit 7 of $C031)
    // This means when DISKREG_SEL=1 (side 1), command 6 becomes 14 (not motor off)
    //
    // Critical: Use LATCHED_SENSE_REG for command code, not IMMEDIATE_PHASES[2:0]
    // because phases may be cleared before strobe fires. Also, don't gate by
    // SW_MOTOR_ON because motor ON command needs to execute when motor is off.
    wire sony_cmd_strobe = IS_35_INCH && (DRIVE_SELECT == DRIVE_SLOT) && IMMEDIATE_PHASES[3] && !prev_strobe_slot[DRIVE_SELECT];
    wire [3:0] sony_cmd_reg = {DISKREG_SEL, LATCHED_SENSE_REG};

    //=========================================================================
    // Computed Values
    //=========================================================================

    wire [9:0]  max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    wire [5:0]  bit_cell_cycles = IS_35_INCH ? BIT_CELL_35 : BIT_CELL_525;

    // Current byte and bit within that byte
    wire [13:0] byte_index = bit_position[16:3];    // bit_position / 8
    wire [2:0]  bit_shift = 3'd7 - bit_position[2:0]; // MSB first (bit 7 = first bit)

    // Get current bit from BRAM data
    wire        current_bit = (BRAM_DATA >> bit_shift) & 1'b1;

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign MOTOR_SPINNING = motor_spinning;
    assign TRACK = head_phase[8:2];             // Quarter-track to full track
    assign BIT_POSITION = bit_position;
    assign BRAM_ADDR = byte_index;
    assign WRITE_PROTECT = DISK_WP;

    //=========================================================================
    // Status Sensing (3.5" drives)
    //=========================================================================
    // For 3.5" drives, status is read via the sense line based on a register
    // index formed from {SEL, phases[2:0]}. Each drive computes its own sense.
    // For 5.25" drives, sense is just the write protect status.
    //
    // Reference: MAME floppy.cpp mac_floppy_device::wpt_r()

    // Use LATCHED_SENSE_REG for sense calculation - MAME latches m_reg when
    // phases are written, and subsequent reads use that latched value even
    // if phases have been cleared. This is critical for the ROM drive detection.
    wire [3:0] status_reg = {DISKREG_SEL, LATCHED_SENSE_REG};
    wire       at_track0 = (head_phase[8:2] == 7'd0);

    // 3.5" status sensing - some registers work without motor power
    // MAME reference: floppy.cpp mac_floppy_device::wpt_r()
    // Note: Many signals use active-low logic (0 = true/active)
    reg sense_35;
    // Match MAME's mac_floppy_device::wpt_r() for 800K GCR drive
    // See mame/src/devices/imagedev/floppy.cpp around line 2885
    always @(*) begin
        case (status_reg)
            4'h0: begin
                sense_35 = step_direction;    // Step direction (0=in, 1=out)
`ifdef SIMULATION
                if (sense_35) $display("FLUX_DRIVE[%0d]: Case 0 returning 1! step_dir=%0d sel=%0d", DRIVE_ID, step_direction, DRIVE_SELECT);
`endif
            end
            4'h1: sense_35 = 1'b1;              // Step signal (always 1 in MAME, no delay)
            4'h2: sense_35 = ~motor_on_sense;    // Motor: 0=ON, 1=OFF (MAME m_mon, based on Sony command)
            4'h3: sense_35 = 1'b1;              // Disk change: 1=No Change (Simplified)
            4'h4: sense_35 = 1'b0;              // Index: 0 for GCR drives (no MFM index)
            4'h5: sense_35 = 1'b0;              // MFM Capable: 0 for 800K GCR drive
            4'h6: sense_35 = 1'b1;              // Double Sided: 1 for 800K drive
            4'h7: sense_35 = 1'b0;              // Drive Present: 0 (Active Low detection)
            4'h8: sense_35 = ~DISK_MOUNTED;     // Disk In Place: 0=Yes, 1=No
            4'h9: sense_35 = ~DISK_WP;          // Write Protect: 0=Protected, 1=Writable (MAME returns !m_wpt, check polarity)
            // Wait, MAME says: case 0x9: return !m_wpt;
            // If m_wpt is true (protected), returns false (0).
            // If m_wpt is false (writable), returns true (1).
            // My DISK_WP is 1=Protected?
            // If DISK_WP=1 (Protected), ~DISK_WP=0. Matches MAME.
            
            4'hA: sense_35 = ~at_track0;        // Track 0: 0=At Track 0, 1=Not At Track 0
            4'hB: sense_35 = 1'b1;              // Tachometer: 1 (Simplified)
            4'hC: sense_35 = 1'b0;              // Index: 0 for GCR
            4'hD: sense_35 = 1'b0;              // Mode: 0=GCR, 1=MFM (800K is GCR)
            4'hE: sense_35 = ~drive_ready;       // NoReady: 0=ready, 1=not ready (MAME m_ready)
            4'hF: sense_35 = 1'b1;              // Interface: 1=2M/800K, 0=400K
        endcase
    end

    // For 5.25" drives, sense is just write protect
    // For 3.5" drives, all status registers work regardless of motor state
    // The motor only affects data reading, not status queries
    // This is critical for ROM drive detection which queries status before turning motor on
    assign SENSE = IS_35_INCH ? sense_35 : DISK_WP;

`ifdef SIMULATION
    // Debug: trace sense computation for 3.5" drive
    reg prev_sense_debug;
    always @(posedge CLK_14M) begin
        if (IS_35_INCH && MOTOR_ON && (sense_35 != prev_sense_debug)) begin
            $display("FLUX_DRIVE: sense=%0d status_reg=%h (SEL=%0d latched=%03b phases=%04b) at_track0=%0d motor_spin=%0d mounted=%0d",
                     sense_35, status_reg, DISKREG_SEL, LATCHED_SENSE_REG, PHASES, at_track0, motor_spinning, DISK_MOUNTED);
        end
        prev_sense_debug <= sense_35;
    end
`endif

    //=========================================================================
    // Head Stepper Motor Logic
    //=========================================================================
    // 5.25" drives: 4-phase stepper (copied from apple_drive.v)
    // 3.5" drives: CA0=direction, CA1=step pulse (Sony mechanism)

    reg prev_step;  // For 3.5" edge detection on CA1

    always @(posedge CLK_14M or posedge RESET) begin
        integer phase_change;
        integer new_phase;
        reg [3:0] rel_phase;

        if (RESET) begin
            head_phase <= 9'd0;
            prev_step <= 1'b0;
            step_direction_slot <= 2'b00;  // Default: toward higher tracks (matches MAME m_dir=0)
            prev_strobe_slot <= 2'b00;     // No strobe active initially
            sony_motor_on <= 1'b0;         // Default: motor off
        end else begin
            // Track step direction commands (like MAME's m_dir)
            // These work even when motor is off - they just set direction for next step
            // Use IMMEDIATE_PHASES since MAME's seek_phase_w() sets direction immediately
            // Only update the currently selected drive's direction (MAME tracks per-drive)
`ifdef SIMULATION
            // Debug: Track all phase changes on 3.5" drive
            if (IS_35_INCH && (IMMEDIATE_PHASES != prev_imm_phases_debug)) begin
                $display("FLUX_DRIVE[%0d]: IMMEDIATE_PHASES %04b -> %04b [2:0]=%0d step_dir[%0d]=%0d",
                         DRIVE_ID, prev_imm_phases_debug, IMMEDIATE_PHASES, IMMEDIATE_PHASES[2:0],
                         DRIVE_SELECT, step_direction_slot[DRIVE_SELECT]);
            end
            prev_imm_phases_debug <= IMMEDIATE_PHASES;
`endif
            // Sony 3.5" drive command interface (MAME floppy.cpp mac_floppy_device::seek_phase_w)
            // Commands execute on rising edge of strobe (phases[3]):
            //   - phases[2:0] = command code
            //   - Command 0: "step dir +1" → dir_w(0) → m_dir=0 (toward higher tracks)
            //   - Command 4: "step dir -1" → dir_w(1) → m_dir=1 (toward track 0)
            //   - Command 2: "motor on"
            //   - Command 6: "motor off"
            // MAME behavior: devsel=0 when motor is off, so seek_phase_w() isn't called.
            // Use SW_MOTOR_ON (immediate soft switch state) not MOTOR_ON (with inertia).
`ifdef SIMULATION
            // Debug: trace strobe conditions
            if (IS_35_INCH && IMMEDIATE_PHASES[3] && !prev_strobe_slot[DRIVE_SELECT]) begin
                $display("FLUX_DRIVE[%0d]: STROBE! DRIVE_SELECT=%0d DRIVE_SLOT=%0d sel_match=%0d cmd_reg=%0d DISK_MOUNTED=%0d",
                         DRIVE_ID, DRIVE_SELECT, DRIVE_SLOT, (DRIVE_SELECT == DRIVE_SLOT), sony_cmd_reg, DISK_MOUNTED);
            end
`endif
            if (sony_cmd_strobe) begin
                // Use 4-bit command register like MAME: {DISKREG_SEL, LATCHED_SENSE_REG}
                // When DISKREG_SEL=1 (side 1), commands 0-7 become 8-15
                case (sony_cmd_reg)
                    4'd0: begin
                        step_direction_slot[DRIVE_SELECT] <= 1'b0;  // "step dir +1" → m_dir=0
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir +1 (m_dir=0)", DRIVE_ID);
`endif
                    end
                    4'd4: begin
                        step_direction_slot[DRIVE_SELECT] <= 1'b1;  // "step dir -1" → m_dir=1
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir -1 (m_dir=1)", DRIVE_ID);
`endif
                    end
                    4'd2: begin
                        if (DISK_MOUNTED) begin
                            sony_motor_on <= 1'b1;
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: cmd motor ON", DRIVE_ID);
`endif
                        end
                    end
                    4'd6: begin
                        sony_motor_on <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd motor OFF", DRIVE_ID);
`endif
                    end
                    default: ;  // Commands 8-15 (DISKREG_SEL=1) don't match motor/step commands
                endcase
            end
            prev_strobe_slot[DRIVE_SELECT] <= IMMEDIATE_PHASES[3];

            if (motor_spinning) begin  // Only step when motor is on
            if (IS_35_INCH) begin
                // 3.5" Sony drive stepping:
                // CA0 (PHASES[0]) = direction: 0=toward track 0, 1=toward track 79
                // CA1 (PHASES[1]) = step pulse: falling edge triggers step
                prev_step <= PHASES[1];
                if (prev_step && !PHASES[1]) begin  // Falling edge on CA1
                    if (PHASES[0]) begin
                        // Step inward (toward higher tracks)
                        if (head_phase < max_phase)
                            head_phase <= head_phase + 4'd4;  // 4 quarter-tracks = 1 full track
                    end else begin
                        // Step outward (toward track 0)
                        if (head_phase >= 4'd4)
                            head_phase <= head_phase - 4'd4;
                        else
                            head_phase <= 9'd0;
                    end
`ifdef SIMULATION
                    $display("FLUX_DRIVE[%0d]: 3.5\" STEP dir=%0d head_phase=%0d->%0d track=%0d",
                             DRIVE_ID, PHASES[0], head_phase,
                             PHASES[0] ? head_phase + 4 : (head_phase >= 4 ? head_phase - 4 : 0),
                             PHASES[0] ? (head_phase + 4) >> 2 : (head_phase >= 4 ? (head_phase - 4) >> 2 : 0));
`endif
                end
            end else begin
                // 5.25" 4-phase stepper logic
                phase_change = 0;
                new_phase = head_phase;
                rel_phase = PHASES;

                case (head_phase[2:1])
                    2'b00: rel_phase = {rel_phase[1:0], rel_phase[3:2]};
                    2'b01: rel_phase = {rel_phase[2:0], rel_phase[3]};
                    2'b10: ;
                    2'b11: rel_phase = {rel_phase[0], rel_phase[3:1]};
                    default: ;
                endcase

                if (head_phase[0] == 1'b1) begin
                    case (rel_phase)
                        4'b0001: phase_change = -3;
                        4'b0010: phase_change = -1;
                        4'b0011: phase_change = -2;
                        4'b0100: phase_change = 1;
                        4'b0101: phase_change = -1;
                        4'b0110: phase_change = 0;
                        4'b0111: phase_change = -1;
                        4'b1000: phase_change = 3;
                        4'b1001: phase_change = 0;
                        4'b1010: phase_change = 1;
                        4'b1011: phase_change = -3;
                        default: phase_change = 0;
                    endcase
                end else begin
                    case (rel_phase)
                        4'b0001: phase_change = -2;
                        4'b0011: phase_change = -1;
                        4'b0100: phase_change = 2;
                        4'b0110: phase_change = 1;
                        4'b1001: phase_change = 1;
                        4'b1010: phase_change = 2;
                        4'b1011: phase_change = -2;
                        default: phase_change = 0;
                    endcase
                end

                new_phase = head_phase + phase_change;
                if (new_phase < 0)
                    head_phase <= 9'd0;
                else if (new_phase > max_phase)
                    head_phase <= max_phase;
                else
                    head_phase <= new_phase;
            end
            end  // motor_spinning
        end  // !RESET
    end  // always

    //=========================================================================
    // Motor State Machine
    //=========================================================================
    // The spindown is handled by iwm_woz.v, which passes the already-delayed
    // motor_spinning signal as MOTOR_ON to this module. We just follow it directly.
    // This ensures MOTOR_ACTIVE (from iwm_woz) and MOTOR_SPINNING (from here)
    // stay synchronized for proper data register reads in iwm_flux.

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            motor_spinning <= 1'b0;
            prev_motor_spinning <= 1'b0;
            spinup_counter <= 2'd0;
            drive_ready <= 1'b0;
        end else begin
            prev_motor_spinning <= motor_spinning;

            if (IS_35_INCH) begin
                // 3.5" Sony drives: motor_spinning controls flux generation
                // MAME calls mon_w(false) immediately when IWM motor bit is set,
                // which starts the motor spinning. The Sony motor command also
                // calls mon_w(), but the IWM motor bit provides the initial trigger.
                // This decouples flux generation timing from sense register timing.
                motor_spinning <= SW_MOTOR_ON || sony_motor_on;
            end else begin
                // 5.25" drives: controlled by IWM enable line + inertia (handled in iwm_woz)
                motor_spinning <= MOTOR_ON;
            end

            // Drive ready logic (MAME floppy.cpp)
            // When motor turns ON: start spin-up counter at 2
            // After 2 rotations: drive becomes ready
            // When motor turns OFF: drive becomes not ready
            if (!prev_motor_spinning && motor_spinning && DISK_MOUNTED) begin
                // Motor just turned ON with disk mounted - start spin-up
                spinup_counter <= 2'd2;
                drive_ready <= 1'b0;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: Motor ON - starting spin-up (counter=2)", DRIVE_ID);
`endif
            end else if (!motor_spinning) begin
                // Motor OFF - not ready
                drive_ready <= 1'b0;
                spinup_counter <= 2'd0;
            end else if (rotation_complete && spinup_counter > 0) begin
                // Rotation completed while still spinning up
                spinup_counter <= spinup_counter - 1'd1;
                if (spinup_counter == 2'd1) begin
                    // This rotation will make counter reach 0 - drive is now ready
                    drive_ready <= 1'b1;
`ifdef SIMULATION
                    $display("FLUX_DRIVE[%0d]: Spin-up complete - drive ready!", DRIVE_ID);
`endif
                end
`ifdef SIMULATION
                else begin
                    $display("FLUX_DRIVE[%0d]: Spin-up rotation, counter: %0d -> %0d",
                             DRIVE_ID, spinup_counter, spinup_counter - 1);
                end
`endif
            end
        end
    end

    //=========================================================================
    // Disk Rotation and Flux Generation
    //=========================================================================
    // The disk rotates at a constant rate (determined by bit_cell_cycles).
    // At each bit cell boundary, we check if the current bit is 1.
    // If so, a flux transition occurs (FLUX_TRANSITION pulses high for 1 cycle).

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            bit_position <= 17'd0;
            bit_timer <= BIT_CELL_35;  // Start at full bit cell time
            FLUX_TRANSITION <= 1'b0;
            prev_flux <= 1'b0;
            SD_TRACK_REQ <= 8'd0;
            SD_TRACK_STROBE <= 1'b0;
            current_track <= 8'd0;
            track_valid <= 1'b0;
            rotation_complete <= 1'b0;
        end else begin
            // Default: no flux transition this cycle, no rotation complete
            FLUX_TRANSITION <= 1'b0;
            SD_TRACK_STROBE <= 1'b0;
            rotation_complete <= 1'b0;

            // Only rotate when motor is spinning and track is loaded
            if (motor_spinning && TRACK_LOADED) begin
                // Generate flux at the START of each bit cell (not the end)
                // This ensures flux transitions occur in the first half of the IWM's window
                if (bit_timer == bit_cell_cycles) begin
                    // Start of new bit cell - generate flux if this bit is 1
                    if (current_bit) begin
                        FLUX_TRANSITION <= 1'b1;
`ifdef SIMULATION
                        if (bit_position < 100) begin
                            $display("FLUX_DRIVE[%0d]: Flux transition at bit %0d (byte %04h, shift %0d)",
                                     DRIVE_ID, bit_position, byte_index, bit_shift);
                        end
`endif
                    end
                end

                if (bit_timer == 6'd1) begin
                    // End of bit cell - advance to next bit
                    bit_timer <= bit_cell_cycles;

                    // Advance bit position with wraparound
                    if (TRACK_BIT_COUNT > 0) begin
                        if (bit_position + 1 >= TRACK_BIT_COUNT) begin
                            bit_position <= 17'd0;
                            // Signal that one full rotation has completed
                            rotation_complete <= 1'b1;
                        end else begin
                            bit_position <= bit_position + 1'd1;
                        end
                    end
                end else begin
                    // Still in current bit cell
                    bit_timer <= bit_timer - 1'd1;
                end
            end else begin
                // Motor not spinning or track not loaded - reset timer
                bit_timer <= bit_cell_cycles;
            end

            // Track change detection - request new track load when head moves
            // (For now, just track the current track for debugging)
            if (head_phase[8:2] != current_track) begin
                current_track <= head_phase[8:2];
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: Head moved to track %0d", DRIVE_ID, head_phase[8:2]);
`endif
            end
        end
    end

`ifdef SIMULATION
    // Debug output
    reg [8:0] prev_head_phase;
    reg [31:0] flux_count_debug;
    reg [31:0] cycle_count_debug;
    reg [31:0] rotate_cycles;    // Cycles where disk is rotating
    reg [31:0] stopped_cycles;   // Cycles where disk is stopped
    reg        prev_motor_on;    // Track MOTOR_ON transitions
    always @(posedge CLK_14M) begin
        if (RESET) begin
            flux_count_debug <= 0;
            rotate_cycles <= 0;
            stopped_cycles <= 0;
            cycle_count_debug <= 0;
            prev_motor_on <= 1'b0;
        end else begin
            // Debug: Track MOTOR_ON transitions
            if (MOTOR_ON != prev_motor_on) begin
                $display("FLUX_DRIVE[%0d]: MOTOR_ON %0d -> %0d (DISK_MOUNTED=%0d TRACK_LOADED=%0d)",
                         DRIVE_ID, prev_motor_on, MOTOR_ON, DISK_MOUNTED, TRACK_LOADED);
            end
            prev_motor_on <= MOTOR_ON;
            cycle_count_debug <= cycle_count_debug + 1;

            // Track rotating vs stopped cycles
            if (motor_spinning && TRACK_LOADED) begin
                rotate_cycles <= rotate_cycles + 1;
            end else begin
                stopped_cycles <= stopped_cycles + 1;
            end

            // Log first flux transitions
            if (FLUX_TRANSITION) begin
                flux_count_debug <= flux_count_debug + 1;
                if (flux_count_debug < 20) begin
                    $display("FLUX_DRIVE[%0d]: FLUX #%0d at cycle=%0d bit_pos=%0d byte=%04h data=%02h bit=%0d",
                             DRIVE_ID, flux_count_debug, cycle_count_debug, bit_position,
                             byte_index, BRAM_DATA, current_bit);
                end
            end

            // Periodic status every 1M cycles
            if (cycle_count_debug[19:0] == 0) begin
                $display("FLUX_DRIVE[%0d]: Status: motor=%b track_loaded=%b bit_pos=%0d/%0d rotate=%0d stopped=%0d ratio=%0d%%",
                         DRIVE_ID, motor_spinning, TRACK_LOADED, bit_position, TRACK_BIT_COUNT,
                         rotate_cycles, stopped_cycles,
                         (rotate_cycles + stopped_cycles > 0) ? (rotate_cycles * 100 / (rotate_cycles + stopped_cycles)) : 0);
            end
        end

        if (head_phase != prev_head_phase) begin
            $display("FLUX_DRIVE[%0d]: Phase %0d -> %0d (track %0d -> %0d)",
                     DRIVE_ID, prev_head_phase, head_phase,
                     prev_head_phase[8:2], head_phase[8:2]);
        end
        prev_head_phase <= head_phase;
    end
`endif

endmodule
