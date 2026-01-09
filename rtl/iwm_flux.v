//
// iwm_flux.v: IWM Core with Flux Transition Interface
//
// This module implements the IWM's flux decoding and register read logic.
// Soft switch state (Q6, Q7, phases, motor) is received as INPUTS from
// the parent module (iwm_woz.v), which is the single source of truth.
//
// Key responsibilities:
// - Flux transition decoding (window-based state machine)
// - Data/shift register management
// - Register read mux (data, status, handshake)
//
// Reference: MAME iwm.cpp (src/devices/machine/iwm.cpp)
//

module iwm_flux (
    // Global signals
    input  wire        CLK_14M,         // 14MHz master clock
    input  wire        RESET,

    // CPU interface
    input  wire [3:0]  ADDR,            // $C0E0-$C0EF offset (for register read mux)
    input  wire        RD,              // Read strobe (active high)
    input  wire        WR,              // Write strobe (active high)
    input  wire [7:0]  DATA_IN,         // Data from CPU (for mode register write)
    output wire [7:0]  DATA_OUT,        // Data to CPU

    // Soft switch state from iwm_woz.v (SINGLE SOURCE OF TRUTH)
    input  wire [3:0]  SW_PHASES,       // Current phase state
    input  wire        SW_MOTOR_ON,     // Motor on command
    input  wire        SW_DRIVE_SEL,    // Drive select
    input  wire        SW_Q6,           // Q6 latch state
    input  wire        SW_Q7,           // Q7 latch state
    input  wire [7:0]  SW_MODE,         // Mode register

    // Flux interface from drive (active high pulse when flux reversal detected)
    input  wire        FLUX_TRANSITION,

    // Status inputs from drive
    input  wire        MOTOR_ACTIVE,    // Motor command is on (like MAME m_active, not gated by disk)
    input  wire        MOTOR_SPINNING,  // Physical motor state (gated by disk presence, for byte decoding)
    input  wire        DISK_READY,      // Track data is valid and motor spinning
    input  wire        DISK_MOUNTED,    // Disk image is loaded (independent of motor)

    // Drive type selection
    input  wire        IS_35_INCH,      // 1 = 3.5" drive, 0 = 5.25" drive

    // Per-drive status sensing (computed by flux_drive, muxed by iwm_woz)
    input  wire        SENSE_BIT,       // Status sense from selected drive
    input  wire [2:0]  LATCHED_SENSE_REG, // Latched sense register index (for debug logging)
    input  wire        DISKREG_SEL,     // SEL bit from $C031 (for debug logging)

    // Write output (future use)
    output wire        FLUX_WRITE,      // Pulse when writing flux transition

    // Debug
    output wire [7:0]  DEBUG_RSH,       // Read shift register (for debug)
    output wire [2:0]  DEBUG_STATE      // State machine state (for debug)
);

    //=========================================================================
    // IWM Data Registers
    //=========================================================================

    reg [7:0]  m_data;      // Data register - holds completed byte from disk
    reg [7:0]  m_rsh;       // Read shift register - bits shift in here
    reg [7:0]  m_wsh;       // Write shift register - bits shift out here
    reg [7:0]  m_whd;       // Write handshake register (MAME: initialized to 0xBF)
    reg        m_data_read; // Flag: data register has been read since last byte loaded
    reg        m_rw_mode;   // 0 = read mode, 1 = write mode (tracks Q7 for mode changes)
    reg        m_motor_was_on; // Track motor state for edge detection
    reg [5:0]  async_update;   // MAME: countdown to clear m_data in async mode (increased to 50 cycles)
    reg        bit7_acknowledged; // MAME: bit 7 was read, mask it for subsequent reads

    // Async mode: mode bit 1 = 1 means async (MAME: is_sync() = !(mode & 0x02))
    wire       is_async = SW_MODE[1];

    //=========================================================================
    // State Machine (from MAME)
    //=========================================================================

    localparam S_IDLE           = 3'd0;
    localparam SR_WINDOW_EDGE_0 = 3'd1;  // Reading: waiting for flux transition
    localparam SR_WINDOW_EDGE_1 = 3'd2;  // Reading: flux detected, wait half window
    localparam SW_WINDOW_LOAD   = 3'd3;  // Writing: load shift register
    localparam SW_WINDOW_MIDDLE = 3'd4;  // Writing: check MSB
    localparam SW_WINDOW_END    = 3'd5;  // Writing: end window
    localparam SW_UNDERRUN      = 3'd6;  // Writing: underrun error

    reg [2:0]  rw_state;
    reg [5:0]  window_counter; // Countdown for window timing

    //=========================================================================
    // Window Timing (from MAME iwm.cpp half_window_size/window_size)
    //=========================================================================
    // Window timing depends on drive type:
    // - 3.5" drives: 28-cycle windows (2µs bit cells)
    // - 5.25" drives: 56-cycle windows (4µs bit cells), or 28 in fast mode

    wire        fast_mode = SW_MODE[3];
    wire [5:0]  full_window = IS_35_INCH ? 6'd28 : (fast_mode ? 6'd28 : 6'd56);
    wire [5:0]  half_window = IS_35_INCH ? 6'd14 : (fast_mode ? 6'd14 : 6'd28);

    //=========================================================================
    // Flux Edge Detection
    //=========================================================================

    reg        prev_flux;
    reg        prev_sm_active;  // For debug: track state machine activation
    reg        flux_pending;    // Latched when flux arrives during EDGE_1
    wire       flux_edge = FLUX_TRANSITION && !prev_flux;

