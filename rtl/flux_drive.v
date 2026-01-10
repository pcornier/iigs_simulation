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
    output wire        DRIVE_READY,     // Drive is ready (motor at speed after spinup)
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
    // 5.25": 4µs per bit = 56 cycles @14M
    // 3.5":  2µs per bit = 28 cycles @14M
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
    reg [1:0]   prev_strobe_slot;       // Previous strobe state per drive slot

    // Immediate step direction for sense calculation
    // When a strobe fires, the sense read should see the NEW direction value immediately,
    // not wait for the clock edge. This matches MAME where m_dir updates synchronously
    // in seek_phase_w() before wpt_r() can return it.
    // Note: sony_cmd_strobe and sony_cmd_reg are defined below, but we need them here
    // for the immediate calculation. Using forward references works in Verilog.
    wire        step_direction_immediate;
    wire        step_direction_registered = step_direction_slot[DRIVE_SELECT];

    // Internal motor state for 3.5" Sony drives (controlled by commands)
    reg         sony_motor_on;
    
    // Disk switched flag (set on mount/reset, cleared by command)
    reg         disk_switched;
    reg         prev_disk_mounted;

    // Motor sense signal - for sense register 0x2 (MAME m_mon equivalent)
    // This follows the Sony command state, NOT the IWM motor bit
    // Decoupled from motor_spinning which controls flux generation
    wire        motor_on_sense = sony_motor_on;

`ifdef SIMULATION
    reg [3:0]   prev_imm_phases_debug;  // For tracking phase changes
    reg [31:0]  prev_track_bit_count;   // Track changes in TRACK_BIT_COUNT
    reg         side_transition_logged; // One-shot for side transition logging
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

    // Compute immediate step direction: if strobe is firing with a direction command,
    // use the NEW value; otherwise use the registered value.
    // cmd_reg 0 = DirNext (m_dir=0, toward higher tracks)
    // cmd_reg 4 = DirPrev (m_dir=1, toward track 0)
    assign step_direction_immediate = (sony_cmd_strobe && sony_cmd_reg == 4'd0) ? 1'b0 :
                                      (sony_cmd_strobe && sony_cmd_reg == 4'd4) ? 1'b1 :
                                      step_direction_registered;

    //=========================================================================
    // Computed Values
    //=========================================================================

    wire [9:0]  max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    wire [5:0]  bit_cell_cycles = IS_35_INCH ? BIT_CELL_35 : BIT_CELL_525;

    // Current byte and bit within that byte
    // Clamp byte_index to prevent out-of-bounds reads during track transitions
    // When TRACK_BIT_COUNT changes, bit_position might exceed the new track's size
    // for one cycle before it gets wrapped. This clamp ensures we don't read garbage.
    wire [13:0] raw_byte_index = bit_position[16:3];    // bit_position / 8
    wire [13:0] max_byte_index = (TRACK_BIT_COUNT > 0) ? ((TRACK_BIT_COUNT - 1) >> 3) : 14'd0;
    wire [13:0] byte_index = (raw_byte_index > max_byte_index) ? 14'd0 : raw_byte_index;
    wire [2:0]  bit_shift = 3'd7 - bit_position[2:0]; // MSB first (bit 7 = first bit)

    // Get current bit from BRAM data
    wire        current_bit = (BRAM_DATA >> bit_shift) & 1'b1;

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign MOTOR_SPINNING = motor_spinning;
    assign DRIVE_READY = drive_ready;           // Ready after 2 rotation spinup
    assign TRACK = head_phase[8:2];             // Quarter-track to full track
    assign BIT_POSITION = bit_position;
    // Look-ahead for BRAM address to handle simulation/C++ update latency
    wire [16:0] next_bit_pos = (TRACK_BIT_COUNT > 0 && bit_position + 1 >= TRACK_BIT_COUNT) ? 17'd0 : bit_position + 1'd1;
    // Clamp BRAM_ADDR to prevent out-of-bounds reads during track transitions.
    // Both next_bit_pos[16:3] and byte_index need protection because bit_position
    // may exceed the new track's size for one cycle before wrapping occurs.
    wire [13:0] unclamped_bram_addr = (bit_timer == 6'd1) ? next_bit_pos[16:3] : byte_index;
    assign BRAM_ADDR = (unclamped_bram_addr > max_byte_index) ? 14'd0 : unclamped_bram_addr;
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
                // Use immediate value so sense read in same cycle as direction command sees new value
                // This matches MAME where m_dir updates synchronously in seek_phase_w() before wpt_r()
                sense_35 = step_direction_immediate;
`ifdef SIMULATION
                if (sense_35) $display("FLUX_DRIVE[%0d]: Case 0 returning 1! step_dir_imm=%0d step_dir_reg=%0d sel=%0d", DRIVE_ID, step_direction_immediate, step_direction_registered, DRIVE_SELECT);
