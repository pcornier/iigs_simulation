//
// iwm_woz.v: IWM Controller with WOZ/Flux Interface
//
// This module is the SINGLE SOURCE OF TRUTH for all IWM soft switch state.
// It integrates:
// - Soft switch handling (phases, motor, Q6, Q7, mode register)
// - flux_drive.v instances (per-drive state and flux generation)
// - iwm_flux.v (flux decoding and register read logic)
//
// Interface is compatible with iwm_controller.v for easy substitution in iigs.sv
//

module iwm_woz (
    // Global signals
    input           CLK_14M,
    input           CLK_7M_EN,
    input           Q3,
    input           PH0,
    input           PH2,
    input           RESET,

    // CPU bus interface
    input           IO_SELECT,
    input           DEVICE_SELECT,
    input           WR_CYCLE,        // 0=write cycle, 1=read cycle
    input           VDA,
    input  [15:0]   A,
    input  [7:0]    D_IN,
    output [7:0]    D_OUT,

    // Drive status
    input  [3:0]    DISK_READY,      // Per-drive ready status from SD block

    // External control/status
    input  [7:0]    DISK35,          // $C031 disk register
    input           WRITE_PROTECT,

    // WOZ Track bit interface for 3.5" drive 1 (directly to sim.v)
    output [7:0]    WOZ_TRACK3,
    output [13:0]   WOZ_TRACK3_BIT_ADDR,
    input  [7:0]    WOZ_TRACK3_BIT_DATA,
    input  [31:0]   WOZ_TRACK3_BIT_COUNT,

    // WOZ Track bit interface for 5.25" drive 1
    output [5:0]    WOZ_TRACK1,
    output [12:0]   WOZ_TRACK1_BIT_ADDR,
    input  [7:0]    WOZ_TRACK1_BIT_DATA,
    input  [31:0]   WOZ_TRACK1_BIT_COUNT,

    // Motor status for clock slowdown
    output          FLOPPY_MOTOR_ON
);

    //=========================================================================
    // IWM Soft Switch State (SINGLE SOURCE OF TRUTH)
    //=========================================================================

    reg [3:0]  motor_phase;     // Head stepper phases (PH0-PH3)
    reg        drive_on;        // Motor enable command
    reg        drive_sel;       // Drive select (0=drive1, 1=drive2)
    reg        q6;              // Q6 state bit
    reg        q7;              // Q7 state bit
    reg [7:0]  mode_reg;        // Mode register

    // Drive type from DISK35 register
    wire       is_35_inch = DISK35[6];

    // DISKREG bit7 (HDSEL) is only meaningful while 35SEL is asserted.
    // The IIgs ROM frequently clears DISKREG (including bit7) at command boundaries; in MAME,
    // the head-select line is only updated when 35SEL is active.
    //
    // IMPORTANT timing detail:
    // - The ROM uses SDCLINES to update CA0/CA1/CA2 and then writes $C031 (HDSEL/SEL) immediately
    //   before pulsing LSTRB. If we add an extra registered stage here, the SEL bit can lag and
    //   the Sony command nibble seen by `flux_drive` can be wrong.
    // - Therefore, use DISK35[7] directly when 35SEL is asserted (no extra cycle), but retain a
    //   latched copy for the periods when 35SEL is deasserted so brief deselect windows don't
    //   force HDSEL low.
    reg        diskreg_sel_latched;
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            diskreg_sel_latched <= 1'b0;
        end else if (is_35_inch) begin
            diskreg_sel_latched <= DISK35[7];
        end
    end
    wire       diskreg_sel = is_35_inch ? DISK35[7] : diskreg_sel_latched;

    // DISK35[6] is the IIgs 35SEL line (3.5" vs 5.25" select). The ROM routinely clears it
    // (see ad35driver_mainline.asm: STZ $C031) when returning to the caller, which in MAME
    // immediately forces the Sony drive motor off (mac_floppy_device::tfsel_w()).

    //=========================================================================
    // Soft Switch Handling
    //=========================================================================

    // Access strobes (IWM-selected CPU cycle)
    wire cpu_rd = DEVICE_SELECT && WR_CYCLE;
    wire cpu_wr = DEVICE_SELECT && !WR_CYCLE;
    wire cpu_accessing = cpu_rd || cpu_wr;

    // IWM bus timing:
    // The CPU address is stable during PH2=0 and advances on the PH2 pulse. Sample the bus on
    // the PH2 pulse (seeing the prior stable address/data) rather than using PH2+1.
    wire bus_cen = PH2;

    //=========================================================================
    // CPU bus view for IWM (must be same-cycle accurate)
    //=========================================================================
    // A separate latch updated with nonblocking assignments causes the soft-switch decode
    // (in the other posedge block) to see the *previous* cycle’s bus_addr. That matches the
    // observed failure: during an E1:C0EE access, the state update behaved like C0ED.
    //
    // Use the raw bus signals during the PH2 pulse and rely on iwm_flux’s own immediate
    // Q6/Q7 decoding for correct same-cycle behavior.
    wire [3:0] bus_addr = A[3:0];
    wire       bus_rd   = bus_cen && cpu_rd;
    wire       bus_wr   = bus_cen && cpu_wr;
    wire [7:0] bus_din  = D_IN;

    wire cpu_access_edge = bus_cen && cpu_accessing;

    // Immediate Q6/Q7 values for mode register write detection
    // When accessing the Q6/Q7 switch, use the NEW value from A[0], not the latched value
    // This is critical: writing to $C0EF (Q7=1) must trigger mode write in the same cycle
    wire access_q6 = (bus_addr[3:1] == 3'b110);
    wire access_q7 = (bus_addr[3:1] == 3'b111);
    wire immediate_q6 = access_q6 ? bus_addr[0] : q6;
    wire immediate_q7 = access_q7 ? bus_addr[0] : q7;

    //=========================================================================
    // Mode Register Write Detection (ROM3 verify loop at FF:4720)
    //=========================================================================
    // Detect mode register writes using raw bus signals. The ROM writes the mode value to
    // $C0EF (Q7=1, odd) while Q6 is already set, then reads back via $C0EE.
    wire write_mode_q6 = (A[3:1] == 3'b110) ? A[0] : q6;
    wire write_mode_q7 = (A[3:1] == 3'b111) ? A[0] : q7;
    wire is_mode_write_access = cpu_access_edge && cpu_wr && !iwm_active &&
                                (A[3:0] == 4'hF) && write_mode_q6 && write_mode_q7;

    //=========================================================================
    // IWM Active State (Motor Delay Emulation)
    //=========================================================================

    // MAME delays motor-off by ~1 second unless mode bit2 requests immediate off.
    localparam [23:0] IWM_DELAY_CYCLES = 24'd14000000; // ~1 second at 14MHz
    reg        iwm_active;
    reg [23:0] iwm_delay_cnt;

    // Immediate motor value for status register
    // MAME behavior: When reading $C0E9 (motor on), the status immediately reflects
    // motor=1. This is critical for the boot ROM which checks status after motor on.
    wire access_motor = (bus_addr[3:1] == 3'b100);  // $C0E8/$C0E9
    wire immediate_motor = cpu_access_edge && access_motor ? bus_addr[0] : drive_on;

    // Immediate mode value for status register
    // MAME behavior: When writing mode register via $C0EF (Q6=1, Q7=1, IWM inactive, odd address),
    // the status register immediately reflects the new mode value. This is critical because
    // the ROM writes mode then immediately reads status, expecting to see the new mode bits.
    // The mode write condition is: cpu_wr && !m_active && immediate_q7 && immediate_q6 && A[0]
    wire mode_write_active = bus_wr && !iwm_active && immediate_q7 && immediate_q6 && bus_addr[0];
    wire [7:0] immediate_mode = mode_write_active ? {3'b000, bus_din[4:0]} : mode_reg;

`ifdef SIMULATION
    // Debug: track immediate_mode during status reads
    reg [7:0] prev_immediate_mode;
    reg       prev_cpu_rd;
    always @(posedge CLK_14M) begin
        // Log status reads where mode might be 0
        if (cpu_rd && PH2 && immediate_q6 && !immediate_q7) begin
            $display("IWM_WOZ: STATUS_READ mode_reg=%02h immediate_mode=%02h mode_write_active=%0d cpu_wr=%0d drive_on=%0d imm_q6=%0d imm_q7=%0d A=%04h D_IN=%02h",
                     mode_reg, immediate_mode, mode_write_active, cpu_wr, drive_on, immediate_q6, immediate_q7, A, D_IN);
        end
        // Log when mode_reg changes
        if (prev_immediate_mode != mode_reg) begin
            $display("IWM_WOZ: MODE_REG_CHANGED %02h -> %02h", prev_immediate_mode, mode_reg);
        end
        prev_immediate_mode <= mode_reg;
        prev_cpu_rd <= cpu_rd;
    end
`endif

    // Immediate phase values for sense calculation
    // When the ROM accesses a phase register (e.g., bit $C0E3), the sense value
    // should use the NEW phase value immediately, not wait for the next cycle.
    // This is critical for the boot ROM's drive detection logic.
    wire access_phase0 = (bus_addr[3:1] == 3'b000);
    wire access_phase1 = (bus_addr[3:1] == 3'b001);
    wire access_phase2 = (bus_addr[3:1] == 3'b010);
    wire access_phase3 = (bus_addr[3:1] == 3'b011);
    // Note: use `cpu_access_edge` so we only treat bus_addr[0] as valid on PH2+1.
    wire [3:0] immediate_phases = {
        (cpu_access_edge && access_phase3) ? bus_addr[0] : motor_phase[3],
        (cpu_access_edge && access_phase2) ? bus_addr[0] : motor_phase[2],
        (cpu_access_edge && access_phase1) ? bus_addr[0] : motor_phase[1],
        (cpu_access_edge && access_phase0) ? bus_addr[0] : motor_phase[0]
    };

    // Latched sense register - MAME behavior
    // MAME latches m_reg when seek_phase_w() is called (i.e., when phases are written).
    // The sense lookup uses this latched value, NOT the current phases.
    // This allows the ROM to set phases, then immediately read back a sense value
    // that persists even after phases are cleared.
    reg [2:0] latched_sense_reg;
    wire [3:0] latched_immediate_phases = {
        (cpu_access_edge && access_phase3) ? bus_addr[0] : motor_phase[3],
        (cpu_access_edge && access_phase2) ? bus_addr[0] : motor_phase[2],
        (cpu_access_edge && access_phase1) ? bus_addr[0] : motor_phase[1],
        (cpu_access_edge && access_phase0) ? bus_addr[0] : motor_phase[0]
    };
    wire [2:0] immediate_latched_sense_reg = (cpu_access_edge && bus_addr[3:1] < 3'b100)
                                           ? latched_immediate_phases[2:0]
                                           : latched_sense_reg;

    //=========================================================================
    // IWM Active State Machine
    //=========================================================================
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            motor_phase <= 4'b0000;
            drive_on <= 1'b0;
            drive_sel <= 1'b0;
            q6 <= 1'b0;
            q7 <= 1'b0;
            mode_reg <= 8'h00;
            latched_sense_reg <= 3'b000;
            iwm_active <= 1'b0;
            iwm_delay_cnt <= 24'd0;
        end else begin
            // Robust mode register capture:
            // The IIgs ROM expects a write to $C0EF (odd, Q7=1) while the IWM is idle to latch the
            // mode bits, then immediately reads back via $C0EE. Capture the mode write when the
            // sampled bus indicates a write to offset $F. Repeated captures are harmless.
            if (cpu_access_edge && bus_wr && !iwm_active && (bus_addr == 4'hF)) begin
                mode_reg <= {3'b000, bus_din[4:0]};
`ifdef SIMULATION
                $display("IWM_WOZ: MODE_REG <= %02h (robust wr, D_IN=%02h A=%01h)", {3'b000, bus_din[4:0]}, bus_din, bus_addr);
`endif
            end

            // Process soft switch updates once per IWM bus cycle (PH2 pulse).
            if (cpu_access_edge) begin
                // IWM soft switches are "touch" switches: any access (read or write) updates state.
                // MAME implements this by routing both reads and writes through the same control() path.
                case (bus_addr[3:1])
                    3'b000: motor_phase[0] <= bus_addr[0];  // $C0E0/$C0E1: Phase 0
                    3'b001: motor_phase[1] <= bus_addr[0];  // $C0E2/$C0E3: Phase 1
                    3'b010: motor_phase[2] <= bus_addr[0];  // $C0E4/$C0E5: Phase 2
                    3'b011: motor_phase[3] <= bus_addr[0];  // $C0E6/$C0E7: Phase 3
                    3'b100: drive_on      <= bus_addr[0];  // $C0E8/$C0E9: Motor
                    3'b101: begin
                        drive_sel     <= bus_addr[0];  // $C0EA/$C0EB: Drive select
`ifdef SIMULATION
                        $display("IWM_WOZ: DRIVE_SEL %0d -> %0d (A=%04h is_35=%0d)", drive_sel, bus_addr[0], A, is_35_inch);
`endif
                    end
                    3'b110: q6            <= bus_addr[0];  // $C0EC/$C0ED: Q6
                    3'b111: q7            <= bus_addr[0];  // $C0EE/$C0EF: Q7
                endcase

            // MAME behavior: Latch sense register index on EVERY phase access (SET or CLEAR)
            // MAME's control() always calls update_phases() which calls seek_phase_w() for all
            // phase register accesses. The m_reg value is updated to (phases & 7) | ss.
            if (bus_addr[3:1] < 3'b100) begin
                // Writing to phase 0-3 ($C0E0-$C0E7)
                latched_sense_reg <= latched_immediate_phases[2:0];
`ifdef SIMULATION
                // Debug ALL phase accesses to trace command flow
                $display("IWM_WOZ: PHASE_ACCESS A=%04h A31=%03b A0=%0d is_35=%0d drv_sel=%0d phases=%04b imm_phases=%04b",
                         A, A[3:1], A[0], is_35_inch, drive_sel, motor_phase, immediate_phases);
`endif
            end
`ifdef SIMULATION
            // Debug: Log EVERY phase change access when motor is on
            if (is_35_inch && motor_spinning && A[3:1] < 3'b100) begin
                $display("IWM_WOZ: PHASE_SW addr=%04h A31=%03b A0=%0d phase[%0d]<=%0d (cur=%04b SEL=%0d)",
                         A, A[3:1], A[0], A[3:1], A[0], motor_phase, diskreg_sel);
            end
`endif

            // Mode register write: see `is_mode_write_access` above.
            if (is_mode_write_access) begin
                mode_reg <= {3'b000, D_IN[4:0]};
`ifdef SIMULATION
                $display("IWM_WOZ: MODE_REG <= %02h (D_IN=%02h q6=%0d q7=%0d)", {3'b000, D_IN[4:0]}, D_IN, write_mode_q6, write_mode_q7);
`endif
            end

`ifdef SIMULATION
            // Debug: Show Q6/Q7 changes for tracking soft switch state
            if (A[3:1] == 3'b110) begin
                $display("IWM_WOZ: Q6 <= %0d (addr=%04h is_35=%0d)", A[0], A, is_35_inch);
            end
            if (A[3:1] == 3'b111) begin
                $display("IWM_WOZ: Q7 <= %0d (addr=%04h is_35=%0d)", A[0], A, is_35_inch);
            end
`endif
            end  // end of cpu_access_edge block

            // IWM "active" timing (MAME: m_active MODE_ACTIVE/MODE_DELAY):
            // - Rising edge of motor enable: becomes active immediately.
            // - Falling edge of motor enable:
            //     - mode bit2 set  -> immediate off (MODE_IDLE)
            //     - mode bit2 clear -> delayed off (~1s, MODE_DELAY)
            //
            // Critical: Do NOT restart the delayed-off timer on repeated "motor off" accesses
            // while already off; MAME only starts the 1s timer when transitioning from ACTIVE->DELAY.
            if (cpu_access_edge && access_motor) begin
                // drive_on will be updated to A[0] by the switch case above (nonblocking).
                // Use the *previous* drive_on value to detect transitions.
                if (bus_addr[0] && !drive_on) begin
                    // Motor command OFF -> ON
                    iwm_active <= 1'b1;
                    iwm_delay_cnt <= IWM_DELAY_CYCLES;
                end else if (!bus_addr[0] && drive_on) begin
                    // Motor command ON -> OFF
                    if (immediate_mode[2]) begin
                        iwm_active <= 1'b0;
                        iwm_delay_cnt <= 24'd0;
                    end else begin
                        iwm_active <= 1'b1;
                        iwm_delay_cnt <= IWM_DELAY_CYCLES;
                    end
                end
            end else if (drive_on) begin
                // While motor is commanded on, stay active.
                iwm_active <= 1'b1;
                iwm_delay_cnt <= IWM_DELAY_CYCLES;
            end else if (iwm_active) begin
                // Motor commanded off: count down delayed-off, then drop to idle.
                if (iwm_delay_cnt != 24'd0) begin
                    iwm_delay_cnt <= iwm_delay_cnt - 1'd1;
                end else begin
                    iwm_active <= 1'b0;
                end
            end
        end  // end of else (not reset)
    end  // end of always

    //=========================================================================
    // Motor Spinup/Spindown State
    //=========================================================================
    // 5.25" drives have:
    // - ~300ms spinup delay after motor on command (motor_spinning stays 0)
    // - ~1 second spindown after motor off command (motor_spinning stays 1)
    //
    // 3.5" Sony drives are now handled entirely in flux_drive.v via Sony commands.
    // This register now only manages the 5.25" inertia.

    reg        motor_spinning;
    reg [23:0] motor_counter;
    reg        motor_spinup_done;
    localparam SPINUP_TIME  = 24'd4200000;   // ~300ms at 14MHz (5.25" only)
    localparam SPINDOWN_TIME = 24'd14000000;  // ~1 second at 14MHz

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            motor_spinning <= 1'b0;
            motor_counter <= 24'd0;
            motor_spinup_done <= 1'b0;
        end else begin
            if (drive_on) begin
                if (!is_35_inch) begin 
                    // 5.25" drives: Spinup delay
                    if (!motor_spinup_done) begin
                        if (motor_counter >= SPINUP_TIME) begin
                            motor_spinning <= 1'b1;
                            motor_spinup_done <= 1'b1;
                            motor_counter <= SPINDOWN_TIME;
`ifdef SIMULATION
                            $display("IWM_WOZ: Motor spinup complete, motor_spinning=1");
`endif
                        end else begin
                            motor_counter <= motor_counter + 1'd1;
                        end
                    end else begin
                        // Already spun up, keep counter at spindown time
                        motor_spinning <= 1'b1;
                        motor_counter <= SPINDOWN_TIME;
                    end
                end else begin
                    // For 3.5", we don't manage inertia here anymore.
                    // But we keep motor_spinning=0 to avoid confusing the 5.25" logic
                    // if we switch drive types on the fly (unlikely but safe).
                    // Actually, if we switch to 3.5", flux_drive ignores this signal.
                    motor_spinning <= 1'b0; 
                end
            end else begin
                // Motor off command - reset spinup state, start spindown
                motor_spinup_done <= 1'b0;
                if (motor_counter > 0) begin
                    motor_counter <= motor_counter - 1'd1;
                end else begin
                    motor_spinning <= 1'b0;
                end
            end
        end
    end

    //=========================================================================
    // 3.5" Drive - Flux-Based
    //=========================================================================

    wire        flux_transition_35;
    wire        drive35_wp;
    wire        drive35_sense;
    wire        drive35_motor_spinning;
    wire        drive35_ready;          // Drive ready after spinup
    wire [6:0]  drive35_track;
    wire [16:0] drive35_bit_position;
    wire [13:0] drive35_bram_addr;

    // 3.5" drives must NOT use the 5.25" inertia-managed motor_spinning signal.
    // The IIgs ROM (Sony driver) can toggle DISK35 during command boundaries, and
    // motor_spinning is intentionally forced low when is_35_inch=1. Feeding that into
    // the 3.5" flux_drive causes brief/glitchy motor pulses that prevent spin-up.
    //
    // For 3.5", MOTOR_ON should be driven from the IWM motor command (drive_on) gated
    // by the software 3.5" select (DISK35[6]) and disk presence.
    wire drive35_motor_on = drive_on && is_35_inch && DISK_READY[2];

    // Drive is active when the 3.5" motor is physically spinning and disk is present
    wire drive35_active = drive35_motor_spinning && DISK_READY[2];

    flux_drive drive35 (
        .IS_35_INCH(1'b1),
        .DRIVE_ID(2'd1),
        .CLK_14M(CLK_14M),
        .RESET(RESET),
        .PHASES(motor_phase),
        .IMMEDIATE_PHASES(immediate_phases),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),  // Use immediate for same-cycle visibility
        .IWM_MODE(immediate_mode[4:0]),
        .MOTOR_ON(drive35_motor_on),
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for direction gating
        .DISKREG_SEL(diskreg_sel),
        .SEL35(is_35_inch),
        .DRIVE_SELECT(drive_sel),       // Pass drive selection for per-slot direction tracking
        .DRIVE_SLOT(1'b0),              // This drive is slot 0 (drive 1 - internal drive)
        .DISK_MOUNTED(DISK_READY[2]),
        .DISK_WP(1'b1),
        .DOUBLE_SIDED(1'b1),
        .FLUX_TRANSITION(flux_transition_35),
        .WRITE_PROTECT(drive35_wp),
        .SENSE(drive35_sense),
        .MOTOR_SPINNING(drive35_motor_spinning),
        .DRIVE_READY(drive35_ready),
        .TRACK(drive35_track),
        .BIT_POSITION(drive35_bit_position),
        .TRACK_BIT_COUNT(WOZ_TRACK3_BIT_COUNT),
        .TRACK_LOADED(DISK_READY[2]),
        .BRAM_ADDR(drive35_bram_addr),
        .BRAM_DATA(WOZ_TRACK3_BIT_DATA),
        .SD_TRACK_REQ(),
        .SD_TRACK_STROBE(),
        .SD_TRACK_ACK(1'b0)
    );

    // WOZ_TRACK3: Register the track output to synchronize with C++ data updates.
    // The C++ BeforeEval() runs before Verilog eval, so if we changed WOZ_TRACK3
    // combinationally, the C++ would provide the OLD track's data while Verilog
    // is already reading from the NEW track position. By registering WOZ_TRACK3,
    // the track change is delayed by one cycle to match the C++ timing.
    //
    // IMPORTANT (ROM-confirmed): The IIgs Sony driver addresses tracks as cylinder*2 + side
    // (see IIgsRomSource/Bank FF/ad35driver_subroutines.asm:2198). That means side 1 is the
    // LSB, not an +80 offset. Using +80 causes completely wrong tracks beyond cylinder 0.
    wire [7:0] woz_track3_comb = {drive35_track, 1'b0} | {7'b0, diskreg_sel};
    reg [7:0] woz_track3_reg;

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            woz_track3_reg <= 8'd0;
        end else begin
            woz_track3_reg <= woz_track3_comb;
        end
    end

    assign WOZ_TRACK3 = woz_track3_reg;
    assign WOZ_TRACK3_BIT_ADDR = drive35_bram_addr;

`ifdef SIMULATION
    // Debug: track diskreg_sel changes to detect oscillation bug
    reg prev_diskreg_sel;
    reg [6:0] prev_drive35_track;
    always @(posedge CLK_14M) begin
        if (prev_diskreg_sel != diskreg_sel) begin
            $display("IWM_WOZ: *** diskreg_sel CHANGED: %0d -> %0d (DISK35=%02h drive35_track=%0d WOZ_TRACK3_comb=%0d WOZ_TRACK3_reg=%0d)",
                     prev_diskreg_sel, diskreg_sel, DISK35, drive35_track, woz_track3_comb, woz_track3_reg);
        end
        // Debug: Track drive35_track changes (from flux_drive TRACK output)
        if (prev_drive35_track != drive35_track) begin
            $display("IWM_WOZ: *** drive35_track CHANGED: %0d -> %0d (woz_track3_comb=%0d woz_track3_reg=%0d)",
                     prev_drive35_track, drive35_track, woz_track3_comb, woz_track3_reg);
        end
        prev_diskreg_sel <= diskreg_sel;
        prev_drive35_track <= drive35_track;
    end
`endif

    //=========================================================================
    // 3.5" Drive 2 - Empty (No Disk)
    //=========================================================================
    // Matches MAME behavior: Drive exists and responds to commands, but has no disk.

    wire        flux_transition_35_2;
    wire        drive35_2_wp;
    wire        drive35_2_sense;
    wire        drive35_2_motor_spinning;
    wire        drive35_2_ready;

    flux_drive drive35_2 (
        .IS_35_INCH(1'b1),
        .DRIVE_ID(2'd2),
        .CLK_14M(CLK_14M),
        .RESET(RESET),
        .PHASES(motor_phase),
        .IMMEDIATE_PHASES(immediate_phases),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),
        .IWM_MODE(immediate_mode[4:0]),
        .MOTOR_ON(1'b0),                // No disk inertia tracking for empty drive
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for command processing
        .DISKREG_SEL(diskreg_sel),
        .SEL35(is_35_inch),
        .DRIVE_SELECT(drive_sel),
        .DRIVE_SLOT(1'b1),              // This drive is slot 1 (external drive, typically empty)
        .DISK_MOUNTED(1'b0),            // No disk
        .DISK_WP(1'b1),                 // Write protected if no disk
        .DOUBLE_SIDED(1'b1),
        .FLUX_TRANSITION(flux_transition_35_2),
        .WRITE_PROTECT(drive35_2_wp),
        .SENSE(drive35_2_sense),
        .MOTOR_SPINNING(drive35_2_motor_spinning),
        .DRIVE_READY(drive35_2_ready),
        .TRACK(),
        .BIT_POSITION(),
        .TRACK_BIT_COUNT(32'd0),
        .TRACK_LOADED(1'b0),
        .BRAM_ADDR(),
        .BRAM_DATA(8'h00),
        .SD_TRACK_REQ(),
        .SD_TRACK_STROBE(),
        .SD_TRACK_ACK(1'b0)
    );

    //=========================================================================
    // 5.25" Drive - Flux-Based
    //=========================================================================

    wire        flux_transition_525;
    wire        drive525_wp;
    wire        drive525_sense;
    wire        drive525_motor_spinning;
    wire        drive525_ready;
    wire [6:0]  drive525_track_7bit;
    wire [5:0]  drive525_track = drive525_track_7bit[5:0];
    wire [16:0] drive525_bit_position;
    wire [13:0] drive525_bram_addr;

    // Drive is active when motor is spinning, 5.25" mode, and disk ready
    wire drive525_active = motor_spinning && !is_35_inch && DISK_READY[0];

    flux_drive drive525 (
        .IS_35_INCH(1'b0),
        .DRIVE_ID(2'd0),
        .CLK_14M(CLK_14M),
        .RESET(RESET),
        .PHASES(motor_phase),
        .IMMEDIATE_PHASES(immediate_phases),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),
        .IWM_MODE(immediate_mode[4:0]),
        .MOTOR_ON(motor_spinning && DISK_READY[0]),
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for direction gating
        .DISKREG_SEL(1'b0),
        .SEL35(1'b0),
        .DRIVE_SELECT(drive_sel),       // Pass drive selection
        .DRIVE_SLOT(1'b0),              // 5.25" doesn't use per-slot direction (IS_35_INCH=0)
        .DISK_MOUNTED(DISK_READY[0]),
        .DISK_WP(1'b1),
        .DOUBLE_SIDED(1'b0),
        .FLUX_TRANSITION(flux_transition_525),
        .WRITE_PROTECT(drive525_wp),
        .SENSE(drive525_sense),
        .MOTOR_SPINNING(drive525_motor_spinning),
        .DRIVE_READY(drive525_ready),
        .TRACK(drive525_track_7bit),
        .BIT_POSITION(drive525_bit_position),
        .TRACK_BIT_COUNT(WOZ_TRACK1_BIT_COUNT),
        .TRACK_LOADED(DISK_READY[0]),
        .BRAM_ADDR(drive525_bram_addr),
        .BRAM_DATA(WOZ_TRACK1_BIT_DATA),
        .SD_TRACK_REQ(),
        .SD_TRACK_STROBE(),
        .SD_TRACK_ACK(1'b0)
    );

    assign WOZ_TRACK1 = drive525_track;
    assign WOZ_TRACK1_BIT_ADDR = drive525_bram_addr[12:0];

    //=========================================================================
    // Flux Mux - Select active drive's flux transitions
    //=========================================================================

    // Flux transition: use selected drive's transitions
    // CRITICAL: Must use flux_is_35_inch (based on spinning motor) not is_35_inch (software register)!
    // When 3.5" drive is spinning but ROM temporarily accesses slot 5 mode, we must still
    // read flux from the 3.5" drive.
    wire flux_transition = (flux_is_35_inch) ? ((drive_sel == 0) ? flux_transition_35 : flux_transition_35_2) :
                                              ((drive_sel == 0) ? flux_transition_525 : 1'b0);

    // Track which drive type's flux we're actually using (for window timing)
    // CRITICAL: Window timing must match the SPINNING drive, not software DISK35 register!
    // When a 3.5" drive is spinning, use 28-cycle windows even if ROM temporarily
    // accesses slot 5 (5.25" mode). Otherwise byte decoding gets corrupted!
    wire flux_is_35_inch = drive35_motor_spinning ? 1'b1 :
                          drive35_2_motor_spinning ? 1'b1 :
                          drive525_motor_spinning ? 1'b0 :
                          is_35_inch;  // Fallback to software setting when no drive spinning

    wire drive_active = flux_is_35_inch ? drive35_active : drive525_active;
    wire current_wp = flux_is_35_inch ? drive35_wp : drive525_wp;

    // Any disk spinning - used for IWM MOTOR_SPINNING independent of is_35_inch
    wire any_disk_spinning = drive35_motor_spinning || drive35_2_motor_spinning || drive525_motor_spinning;
    // Any disk ready - drive must be spun up AND have track data loaded
    // The state machine should wait until drive_ready is true (spinup complete)
    // This prevents decoding garbage during motor spin-up period
    // NOTE: drive35_2 is not included - it has no separate DISK_READY signal and
    // its motor is gated off when DISK_READY[2]=1 (disk in primary 3.5" drive)
    wire any_disk_ready = (drive35_ready && DISK_READY[2]) ||
                          (drive525_ready && DISK_READY[0]);

    //=========================================================================
    // Sense Mux - Select active drive's status sense
    //=========================================================================
    // Select between Drive 1 and Drive 2 based on drive_sel.
    wire drive_sense = (flux_is_35_inch) ? ((drive_sel == 0) ? drive35_sense : drive35_2_sense) :
                                          ((drive_sel == 0) ? drive525_sense : 1'b1);

    // Sense gating: when no drive is enabled, the IWM sense input floats high.
    wire sense_enabled = drive_on;
    wire current_sense = sense_enabled ? drive_sense : 1'b1;

    wire current_motor_spinning = flux_is_35_inch ? drive35_motor_spinning : drive525_motor_spinning;

    //=========================================================================
    // IWM Chip (Flux-Based Byte Decoding)
    //=========================================================================

    wire [7:0] iwm_data_out;

    // Disk mounted status
    wire disk_mounted = DISK_READY[2] ? 1'b1 :
                       DISK_READY[0] ? 1'b1 :
                       (is_35_inch ? DISK_READY[2] : DISK_READY[0]);

    // Muxed bit position for debug logging and flux decoder
    // Use flux_is_35_inch (based on which motor is spinning) instead of is_35_inch (register)
    // to ensure correct drive's position is used even when ROM temporarily accesses other slot
    wire [16:0] current_bit_position = flux_is_35_inch ? drive35_bit_position : drive525_bit_position;

    // Disk II / IWM compatibility behavior:
    // The IIgs ROM writes the mode register via $C0EF (which sets Q7=1) and can then
    // immediately read $C0EC for disk data without first touching $C0EE to clear Q7.
    // Real hardware effectively treats $C0EC as a DATA-register read when the selected
    // drive has media and the motor is on. Without this, $C0EC can return 0x80
    // (handshake, Q7=1 Q6=0), corrupting the ROM's read loops.
    // IMPORTANT: Use the *active/spinning* drive type (flux_is_35_inch), not DISK35[6].
    // The ROM frequently toggles DISK35 during command boundaries; if we key off DISK35[6]
    // here we can incorrectly treat $C0EC reads as handshake (Q7=1) while the ROM is
    // actually trying to read disk data from the still-spinning 3.5" drive.
    wire selected_disk_present = flux_is_35_inch ? (drive_sel ? DISK_READY[3] : DISK_READY[2])
                                                 : (drive_sel ? DISK_READY[1] : DISK_READY[0]);
    // Only force $C0EC to be treated as a data read when the IWM motor output is enabled.
    // If we force this while `drive_on` is 0 but the Sony spindle is still spinning
    // (common between SmartPort calls), the CPU can read 0xFF as "data" and corrupt
    // the ROM's nibble decode loops.
    // IMPORTANT: Do NOT apply this compatibility hack in SmartPort/C-Bus mode.
    // The SmartPort driver intentionally reads $C0EC as the WHD/handshake register
    // (Q7=1,Q6=0) using `ASL $C08C,X` polling. Forcing Q7 low there breaks the
    // handshake loop and the ROM will hang in `smartdrvr.asm` at FF:56CD.
    wire smartport_mode = (!immediate_mode[3]) && immediate_mode[1];
    wire force_q7_data_read = bus_rd && (bus_addr == 4'hC) &&
                              selected_disk_present &&
                              drive_on &&
                              !smartport_mode;
    wire q7_for_flux = force_q7_data_read ? 1'b0 : q7;

    iwm_flux iwm (
        .CLK_14M(CLK_14M),
        .CLK_7M_EN(CLK_7M_EN),  // 7M clock enable for IWM timing (matches real hardware)
        .RESET(RESET),
        // In this sim architecture, IWM bus address/control are valid on PH2+1.
        // Drive iwm_flux's access tracking from the same qualified enable.
        .CEN(bus_cen),
        .ADDR(bus_addr),
        .RD(bus_rd),
        .WR(bus_wr),
        .DATA_IN(bus_din),
        .DATA_OUT(iwm_data_out),

        // Soft switch state from this module (SINGLE SOURCE OF TRUTH)
        .SW_PHASES(motor_phase),
        .SW_MOTOR_ON(drive_on),
        .SW_DRIVE_SEL(drive_sel),
        .SW_Q6(q6),
        .SW_Q7(q7_for_flux),
        .SW_MODE(immediate_mode),

        .FLUX_TRANSITION(flux_transition),
        // MOTOR_ACTIVE drives the IWM status bit5 (0x20). The IIgs ROM's `SETIWMMODE`
        // polls this bit after touching `DeSelect` ($C0E8) and expects it to drop
        // immediately when mode bit2 is set (ROM uses mode=0x0F).
        // MAME-style active/delay behavior (not just raw motor soft switch).
        .MOTOR_ACTIVE(iwm_active),
        .MOTOR_SPINNING(any_disk_spinning),  // Physical spinning (for flux decoding)
        .DISK_READY(any_disk_ready),
        .DISK_MOUNTED(disk_mounted),
        .IS_35_INCH(flux_is_35_inch),
        .SENSE_BIT(current_sense),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),  // Use immediate for same-cycle visibility
        .DISKREG_SEL(diskreg_sel),
        .DISK_BIT_POSITION(current_bit_position),
        .FLUX_WRITE(),
        .DEBUG_RSH(),
        .DEBUG_STATE()
    );

    assign D_OUT = iwm_data_out;

    //=========================================================================
    // Motor Status Output
    //=========================================================================

    // Only slow down for 5.25" drives (motor_spinning tracks 5.25" state/inertia).
    // 3.5" drives (handled by Sony logic) should NOT slow the system to 1MHz.
    assign FLOPPY_MOTOR_ON = motor_spinning;

`ifdef SIMULATION
    // Debug: Monitor state changes
    reg [3:0] prev_phase;
    reg       prev_drive_on;
    reg       prev_motor_spinning;
    reg       prev_iwm_active;
    reg [31:0] debug_cycle;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            debug_cycle <= 0;
            prev_iwm_active <= 1'b0;
        end else begin
            debug_cycle <= debug_cycle + 1;
        end

        if (motor_phase != prev_phase) begin
            $display("IWM_WOZ: phases %04b -> %04b (is_35=%0d)", prev_phase, motor_phase, is_35_inch);
        end
        if (drive_on != prev_drive_on) begin
            $display("IWM_WOZ: drive_on %0d -> %0d (is_35=%0d ready=%04b motor_spinning=%0d)",
                     prev_drive_on, drive_on, is_35_inch, DISK_READY, motor_spinning);
        end
        if (iwm_active != prev_iwm_active) begin
            $display("IWM_WOZ: iwm_active %0d -> %0d (drive_on=%0d mode=%02h delay_cnt=%0d)",
                     prev_iwm_active, iwm_active, drive_on, mode_reg, iwm_delay_cnt);
        end
        if (motor_spinning != prev_motor_spinning) begin
            $display("IWM_WOZ: motor_spinning %0d -> %0d (drive_on=%0d ready=%04b is_35=%0d)",
                     prev_motor_spinning, motor_spinning, drive_on, DISK_READY, is_35_inch);
        end
        prev_phase <= motor_phase;
        prev_drive_on <= drive_on;
        prev_motor_spinning <= motor_spinning;
        prev_iwm_active <= iwm_active;

        // Periodic status when motor is on
        if (motor_spinning && (debug_cycle[19:0] == 20'h80000)) begin
            $display("IWM_WOZ: Status: is_35=%0d drive35_active=%0d drive525_active=%0d DISK_READY=%04b q6=%0d q7=%0d drive_sel=%0d",
                     is_35_inch, drive35_active, drive525_active, DISK_READY, q6, q7, drive_sel);
            $display("IWM_WOZ: Track3=%0d BitAddr3=%0d BitCount3=%0d Data3=%02h woz_track3_comb=%0d woz_track3_reg=%0d diskreg_sel=%0d",
                     drive35_track, drive35_bram_addr, WOZ_TRACK3_BIT_COUNT, WOZ_TRACK3_BIT_DATA, woz_track3_comb, woz_track3_reg, diskreg_sel);
        end
    end

    // Debug: Monitor flux transitions
    reg [15:0] flux_count;
    reg        prev_flux;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            flux_count <= 16'd0;
            prev_flux <= 1'b0;
        end else begin
            prev_flux <= flux_transition;
            if (flux_transition && !prev_flux && motor_spinning) begin
                flux_count <= flux_count + 1'd1;
                if (flux_count < 16'd50) begin
                    $display("IWM_WOZ: Flux #%0d at bit_pos=%0d (is_35=%0d active=%0d)",
                             flux_count, is_35_inch ? drive35_bit_position : drive525_bit_position,
                             is_35_inch, drive_active);
                end
            end
        end
    end
`endif

endmodule
