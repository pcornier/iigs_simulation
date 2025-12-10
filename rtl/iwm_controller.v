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
    CLK_14M, CLK_7M_EN, Q3, PH0, RESET,
    // CPU bus interface
    IO_SELECT, DEVICE_SELECT, WR_CYCLE, A, D_IN, D_OUT,
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
    TRACK3, TRACK3_ADDR, TRACK3_SIDE, TRACK3_DI, TRACK3_DO, TRACK3_WE, TRACK3_BUSY,
    // Drive 4 (3.5", 800K)
    TRACK4, TRACK4_ADDR, TRACK4_SIDE, TRACK4_DI, TRACK4_DO, TRACK4_WE, TRACK4_BUSY
);

    // I/O Port Declarations
    input           CLK_14M;
    input           CLK_7M_EN;
    input           Q3;
    input           PH0;
    input           IO_SELECT;
    input           DEVICE_SELECT;
    input           WR_CYCLE;        // 0=write cycle, 1=read cycle
    input           RESET;
    input [3:0]     DISK_READY;
    input [7:0]     DISK35;
    input           WRITE_PROTECT;
    input [15:0]    A;
    input [7:0]     D_IN;
    output [7:0]    D_OUT;

    // --- Interface for two 5.25" drives ---
    output [5:0]    TRACK1;
    output [12:0]   TRACK1_ADDR;
    output [7:0]    TRACK1_DI;
    input [7:0]     TRACK1_DO;
    output          TRACK1_WE;
    input           TRACK1_BUSY;
    output          FD_DISK_1;      // Drive 1 is actively reading/writing

    output [5:0]    TRACK2;
    output [12:0]   TRACK2_ADDR;
    output [7:0]    TRACK2_DI;
    input [7:0]     TRACK2_DO;
    output          TRACK2_WE;
    input           TRACK2_BUSY;
    output          FD_DISK_2;      // Drive 2 is actively reading/writing

    // --- Expanded interface for two 3.5" 800K drives ---
    output [6:0]    TRACK3;
    output [12:0]   TRACK3_ADDR;
    output          TRACK3_SIDE;
    output [7:0]    TRACK3_DI;
    input [7:0]     TRACK3_DO;
    output          TRACK3_WE;
    input           TRACK3_BUSY;

    output [6:0]    TRACK4;
    output [12:0]   TRACK4_ADDR;
    output          TRACK4_SIDE;
    output [7:0]    TRACK4_DI;
    input [7:0]     TRACK4_DO;
    output          TRACK4_WE;
    input           TRACK4_BUSY;

    // --- Internal IWM Registers ---
    reg [3:0]       motor_phase;
    reg             drive_on;
    reg             drive_real_on;
    reg             drive2_select;      // Selects between drive 1/2 or 3/4
    reg             q6;
    reg             q7;                 // L6 and L7 state bits
    reg [7:0]       mode_reg;           // IWM Mode Register (lower 5 bits used)
    reg [7:0]       read_latch;         // Data read from disk

    // --- Wires and Assignments ---
    wire [7:0]      d_out1, d_out2, d_out3, d_out4;
    wire            write_mode = q7;
    wire            fast_mode = mode_reg[3];      // Fast mode (2µs bit cell) is bit 3 of mode_reg
    // Drive type select from DISK35[6]
    wire            drive35_select = DISK35[6];
    reg             drive35_select_d;
    wire            read_disk = (DEVICE_SELECT == 1'b1 && A[3:0] == 4'hC);
    // Generate a data-read strobe when CPU reads DATA register (q7q6=00) at any address
    wire            data_read_strobe = (DEVICE_SELECT == 1'b1 && WR_CYCLE && ({q7,q6} == 2'b00));