`ifdef SIMULATION
    reg [31:0] debug_cycle;
`endif

    //=========================================================================
    // State Machine and Data Register Logic
    //=========================================================================

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            rw_state       <= S_IDLE;
            m_rsh          <= 8'h00;
            m_data         <= 8'h00;
            m_whd          <= 8'hBF;  // MAME: initialized to 0xBF
            async_update   <= 4'd0;
            bit7_acknowledged <= 1'b0;
            m_data_read    <= 1'b1;   // Start as "read" so first byte triggers ready
            m_rw_mode      <= 1'b0;   // Start in read mode
            m_motor_was_on <= 1'b0;
            window_counter <= 6'd0;
            prev_flux      <= 1'b0;
            prev_sm_active <= 1'b0;
            flux_pending   <= 1'b0;
`ifdef SIMULATION
            debug_cycle    <= 32'd0;
`endif
        end else begin
`ifdef SIMULATION
            debug_cycle <= debug_cycle + 1;
`endif
            // MAME behavior: Clear m_data when entering read mode
            // Only reset if motor was truly stopped (not spinning), not just command toggling
            if (MOTOR_ACTIVE && !m_motor_was_on && !SW_Q7 && !MOTOR_SPINNING) begin
                m_data <= 8'h00;
                m_rw_mode <= 1'b0;
                rw_state <= S_IDLE;
`ifdef SIMULATION
                $display("IWM_FLUX: Entering READ mode, m_data <= 0x00");
`endif
            end else if (MOTOR_ACTIVE && m_motor_was_on && m_rw_mode && !SW_Q7) begin
                // Switching from write mode to read mode - always reset
                m_data <= 8'h00;
                m_rw_mode <= 1'b0;
                rw_state <= S_IDLE;
`ifdef SIMULATION
                $display("IWM_FLUX: Switching to READ mode, m_data <= 0x00");
`endif
            end else if (MOTOR_ACTIVE && SW_Q7 && !m_rw_mode) begin
                m_rw_mode <= 1'b1;
                m_whd <= m_whd | 8'h40;
            end else if (!MOTOR_ACTIVE && m_motor_was_on) begin
                // Motor command off - but only reset state if motor actually stopped
                m_whd <= m_whd & 8'hBF;
                m_rw_mode <= 1'b0;
                // Don't reset state if motor is still spinning - bytes may still be decoding
                if (!MOTOR_SPINNING) begin
                    rw_state <= S_IDLE;
                end
