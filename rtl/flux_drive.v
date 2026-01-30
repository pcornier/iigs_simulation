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

module flux_drive #(
    parameter BRAM_LATENCY = 0  // 0 = combinational BRAM, 1 = registered BRAM
) (
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
    input  wire [4:0]  IWM_MODE,        // IWM mode bits [4:0] (for SmartPort vs 3.5" sense behavior)
    input  wire        MOTOR_ON,        // Motor enable from IWM (with spinup inertia)
    input  wire        SW_MOTOR_ON,     // Software motor on state (immediate, from $C0E9)
    input  wire        DISKREG_SEL,     // SEL line from $C031 bit 7 (for 3.5" status)
    input  wire        SEL35,           // 1 = 3.5" selected (DISK35[6]); 0 forces 3.5 motor off after timeout
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
    input  wire        TRACK_LOAD_COMPLETE, // Pulses when track finishes loading (reset bit_position)

    // BRAM interface for track bits
    output wire [15:0] BRAM_ADDR,       // Byte address in track buffer (16-bit for FLUX tracks up to 64KB)
    input  wire [7:0]  BRAM_DATA,       // Byte data from track buffer

    // WOZ v3 FLUX track support
    input  wire        IS_FLUX_TRACK,   // Current track uses flux timing data (not bitstream)
    input  wire [31:0] FLUX_DATA_SIZE,  // Size in bytes of flux timing data
    input  wire [31:0] FLUX_TOTAL_TICKS, // Sum of FLUX bytes for timing normalization

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

    // Nominal rotation period at 300 RPM (200ms) in 14MHz cycles.
    localparam [31:0] ROTATION_CYCLES_14M = 32'd2863636;

    //=========================================================================
    // Internal State
    //=========================================================================

    // Motor state
    reg         motor_spinning;         // Physical motor rotation state
    reg         prev_motor_spinning;    // For edge detection on motor state

    // Drive ready state (MAME m_ready equivalent)
    // MAME: m_ready=true means NOT ready, m_ready=false means ready (active-low)
    // After motor turns on, drive needs ~2 rotations worth of bits to become ready.
    // Using fixed bit count instead of rotation detection because rapid side switching
    // can cause spurious rotation_complete signals that make spinup too short.
    // MAME spinup is ~0.5 seconds. At 2µs/bit (28 cycles at 14MHz):
    // 0.5 sec = 7,000,000 cycles / 28 cycles/bit = 250,000 bits
    // FIX8: Increased from 170,000 (0.33 sec) to 250,000 (0.5 sec) to match MAME
    parameter SPINUP_BIT_COUNT = 250000;
    reg [17:0]  spinup_bits;            // Count bits during spin-up
    reg         drive_ready;            // True when drive is spun up and ready
    reg [5:0]   spinup_timer;           // 14MHz divider to approximate bit-cell timing for spinup
    reg         rotation_complete;      // Pulse when disk completes one rotation (for debug)

    // Head position (quarter-track)
    reg [8:0]   head_phase;             // 0-319 for 80 tracks (3.5") or 0-139 for 35 tracks (5.25")

    // Disk rotation
    reg [16:0]  bit_position;           // Current bit position within track (0 to bit_count-1)
    reg [5:0]   bit_timer;              // Countdown for bit cell timing
    reg [5:0]   bit_half_timer;         // Mid-cell timing for flux pulses
    reg [9:0]   bit_cell_frac;          // Fractional bit cell accumulator (3.5")
    reg [9:0]   bit_half_frac;          // Fractional half-cell accumulator (3.5")
    reg [5:0]   bit_cell_cycles_reg;    // Per-bit-cell length (with fractional add)

    // Track loading state
    reg [7:0]   current_track;          // Track currently in buffer
    reg         track_valid;            // Track data is valid

    // Flux generation state
    reg         prev_flux;              // Previous flux state for edge detection

    // BRAM first-read wait (only used when BRAM_LATENCY > 0)
    // After bit_position resets (track load, drive_ready), wait 1 cycle for BRAM data
    reg         bram_first_read_pending;

    // WOZ FLUX timing playback state (when IS_FLUX_TRACK=1)
    // Flux tick phase accumulator.
    // Uses total FLUX ticks per track to normalize timing to a fixed rotation period.
    reg [31:0]  flux_phase_accum;       // Phase accumulator for scaled flux timing
    reg [7:0]   flux_byte_counter;      // Current flux byte countdown (in 125ns ticks)
    reg [15:0]  flux_byte_addr;         // Current byte address in flux data
    reg [7:0]   next_flux_byte;         // Prefetched flux byte
    reg         next_byte_valid;        // Prefetched byte is valid
    reg         flux_byte_pending;      // Need to load next flux byte
    reg         flux_waiting_bram;      // Waiting for BRAM read latency
    reg         flux_is_continuation;   // Current byte was 0xFF (no transition, timing only)

    // Step direction tracking (MAME's m_dir equivalent)
    // Sony 3.5" drives use a command interface:
    //   - phases[3] = strobe (rising edge triggers command)
    //   - phases[2:0] = command code (0 = step dir +1, 4 = step dir -1)
    //   - Command 0: step toward higher tracks → m_dir = 0
    //   - Command 4: step toward track 0 → m_dir = 1
    // Track per drive slot since MAME tracks m_dir per physical drive
    reg [1:0]   step_direction_slot;    // One per drive slot (0 and 1)
    reg         prev_lstrb;             // Previous LSTRB state (global, not per-slot)
                                        // Fixes spurious strobes when DRIVE_SELECT changes

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
    reg         prev_drive_ready;  // For detecting drive_ready rising edge

    // Motor sense signal - for sense register 0x2 (MAME m_mon equivalent)
    // This follows the Sony command state, NOT the IWM motor bit
    // Decoupled from motor_spinning which controls flux generation
    wire        motor_on_sense = sony_motor_on;

    reg [3:0]   prev_imm_phases_debug;  // For tracking phase changes
    reg [31:0]  prev_track_bit_count;   // Track changes in TRACK_BIT_COUNT
    reg         side_transition_logged; // One-shot for side transition logging
    reg [4:0]   side_transition_byte_count; // Counter for post-transition byte logging

    //=========================================================================
    // Apple IIgs 3.5" drive control protocol (Clemens / ROM-confirmed)
    //=========================================================================
    // The IIgs ROM does NOT drive a 4-phase stepper for 3.5". Instead it uses the
    // IWM phase outputs as control lines (ad35driver_subroutines.asm SDCLINES):
    //   phase0 = CA0
    //   phase1 = CA1
    //   phase2 = CA2
    //   phase3 = LSTRB (strobe pulse)
    // And DISKREG_SEL ($C031 bit7) is used as the "SEL" bit in the 4-bit command/address.
    //
    // The ROM passes a 4-bit nibble in A: XXXX CA1 CA0 SEL CA2. SDCLINES drives those
    // lines, then WriteBit pulses LSTRB to latch the nibble into the drive.
    //
    // Key ROM evidence:
    // - cmd 1 is direction out, cmd 4 is step (see IIgsRomSource/Bank FF/ad35driver_subroutines.asm:1569)
    // - ReadBit uses the nibble to select which status appears on the SENSE line.
    wire ca0 = IMMEDIATE_PHASES[0];
    wire ca1 = IMMEDIATE_PHASES[1];
    wire ca2 = IMMEDIATE_PHASES[2];
    wire lstrb = IMMEDIATE_PHASES[3];
    wire [3:0] sony_ctl = {ca1, ca0, DISKREG_SEL, ca2};
    // Command decode should ignore SEL (head select) for action bits.
    // The ROM can toggle SEL while issuing commands; only CA1/CA0/CA2 define the opcode.
    wire [3:0] sony_cmd = {ca1, ca0, 1'b0, ca2};

    // Strobe fires on rising edge of LSTRB when this drive is selected.
    // CRITICAL: Use global prev_lstrb (not per-slot) to prevent spurious strobes
    // when DRIVE_SELECT changes. The ROM pulses LSTRB once per command; using
    // per-slot tracking caused the strobe to fire multiple times when switching
    // between drives (once for each drive with stale prev_strobe=0).
    wire sony_cmd_strobe = IS_35_INCH && (DRIVE_SELECT == DRIVE_SLOT) && lstrb && !prev_lstrb;

    // Immediate direction reflects a same-cycle strobe of 0/1.
    assign step_direction_immediate = (sony_cmd_strobe && sony_cmd == 4'h0) ? 1'b0 :
                                      (sony_cmd_strobe && sony_cmd == 4'h1) ? 1'b1 :
                                      step_direction_registered;

    //=========================================================================
    // Computed Values
    //=========================================================================

    wire [9:0]  max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    wire [5:0]  bit_cell_base = IS_35_INCH ? BIT_CELL_35 : BIT_CELL_525;
    wire [5:0]  bit_half_base = IS_35_INCH ? (BIT_CELL_35 >> 1) : (BIT_CELL_525 >> 1);
    // Fractional timing for 3.5" (2us bit cells @ 14.318MHz ~ 28.636 cycles).
    // Keep 3.5" at a constant 2us bit cell; rotation varies by track bit count.
    wire        use_fractional_bitcell = IS_35_INCH;
    wire [9:0]  bit_cell_step = use_fractional_bitcell ? 10'd636 : 10'd0;
    wire [9:0]  bit_half_step = use_fractional_bitcell ? 10'd318 : 10'd0;
    wire [5:0]  bit_cell_cycles = bit_cell_cycles_reg;
    // FLUX timing: Always use fixed 125ns tick rate (1.79 clocks at 14MHz).
    // WOZ FLUX format encodes real 125ns tick counts between transitions.
    // Do NOT scale based on FLUX_TOTAL_TICKS - that caused timing mismatch
    // with iwm_flux.v's fixed 28-cycle (2µs) window timing.
    // The track data may not fill a full 200ms rotation, which is fine.
    wire        flux_use_scaling = 1'b0;  // Disabled - use real 125ns timing
    wire [31:0] flux_phase_inc = 32'd1000;
    wire [31:0] flux_phase_mod = 32'd1790;
    wire [32:0] flux_phase_sum = {1'b0, flux_phase_accum} + {1'b0, flux_phase_inc};
    wire [32:0] flux_phase_diff = flux_phase_sum - {1'b0, flux_phase_mod};
    wire        flux_tick = (flux_phase_sum >= {1'b0, flux_phase_mod});
    wire [31:0] flux_phase_next = flux_tick ? flux_phase_diff[31:0] : flux_phase_sum[31:0];

    // Current byte and bit within that byte
    // Use modulo-like calculation to handle track size changes during side selection
    // When TRACK_BIT_COUNT changes (e.g., from 75215 to 62756 on side toggle),
    // bit_position may exceed the new track's size. Instead of resetting to 0
    // (which loses angular position), we use conditional subtraction to compute
    // an effective position within the new track bounds.
    //
    // This preserves angular position through rapid side toggles, matching MAME's
    // behavior where position is time-based and independent of track selection.
    wire [16:0] track_bit_count_17 = TRACK_BIT_COUNT[16:0];
    wire        pos_exceeds_1x = (bit_position >= track_bit_count_17) && (TRACK_BIT_COUNT > 0);
    wire [16:0] pos_minus_1x = bit_position - track_bit_count_17;
    wire        pos_exceeds_2x = (pos_minus_1x >= track_bit_count_17) && (TRACK_BIT_COUNT > 0);
    wire [16:0] pos_minus_2x = pos_minus_1x - track_bit_count_17;
    wire [16:0] effective_bit_position = pos_exceeds_1x ?
                                         (pos_exceeds_2x ? pos_minus_2x : pos_minus_1x) :
                                         bit_position;

    task automatic load_bit_timers;
        reg [9:0] tmp;
        reg [5:0] next_full;
        reg [5:0] next_half;
        begin
            next_full = bit_cell_base;
            tmp = bit_cell_frac + bit_cell_step;
            if (tmp >= 10'd1000) begin
                next_full = bit_cell_base + 6'd1;
                bit_cell_frac <= tmp - 10'd1000;
            end else begin
                bit_cell_frac <= tmp;
            end

            next_half = bit_half_base;
            tmp = bit_half_frac + bit_half_step;
            if (tmp >= 10'd1000) begin
                next_half = bit_half_base + 6'd1;
                bit_half_frac <= tmp - 10'd1000;
            end else begin
                bit_half_frac <= tmp;
            end

            bit_timer <= next_full;
            bit_half_timer <= next_half;
            bit_cell_cycles_reg <= next_full;
        end
    endtask

    wire [15:0] raw_byte_index = effective_bit_position[18:3];    // effective_bit_position / 8 (16-bit for large tracks)
    wire [15:0] max_byte_index = (TRACK_BIT_COUNT > 0) ? ((TRACK_BIT_COUNT - 1) >> 3) : 16'd0;
    wire [15:0] byte_index = (raw_byte_index > max_byte_index) ? max_byte_index : raw_byte_index;
    wire [2:0]  bit_shift = 3'd7 - effective_bit_position[2:0]; // MSB first (bit 7 = first bit)

    // Get current bit from BRAM data
    // BRAM has 1-cycle read latency: address at cycle N → BRAM_DATA valid at cycle N+1
    //
    // The critical timing constraint: flux is generated at bit_timer == bit_cell_cycles
    // (start of bit cell). When crossing a byte boundary, bit_position advances from 7→8
    // at the clock edge when bit_timer==1, and the NEXT cycle has bit_timer==bit_cell_cycles.
    //
    // Problem: If we set BRAM_ADDR to the new byte_index at that same cycle, BRAM_DATA
    // won't be valid until the FOLLOWING cycle - too late for the flux check!
    //
    // Solution: Look-ahead addressing. When we're on the last bit of a byte (bit_shift=0)
    // AND about to advance (bit_timer==2), switch to the next byte address early.
    // This gives BRAM one cycle to return the new data before the flux check.
    //
    // For bit_shift: use current bit_shift directly. At the flux check, bit_position has
    // already advanced so bit_shift reflects the correct bit in the new byte. The look-ahead
    // addressing ensures BRAM_DATA is the correct byte by that time.
    wire        current_bit = (BRAM_DATA >> bit_shift) & 1'b1;

    // Look-ahead logic for byte boundary crossing
    // When at bit_shift=0 (last bit of byte) and bit_timer is about to expire,
    // we need to present the NEXT byte's address so BRAM_DATA is ready at the flux check.
    //
    // Timing:
    //   bit_timer=2: Start look-ahead (present next_byte_index)
    //   bit_timer=1: HOLD look-ahead (BRAM returns next byte data)
    //   bit_timer=bit_cell_cycles (after advance): Flux check uses correct BRAM_DATA
    //
    // We must hold the look-ahead for 2 cycles (timer=2 and timer=1) because:
    // - At timer=2: We set BRAM_ADDR to next_byte_index
    // - At timer=1: BRAM_DATA becomes valid for next byte (but bit_position hasn't advanced yet)
    // - At timer=28 (after advance): bit_position advanced, flux check uses BRAM_DATA
    //
    // If we revert at timer=1, BRAM_DATA would be wrong at the flux check!
    wire        at_byte_end = (bit_shift == 3'd0);
    wire        about_to_advance = (bit_timer <= 6'd2) && (bit_timer >= 6'd1);
    wire        wrap_next_bit = (TRACK_BIT_COUNT > 0) && (effective_bit_position + 1 >= track_bit_count_17);
    wire        need_lookahead = at_byte_end && about_to_advance && motor_spinning && TRACK_LOADED;
    wire        need_wrap_prefetch = wrap_next_bit && about_to_advance && motor_spinning && TRACK_LOADED;
    wire        need_prefetch = need_lookahead || need_wrap_prefetch;
    wire [15:0] next_byte_index = (byte_index >= max_byte_index) ? 16'd0 : (byte_index + 16'd1);
    wire [15:0] prefetch_byte_index = wrap_next_bit ? 16'd0 : next_byte_index;

    // Skip position advance when TRACK_LOAD_COMPLETE, drive_ready rising edge, or motor restart occurs.
    // This prevents the timer code (which runs later in the always block) from
    // overwriting the position reset (bit_position <= 0) with bit_position + 1.
    // Motor restart: motor_spinning 0→1 while drive_ready already true (common with 3.5" drives)
    wire        drive_ready_rising = drive_ready && !prev_drive_ready && (TRACK_BIT_COUNT > 0);
    wire        motor_restart_ready = motor_spinning && !prev_motor_for_position && drive_ready && (TRACK_BIT_COUNT > 0);
    wire        track_load_reset = TRACK_LOAD_COMPLETE && !motor_spinning;
    wire        skip_position_advance = track_load_reset || drive_ready_rising || (motor_restart_ready && (BRAM_LATENCY > 0));

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign MOTOR_SPINNING = motor_spinning;
    assign DRIVE_READY = drive_ready;           // Ready after 2 rotation spinup
    assign TRACK = head_phase[8:2];             // Quarter-track to full track
    assign BIT_POSITION = bit_position;
    // BRAM address: flux mode uses flux_byte_addr (16-bit), bitstream mode uses byte_index with look-ahead
    assign BRAM_ADDR = IS_FLUX_TRACK ? flux_byte_addr :
                       (need_prefetch ? prefetch_byte_index : byte_index);
    assign WRITE_PROTECT = DISK_WP;

    //=========================================================================
    // Status Sensing (3.5" drives)
    //=========================================================================
    // For 3.5" drives, the IIgs ROM uses the IWM phase outputs as control lines
    // (CA0/CA1/CA2 + SEL) and reads the SENSE line based on the selected nibble.
    // See IIgsRomSource/Bank FF/ad35driver_subroutines.asm (ReadBit/WriteBit):
    //   A nibble format: XXXX CA1 CA0 SEL CA2
    //
    // For 5.25" drives, SENSE is just the write-protect input.
    // For 3.5" drives, the Sony protocol uses nibble order:
    //   {CA1, CA0, SEL, CA2}
    // We latch {CA2, CA1, CA0} in LATCHED_SENSE_REG[2:0], so reorder here.
    wire [3:0] status_reg = {LATCHED_SENSE_REG[1], LATCHED_SENSE_REG[0],
                             DISKREG_SEL, LATCHED_SENSE_REG[2]};
    wire       at_track0 = (head_phase[8:2] == 7'd0);

    // Disk stepping status used by STAT35 ($04).
    // Apple docs: step one track takes ~12ms; bit is 0 while stepping, 1 when idle.
    localparam [17:0] STEP_BUSY_CYCLES = 18'd168000; // ~12ms at 14MHz
    reg [17:0] step_busy_cnt;
    wire      step_busy = (step_busy_cnt != 18'd0);

    // 3.5" status sensing (IIgs ROM protocol; many signals are active-low)
    // In SmartPort/C-Bus mode the ROM reads the IWM status sense bit as /BSY and
    // will wait forever for it to go high in `smartdrvr.asm` (RDH0) if we hold it low.
    // Mode bit 3 selects bit-cell width (1=2us 3.5" disk, 0=4us SmartPort/5.25").
    // Mode bit 1 selects async handshake (used by SmartPort devices).
    //
    // For now, keep /BSY deasserted (high) in SmartPort mode to avoid the hang.
    // Proper C-Bus device emulation belongs above the flux-level drive model.
    wire smartport_mode = (!IWM_MODE[3]) && IWM_MODE[1];
    reg sense_35;
    always @(*) begin
        if (smartport_mode) begin
            sense_35 = 1'b1;
        end else begin
        case (status_reg)
            4'h0: sense_35 = step_direction_immediate;  // Dir readback (IS35DRIVE)
            4'h1: sense_35 = step_direction_immediate;  // Dir readback (paired test)
            4'h2: sense_35 = ~DISK_MOUNTED;             // /DIP: 0=disk present, 1=no disk
            4'h4: sense_35 = ~step_busy;                // Disk stepping (0=stepping, 1=idle)
            4'h8: sense_35 = ~motor_on_sense;           // /MOTOR: 0=on, 1=off
            4'hA: sense_35 = ~at_track0;                // /TK0: 0=at track0, 1=not track0
            4'hB: sense_35 = ~drive_ready;              // /READY: 0=ready, 1=not ready
            // Disk switched (/eject) status: ROM/driver treats SENSE high as "disk switched/ejected".
            // See `IIgsRomSource/GSOS/Drivers/AD3.5.drivsubs.asm`:
            // - `read_bit` returns C=1 when SENSE is high
            // - `Enable_Sense` sets drv_sts bit7 when SENSE is high (dsw true)
            // - `read_dsw_status` branches on BCC (SENSE low) as "no eject/dsw"
            4'hC: sense_35 = disk_switched;
            4'h9: sense_35 = 1'b1;                      // Default-high for unused reads
            4'hD: sense_35 = 1'b1;                      // Default-high for unused reads
            4'hE: sense_35 = ~drive_ready;              // Treat as /READY as well (safe)
            4'hF: sense_35 = 1'b1;
            4'h3: sense_35 = 1'b1;
            4'h5: sense_35 = 1'b1;
            4'h6: sense_35 = 1'b1;
            4'h7: sense_35 = 1'b1;
        endcase
        end
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
            $display("FLUX_DRIVE: sense=%0d status_reg=%h (sony_ctl=%01x SEL35=%0d phases=%04b) at_track0=%0d motor_spin=%0d mounted=%0d",
                     sense_35, status_reg, sony_ctl, SEL35, PHASES, at_track0, motor_spinning, DISK_MOUNTED);
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
            prev_lstrb <= 1'b0;            // No strobe active initially
            sony_motor_on <= 1'b0;         // Default: motor off
            disk_switched <= 1'b1;         // Assume disk switched on reset
            prev_disk_mounted <= 1'b0;
            step_busy_cnt <= 18'd0;
        end else begin
            if (step_busy_cnt != 18'd0)
                step_busy_cnt <= step_busy_cnt - 18'd1;

            // NOTE: The ROM routinely clears $C031 (including 35SEL) at command boundaries.
            // Do not forcibly clear the Sony motor command immediately when SEL35 deasserts,
            // or we can lose the spindle state across brief deselect windows and fail boot.

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
            // Apple IIgs 3.5" drive command interface (ROM SDCLINES + LSTRB pulse).
`ifdef SIMULATION
            // Debug: trace strobe conditions
            if (IS_35_INCH && lstrb && !prev_lstrb) begin
                $display("FLUX_DRIVE[%0d]: LSTRB! DRIVE_SELECT=%0d DRIVE_SLOT=%0d sel_match=%0d sony_ctl=%01x DISK_MOUNTED=%0d SEL35=%0d",
                         DRIVE_ID, DRIVE_SELECT, DRIVE_SLOT, (DRIVE_SELECT == DRIVE_SLOT), sony_ctl, DISK_MOUNTED, SEL35);
            end
`endif
            if (sony_cmd_strobe) begin
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: sony_cmd_strobe! sony_ctl=%01x SEL35=%0d DISK_MOUNTED=%0d",
                         DRIVE_ID, sony_ctl, SEL35, DISK_MOUNTED);
`endif
                case (sony_cmd)
                    4'h0: begin
                        // Direction inward (toward higher tracks) - ROM dirinadr=0
                        step_direction_slot[DRIVE_SELECT] <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir +1 (toward higher tracks) t=%0t", DRIVE_ID, $time);
`endif
                    end

                    4'h1: begin
                        // Direction outward (toward track 0) - ROM diroutadr=1
                        step_direction_slot[DRIVE_SELECT] <= 1'b1;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd step dir -1 (toward track 0) t=%0t", DRIVE_ID, $time);
`endif
                    end

                    4'h4: begin
                        // Step one track - ROM step0adr=4 (see SENDSTEPS)
                        // Ignore SEL35 deassertions; the ROM clears $C031 between commands.
                        if (DISK_MOUNTED) begin
                            if (step_direction_slot[DRIVE_SELECT] == 1'b0) begin
                                if (head_phase < max_phase)
                                    head_phase <= head_phase + 9'd4;
                            end else begin
                                if (head_phase >= 9'd4)
                                    head_phase <= head_phase - 9'd4;
                                else
                                    head_phase <= 9'd0;
                            end
                        end
                        // Indicate head is stepping; ROM polls STAT35 $04 until it returns high.
                        step_busy_cnt <= STEP_BUSY_CYCLES;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd STEP (dir=%0d head_phase=%0d)", DRIVE_ID, step_direction_slot[DRIVE_SELECT], head_phase);
`endif
                    end

                    4'h8: begin
                        // Motor on - ROM mtronadr=8
                        // Ignore SEL35 deassertions; the ROM clears $C031 between commands.
                        if (DISK_MOUNTED) begin
                            sony_motor_on <= 1'b1;
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: cmd motor ON (SEL35=%0d DISK_MOUNTED=%0d) -> sony_motor_on=1", DRIVE_ID, SEL35, DISK_MOUNTED);
`endif
                        end
`ifdef SIMULATION
                        else begin
                            $display("FLUX_DRIVE[%0d]: cmd motor ON SKIPPED (SEL35=%0d DISK_MOUNTED=%0d)", DRIVE_ID, SEL35, DISK_MOUNTED);
                        end
`endif
                    end

                    4'h9: begin
                        // Motor off - ROM mtroffadr=9
                        sony_motor_on <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd motor OFF", DRIVE_ID);
`endif
                    end

                    4'hC: begin
                        // Disk-change clear (ROM uses DskchgClear via ReadBit/WriteBit)
                        disk_switched <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd disk change clear", DRIVE_ID);
`endif
                    end

                    default: begin
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: cmd %01x (unhandled)", DRIVE_ID, sony_ctl);
`endif
                    end
                endcase
                // SEL-bearing variants that use the same CA opcode but different SEL bit.
                if (sony_ctl == 4'h3) begin
                    // Eject reset / disk-switched clear used during CONFIGURE (ejct_reset=3)
                    disk_switched <= 1'b0;
`ifdef SIMULATION
                    $display("FLUX_DRIVE[%0d]: cmd eject reset (disk change clear)", DRIVE_ID);
`endif
                end
                if (sony_ctl == 4'h7) begin
                    // Start eject: treat as disk removed (best-effort)
                    // Real hardware would unload; in sim we don't hot-unmount here.
`ifdef SIMULATION
                    $display("FLUX_DRIVE[%0d]: cmd eject on (not implemented)", DRIVE_ID);
`endif
                end
            end
            prev_lstrb <= lstrb;

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
            spinup_bits <= 18'd0;
            drive_ready <= 1'b0;
            spinup_timer <= BIT_CELL_35;
        end else begin
            prev_motor_spinning <= motor_spinning;

            if (IS_35_INCH) begin
                // 3.5" Sony drives: motor_spinning controls flux generation
                // IIgs ROM controls motor via the 0x8/0x9 LSTRB command.
                // Note: SEL35 (DISK35[6]) is a selection/control line used by the ROM at
                // command boundaries. The physical spindle keeps rotating based on the
                // Sony motor command; do not gate rotation on SEL35 or we will "freeze"
                // angular position during deselect windows and break subsequent prologue scans.
                motor_spinning <= sony_motor_on && DISK_MOUNTED;
`ifdef SIMULATION
                if ((sony_motor_on && DISK_MOUNTED) != motor_spinning) begin
                    $display("FLUX_DRIVE[%0d]: motor_spinning %0d -> %0d (sony_motor_on=%0d DISK_MOUNTED=%0d)",
                             DRIVE_ID, motor_spinning, (sony_motor_on && DISK_MOUNTED), sony_motor_on, DISK_MOUNTED);
                end
`endif
            end else begin
                // 5.25" drives: controlled by IWM enable line + inertia (handled in iwm_woz)
                motor_spinning <= MOTOR_ON;
            end

            // Drive ready logic - bit-count based spinup
            // Using fixed bit count (SPINUP_BIT_COUNT = ~2 rotations) instead of
            // rotation detection because rapid side switching during ROM drive
            // detection causes spurious rotation_complete signals.
            if (!prev_motor_spinning && motor_spinning && DISK_MOUNTED) begin
                // Motor just turned ON with disk mounted - start spin-up
                spinup_bits <= 18'd0;
                drive_ready <= 1'b0;
                spinup_timer <= bit_cell_cycles;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: Motor ON - starting spin-up (need %0d bits)", DRIVE_ID, SPINUP_BIT_COUNT);
`endif
            end else if (!motor_spinning) begin
                // Motor not spinning.
                //
                // For 5.25" drives, this means the motor is actually off, so we must clear ready.
                //
                // For 3.5" Sony drives, `motor_spinning` is gated by SEL35 (3.5" enable). The ROM
                // routinely deasserts SEL35 at command boundaries, which would otherwise clear
                // drive_ready and force the ROM into long /READY polling loops. Real hardware keeps
                // the spindle spinning (inertia) and the drive electronics remain ready across brief
                // deselect windows; treat the Sony motor command as the authoritative "spindle on".
                if (!IS_35_INCH) begin
                    drive_ready <= 1'b0;
                    spinup_bits <= 18'd0;
                    spinup_timer <= bit_cell_cycles;
                end else if (!sony_motor_on || !DISK_MOUNTED) begin
                    drive_ready <= 1'b0;
                    spinup_bits <= 18'd0;
                    spinup_timer <= bit_cell_cycles;
                end
            end

            // Spin-up timing should not depend on track data being loaded: /READY is a physical-drive
            // signal that the ROM polls before/while track data is being streamed.
            if (motor_spinning && !drive_ready && DISK_MOUNTED) begin
                if (spinup_timer == 6'd1) begin
                    spinup_timer <= bit_cell_cycles;
                    if (spinup_bits < SPINUP_BIT_COUNT) begin
                        spinup_bits <= spinup_bits + 1'd1;
                        if (spinup_bits + 1 >= SPINUP_BIT_COUNT) begin
                            drive_ready <= 1'b1;
`ifdef SIMULATION
                            $display("FLUX_DRIVE[%0d]: Drive ready after %0d bits spinup (needed %0d)",
                                     DRIVE_ID, spinup_bits + 1, SPINUP_BIT_COUNT);
`endif
                        end
                    end
                end else begin
                    spinup_timer <= spinup_timer - 1'd1;
                end
            end else begin
                spinup_timer <= bit_cell_cycles;
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
            bit_timer <= bit_cell_base;  // Start at full bit cell time
            bit_half_timer <= bit_half_base;
            bit_cell_cycles_reg <= bit_cell_base;
            bit_cell_frac <= 10'd0;
            bit_half_frac <= 10'd0;
            FLUX_TRANSITION <= 1'b0;
            prev_flux <= 1'b0;
            SD_TRACK_REQ <= 8'd0;
            SD_TRACK_STROBE <= 1'b0;
            current_track <= 8'd0;
            track_valid <= 1'b0;
            rotation_complete <= 1'b0;
            prev_motor_for_position <= 1'b0;
            prev_drive_ready <= 1'b0;
            prev_track_bit_count <= 32'd0;
            // Flux timing playback state
            flux_phase_accum <= 32'd0;
            flux_byte_counter <= 8'd0;
            flux_byte_addr <= 16'd0;
            flux_byte_pending <= 1'b1;  // Need to load first byte
            flux_waiting_bram <= 1'b0;
            flux_is_continuation <= 1'b0;
            next_flux_byte <= 8'd0;
            next_byte_valid <= 1'b0;
            bram_first_read_pending <= (BRAM_LATENCY > 0) ? 1'b1 : 1'b0;  // Wait for BRAM on startup
`ifdef SIMULATION
            side_transition_logged <= 1'b1;  // Start as logged to avoid spam at startup
            debug_read_count <= 5'd16;       // Disable log until first track change
            side_transition_byte_count <= 5'd16;  // Start above threshold to avoid spam
`endif
        end else begin
            // Default: no flux transition this cycle, no rotation complete
            FLUX_TRANSITION <= 1'b0;
            SD_TRACK_STROBE <= 1'b0;
            rotation_complete <= 1'b0;

            // Reset bit_position when track load completes while stopped.
            // Avoid mid-rotation jumps that would desync the bitstream from flux timing.
            //
            // NOTE: For FPGA BRAM with 1-cycle read latency, we start bit_timer at bit_cell_cycles-1
            // to give BRAM one cycle to load the new track's first byte before flux checks.
            if (track_load_reset) begin
                bit_position <= 17'd0;
                bit_timer <= bit_cell_base;  // Full bit cell time
                bit_half_timer <= bit_half_base;
                bit_cell_cycles_reg <= bit_cell_base;
                bit_cell_cycles_reg <= bit_cell_base;
                bit_cell_cycles_reg <= bit_cell_base;
                bit_cell_frac <= 10'd0;
                bit_half_frac <= 10'd0;
                // skip_position_advance wire handles this automatically
                // For BRAM_LATENCY > 0, wait 1 cycle for BRAM data before first flux check
                if (BRAM_LATENCY > 0) bram_first_read_pending <= 1'b1;
                // Reset flux playback state for new track
                flux_phase_accum <= 32'd0;
                flux_byte_counter <= 8'd0;
                flux_byte_addr <= 16'd0;
                flux_byte_pending <= 1'b1;  // Need to load first byte
                flux_waiting_bram <= 1'b0;
                flux_is_continuation <= 1'b0;
                next_byte_valid <= 1'b0;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: TRACK_LOAD_COMPLETE - resetting bit_position to 0 (was %0d) is_flux=%0d BRAM_LAT=%0d", DRIVE_ID, bit_position, IS_FLUX_TRACK, BRAM_LATENCY);
                if (BRAM_LATENCY > 0) begin
                    $display("FLUX_DRIVE[%0d]: TRACK_LOAD_COMPLETE bram_wait=1 bit_timer=%0d cell=%0d addr=%0d pos=%0d",
                             DRIVE_ID, bit_timer, bit_cell_cycles, BRAM_ADDR, bit_position);
                end
`endif
            end
`ifdef SIMULATION
            if (TRACK_LOAD_COMPLETE && motor_spinning) begin
                $display("FLUX_DRIVE[%0d]: TRACK_LOAD_COMPLETE ignored while spinning (pos=%0d)",
                         DRIVE_ID, bit_position);
            end
`endif

            // Reset bit_position when drive becomes ready (after spinup completes)
            // This ensures the decoder starts at a known position when the state machine activates.
            // Without this reset, bit_position accumulates during spinup (~170000 bits) and the
            // decoder starts mid-track, never seeing the D5 AA prologue markers at the track start.
            //
            // NOTE: For FPGA BRAM with 1-cycle read latency, we start bit_timer at bit_cell_cycles-1
            // instead of bit_cell_cycles. This gives BRAM one cycle to load the initial byte before
            // the first flux check (which happens when bit_timer == bit_cell_cycles).
            //
            // MOTOR RESTART HANDLING (BRAM_LATENCY > 0):
            // When motor_spinning restarts (0→1) while drive_ready is ALREADY true (common with
            // 3.5" drives during GS/OS loading due to SEL35 toggling), we need to wait for
            // fresh BRAM data. The first flux check after restart would otherwise use stale data.
            if (drive_ready && !prev_drive_ready && TRACK_BIT_COUNT > 0) begin
                bit_position <= 17'd0;
                bit_timer <= bit_cell_base;  // Full bit cell time
                bit_half_timer <= bit_half_base;
                bit_cell_frac <= 10'd0;
                bit_half_frac <= 10'd0;
                // skip_position_advance wire handles this automatically
                // For BRAM_LATENCY > 0, wait 1 cycle for BRAM data before first flux check
                if (BRAM_LATENCY > 0) bram_first_read_pending <= 1'b1;
                // Also reset flux playback state
                flux_phase_accum <= 32'd0;
                flux_byte_counter <= 8'd0;
                flux_byte_addr <= 16'd0;
                flux_byte_pending <= 1'b1;
                flux_waiting_bram <= 1'b0;
                flux_is_continuation <= 1'b0;
                next_byte_valid <= 1'b0;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: DRIVE_READY rising edge - resetting bit_position to 0 (was %0d) BRAM_LAT=%0d", DRIVE_ID, bit_position, BRAM_LATENCY);
                if (BRAM_LATENCY > 0) begin
                    $display("FLUX_DRIVE[%0d]: DRIVE_READY bram_wait=1 bit_timer=%0d cell=%0d addr=%0d pos=%0d",
                             DRIVE_ID, bit_timer, bit_cell_cycles, BRAM_ADDR, bit_position);
                end
`endif
            end
            prev_drive_ready <= drive_ready;

            // Track motor state transitions
            // MOTOR RESTART WITH DRIVE ALREADY READY (BRAM_LATENCY handling):
            // When motor_spinning goes 0→1 while drive_ready is already true (common with 3.5"
            // drives due to SEL35 toggling), we need to wait for fresh BRAM data. Without this,
            // the first flux check after motor restart uses stale BRAM data from the old address.
            if (motor_spinning && !prev_motor_for_position && drive_ready && TRACK_BIT_COUNT > 0) begin
                if (BRAM_LATENCY > 0) bram_first_read_pending <= 1'b1;
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: MOTOR_RESTART while drive_ready - waiting for BRAM (addr=%0d) BRAM_LAT=%0d",
                         DRIVE_ID, BRAM_ADDR, BRAM_LATENCY);
                if (BRAM_LATENCY > 0) begin
                    $display("FLUX_DRIVE[%0d]: MOTOR_RESTART bram_wait=1 bit_timer=%0d cell=%0d pos=%0d",
                             DRIVE_ID, bit_timer, bit_cell_cycles, bit_position);
                end
`endif
            end
            prev_motor_for_position <= motor_spinning;

            // Handle TRACK_BIT_COUNT changes (side selection transitions)
            // When switching sides, the new track may have different bit count.
            // We NO LONGER reset bit_position to 0 here - instead, the combinational
            // effective_bit_position logic computes a valid position using modulo.
            // This preserves angular position through rapid side toggles.
            if (prev_track_bit_count != TRACK_BIT_COUNT && TRACK_BIT_COUNT > 0) begin
`ifdef SIMULATION
                $display("FLUX_DRIVE[%0d]: *** TRACK_BIT_COUNT CHANGED: %0d -> %0d (bit_pos=%0d, eff_pos=%0d, byte_idx=%0d, head_phase=%0d, track=%0d)",
                         DRIVE_ID, prev_track_bit_count, TRACK_BIT_COUNT, bit_position, effective_bit_position, byte_index, head_phase, head_phase[8:2]);
                $display("FLUX_DRIVE[%0d]: *** TRACK_TRANSITION: BRAM_ADDR=%0d BRAM_DATA=0x%02X current_bit=%0d motor_spin=%0d drive_ready=%0d",
                         DRIVE_ID, BRAM_ADDR, BRAM_DATA, current_bit, motor_spinning, drive_ready);
                // No longer wrapping - effective_bit_position handles overflow via modulo
                side_transition_logged <= 1'b0;  // Reset to allow logging of data
                side_transition_byte_count <= 5'd0;  // Reset byte counter for post-transition logging
`endif
            end
            prev_track_bit_count <= TRACK_BIT_COUNT;

`ifdef SIMULATION
            // Log first 16 bytes after a side transition to verify data
            if (motor_spinning && TRACK_LOADED && TRACK_BIT_COUNT > 0 && side_transition_byte_count < 16) begin
                // Log once per byte boundary (when starting a new byte)
                if (effective_bit_position[2:0] == 3'd0 && bit_timer == bit_cell_cycles) begin
                    $display("FLUX_DRIVE[%0d]: SIDE_DATA[%0d]: byte_idx=%0d BRAM_DATA=0x%02X eff_pos=%0d raw_pos=%0d",
                             DRIVE_ID, side_transition_byte_count, byte_index, BRAM_DATA, effective_bit_position, bit_position);
                    side_transition_byte_count <= side_transition_byte_count + 1'd1;
                end
            end

            // Focused debug around suspected divergence position.
            if (motor_spinning && TRACK_LOADED &&
                (bit_position >= 17'd70190) && (bit_position <= 17'd70230)) begin
                $display("FLUX_DRIVE_WIN pos=%0d addr=%0d data=%02h shift=%0d bit=%0d timer=%0d",
                         bit_position, BRAM_ADDR, BRAM_DATA, bit_position[2:0], current_bit, bit_timer);
            end

            // Debug divergence point at position ~55883
            if (motor_spinning && TRACK_LOADED &&
                (bit_position >= 17'd70190) && (bit_position <= 17'd70230)) begin
                $display("FLUX_DIV pos=%0d eff_pos=%0d addr=%0d data=%02h TBC=%0d shift=%0d bit=%0d timer=%0d",
                         bit_position, effective_bit_position, BRAM_ADDR, BRAM_DATA,
                         TRACK_BIT_COUNT, bit_shift, current_bit, bit_timer);
            end
`endif

            // Rotate whenever motor is spinning so angular position keeps advancing
            if (motor_spinning) begin
`ifdef SIMULATION
                if (BRAM_LATENCY > 0 && (TRACK_LOAD_COMPLETE || drive_ready_rising || motor_restart_ready)) begin
                    $display("FLUX_DRIVE[%0d]: SKIP_ADVANCE reason=%0d%0d%0d timer=%0d pos=%0d eff=%0d addr=%0d",
                             DRIVE_ID, TRACK_LOAD_COMPLETE, drive_ready_rising, motor_restart_ready,
                             bit_timer, bit_position, effective_bit_position, BRAM_ADDR);
                end
`endif
                if (IS_FLUX_TRACK && TRACK_LOADED) begin
                    //=================================================================
                    // FLUX TIMING PLAYBACK MODE
                    //=================================================================
                    // Each flux byte = number of 125ns ticks until next transition
                    // Phase accumulator: 125ns / 69.84ns = 1.79 clocks per tick
                    // Using 1790/1000 ratio for ~0.01% error
                    //
                    // Algorithm:
                    // 1. Each CLK_14M: accumulator += 1000
                    // 2. When accumulator >= 1790: subtract 1790, decrement flux_byte_counter
                    // 3. When counter reaches 0:
                    //    - If byte was != 0xFF: output FLUX_TRANSITION
                    //    - Load next byte from BRAM (with 1-cycle latency handling)
                    // 4. Handle 0xFF: no transition, just add 255 ticks (timing extension)

                    // Handle BRAM read latency - after requesting a byte, wait one cycle
                    if (flux_waiting_bram) begin
                        // BRAM data is now valid
                        flux_waiting_bram <= 1'b0;
                        
                        if (flux_byte_pending) begin
                            // This was the initial load (first byte)
                            flux_byte_counter <= BRAM_DATA;
                            flux_byte_pending <= 1'b0;
                            flux_is_continuation <= (BRAM_DATA == 8'hFF);
                        end else begin
                            // This was a prefetch
                            next_flux_byte <= BRAM_DATA;
                            next_byte_valid <= 1'b1;
                        end

`ifdef SIMULATION
                        if (flux_byte_addr < 20 || (flux_byte_addr >= 95 && flux_byte_addr <= 105) || (flux_byte_addr >= FLUX_DATA_SIZE - 5)) begin
                            $display("FLUX_PLAY[%0d]: Loaded byte[%0d] = %0d (0x%02X) cont=%0d pending=%0d",
                                     DRIVE_ID, flux_byte_addr, BRAM_DATA, BRAM_DATA, (BRAM_DATA == 8'hFF), flux_byte_pending);
                        end
`endif
                        // Advance address for next read
                        if (flux_byte_addr + 1 >= FLUX_DATA_SIZE) begin
                            flux_byte_addr <= 16'd0;  // Wrap to start of track
                            rotation_complete <= 1'b1;
                        end else begin
                            flux_byte_addr <= flux_byte_addr + 1'd1;
                        end
                    end else if (flux_byte_pending) begin
                        // Request first byte from BRAM (initial state)
                        flux_waiting_bram <= 1'b1;
                    end else begin
                    // Normal flux timing: run phase accumulator (normalized to rotation period).
                    // If FLUX_TOTAL_TICKS is unavailable, fall back to fixed 125ns timing.
                    if (flux_tick) begin
                        flux_phase_accum <= flux_phase_next;

                        if (flux_byte_counter > 8'd1) begin
                            // Still counting down
                            flux_byte_counter <= flux_byte_counter - 8'd1;
                            
                            // PREFETCH LOGIC: If counter is low, request next byte now
                            if (flux_byte_counter <= 8'd3 && !next_byte_valid && !flux_waiting_bram) begin
                                flux_waiting_bram <= 1'b1;
                            end
                        end else if (flux_byte_counter <= 8'd1) begin
                            // Counter expired - generate transition if not a continuation byte
                            if (!flux_is_continuation && drive_ready) begin
                                FLUX_TRANSITION <= 1'b1;
`ifdef SIMULATION
                                    if (flux_count_debug < 110) begin
                                        $display("FLUX_PLAY[%0d]: Transition #%0d cycle=%0d byte_addr=%0d",
                                                 DRIVE_ID, flux_count_debug, cycle_count_debug, flux_byte_addr - 1);
                                    end
`endif
                                end
                                
                                // Load next byte from prefetch buffer
                                if (next_byte_valid) begin
                                    flux_byte_counter <= next_flux_byte;
                                    flux_is_continuation <= (next_flux_byte == 8'hFF);
                                    next_byte_valid <= 1'b0;
                                    // Trigger immediate fetch for NEXT byte if the loaded one is small
                                    if (next_flux_byte <= 8'd3) begin
                                        flux_waiting_bram <= 1'b1;
                                    end
                                end else begin
                                    // UNDERFLOW - Prefetch didn't finish in time (or initial)
                                    // Stall and wait for BRAM (via flux_byte_pending logic above)
                                    // But flux_byte_pending triggers a wait state which stops accumulator
                                    // Here we just want to fetch.
                                    // If we are here, next_byte_valid is false.
                                    // Check if a fetch is already in progress
                                    if (flux_waiting_bram) begin
                                        // Fetch is in progress, we must wait (STALL)
                                        // Ideally we shouldn't stall, but if we have 0-byte, we must.
                                        // For now, allow stall if we missed deadline.
                                        flux_byte_pending <= 1'b1; // Fall back to stall logic
`ifdef SIMULATION
                                        $display("FLUX_PLAY[%0d]: UNDERFLOW/STALL at byte_addr=%0d", DRIVE_ID, flux_byte_addr);
`endif
                                    end else begin
                                        // No fetch in progress? Request one immediately.
                                        // This implies we missed the prefetch window.
                                        flux_byte_pending <= 1'b1;
                                        flux_waiting_bram <= 1'b1;
                                    end
                                end
                        end
                    end else begin
                        flux_phase_accum <= flux_phase_next;
                        
                        // Opportunity to start prefetch during non-tick cycles
                        if (!next_byte_valid && !flux_waiting_bram && !flux_byte_pending) begin
                            flux_waiting_bram <= 1'b1;
                            end
                        end
                    end

                    // Track bit position in FLUX mode using same bit_timer mechanism as bitstream mode.
                    // This ensures DISK_BIT_POSITION advances at the expected rate for IWM timing.
                    // skip_position_advance prevents this code from overwriting position resets
                    if (bit_timer == 6'd1 && !skip_position_advance) begin
                        load_bit_timers();
                        // Advance bit position with wraparound
                        if (TRACK_BIT_COUNT > 0) begin
                            if (effective_bit_position + 1 >= track_bit_count_17) begin
                                bit_position <= 17'd0;
                            end else begin
                                bit_position <= bit_position + 1'd1;
                            end
                        end else begin
                            bit_position <= bit_position + 1'd1;
                        end
                    end else if (!skip_position_advance) begin
                        bit_timer <= bit_timer - 1'd1;
                    end

                end else if (!IS_FLUX_TRACK) begin
                    //=================================================================
                    // BITSTREAM PLAYBACK MODE (original code)
                    //=================================================================
                    // Generate flux pulse.
                    // The WOZ bitstream encodes flux transitions as 1-bits in fixed bit cells.
                    //
                    // Emit transitions near the mid-cell point (MAME: i*2+1).
                    // Bit cell timing is scaled to the track length to keep rotation time constant.
                    //
                    // BRAM LATENCY HANDLING:
                    // With registered BRAM (BRAM_LATENCY > 0), we need to wait 1 cycle after any
                    // bit_position reset for BRAM_DATA to become valid. This wait is ONLY needed
                    // when BRAM_LATENCY > 0; with combinational BRAM, data is immediately valid.
                    if (bram_first_read_pending) begin
                        // BRAM wait cycle: stall rotation for one 14M tick so we don't drop a bit.
                        // With BRAM_LATENCY > 0, data isn't valid this cycle.
                        bram_first_read_pending <= 1'b0;
`ifdef SIMULATION
                        $display("FLUX_DRIVE[%0d]: BRAM first read wait - stalling (addr=%0d pos=%0d)",
                                 DRIVE_ID, BRAM_ADDR, bit_position);
`endif
                    end else if (bit_timer == bit_half_timer) begin
                        // Generate flux near mid-cell using the current cell timing.
                        // IMPORTANT: Only generate FLUX_TRANSITION after drive is up to speed (drive_ready)
                        // During spinup, the IWM shouldn't receive flux transitions
                        // This matches MAME behavior where m_data stays 0x00 during spinup
                        if (TRACK_LOADED && (TRACK_BIT_COUNT > 0) && current_bit && drive_ready) begin
                            FLUX_TRANSITION <= 1'b1;
`ifdef SIMULATION
                            if (flux_count_debug < 50) begin
                                $display("FLUX[%0d] #%0d: pos=%0d addr=%0d data=%02X shift=%0d bit=%0d timer=%0d",
                                         DRIVE_ID, flux_count_debug, bit_position, BRAM_ADDR, BRAM_DATA, bit_shift, current_bit, bit_timer);
                            end
                            if (effective_bit_position < 100) begin
                                $display("FLUX_DRIVE[%0d]: Flux transition at bit %0d (eff=%0d, byte %04h, shift %0d)",
                                         DRIVE_ID, bit_position, effective_bit_position, byte_index, bit_shift);
                            end
`endif
                        end
                    end

                    // Timer operations: position advances at a constant rate, independent of BRAM waits.
                    // The disk rotates continuously; bram_first_read_pending only skips flux check,
                    // not position tracking. This keeps the simulated disk synchronized with real timing.
                    // skip_position_advance is set when TRACK_LOAD_COMPLETE or drive_ready resets position.
                    if (!bram_first_read_pending) begin
                        if (bit_timer == 6'd1 && !skip_position_advance) begin
                        // End of bit cell - advance to next bit
                        load_bit_timers();

                        // Advance bit position with wraparound
                        // Use effective_bit_position for wrap check to handle side toggles correctly.
                        // We wrap when the effective position completes a track, not raw position.
                        if (TRACK_BIT_COUNT > 0) begin
                            if (effective_bit_position + 1 >= track_bit_count_17) begin
                                // Wrap: set bit_position to where effective_position would wrap to
                                // This handles cases where bit_position > TRACK_BIT_COUNT
                                bit_position <= 17'd0;
                                // Signal that one full rotation has completed
                                rotation_complete <= 1'b1;
                            end else begin
                                bit_position <= bit_position + 1'd1;
                            end
                        end else begin
                            // No track loaded yet; keep angular position advancing.
                            bit_position <= bit_position + 1'd1;
                        end

                        end else if (!skip_position_advance) begin
                        // Still in current bit cell
                        bit_timer <= bit_timer - 1'd1;
                        end
                    end
                end
            end else begin
                // Motor not spinning or track not loaded - reset timer
                bit_timer <= bit_cell_base;
                bit_half_timer <= bit_half_base;
                bit_cell_cycles_reg <= bit_cell_base;
                bit_cell_frac <= 10'd0;
                bit_half_frac <= 10'd0;
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

    reg [4:0] debug_read_count;  // Counter for track dump logging
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
                if (flux_count_debug < 2000000 && head_phase == 0) begin
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
            $display("FLUX_DRIVE[%0d]: Phase %0d -> %0d (track %0d -> %0d) TRACK_OUTPUT=%0d",
                     DRIVE_ID, prev_head_phase, head_phase,
                     prev_head_phase[8:2], head_phase[8:2], TRACK);
        end
        prev_head_phase <= head_phase;
    end
`endif

endmodule