`ifdef SIMULATION
    reg prev_data_read_strobe;
    always @(posedge CLK_14M) begin
        prev_data_read_strobe <= data_read_strobe;
        if (data_read_strobe && !prev_data_read_strobe) begin
            $display("IWM: DATA_READ_STROBE active (DEVICE_SELECT=%0d WR_CYCLE=%0d q7q6=%0d%0d A[0]=%0d)", 
                     DEVICE_SELECT, WR_CYCLE, q7, q6, A[0]);
        end
    end
`endif
    wire            write_reg = (DEVICE_SELECT == 1'b1 && A[3:2] == 2'b11 && A[0] == 1'b1);
    
    // Effective drive-type selection: prefer any ready 5.25" if 3.5" is selected but not ready
    wire any_525_ready = DISK_READY[0] | DISK_READY[1];
    wire any_35_ready  = DISK_READY[2] | DISK_READY[3];
    wire eff_drive35   = any_525_ready ? 1'b0 : (drive35_select & any_35_ready);
`ifdef SIMULATION
    // Trace when we override a 3.5" selection due to only 5.25" media being present
    always @(posedge CLK_14M) begin
        if (drive35_select && !any_35_ready && any_525_ready) begin
            $display("IWM DBG: fallback to 5.25\" (3.5\" selected but no 3.5 media ready)");
        end
    end
`endif
    // Drive activity signals based on effective selects and motor state
    wire D1_ACTIVE = drive_real_on & ~drive2_select & ~eff_drive35;
    wire D2_ACTIVE = drive_real_on &  drive2_select & ~eff_drive35;
    wire D3_ACTIVE = drive_real_on & ~drive2_select &  eff_drive35;
    wire D4_ACTIVE = drive_real_on &  drive2_select &  eff_drive35;

    // Export drive active signals for track buffer coordination
    assign FD_DISK_1 = D1_ACTIVE;
    assign FD_DISK_2 = D2_ACTIVE;

    wire selected_ready = (~eff_drive35 & ~drive2_select & DISK_READY[0]) |
                          (~eff_drive35 &  drive2_select & DISK_READY[1]) |
                          ( eff_drive35 & ~drive2_select & DISK_READY[2]) |
                          ( eff_drive35 &  drive2_select & DISK_READY[3]);


    // Edge detection for DEVICE_SELECT to prevent multiple state changes per CPU cycle
    reg device_select_prev;
    wire device_select_edge = DEVICE_SELECT && !device_select_prev;

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
        end else begin
            // Track DEVICE_SELECT for edge detection
            device_select_prev <= DEVICE_SELECT;

        if (device_select_edge) begin
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
                        drive2_select <= A[0];
`ifdef SIMULATION
                        $display("IWM SW: drive2_select <= %0d (A=%h WR=%0d)", A[0], A[3:0], !WR_CYCLE);
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
            if (!WR_CYCLE && !drive_on && q7 && q6 && A[0]) begin
                mode_reg <= {3'b000, D_IN[4:0]};
`ifdef SIMULATION
                $display("IWM: MODE_REG <= %02h (fast=%0d)", {3'b000,D_IN[4:0]}, D_IN[3]);
`endif
            end

            // Opportunistic motor auto-start on read accesses if a disk is ready
            // This mirrors firmware behavior which normally turns on the motor; it helps the sim progress.
            // IMPORTANT: Do NOT auto-start motor when no disk is mounted - this causes the boot ROM
            // to enter a read loop that never finds valid data and then jumps to Applesoft
            if (WR_CYCLE && selected_ready && !drive_on) begin
                if ({q7,q6} == 2'b00 || (A[7:4] == 4'hE)) begin
                    drive_on <= 1'b1;
`ifdef SIMULATION
                    $display("IWM: MOTOR ON (auto) due to read @%02h q7q6=%0d%0d and disk ready", A[7:0], q7, q6);
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

    // Mux the data input from the active drive into the read latch
    always @(*) begin
        if (D1_ACTIVE) read_latch = d_out1;
        else if (D2_ACTIVE) read_latch = d_out2;
        else if (D3_ACTIVE) read_latch = d_out3;
        else if (D4_ACTIVE) read_latch = d_out4;
        else read_latch = 8'h00;
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
    // Bit5: motor on status
    // Bits4:0: mode bits
    wire write_protect = WRITE_PROTECT;
    wire [7:0] normal_status_reg = { write_protect,
                                    1'b0,
                                    (D1_ACTIVE || D2_ACTIVE || D3_ACTIVE || D4_ACTIVE),
                                    mode_reg[4:0] };
    wire [7:0] no_drive_status_reg = 8'hC0 | {3'b000, last_mode_wr};  // Ready status from working stub
    wire [7:0] status_reg = selected_ready ? normal_status_reg : no_drive_status_reg;
    
    // Write-handshake register - bit 7 high indicates buffer ready, bit 6 clear indicates no underrun
    wire [7:0] handshake_reg = 8'h80;  // Buffer ready (bit 7=1), no underrun (bit 6=0) - matches iwm.cpp logic
    
    // Current Q6/Q7 state based on access address (real-time during access)
    wire current_q6 = (A[3:1] == 3'b110) ? A[0] : q6;  // C0EC/C0ED access sets Q6, otherwise use stored Q6
    wire current_q7 = (A[3:1] == 3'b111) ? A[0] : q7;  // C0EE/C0EF access sets Q7, otherwise use stored Q7
    
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
    
    // 3.5" drive status logic based on motor phases (from iwm.cpp iwm_read_status35)
    wire [3:0] status35_state = {motor_phase[1], motor_phase[0], drive35_select, motor_phase[2]};
    wire drive35_at_track0 = 1'b1;  // Assume 3.5" drive at track 0 for boot progression
    
    // Track 0 status value: bit 5 should be 0 when at track 0, 1 when not at track 0  
    // ROM loop: eor $c0ee; and #$1f; bne loop  -> continues loop if bit 5 is set
    wire [7:0] track0_status_525 = {2'b11, ~drive525_at_track0, last_mode_wr};  // Bit 5 clear when at track 0
    wire [7:0] track0_status_35 = (status35_state == 4'h0A) ? {7'b0000000, ~drive35_at_track0} : 8'h00;
    
    // Track status check ONLY when motor is OFF and we're probing for track 0
    // When motor is ON, always return actual disk data, not track status
    // This was incorrectly overriding all reads from $C0EE which broke disk booting
    wire track_status_check = (A[3:0] == 4'hE) && ({current_q7, current_q6} == 2'b00) && selected_ready && !drive_on;
    // No-drive data read: any data register read (q7=0, q6=0) when no floppy disk is mounted
    wire no_drive_data_read = ({current_q7, current_q6} == 2'b00) && !selected_ready;
    wire [7:0] stub_status = 8'hC0 | {3'b000, last_mode_wr};
    
    // Select appropriate track status
    wire [7:0] track_status_value = eff_drive35 ? track0_status_35 : track0_status_525;
    
    // No-drive data register value:
    // - Bit 7 = 1 (valid nibble marker - needed for FF:581F to exit)
    // - Bit 6 = 1 (reserved)
    // - Bit 5 = 0 (at track 0 / no drive - exits IIgs ROM loop at FF:4717)
    // - Bits 4:0 = last_mode_wr (echoes back written value for handshake at FF:4723-4729)
    // Note: C661 loop has timeout via Y counter, so bit 7=1 is OK there
    wire [7:0] no_drive_data_reg = {2'b11, 1'b0, last_mode_wr};  // $C0 | last_mode_wr with bit 5 clear

    // Data register output logic:
    // - No disk mounted: return no_drive_data_reg ($C0 | last_mode_wr, bit 5 clear)
    //   This passes ROM checks: FF:4717 (bit5=0), FF:4720 (bits4:0 match), FF:581F (bit7=1)
    // - Disk mounted, motor off: return $FF
    // - Disk mounted, motor on: return actual data from read_latch
    // - Track status check: return track0 status for stepper positioning
    wire [7:0] iwm_reg_out = ({current_q7, current_q6} == 2'b00) ? (no_drive_data_read ? no_drive_data_reg :   // No drives: echoes mode with bits 7,6,5=0
                                                                     track_status_check ? track_status_value :  // Track status check
                                                                     drive_on ? read_latch : 8'hFF) :           // Normal data/motor off
                             ({current_q7, current_q6} == 2'b01) ? status_reg :                                // Status register 
                             ({current_q7, current_q6} == 2'b10) ? handshake_reg :                            // Write-handshake register
                             ({current_q7, current_q6} == 2'b11) ? 8'h00 :                                   // q7=1,q6=1: return 0x00
                             8'hZZ;

`ifdef SIMULATION
    // Debug when returning 0xFF for data register with motor off
    reg motor_off_ff_sent;
    reg no_drive_status_sent;
    always @(posedge CLK_14M) begin
        if (({current_q7, current_q6} == 2'b00) && !drive_on && DEVICE_SELECT && WR_CYCLE) begin
            if (!motor_off_ff_sent) begin
                $display("IWM: Returning 0xFF for DATA register - motor off (matches reference iwm.cpp)");
                motor_off_ff_sent <= 1'b1;
            end
        end else begin
            motor_off_ff_sent <= 1'b0;
        end
        
        // Debug no-drive status register returns
        if (({current_q7, current_q6} == 2'b01) && !selected_ready && DEVICE_SELECT && WR_CYCLE) begin
            if (!no_drive_status_sent) begin
                $display("IWM: Returning NO_DRIVE_STATUS_REG (%02h) = 0xC0 | last_mode_wr(%02h)", no_drive_status_reg, last_mode_wr);
                no_drive_status_sent <= 1'b1;
            end
        end else begin
            no_drive_status_sent <= 1'b0;
        end
        
        // Debug q7=1,q6=1 case
        if (({current_q7, current_q6} == 2'b11) && DEVICE_SELECT && WR_CYCLE) begin
            $display("IWM: q7=1,q6=1 read @%02h -> 0x00 (matches iwm.cpp)", A[7:0]);
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

    // Convenience wires for active drive signals for SIM debug/correlation
    wire [7:0] active_dout = D1_ACTIVE ? d_out1 :
                             D2_ACTIVE ? d_out2 :
                             D3_ACTIVE ? d_out3 :
                             D4_ACTIVE ? d_out4 : 8'h00;
    wire [12:0] active_taddr = D1_ACTIVE ? TRACK1_ADDR :
                               D2_ACTIVE ? TRACK2_ADDR :
                               D3_ACTIVE ? TRACK3_ADDR :
                               D4_ACTIVE ? TRACK4_ADDR : 13'h0000;

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
    assign D_OUT = (!DEVICE_SELECT) ? 8'hZZ :
                   // Odd addresses read as 0
                   (A[0] ? 8'h00 : iwm_reg_out);
    
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
        
        if (DEVICE_SELECT && WR_CYCLE) begin
            // Decode which register is being read based on current q7/q6
            case ({current_q7,current_q6})
                2'b00: begin
                        cpu_read_counter <= cpu_read_counter + 1;
                        
                        // Track data/address changes
                        if (iwm_reg_out == last_cpu_data) same_data_count <= same_data_count + 1;
                        else same_data_count <= 0;
                        
                        if (active_taddr == last_track_addr) same_addr_count <= same_addr_count + 1;
                        else same_addr_count <= 0;
                        
                        $display("IWM: RD DATA  @%02h -> %02h (from drive=%0d dout=%02h taddr=%04h motor=%0d real=%0d D1:%0d D2:%0d D3:%0d D4:%0d) [CPU READ #%0d cycle=%0d] same_data=%0d same_addr=%0d",
                                           cur_addr8, iwm_reg_out,
                                           D1_ACTIVE?1:D2_ACTIVE?2:D3_ACTIVE?3:D4_ACTIVE?4:0,
                                           active_dout, active_taddr,
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
                        if (drive_on && (D1_ACTIVE|D2_ACTIVE|D3_ACTIVE|D4_ACTIVE)) begin
                            sync_prev2 <= sync_prev1;
                            sync_prev1 <= iwm_reg_out;
                            if (sync_prev2 == 8'hD5 && sync_prev1 == 8'hAA && (iwm_reg_out == 8'h96 || iwm_reg_out == 8'hAD)) begin
                                $display("IWM SYNC: found %s prolog at taddr=%04h (D5 AA %02h)", (iwm_reg_out==8'h96)?"ADDR":"DATA", active_taddr, iwm_reg_out);
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
    apple_drive drive_1 (
        .IS_35_INCH(1'b0), .FAST_MODE(fast_mode),
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[0]), .D_IN(D_IN), .D_OUT(d_out1),
        .DISK_ACTIVE(D1_ACTIVE), .MOTOR_PHASE(motor_phase), .WRITE_MODE(write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe),
        .TRACK(TRACK1), .TRACK_ADDR(TRACK1_ADDR), .TRACK_DI(TRACK1_DI),
        .TRACK_DO(TRACK1_DO), .TRACK_WE(TRACK1_WE), .TRACK_BUSY(TRACK1_BUSY)
    );
    // ... (instantiations for drive_2, drive_3, drive_4 are similar) ...
    // Drive 2
    apple_drive drive_2 (
        .IS_35_INCH(1'b0), .FAST_MODE(fast_mode),
        /* other ports */
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[1]), .D_IN(D_IN), .D_OUT(d_out2),
        .DISK_ACTIVE(D2_ACTIVE), .MOTOR_PHASE(motor_phase), .WRITE_MODE(write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe),
        .TRACK(TRACK2), .TRACK_ADDR(TRACK2_ADDR), .TRACK_DI(TRACK2_DI),
        .TRACK_DO(TRACK2_DO), .TRACK_WE(TRACK2_WE), .TRACK_BUSY(TRACK2_BUSY)
    );
    // Drive 3
    apple_drive drive_3 (
        .IS_35_INCH(1'b1), .FAST_MODE(fast_mode),
        /* other ports */
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[2]), .D_IN(D_IN), .D_OUT(d_out3),
        .DISK_ACTIVE(D3_ACTIVE), .MOTOR_PHASE(motor_phase), .WRITE_MODE(write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe),
        .TRACK(TRACK3), .TRACK_ADDR(TRACK3_ADDR), .TRACK_DI(TRACK3_DI),
        .TRACK_DO(TRACK3_DO), .TRACK_WE(TRACK3_WE), .TRACK_BUSY(TRACK3_BUSY)
    );
    // Drive 4
    apple_drive drive_4 (
        .IS_35_INCH(1'b1), .FAST_MODE(fast_mode),
        /* other ports */
        .CLK_14M(CLK_14M), .Q3(Q3), .PH0(PH0), .RESET(RESET),
        .DISK_READY(DISK_READY[3]), .D_IN(D_IN), .D_OUT(d_out4),
        .DISK_ACTIVE(D4_ACTIVE), .MOTOR_PHASE(motor_phase), .WRITE_MODE(write_mode),
        .READ_DISK(read_disk), .WRITE_REG(write_reg), .READ_STROBE(data_read_strobe),
        .TRACK(TRACK4), .TRACK_ADDR(TRACK4_ADDR), .TRACK_DI(TRACK4_DI),
        .TRACK_DO(TRACK4_DO), .TRACK_WE(TRACK4_WE), .TRACK_BUSY(TRACK4_BUSY)
    );

    // gsplus-style motor timer with inactivity timeout
    // VBL frequency: 60Hz, 14MHz/60 = 233,333 cycles per VBL  
    // Motor timeout: 60 VBL = 1 second = 14,000,000 cycles
    always @(posedge CLK_14M or posedge RESET) begin
        reg [23:0] spindown_delay;
        reg [23:0] inactivity_timer;
        reg drive_on_old;
        reg motor_off_pending;
        if (RESET) begin
            spindown_delay = 24'h0;
            inactivity_timer = 24'h0;
            drive_real_on <= 1'b0;
            drive_on_old <= 1'b0;
            motor_off_pending <= 1'b0;
        end else begin
            // Handle explicit motor on/off commands
            if (drive_on != drive_on_old) begin
                if (drive_on) begin
                    // Motor on: start immediately, reset timers
                    drive_real_on <= 1'b1;
                    spindown_delay = 24'h0;
                    inactivity_timer = 24'h0;
                    motor_off_pending <= 1'b0;
`ifdef SIMULATION
                    $display("IWM: MOTOR ON (immediate)");
`endif
                end else begin
                    // Motor off command: set timer for 1 second delay (gsplus style)  
                    motor_off_pending <= 1'b1;
                    spindown_delay = 14000000; // 1 second
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF command received, starting 1s timer");
`endif
                end
            end
            
            // Inactivity timer: turn off motor after 1 second of no disk access
            if (drive_real_on && !motor_off_pending) begin
                if (data_read_strobe || write_reg) begin
                    // Reset inactivity timer on any disk access
                    inactivity_timer = 24'h0;
                end else if (inactivity_timer < 14000000) begin
                    inactivity_timer = inactivity_timer + 1;
                end else begin
                    // Inactivity timeout reached - turn off motor
                    drive_real_on <= 1'b0;
                    inactivity_timer = 24'h0;
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF (inactivity timeout)");
`endif
                end
            end
            
            // Handle explicit motor-off timer countdown
            if (motor_off_pending && spindown_delay != 0) begin
                spindown_delay = spindown_delay - 1;
                if (spindown_delay == 0) begin
                    drive_real_on <= 1'b0;
                    motor_off_pending <= 1'b0;
`ifdef SIMULATION
                    $display("IWM: MOTOR OFF (command timer expired)");
`endif
                end
            end
            
            drive_on_old <= drive_on;
        end
    end
    
    // Q7 controls side select for 3.5" drives
    assign TRACK3_SIDE = q7;
    assign TRACK4_SIDE = q7;
    
endmodule
