//
// flux_controller.v: Hardware-Accurate IWM Controller with Flux Interface
//
// This module integrates iwm_flux.v (IWM chip) with flux_drive.v (drive module)
// to provide a complete flux-based disk controller.
//
// Key differences from iwm_controller.v:
// - Uses flux transitions for disk reading (hardware-accurate)
// - Track buffer contains WOZ bit data (not pre-decoded nibbles)
// - All timing emerges naturally from flux interface (no byte_consumed hacks)
// - Matches real Apple IIgs hardware architecture
//
// Reference: MAME iwm.cpp, floppy.cpp
//

module flux_controller (
    // Global signals
    input  wire        CLK_14M,
    input  wire        CLK_7M_EN,
    input  wire        Q3,
    input  wire        PH0,
    input  wire        PH2,
    input  wire        RESET,

    // CPU bus interface
    input  wire        IO_SELECT,
    input  wire        DEVICE_SELECT,
    input  wire        WR_CYCLE,        // 1=read, 0=write
    input  wire        VDA,
    input  wire [15:0] A,
    input  wire [7:0]  D_IN,
    output wire [7:0]  D_OUT,

    // Drive status
    input  wire [3:0]  DISK_READY,      // Per-drive disk ready status

    // External control/status
    input  wire [7:0]  DISK35,          // $C031 disk register
    input  wire        WRITE_PROTECT,

    // WOZ Track Bit Interface (for 3.5" drive 1)
    // The track buffer now contains raw WOZ bit data
    output wire [6:0]  WOZ_TRACK,       // Current track number
    output wire [13:0] WOZ_BIT_ADDR,    // Bit address / 8 = byte address in BRAM
    input  wire [7:0]  WOZ_BIT_DATA,    // Byte from track bit buffer
    input  wire [31:0] WOZ_BIT_COUNT,   // Total bits in current track
    input  wire        WOZ_TRACK_LOADED, // Track data is loaded and valid

    // Motor status for clock slowdown
    output wire        FLOPPY_MOTOR_ON
);

    //=========================================================================
    // Internal signals
    //=========================================================================

    // IWM to drive control signals
    wire [3:0]  iwm_phases;
    wire        iwm_motor_on;
    wire        iwm_drive_sel;

    // Drive to IWM status signals
    wire        flux_transition;
    wire        motor_spinning;
    wire [6:0]  track;
    wire [16:0] bit_position;
    wire        drive_write_protect;

    // CPU interface signals
    wire        cpu_rd = DEVICE_SELECT && WR_CYCLE;
    wire        cpu_wr = DEVICE_SELECT && !WR_CYCLE;

    // Drive type from DISK35 register
    wire        is_35_inch = DISK35[6];

    //=========================================================================
    // IWM Chip (iwm_flux.v)
    //=========================================================================

    iwm_flux iwm (
        .CLK_14M(CLK_14M),
        .RESET(RESET),

        // CPU interface
        .ADDR(A[3:0]),
        .RD(cpu_rd),
        .WR(cpu_wr),
        .DATA_IN(D_IN),
        .DATA_OUT(D_OUT),

        // Flux interface from drive
        .FLUX_TRANSITION(flux_transition),

        // Control outputs to drive
        .PHASES(iwm_phases),
        .MOTOR_ON(iwm_motor_on),
        .DRIVE_SEL(iwm_drive_sel),

        // Status inputs from drive
        .WRITE_PROTECT(drive_write_protect),
        .MOTOR_SPINNING(motor_spinning),
        .DISK_READY(WOZ_TRACK_LOADED),
        .AT_TRACK0(track == 7'd0),
        .STEPPING(1'b0),            // Simplified: assume stepping is instant
        .DOUBLE_SIDED(1'b1),        // 3.5" drives are double-sided

        // Drive type selection
        .IS_35_INCH(is_35_inch),

        // Disk register SEL line
        .DISKREG_SEL(DISK35[7]),

        // Write output (not implemented)
        .FLUX_WRITE(),

        // Debug outputs
        .DEBUG_RSH(),
        .DEBUG_STATE()
    );

    //=========================================================================
    // 3.5" Drive (flux_drive.v)
    //=========================================================================

    flux_drive drive35 (
        // Configuration
        .IS_35_INCH(1'b1),          // This is the 3.5" drive
        .DRIVE_ID(2'd1),            // Drive 1

        // Global clocks and reset
        .CLK_14M(CLK_14M),
        .RESET(RESET),

        // Control from IWM
        .PHASES(iwm_phases),
        .IMMEDIATE_PHASES(iwm_phases),
        .LATCHED_SENSE_REG(3'b000),
        .IWM_MODE(5'b00000),
        .MOTOR_ON(iwm_motor_on),
        .SW_MOTOR_ON(iwm_motor_on),
        .DISKREG_SEL(DISK35[7]),
        .SEL35(DISK35[6]),
        .DRIVE_SELECT(iwm_drive_sel),
        .DRIVE_SLOT(1'b0),
        .DISK_MOUNTED(WOZ_TRACK_LOADED),
        .DISK_WP(1'b1),
        .DOUBLE_SIDED(1'b1),

        // Flux interface to IWM
        .FLUX_TRANSITION(flux_transition),
        .WRITE_PROTECT(drive_write_protect),
        .SENSE(),

        // Status outputs
        .MOTOR_SPINNING(motor_spinning),
        .DRIVE_READY(),
        .TRACK(track),

        // Track data interface
        .BIT_POSITION(bit_position),
        .TRACK_BIT_COUNT(WOZ_BIT_COUNT),
        .TRACK_LOADED(WOZ_TRACK_LOADED),

        // BRAM interface for track bits
        .BRAM_ADDR(WOZ_BIT_ADDR),
        .BRAM_DATA(WOZ_BIT_DATA),

        // SD block interface (optional, not used in basic mode)
        .SD_TRACK_REQ(),
        .SD_TRACK_STROBE(),
        .SD_TRACK_ACK(1'b0)
    );

    //=========================================================================
    // Output assignments
    //=========================================================================

    assign WOZ_TRACK = track;
    assign FLOPPY_MOTOR_ON = motor_spinning && is_35_inch;

`ifdef SIMULATION
    // Debug: Monitor IWM/drive interaction
    reg [7:0] debug_byte_count;
    reg [7:0] prev_data_out;

    always @(posedge CLK_14M) begin
        if (RESET) begin
            debug_byte_count <= 8'd0;
            prev_data_out <= 8'h00;
        end else if (cpu_rd && (D_OUT != prev_data_out) && motor_spinning) begin
            if (debug_byte_count < 8'd32) begin
                $display("FLUX_CTRL: CPU read byte %02h at track=%0d bit_pos=%0d",
                         D_OUT, track, bit_position);
                debug_byte_count <= debug_byte_count + 1'd1;
            end
            prev_data_out <= D_OUT;
        end
    end

    // Debug: Flux transition monitoring
    reg flux_trans_prev;
    reg [15:0] flux_count;
    always @(posedge CLK_14M) begin
        if (RESET) begin
            flux_trans_prev <= 1'b0;
            flux_count <= 16'd0;
        end else begin
            flux_trans_prev <= flux_transition;
            if (flux_transition && !flux_trans_prev) begin
                flux_count <= flux_count + 1'd1;
                if (flux_count < 16'd100) begin
                    $display("FLUX_CTRL: Flux transition #%0d at bit_pos=%0d", flux_count, bit_position);
                end
            end
        end
    end
`endif

endmodule
