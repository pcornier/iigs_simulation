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
    DISK_ACTIVE, MOTOR_PHASE, WRITE_MODE, READ_DISK, WRITE_REG,
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

    // --- Drive Geometry and Timing Parameters ---
    localparam MAX_PHASE_525 = 139; // 35 tracks * 4 steps/track - 1
    localparam MAX_PHASE_35  = 319; // 80 tracks * 4 steps/track - 1
    // Data rate: 1 nibble per 32µs (slow) or 16µs (fast)
    // 1 byte = 64µs (slow) or 32µs (fast)
    // With a 2MHz clock (500ns period), we need 128 cycles for slow and 64 for fast.
    localparam SLOW_BYTE_PERIOD = 7'd128;
    localparam FAST_BYTE_PERIOD = 7'd64;

    wire [8:0] max_phase = IS_35_INCH ? MAX_PHASE_35 : MAX_PHASE_525;
    wire [6:0] byte_period = FAST_MODE ? FAST_BYTE_PERIOD : SLOW_BYTE_PERIOD;

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
        reg [6:0] byte_delay;
        reg        disk_ready_d;
        reg        disk_active_d;
        reg [15:0] sample_count;
        if (RESET) begin
            track_byte_addr <= 13'b0;
            byte_delay <= 7'b0;
            reset_data_reg <= 1'b0;
            data_reg <= 8'h00;
            disk_ready_d <= 1'b0;
            disk_active_d <= 1'b0;
            sample_count <= 16'd0;
        end else begin
            TRACK_WE <= 1'b0;
            Q3_D <= Q3;
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
            if (Q3 && ~Q3_D && DISK_READY && DISK_ACTIVE) begin
                if (byte_delay > 0) begin
                    byte_delay <= byte_delay - 1;
                end else begin
                    // Timer expired, perform a byte operation and reset timer
                    byte_delay <= byte_period;

                    if (WRITE_MODE == 1'b0) begin // Read Mode
                        data_reg <= TRACK_DO;
`ifdef SIMULATION
                        if (sample_count < 16'd64) begin
                            $display("DRIVE%0s RD: track=%0d addr=%04h data=%02h", IS_35_INCH?"(3.5)":"(5.25)", TRACK, track_byte_addr, TRACK_DO);
                            sample_count <= sample_count + 1;
                        end
`endif
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
                end
                
                // Latch clearing logic
                if (reset_data_reg) begin
                    data_reg <= 8'b0;
                    reset_data_reg <= 1'b0;
                end
                if (READ_DISK && PH0) begin
                    reset_data_reg <= 1'b1;
                end
            end
        end
    end

    assign D_OUT = data_reg;
    assign TRACK_ADDR = track_byte_addr;
    assign TRACK_DI = data_reg;

endmodule