`endif
            end
            4'h1: sense_35 = 1'b1;              // Step signal (always 1 in MAME, no delay)
            4'h2: sense_35 = ~motor_on_sense;    // Motor: 0=ON, 1=OFF (MAME m_mon, based on Sony command)
            4'h3: sense_35 = ~disk_switched;    // Disk change: 0=Changed, 1=No Change
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
            disk_switched <= 1'b1;         // Assume disk switched on reset
            prev_disk_mounted <= 1'b0;
        end else begin
            // Track disk insertion
            if (DISK_MOUNTED && !prev_disk_mounted) begin
                disk_switched <= 1'b1;
            end
            prev_disk_mounted <= DISK_MOUNTED;

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
                // Sony 3.5" drive command set (from MAME floppy.cpp mac_floppy_device::seek_phase_w):
                //   0x0: DirNext   - Set direction toward higher tracks (m_dir=0)
                //   0x1: StepOn    - Execute one step in current direction
                //   0x2: MotorOn   - Turn motor on
                //   0x3: EjectOff  - End eject sequence (no-op)
                //   0x4: DirPrev   - Set direction toward track 0 (m_dir=1)
                //   0x5: StepOff   - (not used)
                //   0x6: MotorOff  - Turn motor off
                //   0x7: EjectOn   - Start eject sequence
                //   0x9: MFMModeOn - Switch to MFM mode (1.44MB)
                //   0xC: DskchgClear - Clear disk change flag
                //   0xD: GCRModeOn - Switch to GCR mode (800K)
                case (sony_cmd_reg)
                    4'd0: begin
                        step_direction_slot[DRIVE_SELECT] <= 1'b0;  // "step dir +1" → m_dir=0
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir +1 (m_dir=0)", DRIVE_ID);
`endif
                    end

                    4'd1: begin
                        // StepOn: Execute one step using previously set direction
                        // MAME does: stp_w(0); stp_w(1); which pulses the step line
                        // Direction: m_dir=0 means toward higher tracks, m_dir=1 means toward track 0
                        if (step_direction_slot[DRIVE_SELECT] == 1'b0) begin
                            // Step toward higher tracks (inward)
                            if (head_phase < max_phase)
                                head_phase <= head_phase + 4'd4;  // 4 quarter-tracks = 1 full track
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: cmd step on (dir=+1) head_phase=%0d->%0d track=%0d->%0d",
                                     DRIVE_ID, head_phase,
                                     (head_phase < max_phase) ? head_phase + 4 : head_phase,
                                     head_phase >> 2,
                                     (head_phase < max_phase) ? (head_phase + 4) >> 2 : head_phase >> 2);
`endif
                        end else begin
                            // Step toward track 0 (outward)
                            if (head_phase >= 4'd4)
                                head_phase <= head_phase - 4'd4;
                            else
                                head_phase <= 9'd0;
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: cmd step on (dir=-1) head_phase=%0d->%0d track=%0d->%0d",
                                     DRIVE_ID, head_phase,
                                     (head_phase >= 4) ? head_phase - 4 : 0,
                                     head_phase >> 2,
                                     (head_phase >= 4) ? (head_phase - 4) >> 2 : 0);
`endif
                        end
                    end

                    4'd2: begin
                        if (DISK_MOUNTED) begin
                            sony_motor_on <= 1'b1;
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: cmd motor ON", DRIVE_ID);
`endif
                        end
                    end

                    4'd3: begin
                        // EjectOff: End eject sequence (no-op in MAME)
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd eject off (not implemented)", DRIVE_ID);
`endif
                    end

                    4'd4: begin
                        step_direction_slot[DRIVE_SELECT] <= 1'b1;  // "step dir -1" → m_dir=1
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir -1 (m_dir=1)", DRIVE_ID);
`endif
                    end

                    4'd6: begin
                        sony_motor_on <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd motor OFF", DRIVE_ID);
`endif
                    end

                    4'd7: begin
                        // EjectOn: Start eject sequence - MAME calls unload()
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd eject on (not implemented)", DRIVE_ID);
`endif
                    end

                    4'd9: begin
                        // MFMModeOn: Switch to MFM mode for 1.44MB disks
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd MFM mode on (not implemented)", DRIVE_ID);
`endif
                    end

                    4'd12: begin
                        // DskchgClear: Clear disk change flag
                        disk_switched <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd disk change clear", DRIVE_ID);
`endif
                    end

                    4'd13: begin
                        // GCRModeOn: Switch to GCR mode for 800K disks
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd GCR mode on (not implemented)", DRIVE_ID);
`endif
                    end

                    default: begin
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd %0d (unknown)", DRIVE_ID, sony_cmd_reg);
`endif
                    end
                endcase
            end
            prev_strobe_slot[DRIVE_SELECT] <= IMMEDIATE_PHASES[3];

            if (motor_spinning) begin  // Only step when motor is on
            // NOTE: 3.5" Sony drives use command-based stepping (cmd 1 = step on)
            // implemented in the sony_cmd_strobe handler above.
            // Only 5.25" drives use the traditional 4-phase stepper logic below.
            if (!IS_35_INCH) begin
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

    // Edge detection for motor-on in rotation block
    reg         prev_motor_for_position;

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
            prev_motor_for_position <= 1'b0;
            prev_track_bit_count <= 32'd0;
`ifdef SIMULATION
            side_transition_logged <= 1'b1;  // Start as logged to avoid spam at startup
            debug_read_count <= 5'd16;       // Disable log until first track change
