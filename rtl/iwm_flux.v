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

// Enable detailed byte framing debug output for comparing with MAME
// Uncomment the following line to enable:
// `define BYTE_FRAME_DEBUG

// Enable sector read logging with checksum validation
// Uncomment the following line to enable:
// `define SECTOR_DEBUG

// Enable byte offset debugging - tracks first D5 prologue position
// Uncomment the following line to enable:
`define DEBUG_BYTE_OFFSET

// For simulator builds that already use `+define+debug=1`, enable a limited
// sector/prologue trace without needing to edit this file per-run.
`ifdef debug
`define IWM_SECTOR_TRACE
`endif

module iwm_flux (
    // Global signals
    input  wire        CLK_14M,         // 14MHz master clock
    input  wire        CLK_7M_EN,       // 7MHz clock enable (IWM runs at 7M like real hardware)
    input  wire        RESET,
    input  wire        CEN,             // Clock enable (phi2) for CPU bus timing

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

    // Disk position for debug logging (to compare with MAME)
    input  wire [16:0] DISK_BIT_POSITION, // Current bit position on track

    // Bit-cell timing from flux_drive for window synchronization
    input  wire [5:0]  FLUX_BIT_TIMER,    // Current bit timer value from flux_drive

    // Write output (future use)
    output wire        FLUX_WRITE,      // Pulse when writing flux transition

    // Debug
    output wire [7:0]  DEBUG_RSH,       // Read shift register (for debug)
    output wire [2:0]  DEBUG_STATE,     // State machine state (for debug)
    output wire        DEBUG_BYTE_VALID // Pulse when byte completes (new_byte signal)
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
    reg [31:0] m_data_gen;  // Generation counter for m_data updates (guards async clear)
    // Minimal write-mode underrun handling:
    // We don't implement flux writing yet, but the IIgs ROM/SmartPort code can enter the
    // WHD polling loop while Q7=1. In MAME, if no data is written in write mode, the IWM
    // quickly signals an underrun and clears WHD bit6, allowing the ROM loop to exit.
    // Without this, WHD can remain 0xFF and hang at FF:57B7 (LDA $C08C,X; AND #$40; BNE).
    reg [9:0]  write_underrun_cnt;
    localparam [9:0] WRITE_UNDERRUN_DELAY_7M = 10'd64; // ~9µs at 7MHz
    reg [31:0] async_tick_14m;      // 14MHz tick counter for async timing
    reg [31:0] last_sync_14m;       // Last bit-cell sync tick (approx m_last_sync)
    reg [31:0] async_update_deadline;
    reg        async_update_pending;
    reg [31:0] async_clear_gen;     // m_data_gen snapshot for async clear
    // CPU read tracking (PHI2/CEN-relative)
    reg        rd_in_progress;     // RD captured during this PHI2-high bus cycle
    reg        rd_was_data_reg;    // Latched Q7/Q6 decode for this read
    reg        rd_latched_valid;   // Latched a valid data byte during this read
    reg [7:0]  rd_data_latched;    // Byte value observed by CPU during PHI2-high
    reg        rd_from_completion; // FIX: True if rd_data_latched was updated from mid-cycle byte completion
    reg        prev_cen;           // CEN (PHI2) edge detect
    // CPU access tracking (read OR write) for MAME-like async_update scheduling
    reg        access_in_progress;    // Any IWM access captured during this PHI2-high bus cycle
    reg        access_q7_latched;     // Latched Q7 state for this access (MAME uses !(m_control & 0x80))
    reg        access_q6_latched;     // Latched Q6 state for this access (needed to distinguish DATA vs STATUS)
    reg        access_data_valid;     // Latched "byte valid" at access time (m_data bit7)
    reg [31:0] access_gen_latched;    // Latched m_data_gen at access START (not end!)
    wire       rd_is_data_reg;        // Combinational decode for DATA register reads
    reg [3:0]  latch_hold_cnt;       // Latched read hold in bit-times (mode bit0)
    wire       latch_mode = SW_MODE[0];
    wire       latch_hold_active = (latch_hold_cnt != 4'd0);

    // MAME async behavior: In async mode, completed bytes remain in m_data until overwritten by
    // the next completed byte. After the CPU performs an IWM register access while a valid byte
    // is present, MAME schedules m_data to clear after 14 internal cycles (~2µs at 7MHz).
    // We track time at 14MHz, so this is 28 cycles.
    // FIX: Increased to 56 cycles (4µs) because the IIgs ROM has gaps in its read loop
    // (e.g., during sector header parsing) that exceed the 28-cycle deadline.
    localparam [31:0] ASYNC_CLEAR_DELAY_14M = 32'd56;

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
    reg [9:0]  full_window_frac;
    reg [9:0]  half_window_frac;

    //=========================================================================
    // Window Timing (from MAME iwm.cpp half_window_size/window_size)
    //=========================================================================
    // Window timing depends on drive type:
    //
    // IMPORTANT: Window timing runs at 14M for precision!
    // MAME uses cycle counts at 7MHz, but processes flux at exact arrival times.
    // vsim samples at discrete clock edges, so we run at 14M to minimize
    // quantization error. Without 14M precision, flux arrival time is rounded
    // to 7M edges, causing 0-1 cycle error per bit that accumulates and
    // causes byte boundary drift.
    //
    // Window timing in 14M cycles (doubled from MAME's 7MHz values):
    // MAME mode 0x00 (slow): half=14@7M, window=28@7M -> half=28@14M, window=56@14M (4µs)
    // MAME mode 0x08 (fast): half=7@7M, window=14@7M -> half=14@14M, window=28@14M (2µs)
    // Note: 3.5" drives use 2µs bit cells but ROM often doesn't set fast mode bit!

    wire        fast_mode = SW_MODE[3];
    // Window timing: MAME uses 7MHz clock, we run at 14MHz.
    // 3.5" bit cells are 2us -> 28.636 cycles @14.318MHz, so use fractional windows.
    wire [5:0]  base_full_window = IS_35_INCH ? 6'd28 : (fast_mode ? 6'd28 : 6'd56);
    wire [5:0]  base_half_window = IS_35_INCH ? 6'd14 : (fast_mode ? 6'd14 : 6'd28);
    // Fractional window timing for 3.5" drives.
    // Both flux_drive.v and iwm_flux.v need fractional timing to achieve 28.636 cycles/bit.
    // Without it, the windows drift relative to the flux transitions.
    wire        use_fractional_window = IS_35_INCH;
    wire [9:0]  full_window_step = use_fractional_window ? 10'd636 : 10'd0;
    wire [9:0]  half_window_step = use_fractional_window ? 10'd318 : 10'd0;

    task automatic load_full_window;
        reg [9:0] tmp;
        begin
            tmp = full_window_frac + full_window_step;
            if (tmp >= 10'd1000) begin
                window_counter <= base_full_window + 6'd1;
                full_window_frac <= tmp - 10'd1000;
            end else begin
                window_counter <= base_full_window;
                full_window_frac <= tmp;
            end
        end
    endtask

    task automatic load_half_window;
        reg [9:0] tmp;
        begin
            tmp = half_window_frac + half_window_step;
            if (tmp >= 10'd1000) begin
                window_counter <= base_half_window + 6'd1;
                half_window_frac <= tmp - 10'd1000;
            end else begin
                window_counter <= base_half_window;
                half_window_frac <= tmp;
            end
        end
    endtask

    //=========================================================================
    // Flux Edge Detection
    //=========================================================================

    reg        prev_flux;
    reg        prev_sm_active;  // For debug: track state machine activation
    reg        flux_seen;       // Latched at 14M when flux edge detected, cleared after decode
    wire       flux_edge = FLUX_TRANSITION && !prev_flux;
    // Treat a 1-cycle FLUX_TRANSITION pulse as visible to the state machine in the same
    // 14MHz tick; relying on `flux_seen` alone delays visibility by one tick (NBA),
    // which can miss edges that land on window boundaries.
    wire       flux_now  = flux_edge || flux_seen;

    // Data-ready gating: avoid returning stale bytes after they've been read.
    // Predict same-cycle byte completion so reads can see the new byte immediately.
    wire       shift_edge0_now = (rw_state == SR_WINDOW_EDGE_0) && (window_counter == 6'd1) && !flux_now;
    wire       shift_edge1_now = (rw_state == SR_WINDOW_EDGE_1) && (window_counter == 6'd1);
    wire [7:0] next_rsh_edge0 = {m_rsh[6:0], 1'b0};
    wire [7:0] next_rsh_edge1 = {m_rsh[6:0], 1'b1};
    wire       byte_completing = DISK_READY &&
                                 ((shift_edge0_now && next_rsh_edge0[7]) ||
                                  (shift_edge1_now && next_rsh_edge1[7]));
    wire [7:0] byte_complete_data = shift_edge0_now ? next_rsh_edge0 :
                                    shift_edge1_now ? next_rsh_edge1 :
                                    8'h00;

    // Edge detection for byte completion (for DEBUG_BYTE_VALID output)
    // Moved outside ifdef blocks so it's always available
    reg        prev_byte_completing_dbg;
    wire       new_byte_dbg = byte_completing && !prev_byte_completing_dbg;
    // FIX4 REMOVED: The is_flux_async bypass caused the CPU to see stale bytes when timing
    // was tight between prologue read and first data byte read. Without the bypass,
    // the CPU correctly sees 00 after reading a byte (via m_data_read flag), then waits
    // in the polling loop until the next byte completes. This matches ROM expectations.
    // The m_data_read flag provides the necessary "byte consumed" semantics.
    wire       is_flux_async = is_async && DISK_READY;  // Keep for debug logging
    wire       data_ready = byte_completing || (m_data[7] && (!m_data_read || latch_hold_active));
    wire [7:0] effective_data_raw = byte_completing ? byte_complete_data : m_data;
    wire [7:0] effective_data = data_ready ? effective_data_raw : 8'h00;
    // If a byte completes during an active data read, treat it as consumed.
    // FIX: Only consume if the latched byte was NOT from a mid-cycle byte completion.
    // If rd_from_completion is set, the CPU's latch came from the SAME byte that's now completing,
    // meaning the CPU saw it via combinational bypass but shouldn't consume it yet.
    wire       rd_consumes_byte = rd_in_progress && rd_was_data_reg && rd_data_latched[7] && rd_latched_valid && !rd_from_completion;

    // Ack the byte only if it matches the value observed by the CPU.
    // This avoids a late PHI2-fall ack clearing a newly completed byte.
    wire       rd_ack_match_old = (rd_data_latched == m_data);
    wire       rd_ack_match_new = byte_completing && (rd_data_latched == byte_complete_data);
    wire       rd_ack_take = rd_latched_valid && rd_data_latched[7] &&
                             ((byte_completing && rd_ack_match_new) ||
                              (!byte_completing && rd_ack_match_old));

`ifdef SIMULATION
    reg [31:0] debug_cycle;
    reg [31:0] byte_counter;  // Sequential byte counter for comparison with MAME
    reg [31:0] bytes_read_counter;  // How many bytes CPU has read (valid reads with bit7=1)
    reg [31:0] bytes_lost_counter;  // How many bytes were cleared by async_update before CPU read
    reg [7:0]  prev_m_data;  // For tracking m_data changes
    reg [31:0] m_data_change_count;  // Count of m_data changes
    reg [7:0]  flux_edge_log_count;
    reg [15:0] dbg_bp_count;
    reg [7:0]  prolog_last1;  // Most recent completed byte (for prolog detection)
    reg [7:0]  prolog_last2;  // Second most recent completed byte
    wire       dbg_prolog_window = ((DISK_BIT_POSITION >= 17'd21500) && (DISK_BIT_POSITION <= 17'd21540)) ||
                                   ((DISK_BIT_POSITION >= 17'd21660) && (DISK_BIT_POSITION <= 17'd21690)) ||
                                   ((DISK_BIT_POSITION >= 17'd21910) && (DISK_BIT_POSITION <= 17'd21940)) ||
                                   ((DISK_BIT_POSITION >= 17'd55840) && (DISK_BIT_POSITION <= 17'd55870));
`endif

`ifdef DEBUG_BYTE_OFFSET
    // Track first prologue position after motor start
    reg        dbg_motor_started;
    reg [31:0] dbg_first_byte_count;
    reg        dbg_first_d5_found;
    reg [16:0] dbg_first_d5_position;
    reg [31:0] dbg_first_d5_cycle;
    reg [7:0]  dbg_byte_history [0:15];  // Last 16 bytes before first D5
    reg [3:0]  dbg_history_idx;
    // Track first flux after S_IDLE transition
    reg        dbg_waiting_first_flux;
    reg [5:0]  dbg_first_flux_win;      // window_counter when first flux arrived
    reg [31:0] dbg_first_flux_cycle;
    reg [7:0]  dbg_flux_count_after_idle; // Count flux transitions since S_IDLE
`endif

    // Clear the read shift register shortly after a completed byte.
    // We intentionally keep the completed byte in `m_rsh` for 1x 14MHz tick so:
    // - `byte_completing` can bypass for same-cycle CPU reads, and
    // - debug/sector-trace logic can see the completed byte.
    // This is safe because the next bit shift does not occur for many 14MHz ticks.
    reg        clear_rsh_pending;
    reg [7:0]  shifted_rsh;

    //=========================================================================
    // State Machine and Data Register Logic
    //=========================================================================

    always @(posedge CLK_14M or posedge RESET) begin
        if (RESET) begin
            rw_state       <= S_IDLE;
            m_rsh          <= 8'h00;
            m_data         <= 8'h00;
            m_whd          <= 8'hBF;  // MAME: initialized to 0xBF
            async_tick_14m <= 32'd0;
            last_sync_14m  <= 32'd0;
            async_update_deadline <= 32'd0;
            async_update_pending <= 1'b0;
            async_clear_gen <= 32'd0;
            m_data_read    <= 1'b1;   // Start as "read" so first byte triggers ready
            m_rw_mode      <= 1'b0;   // Start in read mode
            m_motor_was_on <= 1'b0;
            m_data_gen     <= 32'd0;
            prev_flux      <= 1'b0;
            prev_sm_active <= 1'b0;
            flux_seen      <= 1'b0;
            window_counter <= 6'd0;
            full_window_frac <= 10'd0;
            half_window_frac <= 10'd0;
            rd_in_progress <= 1'b0;
            rd_was_data_reg <= 1'b0;
            rd_data_latched <= 8'h00;
            rd_from_completion <= 1'b0;
            prev_cen       <= 1'b0;
            access_in_progress <= 1'b0;
            access_q7_latched  <= 1'b0;
            access_q6_latched  <= 1'b0;
            access_data_valid  <= 1'b0;
            access_gen_latched <= 32'd0;
            write_underrun_cnt <= 10'd0;
            clear_rsh_pending   <= 1'b0;
            latch_hold_cnt <= 4'd0;
            prev_byte_completing_dbg <= 1'b0;
`ifdef SIMULATION
            debug_cycle    <= 32'd0;
            byte_counter   <= 32'd0;
            bytes_read_counter <= 32'd0;
            bytes_lost_counter <= 32'd0;
            prev_m_data    <= 8'd0;
            m_data_change_count <= 32'd0;
            flux_edge_log_count <= 8'd0;
            dbg_bp_count <= 16'd0;
            prolog_last1 <= 8'h00;
            prolog_last2 <= 8'h00;
`endif
`ifdef DEBUG_BYTE_OFFSET
            dbg_motor_started <= 1'b0;
            dbg_first_byte_count <= 32'd0;
            dbg_first_d5_found <= 1'b0;
            dbg_first_d5_position <= 17'd0;
            dbg_first_d5_cycle <= 32'd0;
            dbg_history_idx <= 4'd0;
            dbg_waiting_first_flux <= 1'b0;
            dbg_first_flux_win <= 6'd0;
            dbg_first_flux_cycle <= 32'd0;
            dbg_flux_count_after_idle <= 8'd0;
`endif
        end else begin
`ifdef SIMULATION
            debug_cycle <= debug_cycle + 1;
`endif
            // Track byte_completing edges for DEBUG_BYTE_VALID
            prev_byte_completing_dbg <= byte_completing;

            async_tick_14m <= async_tick_14m + 1'd1;
            // Approximate MAME's m_last_sync using bit-cell boundaries.
            if (shift_edge0_now || shift_edge1_now) begin
                last_sync_14m <= async_tick_14m + 1'd1;
            end
            if (clear_rsh_pending) begin
                clear_rsh_pending <= 1'b0;
                m_rsh <= 8'h00;
`ifdef SIMULATION
                if (byte_counter < 20) begin
                    $display("IWM_FLUX: RSH_CLEAR by clear_rsh_pending (was %02h)", m_rsh);
                end
`endif
            end

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
                write_underrun_cnt <= WRITE_UNDERRUN_DELAY_7M;
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

            // MAME async behavior: in async mode, m_data clears when the NEXT bit-cell sync
            // happens at least 14 cycles (7MHz) after the sync that was current during
            // the CPU access. This is different from wall-clock timing!
            // MAME: m_async_update = m_last_sync + 14; fires when m_last_sync >= m_async_update

            // Always track flux edges at 14M (so we don't miss any)
            prev_flux <= FLUX_TRANSITION;
`ifdef SIMULATION
            if (flux_edge && DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230 &&
                flux_edge_log_count < 8) begin
                $display("IWM_FLUX_EDGE pos=%0d state=%0d win=%0d frac=%0d seen=%0d",
                         DISK_BIT_POSITION, rw_state, window_counter, full_window_frac, flux_seen);
                flux_edge_log_count <= flux_edge_log_count + 1'd1;
            end

            // Latch mode hold counter (8 bit times after a completed byte).
            if (!latch_mode) begin
                latch_hold_cnt <= 4'd0;
            end else if ((shift_edge0_now || shift_edge1_now) && latch_hold_cnt != 4'd0) begin
                latch_hold_cnt <= latch_hold_cnt - 1'd1;
`ifdef SIMULATION
                if ((DISK_BIT_POSITION >= 17'd7135) && (DISK_BIT_POSITION <= 17'd7205) &&
                    latch_hold_cnt == 4'd1) begin
                    $display("IWM_LATCH_END: pos=%0d m_data=%02h m_data_read=%0d",
                             DISK_BIT_POSITION, m_data, m_data_read);
                end
`endif
            end
`endif

            // Latch flux edges that arrive in EDGE_1 so they can be applied to the next cell.
            // Do not latch EDGE_0 edges (they are handled immediately), and avoid carrying
            // edges that arrive exactly at the EDGE_1 shift boundary.
            if (flux_edge && (rw_state == SR_WINDOW_EDGE_1) && (window_counter != 6'd1)) begin
                flux_seen <= 1'b1;
`ifdef SIMULATION
                // Debug: trace flux edges as they arrive at IWM
                if (byte_counter < 100) begin
                    $display("IWM_FLUX: FLUX_EDGE #%0d pos=%0d state=%0d win=%0d rsh=%02h",
                             byte_counter, DISK_BIT_POSITION, rw_state, window_counter, m_rsh);
                end
                // Log late edges in EDGE_1 that are now carried to the next window.
                if ((rw_state == SR_WINDOW_EDGE_1) &&
                    (DISK_BIT_POSITION >= 17'd70190) && (DISK_BIT_POSITION <= 17'd70230)) begin
                    $display("IWM_FLUX_EDGE_LATE pos=%0d win=%0d frac=%0d seen=%0d",
                             DISK_BIT_POSITION, window_counter, full_window_frac, flux_seen);
                end
`endif
            end

            // FIX9: Continuous async deadline check (like MAME's sync())
            // MAME's sync() processes all time forward, and byte completions during that
            // interval cancel the async_update deadline. After sync(), if deadline passed
            // and wasn't cancelled, m_data is cleared.
            //
            // In vsim, we run the state machine every clock. The async deadline check should
            // also run every clock, so the clear happens at the actual deadline time rather
            // than being delayed until the next CPU access.
            //
            // This ensures: if deadline fires at cycle N, and byte completes at cycle N+10,
            // the clear happens at N (clearing old byte), then byte completion at N+10 sets
            // new byte. Without continuous check, the clear would happen at next CPU access
            // (say N+100), potentially after the new byte, causing incorrect behavior.
            if (async_update_pending && (async_tick_14m >= async_update_deadline)) begin
                // FIX: Don't clear if CPU has already read the data (m_data_read=1).
                // The async clear is meant for cases where CPU doesn't consume data fast enough,
                // not for clearing data that was successfully read.
                if (is_async && !byte_completing && m_data[7] && (m_data_gen == async_clear_gen) && !m_data_read) begin
                    if (!latch_hold_active) begin
                        m_data <= 8'h00;
`ifdef SIMULATION
                        $display("IWM_FLUX: ASYNC_CLEAR_CONTINUOUS m_data %02h -> 00 (cycle=%0d tick=%0d deadline=%0d gen=%0d)",
                                 m_data, debug_cycle, async_tick_14m, async_update_deadline, m_data_gen);
`endif
                    end
                end
                async_update_pending <= 1'b0;
            end

            // If async mode is disabled, drop any pending clear.
            if (!is_async) begin
                async_update_pending <= 1'b0;
            end

            if (CLK_7M_EN) begin
                // Minimal MAME-like write underrun: if we entered write mode (Q7=1) but no data writes
                // occur (we don't implement writes yet), clear WHD bit6 after a short delay so ROM
                // polling loops can proceed.
                if (m_rw_mode && m_whd[6]) begin
                    if (write_underrun_cnt != 10'd0) begin
                        write_underrun_cnt <= write_underrun_cnt - 10'd1;
                    end else begin
                        m_whd <= m_whd & 8'hBF;
                    end
                end else begin
                    write_underrun_cnt <= 10'd0;
                end
            end

            // State machine runs at 14M for precise flux timing!
            // MAME's IWM clocks at 7M but processes flux at exact arrival times.
            // vsim must run at 14M to avoid timing quantization that causes
            // byte boundary drift. Window values are doubled to compensate.
`ifdef SIMULATION
            if ((MOTOR_SPINNING && DISK_READY) != prev_sm_active) begin
                $display("IWM_FLUX: State machine %s (MOTOR_SPINNING=%0d DISK_READY=%0d pos=%0d byte_cnt=%0d rsh=%02h state=%0d win=%0d frac=%0d)",
                         (MOTOR_SPINNING && DISK_READY) ? "ACTIVE" : "IDLE",
                         MOTOR_SPINNING, DISK_READY, DISK_BIT_POSITION, byte_counter, m_rsh, rw_state, window_counter, full_window_frac);
            end
`endif
            if (MOTOR_SPINNING && DISK_READY) begin
                case (rw_state)
                    S_IDLE: begin
                        // MAME COMPATIBILITY FIX: Always start with EDGE_0 and rsh=0x00
                        //
                        // MAME's S_IDLE unconditionally sets:
                        //   m_rsh = 0x00;
                        //   m_rw_state = SR_WINDOW_EDGE_0;
                        //   m_next_state_change = m_last_sync + window_size();
                        //
                        // Previous vsim code checked for flux_edge and conditionally went to
                        // EDGE_1 with rsh=0x01. This caused a 1-bit byte framing offset because
                        // if a flux edge happened to be present at S_IDLE transition, vsim would
                        // start with a different shift register state than MAME.
                        //
                        // The flux detection during EDGE_0 handles the flux-at-start case
                        // correctly by transitioning to EDGE_1 within the first window.
`ifdef DEBUG_BYTE_OFFSET
                        $display("BYTE_OFFSET_IDLE: S_IDLE->EDGE_0 (MAME-style) - FLUX_TRANSITION=%0d prev_flux=%0d flux_edge=%0d pos=%0d cycle=%0d",
                                 FLUX_TRANSITION, prev_flux, flux_edge, DISK_BIT_POSITION, debug_cycle);
                        $display("BYTE_OFFSET_IDLE: window_counter=%0d base_full=%0d full_frac=%0d flux_bit_timer=%0d (will sync to flux)",
                                 window_counter, base_full_window, full_window_frac, FLUX_BIT_TIMER);
                        dbg_waiting_first_flux <= 1'b1;
                        dbg_flux_count_after_idle <= 8'd0;
`endif
                        rw_state <= SR_WINDOW_EDGE_0;
                        // Sync window_counter to flux_drive's bit_timer for byte alignment.
                        // FLUX_BIT_TIMER is the remaining time until flux_drive's next bit-cell.
                        if (FLUX_BIT_TIMER > 6'd0 && FLUX_BIT_TIMER <= base_full_window) begin
                            window_counter <= FLUX_BIT_TIMER;
                        end else begin
                            // Fallback for invalid timer values
                            window_counter <= base_full_window;
                        end
                        m_rsh <= 8'h00;
                        flux_seen <= 1'b0;
                        // Reset fractional accumulators
                        full_window_frac <= 10'd0;
                        half_window_frac <= 10'd0;
`ifdef SIMULATION
                        $display("IWM_FLUX: START_READ cycle=%0d win=%0d flux_timer=%0d mode=%02h",
                                 debug_cycle, (FLUX_BIT_TIMER > 6'd0 && FLUX_BIT_TIMER <= base_full_window) ? FLUX_BIT_TIMER : base_full_window,
                                 FLUX_BIT_TIMER, SW_MODE);
`endif
                    end

                    SR_WINDOW_EDGE_0: begin
                        if (flux_now) begin
                            rw_state <= SR_WINDOW_EDGE_1;
                            load_half_window();
                            flux_seen <= 1'b0;
`ifdef DEBUG_BYTE_OFFSET
                            dbg_flux_count_after_idle <= dbg_flux_count_after_idle + 1'd1;
                            if (dbg_waiting_first_flux) begin
                                dbg_waiting_first_flux <= 1'b0;
                                dbg_first_flux_win <= window_counter;
                                dbg_first_flux_cycle <= debug_cycle;
                                $display("BYTE_OFFSET_FIRST_FLUX: window_counter=%0d pos=%0d cycle=%0d (flux #%0d since S_IDLE)",
                                         window_counter, DISK_BIT_POSITION, debug_cycle, dbg_flux_count_after_idle + 1);
                            end
`endif
`ifdef BYTE_FRAME_DEBUG
                            $display("IWM_FLUX: EDGE_0->EDGE_1 flux pos=%0d win=%0d half=%0d",
                                     DISK_BIT_POSITION, base_full_window, base_half_window);
`endif
`ifdef SIMULATION
                            if (DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230) begin
                                $display("IWM_EDGE0_HIT pos=%0d cyc=%0d win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d rsh=%02h",
                                         DISK_BIT_POSITION, debug_cycle, window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen, m_rsh);
                            end
                            if (dbg_prolog_window) begin
                                $display("IWM_EDGE0_HIT_DBG pos=%0d cyc=%0d win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d rsh=%02h",
                                         DISK_BIT_POSITION, debug_cycle, window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen, m_rsh);
                            end
`endif
                        end else if (window_counter == 6'd1) begin
`ifdef BYTE_FRAME_DEBUG
                            $display("IWM_FLUX: SHIFT bit=0 rsh=%02h->%02h state=EDGE_0 endw=%0d",
                                     m_rsh, {m_rsh[6:0], 1'b0}, window_counter);
`endif
`ifdef SIMULATION
                            if (DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230) begin
                                $display("IWM_SHIFT0 pos=%0d cyc=%0d rsh=%02h->%02h win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                         DISK_BIT_POSITION, debug_cycle, m_rsh, {m_rsh[6:0], 1'b0},
                                         window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen);
                            end
                            if (dbg_prolog_window) begin
                                $display("IWM_SHIFT0_DBG pos=%0d cyc=%0d rsh=%02h->%02h win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                         DISK_BIT_POSITION, debug_cycle, m_rsh, {m_rsh[6:0], 1'b0},
                                         window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen);
                            end
`endif
                            shifted_rsh = {m_rsh[6:0], 1'b0};
                            m_rsh <= shifted_rsh;
                            if (shifted_rsh[7]) begin
`ifdef BYTE_FRAME_DEBUG
                                $display("IWM_FLUX: BYTE_COMPLETE_ASYNC data=%02h pos=%0d", shifted_rsh, DISK_BIT_POSITION);
`endif
`ifdef SIMULATION
                                    if (prolog_last1 == 8'hD5 && shifted_rsh != 8'hAA) begin
                                        $display("IWM_PROLOG_BAD: d5 %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                 shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                         rw_state, immediate_q6, immediate_q7, debug_cycle);
                                    end
                                    if (prolog_last2 == 8'hD5 && prolog_last1 == 8'hAA) begin
                                        if (shifted_rsh == 8'h96 || shifted_rsh == 8'hAD) begin
                                            $display("IWM_PROLOG_OK: d5 aa %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                     shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                                     rw_state, immediate_q6, immediate_q7, debug_cycle);
                                        end else begin
                                            $display("IWM_PROLOG_MISS: d5 aa %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                     shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                                     rw_state, immediate_q6, immediate_q7, debug_cycle);
                                        end
                                    end
                                    prolog_last2 <= prolog_last1;
                                    prolog_last1 <= shifted_rsh;
                                    if (dbg_prolog_window) begin
                                        $display("IWM_BYTE_DBG pos=%0d data=%02h win=%0d frac=%0d state=%0d q6=%0d q7=%0d cyc=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, window_counter, full_window_frac,
                                                 rw_state, immediate_q6, immediate_q7, debug_cycle);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd7130) && (DISK_BIT_POSITION <= 17'd7190) &&
                                        (shifted_rsh == 8'h9A)) begin
                                        $display("IWM_9A_COMPLETE(E0): pos=%0d data=%02h rsh=%02h win=%0d frac=%0d state=%0d async_pending=%0d m_data=%02h m_data_read=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, window_counter, full_window_frac,
                                                 rw_state, async_update_pending, m_data, m_data_read);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd13280) && (DISK_BIT_POSITION <= 17'd13450)) begin
                                        $display("IWM_BC_WIN(E0): pos=%0d data=%02h rsh=%02h m_data=%02h m_data_read=%0d data_ready=%0d eff=%02h bc=%0d async_pending=%0d q6=%0d q7=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, m_data, m_data_read,
                                                 data_ready, effective_data, byte_completing, async_update_pending,
                                                 immediate_q6, immediate_q7);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd7100) && (DISK_BIT_POSITION <= 17'd7200)) begin
                                        $display("IWM_DEC_BYTE: cycle=%0d pos=%0d data=%02h byte_idx=%0d win=%0d frac=%0d state=%0d m_data=%02h m_data_read=%0d",
                                                 debug_cycle, DISK_BIT_POSITION, shifted_rsh, DISK_BIT_POSITION[16:3],
                                                 window_counter, full_window_frac, rw_state, m_data, m_data_read);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd29500) && (DISK_BIT_POSITION <= 17'd29850) &&
                                        (dbg_bp_count < 16'd200)) begin
                                        dbg_bp_count <= dbg_bp_count + 1'd1;
                                        $display("IWM_BC_WIN(P): pos=%0d data=%02h rsh=%02h win=%0d frac=%0d state=%0d flux_edge=%0d flux_seen=%0d m_data=%02h m_data_read=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, window_counter, full_window_frac,
                                                 rw_state, flux_edge, flux_seen, m_data, m_data_read);
                                    end
                                    byte_counter <= byte_counter + 1;
                                    if (!m_data_read && m_data[7] && !rd_consumes_byte) begin
                                        bytes_lost_counter <= bytes_lost_counter + 1;
`ifdef IWM_BYTELOG
                                        $display("IWM_FLUX: *** BYTE LOST #%0d *** OVERRUN overwriting unread m_data=%02h with %02h (completed=%0d read=%0d) @cycle=%0d",
                                                 bytes_lost_counter + 1, m_data, shifted_rsh, byte_counter + 1, bytes_read_counter, debug_cycle);
`endif
                                    end
                                    // Debug near divergence point - compare internal state
                                    if (DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230) begin
                                        $display("IWM_DIV_E0: byte=%0d pos=%0d data=%02h win=%0d frac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                                 byte_counter + 1, DISK_BIT_POSITION, shifted_rsh, window_counter, full_window_frac, rw_state, flux_edge, flux_seen);
                                    end
`endif
                                    // Always store the completing byte in m_data
                                    // NOTE: Previously tried MAME-style async protection (don't overwrite unread bytes)
                                    // but this caused D5 AA AD prologue bytes to be dropped, breaking sector framing.
                                    // The original 9A overwrite issue needs a different solution - see doc/woz_flux_debugging_current.md
                                    m_data <= shifted_rsh;
                                    m_data_gen <= m_data_gen + 32'd1;
                                    m_data_read <= (rd_consumes_byte && (rd_data_latched == shifted_rsh)) ? 1'b1 : 1'b0;
                                    async_update_pending <= 1'b0;
                                    if (latch_mode) begin
                                        latch_hold_cnt <= 4'd8;
`ifdef SIMULATION
                                        if ((DISK_BIT_POSITION >= 17'd7135) && (DISK_BIT_POSITION <= 17'd7205)) begin
                                            $display("IWM_LATCH_START: pos=%0d data=%02h",
                                                     DISK_BIT_POSITION, shifted_rsh);
                                        end
`endif
                                    end
`ifdef SIMULATION
                                    if (byte_counter < 50) begin
                                        $display("IWM_FLUX: BYTE_COMPLETE(E0) #%0d assigning m_data<=%02h (prev=%02h rsh=%02h)",
                                                 byte_counter, shifted_rsh, m_data, m_rsh);
                                    end
`endif
`ifdef DEBUG_BYTE_OFFSET
                                    // Track first prologue after motor start
                                    if (MOTOR_SPINNING && !dbg_motor_started) begin
                                        dbg_motor_started <= 1'b1;
                                        dbg_first_byte_count <= 32'd0;
                                        dbg_first_d5_found <= 1'b0;
                                        dbg_history_idx <= 4'd0;
                                        $display("BYTE_OFFSET: Motor started spinning, tracking bytes...");
                                    end
                                    if (dbg_motor_started && !dbg_first_d5_found) begin
                                        dbg_first_byte_count <= dbg_first_byte_count + 1;
                                        dbg_byte_history[dbg_history_idx] <= shifted_rsh;
                                        dbg_history_idx <= dbg_history_idx + 1;
                                        // Log first 20 bytes after motor start
                                        if (dbg_first_byte_count < 20) begin
                                            $display("BYTE_OFFSET: byte[%0d] = 0x%02X at pos=%0d cycle=%0d",
                                                     dbg_first_byte_count, shifted_rsh, DISK_BIT_POSITION, debug_cycle);
                                        end
                                        // Track first D5 (non-sync byte)
                                        if (shifted_rsh == 8'hD5) begin
                                            dbg_first_d5_found <= 1'b1;
                                            dbg_first_d5_position <= DISK_BIT_POSITION;
                                            dbg_first_d5_cycle <= debug_cycle;
                                            $display("BYTE_OFFSET: *** FIRST D5 FOUND *** at byte[%0d] pos=%0d cycle=%0d",
                                                     dbg_first_byte_count, DISK_BIT_POSITION, debug_cycle);
                                            $display("BYTE_OFFSET: Last 8 bytes before D5: %02X %02X %02X %02X %02X %02X %02X %02X",
                                                     dbg_byte_history[(dbg_history_idx-8)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-7)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-6)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-5)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-4)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-3)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-2)&4'hF],
                                                     dbg_byte_history[(dbg_history_idx-1)&4'hF]);
                                        end
                                    end
                                    // Reset tracking when motor stops
                                    if (!MOTOR_SPINNING && dbg_motor_started) begin
                                        dbg_motor_started <= 1'b0;
                                    end
`endif
                                    clear_rsh_pending <= 1'b1;
                            end
                            load_full_window();
                        end else begin
                            window_counter <= window_counter - 1'd1;
                        end
                    end

                    SR_WINDOW_EDGE_1: begin
                        if (window_counter == 6'd1) begin
`ifdef BYTE_FRAME_DEBUG
                            $display("IWM_FLUX: SHIFT bit=1 rsh=%02h->%02h state=EDGE_1 endw=%0d",
                                     m_rsh, {m_rsh[6:0], 1'b1}, window_counter);
`endif
`ifdef SIMULATION
                            if (DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230) begin
                                $display("IWM_SHIFT1 pos=%0d cyc=%0d rsh=%02h->%02h win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                         DISK_BIT_POSITION, debug_cycle, m_rsh, {m_rsh[6:0], 1'b1},
                                         window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen);
                            end
                            if (dbg_prolog_window) begin
                                $display("IWM_SHIFT1_DBG pos=%0d cyc=%0d rsh=%02h->%02h win=%0d frac=%0d hfrac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                         DISK_BIT_POSITION, debug_cycle, m_rsh, {m_rsh[6:0], 1'b1},
                                         window_counter, full_window_frac, half_window_frac,
                                         rw_state, flux_edge, flux_seen);
                            end
`endif
                            shifted_rsh = {m_rsh[6:0], 1'b1};
                            m_rsh <= shifted_rsh;
                            if (shifted_rsh[7]) begin
`ifdef BYTE_FRAME_DEBUG
                                $display("IWM_FLUX: BYTE_COMPLETE_ASYNC data=%02h pos=%0d", shifted_rsh, DISK_BIT_POSITION);
`endif
`ifdef SIMULATION
                                    if (prolog_last1 == 8'hD5 && shifted_rsh != 8'hAA) begin
                                        $display("IWM_PROLOG_BAD: d5 %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                 shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                         rw_state, immediate_q6, immediate_q7, debug_cycle);
                                    end
                                    if (prolog_last2 == 8'hD5 && prolog_last1 == 8'hAA) begin
                                        if (shifted_rsh == 8'h96 || shifted_rsh == 8'hAD) begin
                                            $display("IWM_PROLOG_OK: d5 aa %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                     shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                                     rw_state, immediate_q6, immediate_q7, debug_cycle);
                                        end else begin
                                            $display("IWM_PROLOG_MISS: d5 aa %02h pos=%0d win=%0d frac=%0d state=%0d q6=%0d q7=%0d cycle=%0d",
                                                     shifted_rsh, DISK_BIT_POSITION, window_counter, full_window_frac,
                                                     rw_state, immediate_q6, immediate_q7, debug_cycle);
                                        end
                                    end
                                    prolog_last2 <= prolog_last1;
                                    prolog_last1 <= shifted_rsh;
                                    if (dbg_prolog_window) begin
                                        $display("IWM_BYTE_DBG pos=%0d data=%02h win=%0d frac=%0d state=%0d q6=%0d q7=%0d cyc=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, window_counter, full_window_frac,
                                                 rw_state, immediate_q6, immediate_q7, debug_cycle);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd7130) && (DISK_BIT_POSITION <= 17'd7190) &&
                                        (shifted_rsh == 8'h9A)) begin
                                        $display("IWM_9A_COMPLETE(E1): pos=%0d data=%02h rsh=%02h win=%0d frac=%0d state=%0d async_pending=%0d m_data=%02h m_data_read=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, window_counter, full_window_frac,
                                                 rw_state, async_update_pending, m_data, m_data_read);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd13280) && (DISK_BIT_POSITION <= 17'd13450)) begin
                                        $display("IWM_BC_WIN(E1): pos=%0d data=%02h rsh=%02h m_data=%02h m_data_read=%0d data_ready=%0d eff=%02h bc=%0d async_pending=%0d q6=%0d q7=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, m_data, m_data_read,
                                                 data_ready, effective_data, byte_completing, async_update_pending,
                                                 immediate_q6, immediate_q7);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd7100) && (DISK_BIT_POSITION <= 17'd7200)) begin
                                        $display("IWM_DEC_BYTE: cycle=%0d pos=%0d data=%02h byte_idx=%0d win=%0d frac=%0d state=%0d m_data=%02h m_data_read=%0d",
                                                 debug_cycle, DISK_BIT_POSITION, shifted_rsh, DISK_BIT_POSITION[16:3],
                                                 window_counter, full_window_frac, rw_state, m_data, m_data_read);
                                    end
                                    if ((DISK_BIT_POSITION >= 17'd29500) && (DISK_BIT_POSITION <= 17'd29850) &&
                                        (dbg_bp_count < 16'd200)) begin
                                        dbg_bp_count <= dbg_bp_count + 1'd1;
                                        $display("IWM_BC_WIN(P): pos=%0d data=%02h rsh=%02h win=%0d frac=%0d state=%0d flux_edge=%0d flux_seen=%0d m_data=%02h m_data_read=%0d",
                                                 DISK_BIT_POSITION, shifted_rsh, m_rsh, window_counter, full_window_frac,
                                                 rw_state, flux_edge, flux_seen, m_data, m_data_read);
                                    end
                                    byte_counter <= byte_counter + 1;
                                    if (!m_data_read && m_data[7] && !rd_consumes_byte) begin
                                        bytes_lost_counter <= bytes_lost_counter + 1;
`ifdef IWM_BYTELOG
                                        $display("IWM_FLUX: *** BYTE LOST #%0d *** OVERRUN overwriting unread m_data=%02h with %02h (completed=%0d read=%0d) @cycle=%0d",
                                                 bytes_lost_counter + 1, m_data, shifted_rsh, byte_counter + 1, bytes_read_counter, debug_cycle);
`endif
                                    end
                                    // Debug near divergence point - compare internal state
                                    if (DISK_BIT_POSITION >= 17'd70190 && DISK_BIT_POSITION <= 17'd70230) begin
                                        $display("IWM_DIV_E1: byte=%0d pos=%0d data=%02h win=%0d frac=%0d state=%0d flux_edge=%0d flux_seen=%0d",
                                                 byte_counter + 1, DISK_BIT_POSITION, shifted_rsh, window_counter, full_window_frac, rw_state, flux_edge, flux_seen);
                                    end
`endif
                                    // Always store the completing byte in m_data (reverted from async protection)
                                    m_data <= shifted_rsh;
                                    m_data_gen <= m_data_gen + 32'd1;
                                    m_data_read <= (rd_consumes_byte && (rd_data_latched == shifted_rsh)) ? 1'b1 : 1'b0;
                                    async_update_pending <= 1'b0;
                                    if (latch_mode) begin
                                        latch_hold_cnt <= 4'd8;
`ifdef SIMULATION
                                        if ((DISK_BIT_POSITION >= 17'd7135) && (DISK_BIT_POSITION <= 17'd7205)) begin
                                            $display("IWM_LATCH_START: pos=%0d data=%02h",
                                                     DISK_BIT_POSITION, shifted_rsh);
                                        end
`endif
                                    end
`ifdef SIMULATION
                                    if (byte_counter < 50) begin
                                        $display("IWM_FLUX: BYTE_COMPLETE(E1) #%0d assigning m_data<=%02h (prev=%02h rsh=%02h)",
                                                 byte_counter, shifted_rsh, m_data, m_rsh);
                                    end
`endif
`ifdef DEBUG_BYTE_OFFSET
                                    // Track first prologue after motor start (E1 path)
                                    if (MOTOR_SPINNING && !dbg_motor_started) begin
                                        dbg_motor_started <= 1'b1;
                                        dbg_first_byte_count <= 32'd0;
                                        dbg_first_d5_found <= 1'b0;
                                        dbg_history_idx <= 4'd0;
                                        $display("BYTE_OFFSET: Motor started spinning (E1), tracking bytes...");
                                    end
                                    if (dbg_motor_started && !dbg_first_d5_found) begin
                                        dbg_first_byte_count <= dbg_first_byte_count + 1;
                                        dbg_byte_history[dbg_history_idx] <= shifted_rsh;
                                        dbg_history_idx <= dbg_history_idx + 1;
                                        if (dbg_first_byte_count < 20) begin
                                            $display("BYTE_OFFSET: byte[%0d] = 0x%02X at pos=%0d cycle=%0d (E1)",
                                                     dbg_first_byte_count, shifted_rsh, DISK_BIT_POSITION, debug_cycle);
                                        end
                                        if (shifted_rsh == 8'hD5) begin
                                            dbg_first_d5_found <= 1'b1;
                                            dbg_first_d5_position <= DISK_BIT_POSITION;
                                            dbg_first_d5_cycle <= debug_cycle;
                                            $display("BYTE_OFFSET: *** FIRST D5 FOUND (E1) *** at byte[%0d] pos=%0d cycle=%0d",
                                                     dbg_first_byte_count, DISK_BIT_POSITION, debug_cycle);
                                        end
                                    end
`endif
                                    clear_rsh_pending <= 1'b1;
                            end
                            rw_state <= SR_WINDOW_EDGE_0;
                            load_full_window();
                        end else begin
                            window_counter <= window_counter - 1'd1;
                        end
                    end

                    default: begin
                        rw_state <= S_IDLE;
                    end
                endcase
            end

            // Reset state when motor stops or disk removed
            if (!MOTOR_SPINNING || !DISK_READY) begin
`ifdef SIMULATION
                // Log mid-boot state resets - these could cause byte boundary drift!
                if (byte_counter > 0 && prev_sm_active && (rw_state != S_IDLE || full_window_frac != 0)) begin
                    $display("IWM_FLUX: *** STATE_RESET *** byte_cnt=%0d pos=%0d rsh=%02h state=%0d->IDLE win=%0d frac=%0d->0 spin=%0d ready=%0d",
                             byte_counter, DISK_BIT_POSITION, m_rsh, rw_state, window_counter, full_window_frac, MOTOR_SPINNING, DISK_READY);
                end
`endif
                rw_state <= S_IDLE;
                window_counter <= 6'd0;
                full_window_frac <= 10'd0;
                half_window_frac <= 10'd0;
                flux_seen <= 1'b0;
                async_update_pending <= 1'b0;
                latch_hold_cnt <= 4'd0;
            end

            prev_sm_active <= MOTOR_SPINNING && DISK_READY;

            // Track CEN (PHI2) edge; the CPU latches read data near the end of PHI2-high.
            // IMPORTANT: Do not clear/acknowledge the data register during PHI2-high,
            // or the CPU can sample the post-clear value (e.g., 0x55 instead of 0xD5).
            prev_cen <= CEN;

            // Start of a CPU access cycle (PHI2-high). Capture Q6, Q7 and whether a valid byte is present.
            // IMPORTANT: Capture m_data_gen at access START so async_clear targets the correct byte.
            // If captured at access END, a byte completing mid-cycle would increment gen, and
            // async_clear would incorrectly target the NEW byte instead of the one actually read.
            // FIX9: Async deadline check now happens continuously (above), so no check needed here.
            // This matches MAME's sync() behavior where deadline is checked after processing
            // all time forward, not specifically at the moment of CPU access.
            if ((RD || WR) && CEN && !access_in_progress) begin
                access_in_progress <= 1'b1;
                access_q7_latched <= immediate_q7;
                access_q6_latched <= immediate_q6;
                access_data_valid <= data_ready;
                access_gen_latched <= m_data_gen;
            end

            // MAME behavior: In active mode, a write to Q6=1,Q7=1 with odd offset is a DATA write
            // (used for write-mode shifting / SmartPort handshakes), not a mode register write.
            // iwm_woz.v gates mode writes on !iwm_active; handle the active case here.
            if (WR && CEN && immediate_q7 && immediate_q6 && ADDR[0] && MOTOR_ACTIVE && !smartport_mode) begin
                m_data <= DATA_IN;
                m_data_gen <= m_data_gen + 32'd1;
                if (SW_MODE[0]) begin
                    m_whd <= m_whd & 8'h7f;
                end
            end

            // Start of a CPU read cycle (PHI2-high). Track what the CPU will see.
            // Capture data throughout PHI2-high so same-cycle byte completes are acknowledged.
            if (RD && CEN) begin
                if (!rd_in_progress) begin
                    rd_in_progress <= 1'b1;
                    rd_was_data_reg <= rd_is_data_reg;
                    rd_latched_valid <= 1'b0;
                    rd_from_completion <= 1'b0;  // FIX: Start fresh each cycle
                    rd_data_latched <= data_out_mux;
                    if (data_out_mux[7]) begin
                        rd_latched_valid <= 1'b1;
                        // FIX: If the initial latch is from a completing byte, mark it
                        rd_from_completion <= byte_completing;
                    end
                end else if (rd_was_data_reg && data_out_mux[7]) begin
                    // Latch the most recent valid data byte seen during this cycle.
                    rd_data_latched <= data_out_mux;
                    rd_latched_valid <= 1'b1;
                    // FIX: If this update is from a completing byte, mark it
                    rd_from_completion <= byte_completing;
                end
            end

            // End of CPU bus cycle (PHI2 falling). Now it is safe to acknowledge the read.
            if (prev_cen && !CEN) begin
                // MAME async_update scheduling: any IWM access in read mode (Q7=0) while a valid byte
                // is present schedules m_data to clear 28 cycles (2µs) after this access.
                // FIX7: MAME reschedules on EVERY read (iwm.cpp line 314 has no pending check).
                // This keeps pushing the deadline forward while CPU is actively polling.
                // The deadline only fires when CPU stops reading for >2µs.
                if (access_in_progress) begin
                    // FIX: Only schedule async clear on DATA register reads (Q6=0, Q7=0),
                    // not STATUS reads (Q6=1, Q7=0). STATUS reads don't consume the data byte,
                    // so scheduling async clear on them causes premature clearing of unread bytes.
                    if (MOTOR_ACTIVE && is_async && access_data_valid && !access_q7_latched && !access_q6_latched) begin
                        async_update_pending <= 1'b1;
                        // Deadline = current wall-clock time + 28 cycles (2µs)
                        async_update_deadline <= async_tick_14m + ASYNC_CLEAR_DELAY_14M;
                        // FIX: Use gen captured at access START, not current gen which may have
                        // been incremented by a byte completing during this access cycle.
                        async_clear_gen <= access_gen_latched;
`ifdef SIMULATION
                        if ((DISK_BIT_POSITION >= 17'd7100) && (DISK_BIT_POSITION <= 17'd7200)) begin
                            $display("IWM_ASYNC_SCHED: pos=%0d tick=%0d deadline=%0d data=%02h q6=%0d q7=%0d",
                                     DISK_BIT_POSITION, async_tick_14m, async_tick_14m + ASYNC_CLEAR_DELAY_14M,
                                     m_data, access_q6_latched, access_q7_latched);
                        end
`endif
                    end
                end
                if (rd_in_progress) begin
                    if (rd_was_data_reg) begin
                        // Set m_data_read when CPU successfully reads the data register
                        if (rd_ack_take) begin
                            m_data_read <= 1'b1;
                            if (latch_hold_active) begin
                                latch_hold_cnt <= 4'd0; // Stop latch hold once CPU has consumed the byte.
                            end
                        end
`ifdef SIMULATION
                        if (MOTOR_ACTIVE && rd_ack_take) begin
                            bytes_read_counter <= bytes_read_counter + 1;
                        end
                        if (MOTOR_ACTIVE) begin
                            $display("IWM_READ_ACK: cycle=%0d pos=%0d latched=%02h m_data=%02h bc=%0d bc_data=%02h rd_valid=%0d ack=%0d was_data=%0d",
                                     debug_cycle, DISK_BIT_POSITION, rd_data_latched, m_data, byte_completing,
                                     byte_complete_data, rd_latched_valid, rd_ack_take, rd_was_data_reg);
                        end
`endif
                    end
                end
                rd_in_progress <= 1'b0;
                rd_latched_valid <= 1'b0;
                rd_from_completion <= 1'b0;
                access_in_progress <= 1'b0;
            end

            // Abort tracking if RD deasserts early (shouldn't normally happen, but keeps state sane).
            if (!RD) begin
                rd_in_progress <= 1'b0;
                rd_from_completion <= 1'b0;
            end
            if (!(RD || WR)) begin
                access_in_progress <= 1'b0;
            end

            // If data becomes ready during a bus cycle, latch that fact for async clear scheduling.
            if (access_in_progress && CEN && data_ready) begin
                access_data_valid <= 1'b1;
            end

`ifdef SIMULATION
            // Track m_data changes - this runs at end of clock cycle after all assignments
            // Using non-blocking assignment for prev_m_data means we compare current m_data
            // against previous clock cycle's value
            if (m_data != prev_m_data) begin
                m_data_change_count <= m_data_change_count + 1;
                if (m_data_change_count < 500) begin
                    $display("IWM_FLUX: M_DATA_CHANGE #%0d: %02h -> %02h @cycle=%0d pos=%0d spin=%0d ready=%0d state=%0d",
                             m_data_change_count, prev_m_data, m_data, debug_cycle, DISK_BIT_POSITION,
                             MOTOR_SPINNING, DISK_READY, rw_state);
                end
            end
            prev_m_data <= m_data;
`endif
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
    // Bit 5: motor_active (MAME: m_status bit5 reflects IWM active state, not disk presence)
    // Bits 4-0: mode register
    // Note: data_ready is NOT in the status register - it's only relevant for
    //       determining when to read the DATA register (Q6=0, Q7=0)
    wire motor_status_bit = MOTOR_ACTIVE;
    wire [7:0] status_reg = {SENSE_BIT, 1'b0, motor_status_bit, SW_MODE[4:0]};

    // SmartPort/C-Bus mode detection (MAME-style): mode bit3 selects disk bit-cell width,
    // and mode bit1 is used for async/SmartPort handshakes. In this mode we do not emulate
    // a SmartPort device; we must avoid hanging the ROM in `smartdrvr.asm` polling loops.
    wire smartport_mode = (!SW_MODE[3]) && SW_MODE[1];

    // Write handshake register (MAME: m_whd, initialized to 0xBF). In SmartPort mode,
    // always report "ready" (bit7=1) so `ASL $C08C,X` polling loops can progress.
    wire [7:0] handshake_reg = smartport_mode ? 8'h80 : m_whd;

    // Immediate Q6/Q7 values for current access
    // If current access is to Q6/Q7 switch, use ADDR[0] for that bit
    // Otherwise use the latched value from SW_Q6/SW_Q7
    wire access_q6 = (ADDR[3:1] == 3'b110);
    wire access_q7 = (ADDR[3:1] == 3'b111);
    wire immediate_q6 = access_q6 ? ADDR[0] : SW_Q6;
    wire immediate_q7 = access_q7 ? ADDR[0] : SW_Q7;
    assign rd_is_data_reg = (immediate_q7 == 1'b0) && (immediate_q6 == 1'b0);

    // Combinatorial bypass for same-cycle read:
    // if a byte completes during the read, return it immediately.

    reg [7:0] data_out_mux;
    always @(*) begin
        case ({immediate_q7, immediate_q6})
            // Data register should reflect actual disk motion, not just the motor command.
            2'b00: data_out_mux = (MOTOR_SPINNING && DISK_READY) ? effective_data : 8'hFF;
            2'b01: data_out_mux = status_reg;
            2'b10: data_out_mux = handshake_reg;
            2'b11: data_out_mux = 8'hFF;
        endcase
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    // Drive live data so reads can observe bytes that complete mid-PHI2.
    assign DATA_OUT     = data_out_mux;
    assign FLUX_WRITE   = 1'b0;  // TODO: implement write support
    assign DEBUG_RSH    = m_rsh;
    assign DEBUG_STATE  = rw_state;
    assign DEBUG_BYTE_VALID = new_byte_dbg;

`ifdef SIMULATION
    // Debug: log register reads (only on CEN/PH2 to log once per CPU access)
    reg [31:0] debug_win_count;
    always @(posedge CLK_14M) begin
            if (RD && CEN) begin
            case ({immediate_q7, immediate_q6})
                2'b00: $display("IWM_FLUX: READ DATA @%01h -> %02h cycle=%0d pos=%0d (active=%0d spin=%0d rsh=%02h data=%02h bc=%0d dr=%0d q6=%0d q7=%0d async_pending=%0d)",
                               ADDR, data_out_mux, debug_cycle, DISK_BIT_POSITION, MOTOR_ACTIVE, MOTOR_SPINNING, m_rsh, m_data, byte_completing, DISK_READY, SW_Q6, SW_Q7, async_update_pending);
                2'b01: $display("IWM_FLUX: READ STATUS @%01h -> %02h cycle=%0d pos=%0d (sense=%0d m_reg=%01h latched=%01h sel=%0d phases=%04b is_35=%0d motor_active=%0d mounted=%0d data_ready=%0d m_data=%02h m_data_read=%0d)",
                               ADDR, data_out_mux, debug_cycle, DISK_BIT_POSITION, SENSE_BIT,
                               {LATCHED_SENSE_REG[1], LATCHED_SENSE_REG[0], DISKREG_SEL, LATCHED_SENSE_REG[2]},
                               LATCHED_SENSE_REG, DISKREG_SEL, SW_PHASES, IS_35_INCH, MOTOR_ACTIVE, DISK_MOUNTED,
                               data_ready, m_data, m_data_read);
                2'b10: $display("IWM_FLUX: READ HANDSHAKE @%01h -> %02h", ADDR, data_out_mux);
                2'b11: $display("IWM_FLUX: READ @%01h -> %02h (q7=q6=1)", ADDR, data_out_mux);
            endcase
            if ((DISK_BIT_POSITION >= 17'd7100) && (DISK_BIT_POSITION <= 17'd7200)) begin
                $display("IWM_READ_WIN: cycle=%0d pos=%0d dout=%02h eff=%02h m_data=%02h m_data_read=%0d data_ready=%0d rsh=%02h bc=%0d dr=%0d q6=%0d q7=%0d async_pending=%0d latch=%0d spin=%0d rd_valid=%0d",
                         debug_cycle, DISK_BIT_POSITION, data_out_mux, effective_data, m_data, m_data_read, data_ready,
                         m_rsh, byte_completing, DISK_READY, immediate_q6, immediate_q7, async_update_pending,
                         latch_hold_cnt, MOTOR_SPINNING, rd_latched_valid);
            end
            if ((DISK_BIT_POSITION >= 17'd13280) && (DISK_BIT_POSITION <= 17'd13450)) begin
                $display("IWM_READ_WIN2: cycle=%0d pos=%0d dout=%02h eff=%02h m_data=%02h m_data_read=%0d data_ready=%0d rsh=%02h bc=%0d dr=%0d q6=%0d q7=%0d async_pending=%0d spin=%0d rd_data=%0d",
                         debug_cycle, DISK_BIT_POSITION, data_out_mux, effective_data, m_data, m_data_read, data_ready,
                         m_rsh, byte_completing, DISK_READY, immediate_q6, immediate_q7, async_update_pending,
                         MOTOR_SPINNING, rd_is_data_reg);
            end
        end

        // Periodic statistics - every 10M cycles (~0.7 seconds)
        if (debug_cycle[23:0] == 24'h0 && debug_cycle > 0 && MOTOR_ACTIVE) begin
            $display("IWM_FLUX: *** STATS @cycle=%0d *** bytes_completed=%0d bytes_read=%0d bytes_lost=%0d loss_rate=%0d%%",
                     debug_cycle, byte_counter, bytes_read_counter, bytes_lost_counter,
                     (byte_counter > 0) ? (bytes_lost_counter * 100 / byte_counter) : 0);
        end

        // Focused window logging around suspected divergence position.
        if (MOTOR_ACTIVE && DISK_READY &&
            (DISK_BIT_POSITION >= 17'd27460) && (DISK_BIT_POSITION <= 17'd27490) &&
            debug_win_count < 500) begin
            $display("IWM_FLUX_WIN pos=%0d flux=%0d state=%0d win=%0d rsh=%02h data=%02h bc=%0d async_pending=%0d",
                     DISK_BIT_POSITION, FLUX_TRANSITION, rw_state, window_counter,
                     m_rsh, m_data, byte_completing, async_update_pending);
            debug_win_count <= debug_win_count + 1;
        end
    end
`endif

    //=========================================================================
    // Sector Read Tracking (for debug - tracks byte stream, not CPU reads)
    //=========================================================================
    // This state machine watches the byte stream (m_data) and tracks sector reads.
    // 3.5" GCR format:
    //   Address field: D5 AA 96 <track> <sector> <side> <format> <checksum> DE AA
    //   Data field:    D5 AA AD <12 tag> <512 data> <4 checksum> DE AA
    // Note: This tracks raw bytes from the disk, independent of CPU read timing.

`ifdef IWM_SECTOR_TRACE
    // GCR 6-2 decode function for 3.5" disk address fields
    // Input: raw GCR byte (0x80-0xFF), Output: decoded 6-bit value (0x00-0x3F, or 0x80 for invalid)
    // Table from Clemens emulator (clem_disk.c)
    function [7:0] gcr_6_2_decode;
        input [7:0] gcr_byte;
        begin
            case (gcr_byte)
                // 0x90-0x97
                8'h96: gcr_6_2_decode = 8'h00;
                8'h97: gcr_6_2_decode = 8'h01;
                // 0x98-0x9F
                8'h9A: gcr_6_2_decode = 8'h02;
                8'h9B: gcr_6_2_decode = 8'h03;
                8'h9D: gcr_6_2_decode = 8'h04;
                8'h9E: gcr_6_2_decode = 8'h05;
                8'h9F: gcr_6_2_decode = 8'h06;
                // 0xA0-0xA7
                8'hA6: gcr_6_2_decode = 8'h07;
                8'hA7: gcr_6_2_decode = 8'h08;
                // 0xA8-0xAF
                8'hAB: gcr_6_2_decode = 8'h09;
                8'hAC: gcr_6_2_decode = 8'h0A;
                8'hAD: gcr_6_2_decode = 8'h0B;
                8'hAE: gcr_6_2_decode = 8'h0C;
                8'hAF: gcr_6_2_decode = 8'h0D;
                // 0xB0-0xB7
                8'hB2: gcr_6_2_decode = 8'h0E;
                8'hB3: gcr_6_2_decode = 8'h0F;
                8'hB4: gcr_6_2_decode = 8'h10;
                8'hB5: gcr_6_2_decode = 8'h11;
                8'hB6: gcr_6_2_decode = 8'h12;
                8'hB7: gcr_6_2_decode = 8'h13;
                // 0xB8-0xBF
                8'hB9: gcr_6_2_decode = 8'h14;
                8'hBA: gcr_6_2_decode = 8'h15;
                8'hBB: gcr_6_2_decode = 8'h16;
                8'hBC: gcr_6_2_decode = 8'h17;
                8'hBD: gcr_6_2_decode = 8'h18;
                8'hBE: gcr_6_2_decode = 8'h19;
                8'hBF: gcr_6_2_decode = 8'h1A;
                // 0xC8-0xCF
                8'hCB: gcr_6_2_decode = 8'h1B;
                8'hCD: gcr_6_2_decode = 8'h1C;
                8'hCE: gcr_6_2_decode = 8'h1D;
                8'hCF: gcr_6_2_decode = 8'h1E;
                // 0xD0-0xD7
                8'hD3: gcr_6_2_decode = 8'h1F;
                8'hD6: gcr_6_2_decode = 8'h20;
                8'hD7: gcr_6_2_decode = 8'h21;
                // 0xD8-0xDF
                8'hD9: gcr_6_2_decode = 8'h22;
                8'hDA: gcr_6_2_decode = 8'h23;
                8'hDB: gcr_6_2_decode = 8'h24;
                8'hDC: gcr_6_2_decode = 8'h25;
                8'hDD: gcr_6_2_decode = 8'h26;
                8'hDE: gcr_6_2_decode = 8'h27;
                8'hDF: gcr_6_2_decode = 8'h28;
                // 0xE0-0xE7
                8'hE5: gcr_6_2_decode = 8'h29;
                8'hE6: gcr_6_2_decode = 8'h2A;
                8'hE7: gcr_6_2_decode = 8'h2B;
                // 0xE8-0xEF
                8'hE9: gcr_6_2_decode = 8'h2C;
                8'hEA: gcr_6_2_decode = 8'h2D;
                8'hEB: gcr_6_2_decode = 8'h2E;
                8'hEC: gcr_6_2_decode = 8'h2F;
                8'hED: gcr_6_2_decode = 8'h30;
                8'hEE: gcr_6_2_decode = 8'h31;
                8'hEF: gcr_6_2_decode = 8'h32;
                // 0xF0-0xF7
                8'hF2: gcr_6_2_decode = 8'h33;
                8'hF3: gcr_6_2_decode = 8'h34;
                8'hF4: gcr_6_2_decode = 8'h35;
                8'hF5: gcr_6_2_decode = 8'h36;
                8'hF6: gcr_6_2_decode = 8'h37;
                8'hF7: gcr_6_2_decode = 8'h38;
                // 0xF8-0xFF
                8'hF9: gcr_6_2_decode = 8'h39;
                8'hFA: gcr_6_2_decode = 8'h3A;
                8'hFB: gcr_6_2_decode = 8'h3B;
                8'hFC: gcr_6_2_decode = 8'h3C;
                8'hFD: gcr_6_2_decode = 8'h3D;
                8'hFE: gcr_6_2_decode = 8'h3E;
                8'hFF: gcr_6_2_decode = 8'h3F;
                default: gcr_6_2_decode = 8'h80;  // Invalid GCR byte
            endcase
        end
    endfunction

    // Sector tracking state machine
    localparam SEC_IDLE       = 4'd0;
    localparam SEC_WAIT_AA1   = 4'd1;  // Saw D5, waiting for first AA
    localparam SEC_WAIT_96    = 4'd2;  // Saw D5 AA, waiting for 96 (addr) or AD (data)
    localparam SEC_ADDR_TRACK = 4'd3;  // Reading address field: track byte
    localparam SEC_ADDR_SEC   = 4'd4;  // Reading address field: sector byte
    localparam SEC_ADDR_SIDE  = 4'd5;  // Reading address field: side byte
    localparam SEC_ADDR_FMT   = 4'd6;  // Reading address field: format byte
    localparam SEC_ADDR_CSUM  = 4'd7;  // Reading address field: checksum byte
    localparam SEC_DATA_TAG   = 4'd8;  // Reading data field: 12 tag bytes
    localparam SEC_DATA_READ  = 4'd9;  // Reading data field: 512 data bytes
    localparam SEC_DATA_CSUM  = 4'd10; // Reading data field: 4 checksum bytes

    reg [3:0]  sec_state;
    reg [7:0]  sec_track;         // Raw GCR byte
    reg [7:0]  sec_sector;        // Raw GCR byte
    reg [7:0]  sec_side;          // Raw GCR byte
    reg [7:0]  sec_format;        // Raw GCR byte
    reg [7:0]  sec_addr_csum;     // Raw checksum byte from address field
    reg [5:0]  sec_decoded_track; // Decoded 6-bit track value
    reg [5:0]  sec_decoded_sector;// Decoded 6-bit sector value
    reg [5:0]  sec_decoded_side;  // Decoded 6-bit side value
    reg [5:0]  sec_decoded_format;// Decoded 6-bit format value
    reg [5:0]  sec_running_xor;   // Running XOR of decoded values (should be 0 after all 5 bytes)
    reg [9:0]  sec_data_count;    // Counter for data bytes (0-511)
    reg [3:0]  sec_tag_count;     // Counter for tag bytes (0-11)
    reg [1:0]  sec_csum_count;    // Counter for checksum bytes (0-3)
    reg [31:0] sec_data_csum;     // Running checksum for data field (3 bytes used)
    reg [16:0] sec_start_pos;     // Position where sector started (for logging)

	    // Statistics
	    reg [15:0] sec_addr_ok_count;
	    reg [15:0] sec_addr_fail_count;
	    reg [15:0] sec_data_count_total;
	    reg [15:0] sec_prologue_miss_count;
	    reg [15:0] sec_log_count;
	    localparam [15:0] SEC_LOG_MAX = 16'd250;

    // Detect byte completion using m_rsh >= 0x80 signal (byte_completing is defined earlier)
    // Use edge detection since byte_completing is a level signal during the completion cycle.
    reg        prev_byte_completing;
    wire       new_byte = byte_completing && !prev_byte_completing;

	    always @(posedge CLK_14M or posedge RESET) begin
	        if (RESET) begin
            sec_state <= SEC_IDLE;
            sec_track <= 8'd0;
            sec_sector <= 8'd0;
            sec_side <= 8'd0;
            sec_format <= 8'd0;
            sec_addr_csum <= 8'd0;
            sec_decoded_track <= 6'd0;
            sec_decoded_sector <= 6'd0;
            sec_decoded_side <= 6'd0;
            sec_decoded_format <= 6'd0;
            sec_running_xor <= 6'd0;
            sec_data_count <= 10'd0;
            sec_tag_count <= 4'd0;
            sec_csum_count <= 2'd0;
            sec_data_csum <= 32'd0;
            sec_start_pos <= 17'd0;
	            sec_addr_ok_count <= 16'd0;
	            sec_addr_fail_count <= 16'd0;
	            sec_data_count_total <= 16'd0;
	            sec_prologue_miss_count <= 16'd0;
	            sec_log_count <= 16'd0;
	            prev_byte_completing <= 1'b0;
	        end else if (MOTOR_SPINNING && DISK_READY) begin
            prev_byte_completing <= byte_completing;

            // State machine triggered by new bytes
            // NOTE: When new_byte fires (byte_completing edge), the completed byte is in
            // byte_complete_data (combinational), NOT m_rsh (which has old value due to NBA)
            if (new_byte) begin
                case (sec_state)
                    SEC_IDLE: begin
                        if (byte_complete_data == 8'hD5) begin
                            sec_state <= SEC_WAIT_AA1;
                            sec_start_pos <= DISK_BIT_POSITION;
                        end
                    end

                    SEC_WAIT_AA1: begin
                        if (byte_complete_data == 8'hAA)
                            sec_state <= SEC_WAIT_96;
                        else if (byte_complete_data == 8'hD5)
                            sec_state <= SEC_WAIT_AA1;  // Stay, could be new marker
                        else
                            sec_state <= SEC_IDLE;
                    end

	                    SEC_WAIT_96: begin
	                        if (byte_complete_data == 8'h96) begin
	                            // Address field prologue complete
	                            sec_state <= SEC_ADDR_TRACK;
	                            if (sec_log_count < SEC_LOG_MAX) begin
	                                sec_log_count <= sec_log_count + 1'd1;
	                                $display("SECTOR: D5 AA 96 at pos=%0d (address prologue)", sec_start_pos);
	                            end
	                        end else if (byte_complete_data == 8'hAD) begin
	                            // Data field prologue
	                            sec_state <= SEC_DATA_TAG;
	                            sec_tag_count <= 4'd0;
	                            if (sec_log_count < SEC_LOG_MAX) begin
	                                sec_log_count <= sec_log_count + 1'd1;
	                                $display("SECTOR: D5 AA AD at pos=%0d (data prologue) for rawT=%02h rawS=%02h",
	                                         sec_start_pos, sec_track, sec_sector);
	                            end
	                        end else if (byte_complete_data == 8'hD5) begin
	                            sec_state <= SEC_WAIT_AA1;
	                            sec_start_pos <= DISK_BIT_POSITION;
	                        end else begin
	                            // Useful for diagnosing RDADDR hangs: we saw D5 AA but not the third mark.
	                            sec_prologue_miss_count <= sec_prologue_miss_count + 1'd1;
	                            if (sec_prologue_miss_count < 16'd50 && sec_log_count < SEC_LOG_MAX) begin
	                                sec_log_count <= sec_log_count + 1'd1;
	                                $display("SECTOR: PROLOGUE_MISS D5 AA %02h at pos=%0d (start_pos=%0d miss#=%0d)",
	                                         byte_complete_data, DISK_BIT_POSITION, sec_start_pos, sec_prologue_miss_count + 1'd1);
	                            end
	                            sec_state <= SEC_IDLE;
	                        end
	                    end

                    SEC_ADDR_TRACK: begin
                        sec_track <= byte_complete_data;
                        sec_decoded_track <= gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_running_xor <= gcr_6_2_decode(byte_complete_data)[5:0];  // Start running XOR
                        sec_state <= SEC_ADDR_SEC;
                    end

                    SEC_ADDR_SEC: begin
                        sec_sector <= byte_complete_data;
                        sec_decoded_sector <= gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_running_xor <= sec_running_xor ^ gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_state <= SEC_ADDR_SIDE;
                    end

                    SEC_ADDR_SIDE: begin
                        sec_side <= byte_complete_data;
                        sec_decoded_side <= gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_running_xor <= sec_running_xor ^ gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_state <= SEC_ADDR_FMT;
                    end

                    SEC_ADDR_FMT: begin
                        sec_format <= byte_complete_data;
                        sec_decoded_format <= gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_running_xor <= sec_running_xor ^ gcr_6_2_decode(byte_complete_data)[5:0];
                        sec_state <= SEC_ADDR_CSUM;
                    end

	                    SEC_ADDR_CSUM: begin
	                        sec_addr_csum <= byte_complete_data;
                        // ROM-style validation: XOR of all 5 decoded bytes must equal 0
                        // The checksum byte is chosen so that track^sector^side^format^checksum = 0
	                        if ((sec_running_xor ^ gcr_6_2_decode(byte_complete_data)[5:0]) == 6'd0) begin
	                            sec_addr_ok_count <= sec_addr_ok_count + 1;
	                            // Avoid logging every OK (too noisy); counts are enough.
	                        end else begin
	                            sec_addr_fail_count <= sec_addr_fail_count + 1;
	                            if (sec_log_count < SEC_LOG_MAX) begin
	                                sec_log_count <= sec_log_count + 1'd1;
	                                $display("SECTOR: ADDR FAIL T=%0d S=%0d side=%02h fmt=%02h xor=%02h pos=%0d raw=%02h %02h %02h %02h %02h",
	                                         sec_decoded_track, sec_decoded_sector, sec_decoded_side, sec_decoded_format,
	                                         sec_running_xor ^ gcr_6_2_decode(byte_complete_data)[5:0],
	                                         DISK_BIT_POSITION,
	                                         sec_track, sec_sector, sec_side, sec_format, byte_complete_data);
	                            end
	                        end
	                        sec_state <= SEC_IDLE;  // Wait for data field
	                    end

                    SEC_DATA_TAG: begin
                        sec_tag_count <= sec_tag_count + 1;
                        if (sec_tag_count == 4'd11) begin
                            sec_state <= SEC_DATA_READ;
                            sec_data_count <= 10'd0;
                            sec_data_csum <= 32'd0;
                        end
                    end

                    SEC_DATA_READ: begin
                        // Track data bytes (simplified - not computing full checksum)
                        sec_data_count <= sec_data_count + 1;
                        if (sec_data_count == 10'd511) begin
                            sec_state <= SEC_DATA_CSUM;
                            sec_csum_count <= 2'd0;
                            sec_data_count_total <= sec_data_count_total + 1;
                        end
                    end

	                    SEC_DATA_CSUM: begin
	                        sec_csum_count <= sec_csum_count + 1;
	                        if (sec_csum_count == 2'd3) begin
	                            if (sec_log_count < SEC_LOG_MAX) begin
	                                sec_log_count <= sec_log_count + 1'd1;
	                                $display("SECTOR: DATA COMPLETE rawT=%02h rawS=%02h (512 bytes read) pos=%0d",
	                                         sec_track, sec_sector, DISK_BIT_POSITION);
	                            end
	                            sec_state <= SEC_IDLE;
	                        end
	                    end

                    default: sec_state <= SEC_IDLE;
                endcase
            end

            // Reset if marker sequence broken
            if (!MOTOR_SPINNING || !DISK_READY) begin
                sec_state <= SEC_IDLE;
            end
        end
    end

	    // Periodic statistics for sector tracking
	    always @(posedge CLK_14M) begin
	        if (debug_cycle[24:0] == 25'h0 && debug_cycle > 0 && MOTOR_ACTIVE) begin
	            if (sec_log_count < SEC_LOG_MAX) begin
	                sec_log_count <= sec_log_count + 1'd1;
	                $display("SECTOR: *** STATS *** addr_ok=%0d addr_fail=%0d data_complete=%0d prologue_miss=%0d",
	                         sec_addr_ok_count, sec_addr_fail_count, sec_data_count_total, sec_prologue_miss_count);
	            end
	        end
	    end
`endif

endmodule
