//
// iwm_controller.v: Simulates an Apple IIGS Integrated Wozniak Machine
//
// **REVISION 2**
// - Implemented Mode and Status registers based on the IWM specification.
// - Removed controller ROM, as this function is in the IIGS main ROM.
// - Added fast_mode control based on Mode Register bit 3.
// - Drive type (5.25"/3.5") is now selected via Mode Register bit 7.
//
module iwm_controller(

    // Global signals
    CLK_14M, CLK_7M_EN, Q3, PH0, PH2, RESET,
    // CPU bus interface
    IO_SELECT, DEVICE_SELECT, WR_CYCLE, VDA, A, D_IN, D_OUT,
    // Drive status
    DISK_READY,
    // External control/status
    DISK35,
    WRITE_PROTECT,
    // --- Expanded Track Memory Interface ---
    // Drive 1 (5.25")
    TRACK1, TRACK1_ADDR, TRACK1_DI, TRACK1_DO, TRACK1_WE, TRACK1_BUSY, FD_DISK_1,
    // Drive 2 (5.25")
    TRACK2, TRACK2_ADDR, TRACK2_DI, TRACK2_DO, TRACK2_WE, TRACK2_BUSY, FD_DISK_2,
    // Drive 3 (3.5", 800K)
    TRACK3, TRACK3_ADDR, TRACK3_SIDE, TRACK3_DI, TRACK3_DO, TRACK3_WE, TRACK3_BUSY, FD_DISK_3,
    // Drive 4 (3.5", 800K)
    TRACK4, TRACK4_ADDR, TRACK4_SIDE, TRACK4_DI, TRACK4_DO, TRACK4_WE, TRACK4_BUSY,
    // Motor status for clock slowdown
    FLOPPY_MOTOR_ON
);

    // I/O Port Declarations
    input           CLK_14M;
    input           CLK_7M_EN;
    input           Q3;
    input           PH0;
    input           PH2;
    input           IO_SELECT;
    input           DEVICE_SELECT;
    input           WR_CYCLE;        // 0=write cycle, 1=read cycle
    input           VDA;             // Valid Data Address from 65C816
    input           RESET;
    input [3:0]     DISK_READY;
    input [7:0]     DISK35;
    input           WRITE_PROTECT;
    input [15:0]    A;
    input [7:0]     D_IN;
    output [7:0]    D_OUT;

    // --- Interface for two 5.25" drives ---
    output [5:0]    TRACK1;
    output [13:0]   TRACK1_ADDR;   // 14-bit for consistency with 3.5" drives
    output [7:0]    TRACK1_DI;
    input [7:0]     TRACK1_DO;
    output          TRACK1_WE;
    input           TRACK1_BUSY;
    output          FD_DISK_1;      // Drive 1 is actively reading/writing

    output [5:0]    TRACK2;
    output [13:0]   TRACK2_ADDR;   // 14-bit for consistency with 3.5" drives
    output [7:0]    TRACK2_DI;
    input [7:0]     TRACK2_DO;
    output          TRACK2_WE;
    input           TRACK2_BUSY;
    output          FD_DISK_2;      // Drive 2 is actively reading/writing

    // --- Expanded interface for two 3.5" 800K drives ---
    output [6:0]    TRACK3;
    output [13:0]   TRACK3_ADDR;   // 14-bit for up to 10240-byte tracks
    output          TRACK3_SIDE;
    output [7:0]    TRACK3_DI;
    input [7:0]     TRACK3_DO;
    output          TRACK3_WE;
    input           TRACK3_BUSY;
    output          FD_DISK_3;      // Drive 3 is actively reading/writing

    output [6:0]    TRACK4;
    output [12:0]   TRACK4_ADDR;
    output          TRACK4_SIDE;
    output [7:0]    TRACK4_DI;
    input [7:0]     TRACK4_DO;
    output          TRACK4_WE;
    input           TRACK4_BUSY;

    // Motor status output for clock slowdown
    // Only triggers when motor is on AND a 5.25" floppy is actually mounted
    // This prevents false slow mode triggers during ROM probe when no floppy is present
    output          FLOPPY_MOTOR_ON;

    // --- Internal IWM Registers ---
    reg [3:0]       motor_phase;
    reg             drive_on;
    reg             drive_real_on;
    reg             drive2_select;      // Selects between drive 1/2 or 3/4
    reg             q6;
    reg             q7;                 // L6 and L7 state bits
    reg [7:0]       mode_reg;           // IWM Mode Register (lower 5 bits used)
    reg [7:0]       read_latch;         // Data read from disk

    // Motor timer registers (moved to module level for Verilator compatibility)
    reg [23:0]      spindown_delay;
    reg [23:0]      inactivity_timer;
    reg             drive_on_old;
    reg             motor_off_pending;
    reg             drive_real_on_prev;  // For debugging transitions

    // Registered drive selection for stable read_latch mux
    // This prevents glitches when D*_ACTIVE signals flicker during IWM register accesses
    // The mux uses this registered value instead of the combinational D*_ACTIVE signals
    reg [1:0]       read_latch_drive_sel;  // {is_35_inch, is_drive2}

    // --- Wires and Assignments ---
    wire [7:0]      d_out1, d_out2, d_out3, d_out4;
    // Per-drive motor state (each drive tracks its own spindown)
    wire            motor_spinning_1, motor_spinning_2, motor_spinning_3, motor_spinning_4;
    // Internal wires for drive track addresses (to debug port connection issues)
    wire [12:0]     drive1_track_addr;
    wire [12:0]     drive2_track_addr;
    assign TRACK1_ADDR = drive1_track_addr;
    assign TRACK2_ADDR = drive2_track_addr;
    // BUG FIX: Write mode requires Q7=1 AND Q6=0
    // Q7=1, Q6=1 is mode register write (not disk write)
    // Q7=1, Q6=0 is actual disk write mode
    wire            write_mode = q7 && ~q6;
    // BUG FIX: When CPU reads $C0EC (data register), the drive should be in read mode
    // regardless of stored Q7 state. Previously, if the ROM wrote to $C0EF (mode register,
    // which sets Q7=1) then immediately read $C0EC, write_mode would be 1, causing
    // apple_drive to not update data_reg with new disk bytes.
    wire            data_reg_access = (DEVICE_SELECT == 1'b1 && WR_CYCLE && A[3:0] == 4'hC);
    wire            effective_write_mode = write_mode && !data_reg_access;
    wire            fast_mode = mode_reg[3];      // Fast mode (2µs bit cell) is bit 3 of mode_reg
    // Drive type select from DISK35[6]
    wire            drive35_select = DISK35[6];
    reg             drive35_select_d;
    wire            read_disk = (DEVICE_SELECT == 1'b1 && A[3:0] == 4'hC);
    // Generate a data-read strobe when CPU reads DATA register (q7q6=00)
    // The DATA register is returned for ANY even address when Q6=Q7=0
    // The ROM reads from $C0E0, $C0E2, $C0E4 etc. - all should advance the disk
    // BUG FIX: Use address-derived Q6/Q7 values for immediate effect when accessing Q6/Q7 switches
    // When accessing $C0EC, Q6 becomes A[0]=0 immediately; use stored Q7
    // When accessing $C0EE, Q7 becomes A[0]=0 immediately; use stored Q6
    wire            implied_q6_strobe = (A[3:1] == 3'b110) ? A[0] : q6;
    wire            implied_q7_strobe = (A[3:1] == 3'b111) ? A[0] : q7;
    // Data read strobe fires for DATA register reads (even addresses)
    // The ROM at both FF:4717 (motor check) and FF:5B57 (mode verify) expects IWM behavior.
    // The IIgs ROM reads data from $C0E6 (Phase 3) during boot, and expects the disk
    // state to advance (consuming the byte).
    //
    // BUG FIX: Only fire strobe when reading DATA register ($C0EC = A[3:0]=4'hC).
    // Previously this fired on ANY even address (A[0]=0), which caused reads of
    // phase registers ($C0E0, $C0E2, $C0E4) to consume disk bytes. The ROM reads
    // phase registers between data reads, causing valid disk data to be lost.
    wire            data_read_strobe = (DEVICE_SELECT == 1'b1 && WR_CYCLE && PH2 &&
                                        (A[3:0] == 4'hC) && ({current_q7, current_q6} == 2'b00));
    // Keep data_access_prev for debug purposes
    reg             data_access_prev;
`ifdef SIMULATION
    reg prev_data_read_strobe;
    reg [31:0] strobe_cnt;
    always @(posedge CLK_14M) begin
        if (RESET) strobe_cnt <= 0;
        prev_data_read_strobe <= data_read_strobe;
        if (data_read_strobe && !prev_data_read_strobe) begin
            strobe_cnt <= strobe_cnt + 1;
            $display("IWM: DATA_READ_STROBE #%0d rising (DEVICE_SELECT=%0d WR_CYCLE=%0d q7q6=%0d%0d A[0]=%0d strobe=%0d prev=%0d A=%h)",
                     strobe_cnt, DEVICE_SELECT, WR_CYCLE, q7, q6, A[0], data_read_strobe, data_access_prev, A[3:0]);
        end
        // Debug: trace data_read_strobe transitions
        if (data_read_strobe != data_access_prev && strobe_cnt < 20) begin
            $display("IWM: data_read_strobe %0d -> %0d (DEVICE_SELECT=%0d WR_CYCLE=%0d q7q6=%0d%0d A[3:0]=%h)",
                     data_access_prev, data_read_strobe, DEVICE_SELECT, WR_CYCLE, implied_q7_strobe, implied_q6_strobe, A[3:0]);
        end
    end
`endif
    // BUG FIX: write_reg must only be true on CPU WRITE operations, not reads.
    // WR_CYCLE=0 means write cycle, WR_CYCLE=1 means read cycle.
    // Without !WR_CYCLE check, CPU reads from $C0ED would trigger write_reg,
    // causing data_reg in apple_drive to be overwritten with D_IN during disk reads.
    wire            write_reg = (DEVICE_SELECT == 1'b1 && !WR_CYCLE && A[3:2] == 2'b11 && A[0] == 1'b1);

    // Signal for any IWM data access (not PH2-gated) - used to reset inactivity timer
    // This fires on ANY IWM read access, not just PH2-aligned ones.
    // Critical for slow mode where PH2 only fires once per 14 clocks, but we need
    // to detect activity more frequently to prevent spurious motor timeouts.
    wire            any_data_access = (DEVICE_SELECT == 1'b1 && WR_CYCLE && (A[0] == 1'b0));

    // Signal for data register reads - fires when Q6=Q7=0 (data mode) and ANY IWM address.
    // This is used by apple_drive to set byte_consumed for proper bit 7 behavior.
    //
    // When Q6=Q7=0, ANY IWM read returns the data register contents (latched disk byte).
    // All such reads must set byte_consumed=1 so that bit7 clears, signaling to the ROM
    // that this is the same byte (not a new one). Otherwise the ROM sees bit7=1 forever.
    //
    // The ROM's pattern: read C0EC to get byte, read C0E0/C0E2/C0E4 for processing,
    // then read again to check for next byte (bit7=0 means wait, bit7=1 means new byte).
    //
    // BUG FIX (2026-01-04): Removed PH2 gating! PH2 goes low between CPU read cycles,
    // which causes prev_data_reg_read to get stuck at 1 (from the previous PH2-high cycle).
    // On the next PH2-high cycle, the rising edge isn't detected because prev is already 1.
    // By removing PH2, data_reg_read stays high for the entire read burst, and the rising
    // edge is only detected once at the START of the burst.
    //
    // BUG FIX (2026-01-04): Only fire for DATA register (A[3:0]==0xC = $C0EC), not for
    // phase register reads ($C0E0, $C0E2, etc.). When ROM reads phase registers with
    // Q6=Q7=0, it should NOT set byte_consumed. Previously, all even addresses set
    // byte_consumed, causing bit 7 to stay 0 even after new bytes arrived. This broke
    // 3.5" disk boot - ROM would find D5 but then see bit 7=0 for subsequent bytes.
    wire            data_reg_read = (DEVICE_SELECT == 1'b1 && WR_CYCLE &&
                                     (A[3:0] == 4'hC) &&
                                     ({current_q7, current_q6} == 2'b00));

    // Effective drive-type selection: prefer any ready 5.25" if 3.5" is selected but not ready
    wire any_525_ready = DISK_READY[0] | DISK_READY[1];
    wire any_35_ready  = DISK_READY[2] | DISK_READY[3];
    wire eff_drive35   = any_525_ready ? 1'b0 : (drive35_select & any_35_ready);

    // FLOPPY_MOTOR_ON only triggers when motor is on AND a 5.25" floppy is mounted
    // Add "sticky" behavior: keep signal high for ~100ms after motor turns off to prevent
    // rapid slow mode toggling during ROM boot sequence
    reg [20:0] motor_sticky_counter;  // ~100ms at 14MHz
    wire raw_floppy_motor = (drive_on | drive_real_on) & any_525_ready;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            motor_sticky_counter <= 21'd0;
        end else if (raw_floppy_motor) begin
            motor_sticky_counter <= 21'd1400000;  // ~100ms at 14MHz
        end else if (motor_sticky_counter > 0) begin
            motor_sticky_counter <= motor_sticky_counter - 1'b1;
        end
    end
    assign FLOPPY_MOTOR_ON = raw_floppy_motor | (motor_sticky_counter > 0);
`ifdef SIMULATION
    // Trace when we override a 3.5" selection due to only 5.25" media being present
    always @(posedge CLK_14M) begin
        if (drive35_select && !any_35_ready && any_525_ready) begin
            $display("IWM DBG: fallback to 5.25\" (3.5\" selected but no 3.5 media ready)");
        end
    end
    // Debug: trace raw_floppy_motor signal components
    reg prev_raw_floppy_motor;
    reg prev_any_525_ready;
    always @(posedge CLK_14M) begin
        if (raw_floppy_motor != prev_raw_floppy_motor) begin
            $display("IWM: raw_floppy_motor %0d -> %0d (drive_on=%0d drive_real_on=%0d any_525_ready=%0d) t=%0t",
                     prev_raw_floppy_motor, raw_floppy_motor, drive_on, drive_real_on, any_525_ready, $time);
        end
        if (any_525_ready != prev_any_525_ready) begin
            $display("IWM: any_525_ready %0d -> %0d (DISK_READY=%04b) t=%0t",
                     prev_any_525_ready, any_525_ready, DISK_READY, $time);
        end
        prev_raw_floppy_motor <= raw_floppy_motor;
        prev_any_525_ready <= any_525_ready;
    end
`endif
    // Drive activity signals based on effective selects and motor state
    // Drive selection is captured at each motor-on command (drive_on 0->1) to match
    // MAME's dynamic drive selection behavior. When ROM switches drive types and turns
    // motor on, we switch to the new drive type. This allows proper timeout on empty
    // drives during the probe sequence.
    //
    // read_latch_drive_sel[1] = captured eff_drive35 (0=5.25", 1=3.5")
    // read_latch_drive_sel[0] = captured drive2_select (0=drive 1/3, 1=drive 2/4)
    wire D1_ACTIVE = drive_real_on & ~read_latch_drive_sel[0] & ~read_latch_drive_sel[1];
    wire D2_ACTIVE = drive_real_on &  read_latch_drive_sel[0] & ~read_latch_drive_sel[1];
    wire D3_ACTIVE = drive_real_on & ~read_latch_drive_sel[0] &  read_latch_drive_sel[1];
    wire D4_ACTIVE = drive_real_on &  read_latch_drive_sel[0] &  read_latch_drive_sel[1];

    // Export drive active signals for track buffer coordination
    assign FD_DISK_1 = D1_ACTIVE;
    assign FD_DISK_2 = D2_ACTIVE;
    assign FD_DISK_3 = D3_ACTIVE;

    // selected_ready: Use live eff_drive35/drive2_select for initial selection,
    // but once motor is running, use captured values for DATA register consistency
    wire selected_ready = drive_real_on ?
                          ((~read_latch_drive_sel[1] & ~read_latch_drive_sel[0] & DISK_READY[0]) |
                           (~read_latch_drive_sel[1] &  read_latch_drive_sel[0] & DISK_READY[1]) |
                           ( read_latch_drive_sel[1] & ~read_latch_drive_sel[0] & DISK_READY[2]) |
                           ( read_latch_drive_sel[1] &  read_latch_drive_sel[0] & DISK_READY[3])) :
                          ((~eff_drive35 & ~drive2_select & DISK_READY[0]) |
                           (~eff_drive35 &  drive2_select & DISK_READY[1]) |
                           ( eff_drive35 & ~drive2_select & DISK_READY[2]) |
                           ( eff_drive35 &  drive2_select & DISK_READY[3]));

    // live_selected_ready: ALWAYS uses current eff_drive35/drive2_select, not captured values.
    // BUG FIX (2026-01-04): Used for STATUS register to match MAME's per-device motor state.
    // When ROM switches from 3.5" to empty 5.25" drive:
    //   - selected_ready (captured) still points to 3.5" which has a disk = 1
    //   - live_selected_ready uses current 5.25" selection which has no disk = 0
    // This allows status register to return bit 5 = 0 (no disk = motor off equivalent),
    // letting ROM's loop at FF:5EE3 exit and continue the probe sequence.
    wire live_selected_ready = ((~eff_drive35 & ~drive2_select & DISK_READY[0]) |
                                (~eff_drive35 &  drive2_select & DISK_READY[1]) |
                                ( eff_drive35 & ~drive2_select & DISK_READY[2]) |
                                ( eff_drive35 &  drive2_select & DISK_READY[3]));

    // Per-drive motor state selection: ALWAYS uses current drive selection.
    // Each apple_drive tracks its own motor spindown. This mux selects the motor
    // state of the currently addressed drive for status register queries.
    // MAME model: when ROM queries status for 5.25" drive (empty), that specific
    // drive's motor is off, even if 3.5" drive motor is still spinning.
    wire live_selected_motor_spinning = ((~eff_drive35 & ~drive2_select & motor_spinning_1) |
                                         (~eff_drive35 &  drive2_select & motor_spinning_2) |
                                         ( eff_drive35 & ~drive2_select & motor_spinning_3) |
                                         ( eff_drive35 &  drive2_select & motor_spinning_4));


    // Edge detection for DEVICE_SELECT to prevent multiple state changes per CPU cycle
    reg device_select_prev;
    reg [3:0] A_prev;
    wire device_select_edge = DEVICE_SELECT && !device_select_prev;
    wire address_change = (A[3:0] != A_prev);

    // --- IWM State Machine and Register Access ---
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            motor_phase <= 4'b0;
            drive_on <= 1'b0;
            drive2_select <= 1'b0;
            q6 <= 1'b0;
            q7 <= 1'b0;
            mode_reg <= 8'b0; // All mode bits reset to 0
            drive35_select_d <= 1'b0;
            device_select_prev <= 1'b0;
            A_prev <= 4'h0;
            data_access_prev <= 1'b0;  // Initialize edge detection register
        end else begin
            // Track DEVICE_SELECT and A for edge/change detection
            device_select_prev <= DEVICE_SELECT;
            if (DEVICE_SELECT) A_prev <= A[3:0];
            // Track data_read_strobe for debug
            data_access_prev <= data_read_strobe;

        if (device_select_edge || (DEVICE_SELECT && address_change)) begin
            // IWM soft switches respond to address bits, but with important caveats:
            // - Stepper phases ($C0E0-$C0E7): toggle on any access
            // - Motor on/off ($C0E8/$C0E9): toggle on any access
            // - Drive select ($C0EA/$C0EB): toggle on any access
            // - Q6/Q7 ($C0EC-$C0EF): toggle on any access, but also used for data reads
            //
            // CRITICAL FIX: When reading from $C0EC or $C0EE with Q6=0/Q7=0 (data read mode),
            // we should NOT be changing motor or drive_select states. The CPU is reading
            // data, not trying to control the motor. Only latch Q6/Q7 on these addresses.
            //
            // The confusion arises because $C0EC/$C0EE accesses happen during disk reads,
            // and those addresses happen to have the same A[3:0] pattern that would
            // otherwise control motor/drive_select. But in the actual Apple II/IIgs,
            // the IWM knows the difference based on which soft switch is being accessed.

            if (A[3] == 1'b0) begin
                // $C0E0-$C0E7: Stepper motor phases - always latch
                motor_phase[A[2:1]] <= A[0];
`ifdef SIMULATION
                $display("IWM SW: motor_phase[%0d] <= %0d (A=%h WR=%0d)", A[2:1], A[0], A[3:0], !WR_CYCLE);
`endif
            end else begin
                // $C0E8-$C0EF: Motor, drive select, Q6, Q7
                case (A[2:1])
                    2'b00: begin
                        // $C0E8/$C0E9: Motor control - latch the state
                        drive_on <= A[0];
`ifdef SIMULATION
                        $display("IWM SW: drive_on <= %0d (A=%h WR=%0d)", A[0], A[3:0], !WR_CYCLE);
`endif
                    end
                    2'b01: begin
                        // $C0EA/$C0EB: Drive select - latch the state
                        // CRITICAL FIX for 3.5" drives:
                        // When actively reading from a 3.5" drive (motor on, 3.5" mode, drive ready),
                        // do NOT change drive2_select on read accesses. The ROM's polling loop
                        // reads @eb ($C0EB) as part of timing/sync detection, not to switch drives.
                        // Allowing the switch causes the ROM to accidentally move to an empty drive
                        // and lose the D5 AA 96 prolog it just found.
                        // Only allow drive switching when: motor off, write cycle, or 5.25" mode.
                        if (!(drive_real_on && eff_drive35 && WR_CYCLE)) begin
                            drive2_select <= A[0];
`ifdef SIMULATION
                            $display("IWM SW: drive2_select <= %0d (A=%h WR=%0d)", A[0], A[3:0], !WR_CYCLE);
`endif
                        end
`ifdef SIMULATION
                        else begin
                            $display("IWM SW: drive2_select change BLOCKED (3.5\" active read) A=%h WR=%0d", A[3:0], !WR_CYCLE);
                        end
`endif
                    end
                    2'b10: begin
                        // $C0EC/$C0ED: Q6 control - always latch (needed for data reads)
                        q6 <= A[0];
`ifdef SIMULATION
                        $display("IWM SW: q6 <= %0d (A=%h WR=%0d)", A[0], A[3:0], !WR_CYCLE);
`endif
                    end
                    2'b11: begin
                        // $C0EE/$C0EF: Q7 control - always latch (needed for data reads)
                        q7 <= A[0];
`ifdef SIMULATION
                        $display("IWM SW: q7 <= %0d (A=%h WR=%0d)", A[0], A[3:0], !WR_CYCLE);
`endif
                    end
                endcase
            end
            
            // Handle Mode Register writes: only when motor is off, state q7=1,q6=1 and odd address (A0=1)
            // BUG FIX: Use address-derived q7/q6 values, not the registered values which haven't been
            // updated yet (non-blocking assignment). The ROM accesses $C0EF expecting immediate q7=1.
            // current_q7 when A[3:1]==111: A[0] else q7. For $C0EF: A[3:0]=1111, so current_q7=A[0]=1
            // current_q6 when A[3:1]==110: A[0] else q6. For $C0EF: A[3:1]=111 (not 110), so current_q6=q6
            // So for mode write at $C0EF: we need q6=1 from previous $C0ED access, and A[3:0]=0xF
            // The correct condition is: write cycle, motor off, accessing $C0EF (A[3:0]=0xF), and q6=1
            if (!WR_CYCLE && !drive_on && A[3:0] == 4'hF && q6) begin
                mode_reg <= {3'b000, D_IN[4:0]};
`ifdef SIMULATION
                $display("IWM: MODE_REG <= %02h (fast=%0d)", {3'b000,D_IN[4:0]}, D_IN[3]);
`endif
            end

            // Opportunistic motor auto-start on DATA register reads if a disk is ready
            // This mirrors firmware behavior which normally turns on the motor; it helps the sim progress.
            // IMPORTANT: Do NOT auto-start motor when no disk is mounted - this causes the boot ROM
            // to enter a read loop that never finds valid data and then jumps to Applesoft
            // NOTE: Check drive_real_on (actual motor state) not drive_on (command state)
            // because drive_on may have just been set to 0 in this same cycle, but drive_real_on
            // reflects the actual delayed motor state after spindown timeout
            // BUG FIX: Only auto-start on actual DATA register reads ($C0EC/$C0EE, q7q6=00), NOT on
            // stepper phase addresses ($C0E0-$C0E7) which happen to have q7q6=00 after reset.
            // BUG FIX 2: Use ADDRESS-DERIVED q6/q7, not stored values.
            // For $C0EC: A[3:1]=110, A[0]=0 -> implied_q6=0
            // For $C0EE: A[3:1]=111, A[0]=0 -> implied_q7=0
            // Auto-start should trigger when BOTH implied q6 AND implied q7 are 0
            // BUG FIX 3: Only trigger for addresses $C0EC-$C0EF (A[3:2]=11), not stepper phases
            if (WR_CYCLE && selected_ready && !drive_real_on && (A[3:2] == 2'b11)) begin
                // Check if current access implies q6=0 and q7=0 (DATA read mode)
                // implied_q6_is_0: if accessing q6 register (A[3:1]=110), check A[0]; else use stored q6
                // implied_q7_is_0: if accessing q7 register (A[3:1]=111), check A[0]; else use stored q7
                if (((A[3:1] == 3'b110) ? (A[0] == 1'b0) : (q6 == 1'b0)) &&
                    ((A[3:1] == 3'b111) ? (A[0] == 1'b0) : (q7 == 1'b0))) begin
                    drive_on <= 1'b1;
`ifdef SIMULATION
                    $display("IWM: MOTOR ON (auto) due to DATA read @%02h implied_q7q6=00 and disk ready (drive_real_on was 0) selected_ready=%0d DISK_READY=%04b any_525_ready=%0d t=%0t", A[7:0], selected_ready, DISK_READY, any_525_ready, $time);
`endif
                end
            end
`ifdef SIMULATION
            // Debug: log when ROM tries to access disk with no disk mounted
            if (WR_CYCLE && !selected_ready && !drive_on && ({q7,q6} == 2'b00)) begin
                $display("IWM: NO_DISK - not auto-starting motor for read @%02h (no disk mounted)", A[7:0]);
            end
`endif
        end
        // Monitor 3.5"/5.25" select changes
`ifdef SIMULATION
        if (drive35_select != drive35_select_d) begin
            $display("IWM DBG: drive35_select -> %0d (%s)", drive35_select, drive35_select?"3.5\"":"5.25\"");
            drive35_select_d <= drive35_select;
        end
`endif
        end // else begin (not RESET)
    end

    // Mux the data input from the selected drive into the read latch
    // BUG FIX: Use registered drive selection (read_latch_drive_sel) instead of
    // combinational D*_ACTIVE signals. The D*_ACTIVE signals can flicker during
    // IWM register accesses when DEVICE_SELECT or address lines change momentarily.
    // This caused read_latch to briefly return 0x00, corrupting the data seen by CPU.
    // The registered drive selection is stable and only updates when motor is on
    // and no register access is in progress.
    //
    // BUG FIX (2026-01-04): When ROM switches drive types (3.5" <-> 5.25") while motor
    // is running from a previous probe, return 0xFF for the NEW drive type.
    // MAME returns 0xFF when motor is not active (iwm.cpp line 280):
    //   case 0x00: return m_active ? m_data : 0xff;
    // Returning 0xFF (bit 7 set) indicates "data valid but no sync" rather than
    // 0x00 (bit 7 clear) which might indicate "drive not ready".
    wire read_latch_drive_mismatch = eff_drive35 != read_latch_drive_sel[1];
    always @(*) begin
        if (!drive_real_on) begin
            read_latch = 8'hFF;  // Match MAME: return 0xFF when motor not active
        end else if (read_latch_drive_mismatch) begin
            // ROM is asking for different drive type than captured - return 0xFF
            // to match MAME's behavior for empty/inactive drives
            read_latch = 8'hFF;
        end else begin
            case (read_latch_drive_sel)
                2'b00: read_latch = d_out1;  // Drive 1 (5.25")
                2'b01: read_latch = d_out2;  // Drive 2 (5.25")
                2'b10: read_latch = d_out3;  // Drive 3 (3.5")
                2'b11: read_latch = d_out4;  // Drive 4 (3.5")
            endcase
        end
    end
    
`ifdef SIMULATION
    // Debug drive data changes
    reg [7:0] prev_d_out1, prev_d_out2, prev_d_out3, prev_d_out4;
    reg [12:0] prev_track1_addr, prev_track2_addr;
    reg [7:0] debug_count;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            prev_d_out1 <= 8'h00; prev_d_out2 <= 8'h00; prev_d_out3 <= 8'h00; prev_d_out4 <= 8'h00;
            prev_track1_addr <= 13'h0000; prev_track2_addr <= 13'h0000;
            debug_count <= 8'd0;
        end else begin
            if (debug_count < 8'd50) begin
                if (D1_ACTIVE && d_out1 != prev_d_out1) begin
                    $display("IWM: DRIVE1 D_OUT changed %02h -> %02h (TRACK1_ADDR=%04h)", prev_d_out1, d_out1, TRACK1_ADDR);
                    debug_count <= debug_count + 1;
                end
                if (D2_ACTIVE && d_out2 != prev_d_out2) begin
                    $display("IWM: DRIVE2 D_OUT changed %02h -> %02h (TRACK2_ADDR=%04h)", prev_d_out2, d_out2, TRACK2_ADDR);
                    debug_count <= debug_count + 1;
                end
                if (D1_ACTIVE && TRACK1_ADDR != prev_track1_addr) begin
                    $display("IWM: DRIVE1 TRACK_ADDR changed %04h -> %04h", prev_track1_addr, TRACK1_ADDR);
                    debug_count <= debug_count + 1;
                end
            end
            prev_d_out1 <= d_out1; prev_d_out2 <= d_out2; prev_d_out3 <= d_out3; prev_d_out4 <= d_out4;
            prev_track1_addr <= TRACK1_ADDR; prev_track2_addr <= TRACK2_ADDR;
        end
    end
`endif
    
    // The IWM Status Register (q7=0,q6=1)
    // When no drives available: return 0xC0 | last_mode_wr (bits 7-6 = 11, bits 4-0 = last mode written)
    // When drives available: standard status format
    // Bit7: write-protect/sense (1=protected). For now, assume protected.
    // Bit6: reserved/sense (not implemented)
    // Bit5: motor on status (reflects physical motor state with delay, matching MAME)
    //       MAME keeps bit 5 = 1 during MODE_DELAY after motor-off command
    // Bits4:0: mode bits
    wire write_protect = WRITE_PROTECT;
    // BUG FIX (2026-01-04): Use per-drive motor state for status bit 5.
    // MAME uses per-device motor state model where each drive tracks its own spindown.
    // When ROM switches to a different drive (e.g., empty 5.25"), the status register
    // should reflect THAT drive's motor state, not the global motor state.
    // This is critical for the ROM's probe sequence which checks each drive type.
    //
    // live_selected_motor_spinning: motor state of currently selected drive
    // - 3.5" drive spinning + ROM queries empty 5.25" -> bit 5 = 0 (5.25" motor off)
    // - This lets ROM's wait loop at FF:5EE3 exit and continue probing
    wire motor_for_status = live_selected_motor_spinning;

    // 5.25" status register: bit 7 = write protect
    wire [7:0] normal_status_reg_525 = { write_protect,
                                         1'b0,
                                         motor_for_status,  // Motor state
                                         mode_reg[4:0] };

    // BUG FIX (2026-01-04): 3.5" drives use status sensing via motor phases.
    // When ROM reads status register ($C0EE, q7=0 q6=1), bit 7 should return
    // status35_bit based on current phase pattern, NOT write_protect!
    // MAME shows: 0x2f (bit7=0) and 0xaf (bit7=1) alternating based on phase.
    // This is critical for ROM's 3.5" drive detection and boot sequence.
    // The status35_bit is computed below based on {CA1,CA0,SEL,CA2} pattern.
    // NOTE: status35_bit is defined later, so we use a forward reference wire.
    wire [7:0] normal_status_reg_35 = { status35_bit,
                                        1'b0,
                                        motor_for_status,  // Motor state
                                        mode_reg[4:0] };

    // Select appropriate status register based on drive type
    wire [7:0] normal_status_reg = eff_drive35 ? normal_status_reg_35 : normal_status_reg_525;

    // BUG FIX: Use mode_reg[4:0] instead of last_mode_wr for immediate timing.
    // MAME updates m_status immediately when mode is written (mode_w function).
    // Using the delayed last_mode_wr caused the ROM handshake at FF:4720 to fail
    // because the status read saw the old mode value before CLK_7M_EN updated it.
    wire [7:0] no_drive_status_reg = 8'hC0 | {3'b000, mode_reg[4:0]};  // Ready status with immediate mode bits
    // BUG FIX (2026-01-04): Use live_selected_ready for status register, not captured selected_ready.
    // This matches MAME's per-device motor state model. When ROM switches from 3.5" to empty 5.25",
    // live_selected_ready = 0 (no 5.25" disk), so we return no_drive_status_reg with bit 5 = 0.
    // The captured selected_ready would still show 1 (3.5" disk present) and return bit 5 = 1.
    wire [7:0] status_reg = live_selected_ready ? normal_status_reg : no_drive_status_reg;
    
    // Write-handshake register - bit 7 high indicates buffer ready, bit 6 clear indicates no underrun
    wire [7:0] handshake_reg = 8'h80;  // Buffer ready (bit 7=1), no underrun (bit 6=0) - matches iwm.cpp logic
    
    // Current Q6/Q7 state based on access address (real-time during access)
    wire current_q6 = (A[3:1] == 3'b110) ? A[0] : q6;  // C0EC/C0ED access sets Q6, otherwise use stored Q6
    // For C0EC reads when a disk is present and motor is on, force Q7=0 for DATA register.
    // The ROM writes mode register via C0EF (sets q7=1) then reads C0EC without
    // first accessing C0EE. This applies to BOTH 3.5" and 5.25" drives.
    // BUG FIX (2026-01-04): Use selected_ready to check if disk is present.
    // - With disk: Q7=0 forced, returns DATA register (actual disk bytes)
    // - Without disk: Q7 not forced, returns HANDSHAKE (0x80) - ROM detects no disk
    // This fixes 3.5" boot (Pirates.po) while preserving "no disk" detection for regression.
    wire diskii_compat_mode = selected_ready && (drive_on || drive_real_on);
    wire current_q7 = (diskii_compat_mode && A[3:0] == 4'hC) ? 1'b0 :  // 5.25" mode $C0EC forces Q7=0
                      (A[3:1] == 3'b111) ? A[0] : q7;                  // C0EE/C0EF sets Q7, otherwise stored
    
    // The key issue: ROM at FF:4720-4729 is checking track 0 status by reading 0xEE (data register, q7=0,q6=0)
    // and testing bit 5 of the result. For 5.25" drives, this should return track status information, not raw disk data.
    // According to Apple II documentation, when checking track 0, the drive should return status info, not disk data.
    
    // Track 0 detection logic for 5.25" drives
    // Get actual track position from the selected drive
    // TRACK1/TRACK2 are [5:0] giving 0-34 track numbers from the drives
    wire [5:0] drive1_track = TRACK1;
    wire [5:0] drive2_track = TRACK2;
    wire drive1_at_track0 = (drive1_track == 6'd0);
    wire drive2_at_track0 = (drive2_track == 6'd0);
    wire drive525_at_track0 = drive2_select ? drive2_at_track0 : drive1_at_track0;
    
    // 3.5" drive status logic based on motor phases
    // MAME encoding (from floppy.cpp mac_floppy_device::seek_phase_w):
    //   m_reg = (phases & 7) | (m_actual_ss ? 8 : 0);
    // This means:
    //   Bits 0-2: motor phases (CA0, CA1, CA2)
    //   Bit 3: side select (from DISK35[7] which is DISKREG bit 7)
    // BUG FIX (2026-01-05): Previous encoding was scrambled and wrong!
    wire [3:0] status35_state = {DISK35[7], motor_phase[2:0]};
    wire drive35_at_track0 = 1'b1;  // Assume 3.5" drive at track 0 for boot progression

    // 3.5" status register - returns status bit in bit 7 based on phase pattern
    // Reference: MAME floppy.cpp mac_floppy_device::wpt_r()
    // State values match MAME's encoding:
    //   0x0: Step direction (m_dir) - return 0 for inward
    //   0x1: Step signal - always return 1 (true)
    //   0x2: Motor on (m_mon) - return motor state
    //   0x3: Disk change (!m_dskchg) - return 0 (no change)
    //   0x4: Index pulse - return 0
    //   0x5: Superdrive (m_has_mfm) - return 0 (not superdrive)
    //   0x6: Double-sided (m_sides == 2) - return 1 for 800K disks
    //   0x7: Drive exists - return 0 (false = drive exists)
    //   0x8: Disk in place (true if NO disk) - return 0 if disk present
    //   0x9: Write protected (!m_wpt) - return 0 (not protected)
    //   0xA: Not on track 0 (m_cyl != 0) - return 0 if at track 0
    //   0xB: Tachometer - return 0
    //   0xC: Index pulse (same as 0x4) - return 0
    //   0xD: MFM mode - return 0 (GCR mode)
    //   0xE: Ready (m_ready) - return 1 if ready
    //   0xF: HD disk - return 0 (not HD)
    reg status35_bit;
    always @(*) begin
        case (status35_state)
            4'h0: status35_bit = 1'b0;  // Step direction = inward
            4'h1: status35_bit = 1'b1;  // Step signal = always true (ROM expects bit7=1)
            4'h2: status35_bit = drive_real_on ? 1'b0 : 1'b1;  // Motor on: 0=on, 1=off
            4'h3: status35_bit = 1'b0;  // Disk change = no change
            4'h4: status35_bit = 1'b0;  // Index pulse
            4'h5: status35_bit = 1'b0;  // Superdrive = no
            4'h6: status35_bit = 1'b1;  // Double-sided = yes
            4'h7: status35_bit = 1'b0;  // Drive exists = yes (0 means exists)
            4'h8: status35_bit = ~selected_ready;  // Disk in place: 0=present, 1=no disk
            4'h9: status35_bit = 1'b0;  // Write protected = no
            4'hA: status35_bit = ~drive35_at_track0;  // Not at track 0: 0=at track0
            4'hB: status35_bit = 1'b0;  // Tachometer
            4'hC: status35_bit = 1'b0;  // Index pulse (same as 0x4)
            4'hD: status35_bit = 1'b0;  // MFM mode = no (GCR mode)
            4'hE: status35_bit = drive_real_on ? 1'b0 : 1'b1;  // Ready: 0=ready when motor on
            4'hF: status35_bit = 1'b0;  // HD disk = no
            default: status35_bit = 1'b0;
        endcase
    end
    wire [7:0] status35_value = {status35_bit, 7'b0000000};  // Status in bit 7

    // Track 0 status value: bit 5 should be 0 when at track 0, 1 when not at track 0
    // ROM loop: eor $c0ee; and #$1f; bne loop  -> continues loop if bit 5 is set
    wire [7:0] track0_status_525 = {2'b11, ~drive525_at_track0, mode_reg[4:0]};  // Bit 5 clear when at track 0
    wire [7:0] track0_status_35 = status35_value;  // Use full status register for 3.5"
    
    // Track status check ONLY when motor is OFF and we're probing for track 0
    // When motor is ON, always return actual disk data, not track status
    // This was incorrectly overriding all reads from $C0EE which broke disk booting
    // BUG FIX: Restrict to 3.5" drives only (standard Disk II doesn't support this via $C0EE)
    wire track_status_check = (A[3:0] == 4'hE) && ({current_q7, current_q6} == 2'b00) && selected_ready && !drive_on && eff_drive35;
    // No-drive data read: any data register read (q7=0, q6=0) when no floppy disk is mounted
    wire no_drive_data_read = ({current_q7, current_q6} == 2'b00) && !selected_ready;
    wire [7:0] stub_status = 8'hC0 | {3'b000, mode_reg[4:0]};
    
    // Select appropriate track status
    wire [7:0] track_status_value = eff_drive35 ? track0_status_35 : track0_status_525;
    
    // No-drive data register value:
    // For 5.25" (original behavior):
    // - Bit 7 = 1 (valid nibble marker - needed for FF:581F to exit)
    // - Bit 6 = 1 (reserved)
    // - Bit 5 = 0 (at track 0 / no drive - exits IIgs ROM loop at FF:4717)
    // - Bits 4:0 = mode_reg (echoes back written value for handshake at FF:4723-4729)
    // Note: C661 loop has timeout via Y counter, so bit 7=1 is OK there
    //
    // For 3.5" drives with no disk:
    // - Bit 7 = 0 (NO valid nibble - ROM quickly times out and checks next drive)
    // - This is critical for multi-drive probing: when ROM finds D5 on drive 1 then
    //   checks drive 2 (which is empty), bit 7=0 makes it timeout and return to drive 1.
    // - Using bit 7=1 for empty 3.5" drives causes ROM to wait indefinitely for sync.
    // BUG FIX: Use mode_reg[4:0] for immediate timing (same as no_drive_status_reg fix)
    wire [7:0] no_drive_data_reg_525 = {2'b11, 1'b0, mode_reg[4:0]};  // $C0 | mode with bit 5 clear
    wire [7:0] no_drive_data_reg_35  = {2'b00, 1'b0, mode_reg[4:0]};  // $00 | mode - bit 7=0 for timeout
    wire [7:0] no_drive_data_reg = eff_drive35 ? no_drive_data_reg_35 : no_drive_data_reg_525;

    // Data register output logic:
    // - No disk mounted: return no_drive_data_reg ($C0 | mode_reg, bit 5 clear)
    //   This passes ROM checks: FF:4717 (bit5=0), FF:4720 (bits4:0 match), FF:581F (bit7=1)
    // - Disk mounted, motor off: return $FF
    // - Disk mounted, motor on: return actual data from read_latch
    // - Track status check: return track0 status for stepper positioning
    // NOTE: Use drive_real_on (actual motor state) not drive_on (command state)
    // because the motor has a 1-second spindown delay, and we should return real data
    // during that delay period even if drive_on was cleared
    // The Apple IIgs ALWAYS has an IWM controller, regardless of whether a 5.25" or 3.5" drive
    // is attached. The IWM status register (with mode bits) must always be returned.
    // NOTE: The MiSTer disk_ii.v returns 0x00 for status because it emulates an Apple //e
    // which has a Disk II controller (no IWM). The IIgs is different - it always has IWM.
    // The ROM at both FF:4717 (motor check) and FF:5B57 (mode verify) expects IWM behavior.
    wire [7:0] status_for_drive = status_reg;

    // DATA register output logic - matches MAME iwm.cpp line 292:
    //   case 0x00: return m_active ? m_data : 0xff;
    // When motor is OFF: return 0xFF (bit 7 set, but motor off so ROM knows no data)
    // BUG FIX (2026-01-04): Return 0x00 for "motor on, no disk" - NOT 0xFF!
    //   MAME returns m_data (which stays 0x00 for empty drives) when motor is on.
    //   0x00 has bit 7=0, telling ROM "no valid sync data" so it moves on.
    //   0xFF has bit 7=1, which ROM interprets as "sync present, keep waiting"!
    // When motor is ON with disk: return read_latch (actual disk data)
    // Priority order is critical - motor state must be checked first!
    wire [7:0] data_reg_value = !drive_real_on ? 8'hFF :                   // Motor off: 0xFF (MAME behavior)
                                no_drive_data_read ? 8'h00 :               // Motor on, no disk: 0x00 (bit 7=0 = no sync)
                                track_status_check ? track_status_value :  // Track status check
                                read_latch;                                // Motor on, disk: actual data

    wire [7:0] iwm_reg_out = ({current_q7, current_q6} == 2'b00) ? data_reg_value :
                             ({current_q7, current_q6} == 2'b01) ? status_for_drive :                          // Status register
                             ({current_q7, current_q6} == 2'b10) ? handshake_reg :                            // Write-handshake register
                             ({current_q7, current_q6} == 2'b11) ? 8'h00 :                                   // q7=1,q6=1: return 0x00
                             8'hZZ;

`ifdef SIMULATION
    // Debug when returning data register values
    reg motor_off_ff_sent;
    reg no_drive_status_sent;
    always @(posedge CLK_14M) begin
        if (({current_q7, current_q6} == 2'b00) && !drive_real_on && DEVICE_SELECT && WR_CYCLE) begin
            if (!motor_off_ff_sent) begin
                $display("IWM: DATA REG motor-off -> 0xFF (drive_real_on=0)");
                motor_off_ff_sent <= 1'b1;
            end
        end else if (({current_q7, current_q6} == 2'b00) && drive_real_on && no_drive_data_read && DEVICE_SELECT && WR_CYCLE) begin
            if (!motor_off_ff_sent) begin
                $display("IWM: DATA REG motor-on no-disk -> 0xFF (consistent no-sync)");
                motor_off_ff_sent <= 1'b1;
            end
        end else begin
            motor_off_ff_sent <= 1'b0;
        end
        
        // Debug no-drive status register returns (use live_selected_ready to match actual status reg logic)
        if (({current_q7, current_q6} == 2'b01) && DEVICE_SELECT && WR_CYCLE) begin
            if (!no_drive_status_sent) begin
                $display("IWM STATUS: live_sel_rdy=%0d eff35=%0d d2sel=%0d DISK_READY=%04b -> %02h",
                         live_selected_ready, eff_drive35, drive2_select, DISK_READY, status_reg);
                no_drive_status_sent <= 1'b1;
            end
        end else begin
            no_drive_status_sent <= 1'b0;
        end
        
        // Debug q7=1,q6=1 case
        if (({current_q7, current_q6} == 2'b11) && DEVICE_SELECT && WR_CYCLE) begin
            $display("IWM: q7=1,q6=1 read @%02h -> 0x00 (matches iwm.cpp)", A[7:0]);
        end

        // Debug status register reads (q7=0, q6=1) to see if ROM is stuck here
        if (({current_q7, current_q6} == 2'b01) && DEVICE_SELECT && WR_CYCLE && selected_ready) begin
            $display("IWM STATUS_READ: @%02h -> %02h (eff35=%0d status35_state=%01h status35_bit=%0d phase={%0d%0d%0d} DISK35[7]=%0d)",
                     A[7:0], status_for_drive, eff_drive35, status35_state, status35_bit,
                     motor_phase[2], motor_phase[1], motor_phase[0], DISK35[7]);
        end
        
        // Debug no-drive data read case
        if (no_drive_data_read && DEVICE_SELECT && WR_CYCLE) begin
            $display("IWM: NO_DRIVE data read @%02h -> %02h (bit5=0, bits4:0=last_mode_wr)", A[7:0], no_drive_data_reg);
        end
        
        // Debug track status checks
        if (track_status_check && DEVICE_SELECT && WR_CYCLE) begin
            $display("IWM: TRACK_STATUS_CHECK @%02h -> %02h (drive35=%0d at_track0_525=%0d at_track0_35=%0d state35=%01h)", 
                     A[7:0], track_status_value, eff_drive35, drive525_at_track0, drive35_at_track0, status35_state);
        end
    end
`endif

    // BUG FIX (2026-01-04): Detect when ROM is requesting a different drive type than
    // what was captured at motor start. This happens during ROM probe sequence:
    // 1. ROM probes 3.5" drive, motor starts, drive_sel captured as {1,x}
    // 2. ROM switches to 5.25" mode (eff_drive35=0) to probe 5.25" drives
    // 3. Our D3_ACTIVE stays on (using captured drive_sel), returning 3.5" data
    // 4. ROM sees bit7=1 and thinks there's a 5.25" disk!
    //
    // Fix: When ROM is asking for a different drive type (eff_drive35 != captured[1]),
    // return 0xFF (matching MAME) so ROM knows the requested drive type has no sync data.
    wire drive_type_mismatch = drive_real_on && (eff_drive35 != read_latch_drive_sel[1]);

    // Convenience wires for active drive signals for SIM debug/correlation
    // When drive type mismatches, return 0xFF (no sync) to match MAME behavior
    wire [7:0] active_dout = drive_type_mismatch ? 8'hFF :
                             D1_ACTIVE ? d_out1 :
                             D2_ACTIVE ? d_out2 :
                             D3_ACTIVE ? d_out3 :
                             D4_ACTIVE ? d_out4 : 8'hFF;
    wire [13:0] active_taddr = D1_ACTIVE ? {1'b0, TRACK1_ADDR} :
                               D2_ACTIVE ? {1'b0, TRACK2_ADDR} :
                               D3_ACTIVE ? TRACK3_ADDR :
                               D4_ACTIVE ? TRACK4_ADDR : 14'h0000;

    // --- Device Select Timing (matches iwm.v approach) ---
    reg [3:0] iwm_addr_latched;
    reg _devsel_n;
    reg [1:0] devsel_cnt;
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            iwm_addr_latched <= 4'h0;
            _devsel_n <= 1'b1;
            devsel_cnt <= 2'd0;
        end else begin
            // Latch on any DEVICE_SELECT in simulation; gate with 7M in synthesis
            if (DEVICE_SELECT
`ifndef SIMULATION
                && CLK_7M_EN 
`endif
            ) begin
                iwm_addr_latched <= A[3:0];
                devsel_cnt <= 2'd2;
            end else if (devsel_cnt != 0) begin
                devsel_cnt <= devsel_cnt - 2'd1;
            end
            _devsel_n <= (devsel_cnt == 0);
        end
    end
    
    // Track last mode/data written to $C0EF (odd write) to satisfy ROM handshake probe
    reg [4:0] last_mode_wr;
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            last_mode_wr <= 5'd0;
        end else begin
            // Detect writes to $C0EF using proper device select timing
            if (!_devsel_n && iwm_addr_latched == 4'hF && CLK_7M_EN) begin
                last_mode_wr <= D_IN[4:0];
`ifdef SIMULATION
                $display("IWM: Write to $C0EF: %02h, last_mode_wr <= %02h", D_IN, D_IN[4:0]);
`endif
            end
        end
    end

    // Address decoding for debug output
    wire [7:0] cur_addr8 = A[7:0];
    // BUG FIX: Output data combinationally based on address, NOT gated by DEVICE_SELECT.
    // The cpu_din mux in iigs.sv uses combinational iwm_read to select iwm_dout.
    // If D_OUT is gated by DEVICE_SELECT (registered), cpu_din would see stale/zero data.
    // The IWM address space is $C0E0-$C0EF. Reading ANY address returns iwm_reg_out.
    // The even/odd distinction affects control signal latching, not data output.
    // The ROM's 3.5" disk detection reads from both even and odd addresses (e.g., @eb after @ec)
    // and expects to see valid data from both.
    // DEVICE_SELECT is still used for internal state changes (data_read_strobe, q6/q7 latching).
    assign D_OUT = iwm_reg_out;
    
`ifdef SIMULATION
    // Debug output for IWM reads - use proper timing
    reg [31:0] cpu_read_counter;
    reg [31:0] cpu_cycle_counter;
    reg [7:0] last_cpu_data;
    reg [12:0] last_track_addr;
    reg [31:0] same_data_count;
    reg [31:0] same_addr_count;
    
    always @(posedge CLK_14M) begin
        if (RESET) begin
            cpu_read_counter <= 0;
            cpu_cycle_counter <= 0;
            last_cpu_data <= 8'hFF;
            last_track_addr <= 13'h0000;
            same_data_count <= 0;
            same_addr_count <= 0;
        end else begin
            cpu_cycle_counter <= cpu_cycle_counter + 1;
        end
        
        // Debug: Log when DEVICE_SELECT is NOT active during the gap
        if (!DEVICE_SELECT && drive_real_on && (cpu_cycle_counter >= 18000195 && cpu_cycle_counter <= 18000210)) begin
            $display("IWM_GAP: no DEVICE_SELECT at cycle=%0d", cpu_cycle_counter);
        end
        if (DEVICE_SELECT && WR_CYCLE) begin
            // Debug: Log ALL IWM accesses during motor on (regardless of which drive)
            if (drive_real_on && (cpu_cycle_counter >= 18000180 && cpu_cycle_counter <= 18009200)) begin
                $display("IWM_ALL: @%02h q7q6=%0d%0d -> %02h (cycle=%0d) D1:%0d D2:%0d D3:%0d D4:%0d",
                         cur_addr8, current_q7, current_q6, iwm_reg_out, cpu_cycle_counter,
                         D1_ACTIVE, D2_ACTIVE, D3_ACTIVE, D4_ACTIVE);
            end
            // Decode which register is being read based on current q7/q6
            case ({current_q7,current_q6})
                2'b00: begin
                        cpu_read_counter <= cpu_read_counter + 1;
                        
                        // Track data/address changes
                        if (iwm_reg_out == last_cpu_data) same_data_count <= same_data_count + 1;
                        else same_data_count <= 0;
                        
                        if (active_taddr == last_track_addr) same_addr_count <= same_addr_count + 1;
                        else same_addr_count <= 0;
                        
                        $display("IWM: RD DATA  @%02h -> %02h (from drive=%0d dout=%02h taddr=%04h T3A=%04h motor=%0d real=%0d D1:%0d D2:%0d D3:%0d D4:%0d) [CPU READ #%0d cycle=%0d] same_data=%0d same_addr=%0d",
                                           cur_addr8, iwm_reg_out,
                                           D1_ACTIVE?1:D2_ACTIVE?2:D3_ACTIVE?3:D4_ACTIVE?4:0,
                                           active_dout, active_taddr, TRACK3_ADDR,
                                           drive_on, drive_real_on, D1_ACTIVE, D2_ACTIVE, D3_ACTIVE, D4_ACTIVE,
                                           cpu_read_counter, cpu_cycle_counter, same_data_count, same_addr_count);
                        
                        // Warn about repeated reads
                        if (same_data_count > 5) begin
                            $display("IWM: WARNING - CPU reading same data (%02h) %0d times in a row at taddr=%04h", iwm_reg_out, same_data_count+1, active_taddr);
                        end
                        if (same_addr_count > 5) begin
                            $display("IWM: WARNING - track address stuck at %04h for %0d CPU reads", active_taddr, same_addr_count+1);
                        end
                        
                        last_cpu_data <= iwm_reg_out;
                        last_track_addr <= active_taddr;
                        // Simple sync/prolog detection: D5 AA 96 (address) or D5 AA AD (data)
                        // Track last 2 bytes read from DATA register when motor is on
                        // BUG FIX: Use drive_real_on && any_525_ready instead of D1_ACTIVE|D2_ACTIVE|...
                        // The per-drive ACTIVE signals flicker during IWM register accesses (e.g., $C0E9),
                        // which was clearing the sync buffer and preventing D5 AA 96 detection.
                        // Using drive_real_on && any_525_ready keeps the buffer stable while motor spins.
                        // BUG FIX 2: Only accumulate bytes with bit 7=1 (valid GCR bytes).
                        // When data_ready=0, bit 7 is forced to 0, causing invalid bytes like 0x55 (D5)
                        // and 0x2A (AA) to be inserted into the buffer, breaking the D5 AA 96 sequence.
                        // BUG FIX 3: Only update sync buffer when track address changes (new byte).
                        // CPU polls same byte many times; without this check, sync buffer fills with
                        // repeated bytes (D5,D5 or AA,AA) instead of sequence (D5,AA,96).
                        if (drive_real_on && any_525_ready) begin
                            // Only accumulate valid GCR bytes (bit 7=1) at NEW track addresses for sync detection
                            if (iwm_reg_out[7] && (active_taddr != last_track_addr)) begin
                                sync_prev2 <= sync_prev1;
                                sync_prev1 <= iwm_reg_out;
                                if (sync_prev2 == 8'hD5 && sync_prev1 == 8'hAA && (iwm_reg_out == 8'h96 || iwm_reg_out == 8'hAD)) begin
                                    $display("IWM SYNC: found %s prolog at taddr=%04h (D5 AA %02h)", (iwm_reg_out==8'h96)?"ADDR":"DATA", active_taddr, iwm_reg_out);
                                end
                            end
                        end else begin
                            sync_prev2 <= 8'h00;
                            sync_prev1 <= 8'h00;
                        end
                    end
                    2'b01: $display("IWM: RD STATUS@%02h -> %02h (mode=%02h) q7q6=%0d%0d", cur_addr8, iwm_reg_out, mode_reg, current_q7, current_q6);
                    2'b10: $display("IWM: RD WHAND @%02h -> %02h q7q6=%0d%0d", cur_addr8, iwm_reg_out, current_q7, current_q6);
                    2'b11: $display("IWM: RD WHAND @%02h -> %02h q7q6=%0d%0d", cur_addr8, iwm_reg_out, current_q7, current_q6);
                endcase
        end
    end

    // Previous data bytes for sync detection
    reg [7:0] sync_prev1;
    reg [7:0] sync_prev2;

    // One-shot prolog detector for clearer confirmation in long traces
    reg        prolog_seen;
    reg        d5_seen;
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            prolog_seen <= 1'b0;
            d5_seen     <= 1'b0;
        end else if (DEVICE_SELECT && WR_CYCLE && ({q7,q6} == 2'b00) && ~A[0]) begin
            if (!d5_seen && iwm_reg_out == 8'hD5) begin
                d5_seen <= 1'b1;
                $display("IWM SYNC: first D5 at taddr=%04h", active_taddr);
            end
            if (!prolog_seen && sync_prev2 == 8'hD5 && sync_prev1 == 8'hAA &&
                (iwm_reg_out == 8'h96 || iwm_reg_out == 8'hAD)) begin
                prolog_seen <= 1'b1;
                $display("IWM SYNC: first prolog %s at taddr=%04h (D5 AA %02h)",
                         (iwm_reg_out==8'h96)?"ADDR":"DATA", active_taddr, iwm_reg_out);
            end
        end
    end

    // Capture first N data bytes after motor spins up (drive_real_on rising)
    reg        cap_active;
    reg [7:0]  cap_count;
    reg        prev_drive_real_on;
    localparam CAP_MAX = 8'd255;

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            cap_active <= 1'b0;
            cap_count  <= 7'd0;
            prev_drive_real_on <= 1'b0;
        end else begin
            prev_drive_real_on <= drive_real_on;
            // Start capture on rising edge of real motor-on
            if (!prev_drive_real_on && drive_real_on) begin
                cap_active <= 1'b1;
                cap_count  <= 7'd0;
                $display("IWM CAPTURE: START (q7q6=%0d%0d, drive=%0d)", q7, q6,
                         D1_ACTIVE?1:D2_ACTIVE?2:D3_ACTIVE?3:D4_ACTIVE?4:0);
            end
            // Stop capture when motor goes off
            if (prev_drive_real_on && !drive_real_on) begin
                if (cap_active) $display("IWM CAPTURE: END (motor off) count=%0d", cap_count);
                cap_active <= 1'b0;
            end
            // During capture, record DATA register reads
            if (cap_active && DEVICE_SELECT && WR_CYCLE && ({q7,q6} == 2'b00) && ~A[0]) begin
                if (cap_count < CAP_MAX) begin
                    $display("IWM CAP[%0d] @%02h -> %02h (taddr=%04h from drive=%0d)",
                             cap_count, cur_addr8, iwm_reg_out, active_taddr,
                             D1_ACTIVE?1:D2_ACTIVE?2:D3_ACTIVE?3:D4_ACTIVE?4:0);
                    cap_count <= cap_count + 7'd1;
                    if (cap_count == CAP_MAX-1) begin
                        cap_active <= 1'b0;
                        $display("IWM CAPTURE: END (reached %0d)", CAP_MAX);
                    end
                end
            end
        end
    end
`endif

    // --- Drive Instantiations ---
    // Each drive tracks its own motor spindown state via MOTOR_SPINNING output.
    // This matches MAME's per-device motor state model.
    //
    // BUG FIX (2026-01-04): Gate DATA_REG_READ per-drive with DISK_ACTIVE.
    // Previously, data_reg_read was broadcast to ALL drives, causing byte_consumed
    // to be set on ALL drives when the ROM read from ANY drive. This meant that
    // when the ROM polled drive 1 (5.25"), drive 3 (3.5") would also set byte_consumed,
    // effectively "consuming" bytes on a drive the ROM wasn't even reading from.
    // By gating with D*_ACTIVE, only the currently selected drive receives the signal.
    wire data_reg_read_d1 = data_reg_read && D1_ACTIVE;
    wire data_reg_read_d2 = data_reg_read && D2_ACTIVE;
    wire data_reg_read_d3 = data_reg_read && D3_ACTIVE;
    wire data_reg_read_d4 = data_reg_read && D4_ACTIVE;

    apple_drive drive_1 (
        .IS_35_INCH(1'b0), .FAST_MODE(fast_mode), .DRIVE_ID(2'd0),
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[0]), .D_IN(D_IN), .D_OUT(d_out1),
        .DISK_ACTIVE(D1_ACTIVE), .MOTOR_ON(drive_real_on), .MOTOR_PHASE(motor_phase), .WRITE_MODE(effective_write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe), .DATA_REG_READ(data_reg_read_d1),
        .MOTOR_SPINNING(motor_spinning_1),
        .TRACK(TRACK1), .TRACK_ADDR(drive1_track_addr), .TRACK_DI(TRACK1_DI),
        .TRACK_DO(TRACK1_DO), .TRACK_WE(TRACK1_WE), .TRACK_BUSY(TRACK1_BUSY)
    );
    // Drive 2
    apple_drive drive_2 (
        .IS_35_INCH(1'b0), .FAST_MODE(fast_mode), .DRIVE_ID(2'd1),
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[1]), .D_IN(D_IN), .D_OUT(d_out2),
        .DISK_ACTIVE(D2_ACTIVE), .MOTOR_ON(drive_real_on), .MOTOR_PHASE(motor_phase), .WRITE_MODE(effective_write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe), .DATA_REG_READ(data_reg_read_d2),
        .MOTOR_SPINNING(motor_spinning_2),
        .TRACK(TRACK2), .TRACK_ADDR(drive2_track_addr), .TRACK_DI(TRACK2_DI),
        .TRACK_DO(TRACK2_DO), .TRACK_WE(TRACK2_WE), .TRACK_BUSY(TRACK2_BUSY)
    );
    // Drive 3
    apple_drive drive_3 (
        .IS_35_INCH(1'b1), .FAST_MODE(fast_mode), .DRIVE_ID(2'd2),
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[2]), .D_IN(D_IN), .D_OUT(d_out3),
        .DISK_ACTIVE(D3_ACTIVE), .MOTOR_ON(drive_real_on), .MOTOR_PHASE(motor_phase), .WRITE_MODE(effective_write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe), .DATA_REG_READ(data_reg_read_d3),
        .MOTOR_SPINNING(motor_spinning_3),
        .TRACK(TRACK3), .TRACK_ADDR(TRACK3_ADDR), .TRACK_DI(TRACK3_DI),
        .TRACK_DO(TRACK3_DO), .TRACK_WE(TRACK3_WE), .TRACK_BUSY(TRACK3_BUSY)
    );
    // Drive 4
    apple_drive drive_4 (
        .IS_35_INCH(1'b1), .FAST_MODE(fast_mode), .DRIVE_ID(2'd3),
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[3]), .D_IN(D_IN), .D_OUT(d_out4),
        .DISK_ACTIVE(D4_ACTIVE), .MOTOR_ON(drive_real_on), .MOTOR_PHASE(motor_phase), .WRITE_MODE(effective_write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe), .DATA_REG_READ(data_reg_read_d4),
        .MOTOR_SPINNING(motor_spinning_4),
        .TRACK(TRACK4), .TRACK_ADDR(TRACK4_ADDR), .TRACK_DI(TRACK4_DI),
        .TRACK_DO(TRACK4_DO), .TRACK_WE(TRACK4_WE), .TRACK_BUSY(TRACK4_BUSY)
    );

    // gsplus-style motor timer with inactivity timeout
    // VBL frequency: 60Hz, 14MHz/60 = 233,333 cycles per VBL
    // Motor timeout: 60 VBL = 1 second = 14,000,000 cycles
    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            spindown_delay <= 24'h0;
            inactivity_timer <= 24'h0;
            drive_real_on <= 1'b0;
            drive_on_old <= 1'b0;
            motor_off_pending <= 1'b0;
            drive_real_on_prev <= 1'b0;
            read_latch_drive_sel <= 2'b00;  // Default to drive 1 (5.25")
        end else begin
            // BUG FIX (2026-01-03): Don't continuously update drive selection from
            // eff_drive35 while motor is running. The ROM probe sequence switches
            // DISKREG between 3.5"/5.25" mode while probing drives, but the physical
            // 3.5" drive keeps spinning. If we track eff_drive35 here, we'd switch
            // to 5.25" data when ROM writes DISKREG=0x00, losing the 3.5" disk data.
            //
            // Instead, drive_sel is only captured at motor start (drive_real_on 0→1).
            // The drive2_select within a drive type can still be tracked for drive
            // switching within the same type (drive 1/2 for 5.25", or drive 3/4 for 3.5").
            if (drive_real_on && !device_select_edge) begin
                // Only update drive2_select portion, keep eff_drive35 portion locked
                read_latch_drive_sel[0] <= drive2_select;
            end

            // BUG FIX (2026-01-04): When ROM switches from 3.5" to 5.25" mode
            // (eff_drive35 goes 1->0), immediately deselect 3.5" drives by clearing
            // read_latch_drive_sel[1]. This pauses 3.5" disk rotation during ROM probe
            // of 5.25" drives, preventing ~77 bytes of rotation during the ~18000 cycle
            // probe that would corrupt the address field being read.
            // Note: This does NOT affect which data is returned - that's handled by
            // read_latch_drive_mismatch logic. This only affects D3_ACTIVE/D4_ACTIVE
            // which controls disk rotation in apple_drive.v.
            if (!eff_drive35 && read_latch_drive_sel[1]) begin
`ifdef SIMULATION
                $display("IWM: Switching away from 3.5\" mode - clearing read_latch_drive_sel[1] to pause rotation t=%0t", $time);
`endif
                read_latch_drive_sel[1] <= 1'b0;
            end

            // Handle explicit motor on/off commands
            if (drive_on != drive_on_old) begin
                if (drive_on) begin
                    // Motor on: start immediately, reset timers
                    drive_real_on <= 1'b1;
                    spindown_delay <= 24'h0;
                    inactivity_timer <= 24'h0;
                    motor_off_pending <= 1'b0;
                    // BUG FIX (2026-01-04): ALWAYS capture drive selection when motor
                    // command goes on (drive_on 0->1). This matches MAME's devsel_w()
                    // which reads current DISKREG to select drive on EVERY motor on.
                    // Previous fix (only capture when drive_real_on=0) was wrong because
                    // during ROM probe sequence, when switching from 3.5" to 5.25" mode
                    // while motor was still spinning, we kept using old 3.5" selection.
                    // This caused ROM to see valid 3.5" data during 5.25" probe!
                    read_latch_drive_sel <= {eff_drive35, drive2_select};
`ifdef SIMULATION
                    $display("IWM: MOTOR ON (immediate) drive_on=%0d drive_on_old=%0d drive_real_on_WAS=%0d SETTING_TO_1 drive_sel={%0d,%0d} captured=ALWAYS t=%0t", drive_on, drive_on_old, drive_real_on, eff_drive35, drive2_select, $time);
`endif
                end else begin
                    // Motor off command: set timer for 1 second delay (gsplus style)
                    motor_off_pending <= 1'b1;
                    spindown_delay <= 24'd14000000; // 1 second
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF command received, starting 1s timer");
`endif
                end
            end
            
            // Inactivity timer: turn off motor after 1 second of no disk access
            // BUG FIX: Use any_data_access instead of data_read_strobe.
            // data_read_strobe is PH2-gated and only fires once per 14 clocks in slow mode,
            // but we need to detect activity on every CPU access to prevent spurious timeouts.
            if (drive_real_on && !motor_off_pending) begin
                if (any_data_access || write_reg) begin
                    // Reset inactivity timer on any disk access
                    inactivity_timer <= 24'h0;
                end else if (inactivity_timer < 14000000) begin
                    inactivity_timer <= inactivity_timer + 1;
`ifdef SIMULATION
                    // Debug: log timer progress every 1M cycles
                    if (inactivity_timer == 1000000 || inactivity_timer == 5000000 ||
                        inactivity_timer == 10000000 || inactivity_timer == 13000000 ||
                        inactivity_timer == 13900000) begin
                        $display("IWM: inactivity_timer=%0d (%.1fM cycles)", inactivity_timer, inactivity_timer / 1000000.0);
                    end
`endif
                end else begin
                    // Inactivity timeout reached - turn off motor
                    drive_real_on <= 1'b0;
                    inactivity_timer <= 24'h0;
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF (inactivity timeout) after 14M cycles");
`endif
                end
            end
            
            // Handle explicit motor-off timer countdown
            if (motor_off_pending && spindown_delay != 0) begin
                spindown_delay <= spindown_delay - 1;
                if (spindown_delay == 1) begin  // Check for 1 because of non-blocking
                    drive_real_on <= 1'b0;
                    motor_off_pending <= 1'b0;
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF (command timer expired)");
`endif
                end
            end
            
`ifdef SIMULATION
            // Debug: trace drive_on/drive_on_old sync issues
            if (drive_on_old != drive_on) begin
                $display("IWM TIMER: drive_on_old CHANGING from %0d to %0d (drive_on=%0d) t=%0t",
                         drive_on_old, drive_on, drive_on, $time);
            end
`endif
            drive_on_old <= drive_on;
            drive_real_on_prev <= drive_real_on;
`ifdef SIMULATION
            // Debug: trace drive_real_on state transitions
            if (drive_real_on && !drive_real_on_prev) begin
                $display("IWM: drive_real_on JUST BECAME 1 (should see data now) t=%0t", $time);
            end
            if (!drive_real_on && drive_real_on_prev) begin
                $display("IWM: drive_real_on JUST BECAME 0 (motor stopped) t=%0t", $time);
            end
`endif
        end
    end

    // Q7 controls side select for 3.5" drives
    assign TRACK3_SIDE = q7;
    assign TRACK4_SIDE = q7;
    
endmodule