`endif
        end else begin
            // Default: no flux transition this cycle, no rotation complete
            FLUX_TRANSITION <= 1'b0;
            SD_TRACK_STROBE <= 1'b0;
            rotation_complete <= 1'b0;

            // Don't reset bit_position when motor turns on - let the disk continue
            // from wherever it was (like a real disk). MAME calculates position from
            // elapsed time, which naturally gives varying start positions.
            // Resetting to 0 causes the first few bytes to differ because we always
            // start at the same track position.
            if (!prev_motor_for_position && motor_spinning) begin
                // Just reset the bit timer, not the position
                bit_timer <= bit_cell_cycles;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: Motor ON - keeping bit_position at %0d", DRIVE_ID, bit_position);
`endif
            end
            prev_motor_for_position <= motor_spinning;

            // Handle TRACK_BIT_COUNT changes (side selection transitions)
            // When switching sides, the new track may have fewer bits than the old one.
            // If bit_position exceeds the new track's bit count, wrap it to avoid
            // reading garbage data. This is critical for correct side selection.
            if (prev_track_bit_count != TRACK_BIT_COUNT && TRACK_BIT_COUNT > 0) begin
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: *** TRACK_BIT_COUNT CHANGED: %0d -> %0d (bit_pos=%0d, byte_idx=%0d)",
                         DRIVE_ID, prev_track_bit_count, TRACK_BIT_COUNT, bit_position, byte_index);
`endif
                // If bit_position exceeds new track size, wrap it to start of track
                // This prevents reading beyond the track's valid data
                if (bit_position >= TRACK_BIT_COUNT) begin
`ifdef SIMULATION
                    $display("FLUX_DRIVE[%0d]: *** WRAPPING bit_position %0d to 0 (new track size %0d)",
                             DRIVE_ID, bit_position, TRACK_BIT_COUNT);
`endif
                    bit_position <= 17'd0;  // Reset to start of new track
                    bit_timer <= bit_cell_cycles;  // Reset bit timer too
                end
`ifdef SIMULATION
                side_transition_logged <= 1'b0;  // Reset to allow logging of data
`endif
            end
            prev_track_bit_count <= TRACK_BIT_COUNT;

`ifdef SIMULATION
            // Log first 10 bytes after a side transition
            if (motor_spinning && TRACK_LOADED && TRACK_BIT_COUNT > 0 && !side_transition_logged) begin
                $display("FLUX_DRIVE[%0d]: Side transition data: bit_pos=%0d byte_idx=%0d BRAM_DATA=0x%02X bit_shift=%0d current_bit=%0d",
                         DRIVE_ID, bit_position, byte_index, BRAM_DATA, bit_shift, current_bit);
                if (byte_index > 10) begin
                    side_transition_logged <= 1'b1;  // Stop logging after a few samples
                end
            end
`endif

            // Only rotate when motor is spinning and track is loaded
            if (motor_spinning && TRACK_LOADED) begin
                // Generate flux in the middle of each bit cell
                // This ensures flux transitions occur well within the IWM's window
                if (bit_timer == (bit_cell_cycles >> 1)) begin
                    // Start of new bit cell - generate flux if this bit is 1
                    // IMPORTANT: Only generate FLUX_TRANSITION after drive is up to speed (drive_ready)
                    // During spinup, the IWM shouldn't receive flux transitions
                    // This matches MAME behavior where m_data stays 0x00 during spinup
                    if (current_bit && drive_ready) begin
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
                debug_read_count <= 5'd0;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: Head moved to track %0d", DRIVE_ID, head_phase[8:2]);
`endif
            end

`ifdef SIMULATION
            // Log first 16 bytes read from BRAM after track change to verify data
            if (motor_spinning && TRACK_LOADED && debug_read_count < 16) begin
                // Log when we start processing a new byte (bit_shift == 7)
                // Use bit_timer check to log only once per bit cell
                if (bit_timer == bit_cell_cycles && bit_shift == 7) begin
                    $display("FLUX_DRIVE[%0d]: BRAM[%04h] = %02h (track=%0d byte_%0d)", 
                             DRIVE_ID, BRAM_ADDR, BRAM_DATA, current_track, debug_read_count);
                    debug_read_count <= debug_read_count + 1'd1;
                end
            end
`endif
        end
    end

`ifdef SIMULATION
    // Debug output
    reg [8:0] prev_head_phase;
    reg [4:0] debug_read_count;  // Counter for track dump logging
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