`ifdef SIMULATION
                $display("IWM_FLUX: Motor off, m_whd <= %02h (cleared bit 6) spin=%0d", m_whd & 8'hBF, MOTOR_SPINNING);
`endif
            end
            m_motor_was_on <= MOTOR_ACTIVE;

            // MAME async_update logic (must happen BEFORE read handling):
            // In async mode, m_data is cleared 14 cycles after a valid byte was read.
            // This happens BEFORE the next read is processed, so the read sees 0x00.
            if (async_update != 0) begin
                if (async_update == 1) begin
                    // Counter about to hit 0 - clear m_data NOW
                    if (is_async) begin
                        m_data <= 8'h00;
                        bit7_acknowledged <= 1'b0;
`ifdef SIMULATION
                        $display("IWM_FLUX: async_update expired, clearing m_data to 0");
`endif
                    end
                end
                async_update <= async_update - 1'b1;
            end

            // Set data_read flag when CPU reads data register (Q7=0, Q6=0)
            // Use immediate Q6/Q7 values from current address
            // Also handle MAME async mode handshake: clear bit7 immediately on read
            if (RD) begin
                // Calculate immediate Q6/Q7 inline
                if ((((ADDR[3:1] == 3'b111) ? ADDR[0] : SW_Q7) == 1'b0) &&
                    (((ADDR[3:1] == 3'b110) ? ADDR[0] : SW_Q6) == 1'b0)) begin
                    m_data_read <= 1'b1;
                    // MAME async mode behavior:
                    // When reading a valid byte (bit7=1), immediately clear bit7 so
                    // subsequent reads see "not ready". Also start countdown to clear
                    // the entire byte after 14 cycles.
                    // Note: check effective_data_raw[7] (raw bit7), not effective_data[7]
                    // (which may be masked if already acknowledged)
                    if (MOTOR_ACTIVE && is_async && effective_data_raw[7]) begin
                        // Always acknowledge when reading valid byte
                        bit7_acknowledged <= 1'b1;
                        // Start countdown if not already running, OR if this is a new byte
                        // completing (in which case the old countdown is obsolete)
                        if (async_update == 0 || byte_completing) begin
                            async_update <= 6'd50; // Approx 3.5us at 14MHz
`ifdef SIMULATION
                            $display("IWM_FLUX: async_update started (byte_completing=%0d)", byte_completing);
`endif
                        end
                    end
                end
            end
            prev_flux <= FLUX_TRANSITION;

            // State machine runs when motor is spinning and disk is ready
`ifdef SIMULATION
            if ((MOTOR_SPINNING && DISK_READY) != prev_sm_active) begin
                $display("IWM_FLUX: State machine %s (MOTOR_SPINNING=%0d DISK_READY=%0d)",
                         (MOTOR_SPINNING && DISK_READY) ? "ACTIVE" : "IDLE",
                         MOTOR_SPINNING, DISK_READY);
            end
`endif
            if (MOTOR_SPINNING && DISK_READY) begin
                case (rw_state)
                    S_IDLE: begin
                        rw_state <= SR_WINDOW_EDGE_0;
                        window_counter <= full_window;
                        m_rsh <= 8'h00;
                    end

                    SR_WINDOW_EDGE_0: begin
                        // Check for current flux edge OR pending flux from EDGE_1
                        if (flux_edge || flux_pending) begin
                            rw_state <= SR_WINDOW_EDGE_1;
                            window_counter <= half_window;
                            flux_pending <= 1'b0;  // Clear pending flag
`ifdef SIMULATION
                            if (m_rsh < 8'h10) begin
                                $display("IWM_FLUX: @%0d Flux edge, rsh=%02h win=%0d FLUX=%0d prev=%0d pend=%0d",
                                         debug_cycle, m_rsh, window_counter, FLUX_TRANSITION, prev_flux, flux_pending);
                            end
`endif
                        end else if (window_counter == 6'd1) begin
                            m_rsh <= {m_rsh[6:0], 1'b0};
                            window_counter <= full_window;
`ifdef SIMULATION
                            if (m_rsh < 8'h10 && m_rsh > 8'h00) begin
                                $display("IWM_FLUX: @%0d Window timeout, rsh=%02h -> %02h",
                                         debug_cycle, m_rsh, {m_rsh[6:0], 1'b0});
                            end
`endif
                        end else begin
                            window_counter <= window_counter - 1'd1;
                        end
                    end

                    SR_WINDOW_EDGE_1: begin
                        // MAME behavior: In EDGE_1, don't immediately act on flux - but
                        // latch it so we detect it immediately when we go to EDGE_0.
                        // This handles consecutive 1-bits where flux arrives before
                        // the half-window completes.
                        if (flux_edge) begin
                            flux_pending <= 1'b1;  // Latch for use in EDGE_0
                        end

                        if (window_counter == 6'd1) begin
                            m_rsh <= {m_rsh[6:0], 1'b1};
                            rw_state <= SR_WINDOW_EDGE_0;
                            window_counter <= full_window;
`ifdef SIMULATION
                            if (m_rsh < 8'h08) begin
                                $display("IWM_FLUX: @%0d EDGE_1 complete, shift 1, rsh=%02h->%02h pend=%0d",
                                         debug_cycle, m_rsh, {m_rsh[6:0], 1'b1}, flux_pending);
                            end
`endif
                        end else begin
                            window_counter <= window_counter - 1'd1;
                        end
                    end

                    default: begin
                        rw_state <= S_IDLE;
                    end
                endcase

                // Byte complete when MSB is set
                if (m_rsh >= 8'h80) begin
`ifdef SIMULATION
                    $display("IWM_FLUX: @%0d BYTE COMPLETE - m_data <= %02h state=%0d win=%0d FLUX=%0d prev=%0d",
                             debug_cycle, m_rsh, rw_state, window_counter, FLUX_TRANSITION, prev_flux);
`endif
                    m_data <= m_rsh;
                    m_rsh <= 8'h00;
                    m_data_read <= 1'b0;
                    // Reset async_update for new byte, UNLESS CPU is reading valid data
                    // in this same cycle (read handler will set async_update)
                    if (!cpu_reading_valid_data) begin
                        async_update <= 4'd0;
                    end
                    // Clear bit7_acknowledged for new byte, UNLESS CPU is reading
                    // in this same cycle (read handler will set bit7_acknowledged)
                    if (!cpu_reading_data) begin
                        bit7_acknowledged <= 1'b0;
                    end
                end
            end

            // Reset state when motor stops or disk removed
            if (!MOTOR_SPINNING || !DISK_READY) begin
                rw_state <= S_IDLE;
                window_counter <= 6'd0;
                flux_pending <= 1'b0;
                bit7_acknowledged <= 1'b0;
                async_update <= 4'd0;
            end

            prev_sm_active <= MOTOR_SPINNING && DISK_READY;

        end
    end

    //=========================================================================
    // Register Read Logic (Q6/Q7 select)
    //=========================================================================
    // Q7 Q6 | Read Returns
    // ------+-------------
    //  0  0 | Data register (disk byte)
    //  0  1 | Status register
    //  1  0 | Write handshake register
    //  1  1 | 0xFF (or mode bits)

    // Status register (MAME reference: iwm.cpp status_r() line 303)
    // Bit 7: SENSE_BIT - drive status sense line (write-protect, disk present, etc.)
    //        Selected by phase lines, comes from drive via SENSE_BIT input
    // Bit 6: 0 (reserved)
    // Bit 5: motor_active && disk_installed
    // Bits 4-0: mode register
    // Note: data_ready is NOT in the status register - it's only relevant for
    //       determining when to read the DATA register (Q6=0, Q7=0)
    wire motor_status_bit = MOTOR_ACTIVE && DISK_MOUNTED;
    wire [7:0] status_reg = {SENSE_BIT, 1'b0, motor_status_bit, SW_MODE[4:0]};

    // Write handshake register
    wire [7:0] handshake_reg = 8'h80;

    // Immediate Q6/Q7 values for current access
    // If current access is to Q6/Q7 switch, use ADDR[0] for that bit
    // Otherwise use the latched value from SW_Q6/SW_Q7
    wire access_q6 = (ADDR[3:1] == 3'b110);
    wire access_q7 = (ADDR[3:1] == 3'b111);
    wire immediate_q6 = access_q6 ? ADDR[0] : SW_Q6;
    wire immediate_q7 = access_q7 ? ADDR[0] : SW_Q7;

    // Combinatorial bypass for same-cycle read
    // MAME behavior: always return m_data (the completed byte), which holds its value
    // until the next byte completes. The byte_completing bypass handles the case where
    // the CPU reads in the same cycle that m_rsh reaches 0x80+.
    wire byte_completing = (m_rsh >= 8'h80) && MOTOR_SPINNING && DISK_READY;
    wire [7:0] effective_data_raw = byte_completing ? m_rsh : m_data;

    // MAME async mode: m_data keeps its full value (including bit7=1) until async_update
    // expires and clears m_data to 0x00. Unlike our previous approach, we do NOT mask
    // bit7 on output - multiple reads can see bit7=1 until the data is cleared.
    wire [7:0] effective_data = effective_data_raw;

    // Helper wires for byte completion logic to avoid race conditions
    wire cpu_reading_data = RD && !immediate_q7 && !immediate_q6;
    wire cpu_reading_valid_data = cpu_reading_data && MOTOR_ACTIVE && is_async && effective_data_raw[7];

    reg [7:0] data_out_mux;
    always @(*) begin
        case ({immediate_q7, immediate_q6})
            2'b00: data_out_mux = MOTOR_ACTIVE ? effective_data : 8'hFF;
            2'b01: data_out_mux = status_reg;
            2'b10: data_out_mux = handshake_reg;
            2'b11: data_out_mux = 8'hFF;
        endcase
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign DATA_OUT     = data_out_mux;
    assign FLUX_WRITE   = 1'b0;  // TODO: implement write support
    assign DEBUG_RSH    = m_rsh;
    assign DEBUG_STATE  = rw_state;

`ifdef SIMULATION
    // Debug: log state transitions
    reg [2:0] prev_state;
    always @(posedge CLK_14M) begin
        if (rw_state != prev_state && prev_state != S_IDLE) begin
            $display("IWM_FLUX: State %0d -> %0d (window=%0d rsh=%02h data=%02h)",
                     prev_state, rw_state, window_counter, m_rsh, m_data);
        end
        prev_state <= rw_state;
    end

    // Debug: log register reads
    always @(posedge CLK_14M) begin
        if (RD) begin
            case ({immediate_q7, immediate_q6})
                2'b00: $display("IWM_FLUX: READ DATA @%01h -> %02h (motor=%0d rsh=%02h data=%02h bc=%0d dr=%0d q6=%0d q7=%0d)",
                               ADDR, data_out_mux, MOTOR_ACTIVE, m_rsh, m_data, byte_completing, DISK_READY, SW_Q6, SW_Q7);
                2'b01: $display("IWM_FLUX: READ STATUS @%01h -> %02h (sense=%0d m_reg=%01h latched=%01h sel=%0d phases=%04b is_35=%0d motor_active=%0d mounted=%0d)",
                               ADDR, data_out_mux, SENSE_BIT, {DISKREG_SEL, LATCHED_SENSE_REG}, LATCHED_SENSE_REG, DISKREG_SEL, SW_PHASES, IS_35_INCH, MOTOR_ACTIVE, DISK_MOUNTED);
                2'b10: $display("IWM_FLUX: READ HANDSHAKE @%01h -> %02h", ADDR, data_out_mux);
                2'b11: $display("IWM_FLUX: READ @%01h -> %02h (q7=q6=1)", ADDR, data_out_mux);
            endcase
        end
    end
`endif

endmodule
