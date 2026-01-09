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
    wire       diskreg_sel = DISK35[7];

    //=========================================================================
    // Soft Switch Handling
    //=========================================================================

    // Access strobes (active for entire CPU bus cycle)
    wire cpu_rd = DEVICE_SELECT && WR_CYCLE;
    wire cpu_wr = DEVICE_SELECT && !WR_CYCLE;
    wire cpu_accessing = cpu_rd || cpu_wr;

    // Edge detection for soft switch updates - process once per CPU access
    reg  cpu_access_latched;
    wire cpu_access_edge = cpu_accessing && PH2 && !cpu_access_latched;

    // Immediate Q6/Q7 values for mode register write detection
    // When accessing the Q6/Q7 switch, use the NEW value from A[0], not the latched value
    // This is critical: writing to $C0EF (Q7=1) must trigger mode write in the same cycle
    wire access_q6 = (A[3:1] == 3'b110);
    wire access_q7 = (A[3:1] == 3'b111);
    wire immediate_q6 = access_q6 ? A[0] : q6;
    wire immediate_q7 = access_q7 ? A[0] : q7;

    // Immediate motor value for status register
    // MAME behavior: When reading $C0E9 (motor on), the status immediately reflects
    // motor=1. This is critical for the boot ROM which checks status after motor on.
    wire access_motor = (A[3:1] == 3'b100);  // $C0E8/$C0E9
    wire immediate_motor = cpu_accessing && access_motor ? A[0] : drive_on;

    // Immediate mode value for status register
    // MAME behavior: When writing mode register via $C0EF (Q6=1, Q7=1, motor off, odd address),
    // the status register immediately reflects the new mode value. This is critical because
    // the ROM writes mode then immediately reads status, expecting to see the new mode bits.
    // The mode write condition is: cpu_wr && !drive_on && immediate_q7 && immediate_q6 && A[0]
    wire mode_write_active = cpu_wr && !drive_on && immediate_q7 && immediate_q6 && A[0];
    wire [7:0] immediate_mode = mode_write_active ? {3'b000, D_IN[4:0]} : mode_reg;

    // Immediate phase values for sense calculation
    // When the ROM accesses a phase register (e.g., bit $C0E3), the sense value
    // should use the NEW phase value immediately, not wait for the next cycle.
    // This is critical for the boot ROM's drive detection logic.
    wire access_phase0 = (A[3:1] == 3'b000);
    wire access_phase1 = (A[3:1] == 3'b001);
    wire access_phase2 = (A[3:1] == 3'b010);
    wire access_phase3 = (A[3:1] == 3'b011);
    // Note: cpu_accessing is defined above with edge detection
    wire [3:0] immediate_phases = {
        (cpu_accessing && access_phase3) ? A[0] : motor_phase[3],
        (cpu_accessing && access_phase2) ? A[0] : motor_phase[2],
        (cpu_accessing && access_phase1) ? A[0] : motor_phase[1],
        (cpu_accessing && access_phase0) ? A[0] : motor_phase[0]
    };

    // Latched sense register - MAME behavior
    // MAME latches m_reg when seek_phase_w() is called (i.e., when phases are written).
    // The sense lookup uses this latched value, NOT the current phases.
    // This allows the ROM to set phases, then immediately read back a sense value
    // that persists even after phases are cleared.
    reg [2:0] latched_sense_reg;
    wire [3:0] latched_immediate_phases = {
        (cpu_accessing && access_phase3) ? A[0] : motor_phase[3],
        (cpu_accessing && access_phase2) ? A[0] : motor_phase[2],
        (cpu_accessing && access_phase1) ? A[0] : motor_phase[1],
        (cpu_accessing && access_phase0) ? A[0] : motor_phase[0]
    };
    wire [2:0] immediate_latched_sense_reg = (cpu_accessing && A[3:1] < 3'b100)
                                           ? latched_immediate_phases[2:0]
                                           : latched_sense_reg;

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            motor_phase <= 4'b0000;
            drive_on <= 1'b0;
            drive_sel <= 1'b0;
            q6 <= 1'b0;
            q7 <= 1'b0;
            mode_reg <= 8'h00;
            latched_sense_reg <= 3'b000;
            cpu_access_latched <= 1'b0;
        end else begin
            // Edge detection: clear latch when access ends
            if (!cpu_accessing) begin
                cpu_access_latched <= 1'b0;
            end

            // Process soft switch updates once per CPU access
            if (cpu_access_edge) begin
                cpu_access_latched <= 1'b1;
            // Any access to soft switch latches the bit from A[0]
            case (A[3:1])
                3'b000: motor_phase[0] <= A[0];  // $C0E0/$C0E1: Phase 0
                3'b001: motor_phase[1] <= A[0];  // $C0E2/$C0E3: Phase 1
                3'b010: motor_phase[2] <= A[0];  // $C0E4/$C0E5: Phase 2
                3'b011: motor_phase[3] <= A[0];  // $C0E6/$C0E7: Phase 3
                3'b100: drive_on      <= A[0];  // $C0E8/$C0E9: Motor
                3'b101: begin
                    drive_sel     <= A[0];  // $C0EA/$C0EB: Drive select
`ifdef SIMULATION
                    $display("IWM_WOZ: DRIVE_SEL %0d -> %0d (A=%04h is_35=%0d)", drive_sel, A[0], A, is_35_inch);
`endif
                end
                3'b110: q6            <= A[0];  // $C0EC/$C0ED: Q6
                3'b111: q7            <= A[0];  // $C0EE/$C0EF: Q7
            endcase

            // MAME behavior: Latch sense register index on EVERY phase access (SET or CLEAR)
            // MAME's control() always calls update_phases() which calls seek_phase_w() for all
            // phase register accesses. The m_reg value is updated to (phases & 7) | ss.
            if (A[3:1] < 3'b100) begin
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

            // Mode register write: WR + motor off + Q7=1 + Q6=1 + odd address
            // Use IMMEDIATE Q6/Q7 values (what they will become after this access)
            // This is critical: the ROM sets Q6=1 first, then writes to $C0EF (Q7=1) with mode value
            if (cpu_wr && !drive_on && immediate_q7 && immediate_q6 && A[0]) begin
                mode_reg <= {3'b000, D_IN[4:0]};
`ifdef SIMULATION
                $display("IWM_WOZ: MODE_REG <= %02h (fast=%0d D_IN=%02h q6=%0d q7=%0d imm_q6=%0d imm_q7=%0d)",
                         {3'b000, D_IN[4:0]}, D_IN[3], D_IN, q6, q7, immediate_q6, immediate_q7);
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

    // Drive is active when motor is spinning, 3.5" mode, and disk ready
    wire drive35_active = motor_spinning && is_35_inch && DISK_READY[2];

    flux_drive drive35 (
        .IS_35_INCH(1'b1),
        .DRIVE_ID(2'd1),
        .CLK_14M(CLK_14M),
        .RESET(RESET),
        .PHASES(motor_phase),
        .IMMEDIATE_PHASES(immediate_phases),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),  // Use immediate for same-cycle visibility
        .MOTOR_ON(motor_spinning && DISK_READY[2]),
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for direction gating
        .DISKREG_SEL(diskreg_sel),
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

    assign WOZ_TRACK3 = {1'b0, drive35_track} + (diskreg_sel ? 8'd80 : 8'd0);
    assign WOZ_TRACK3_BIT_ADDR = drive35_bram_addr;

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
        .MOTOR_ON(1'b0),                // No disk inertia tracking for empty drive
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for command processing
        .DISKREG_SEL(diskreg_sel),
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
        .MOTOR_ON(motor_spinning && DISK_READY[0]),
        .SW_MOTOR_ON(drive_on),         // Immediate motor state for direction gating
        .DISKREG_SEL(1'b0),
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
    wire flux_transition = (is_35_inch) ? ((drive_sel == 0) ? flux_transition_35 : flux_transition_35_2) :
                                         ((drive_sel == 0) ? flux_transition_525 : 1'b0);

    // Track which drive type's flux we're actually using (for window timing)
    wire flux_is_35_inch = is_35_inch;

    wire drive_active = is_35_inch ? drive35_active : drive525_active;
    wire current_wp = is_35_inch ? drive35_wp : drive525_wp;

    // Any disk spinning - used for IWM MOTOR_SPINNING independent of is_35_inch
    wire any_disk_spinning = drive35_motor_spinning || drive35_2_motor_spinning || drive525_motor_spinning;
    // Any disk ready - use disk mounted status, NOT spinup completion
    // The state machine must run as soon as motor is spinning (like MAME), not wait for spinup
    wire any_disk_ready = DISK_READY[2] || DISK_READY[0];

    //=========================================================================
    // Sense Mux - Select active drive's status sense
    //=========================================================================
    // Select between Drive 1 and Drive 2 based on drive_sel.

    wire drive_sense = (is_35_inch) ? ((drive_sel == 0) ? drive35_sense : drive35_2_sense) :
                                     ((drive_sel == 0) ? drive525_sense : 1'b1);

    // When motor is off (drive_on=0), MAME's m_floppy is null, so sense=1 (bit7=1)
    wire current_sense = drive_on ? drive_sense : 1'b1;

    wire current_motor_spinning = is_35_inch ? drive35_motor_spinning : drive525_motor_spinning;

    //=========================================================================
    // IWM Chip (Flux-Based Byte Decoding)
    //=========================================================================

    wire [7:0] iwm_data_out;

    // Disk mounted status
    wire disk_mounted = DISK_READY[2] ? 1'b1 :
                       DISK_READY[0] ? 1'b1 :
                       (is_35_inch ? DISK_READY[2] : DISK_READY[0]);

    iwm_flux iwm (
        .CLK_14M(CLK_14M),
        .RESET(RESET),
        .CEN(PH2),              // Clock enable (phi2) for CPU bus timing
        .ADDR(A[3:0]),
        .RD(cpu_rd),
        .WR(cpu_wr),
        .DATA_IN(D_IN),
        .DATA_OUT(iwm_data_out),

        // Soft switch state from this module (SINGLE SOURCE OF TRUTH)
        .SW_PHASES(motor_phase),
        .SW_MOTOR_ON(drive_on),
        .SW_DRIVE_SEL(drive_sel),
        .SW_Q6(q6),
        .SW_Q7(q7),
        .SW_MODE(immediate_mode),

        .FLUX_TRANSITION(flux_transition),
        .MOTOR_ACTIVE(immediate_motor),  // Motor command state (for status register) - use IMMEDIATE value
        .MOTOR_SPINNING(any_disk_spinning),  // Physical spinning (for flux decoding)
        .DISK_READY(any_disk_ready),
        .DISK_MOUNTED(disk_mounted),
        .IS_35_INCH(flux_is_35_inch),
        .SENSE_BIT(current_sense),
        .LATCHED_SENSE_REG(immediate_latched_sense_reg),  // Use immediate for same-cycle visibility
        .DISKREG_SEL(diskreg_sel),
        .FLUX_WRITE(),
        .DEBUG_RSH(),
        .DEBUG_STATE()
    );

    assign D_OUT = iwm_data_out;

    //=========================================================================
    // Motor Status Output
    //=========================================================================

    assign FLOPPY_MOTOR_ON = any_disk_spinning;

`ifdef SIMULATION
    // Debug: Monitor state changes
    reg [3:0] prev_phase;
    reg       prev_drive_on;
    reg       prev_motor_spinning;
    reg [31:0] debug_cycle;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            debug_cycle <= 0;
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
        if (motor_spinning != prev_motor_spinning) begin
            $display("IWM_WOZ: motor_spinning %0d -> %0d (drive_on=%0d ready=%04b is_35=%0d)",
                     prev_motor_spinning, motor_spinning, drive_on, DISK_READY, is_35_inch);
        end
        prev_phase <= motor_phase;
        prev_drive_on <= drive_on;
        prev_motor_spinning <= motor_spinning;

        // Periodic status when motor is on
        if (motor_spinning && (debug_cycle[19:0] == 20'h80000)) begin
            $display("IWM_WOZ: Status: is_35=%0d drive35_active=%0d drive525_active=%0d DISK_READY=%04b q6=%0d q7=%0d",
                     is_35_inch, drive35_active, drive525_active, DISK_READY, q6, q7);
            $display("IWM_WOZ: Track3=%0d BitAddr3=%0d BitCount3=%0d Data3=%02h",
                     drive35_track, drive35_bram_addr, WOZ_TRACK3_BIT_COUNT, WOZ_TRACK3_BIT_DATA);
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
