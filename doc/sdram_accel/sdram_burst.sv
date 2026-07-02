//
// sdram_burst.sv -- PROTOTYPE burst-read SDRAM controller (doc-01 (b)). NOT the production
// controller; kept separate from rtl/sdram.sv so the shipping path and FPGA synth are untouched.
// Exercised + measured by vsim/sdram_tb/tb_burst.sv against doc/sdram_accel/sdram_sim_chip.sv.
//
// Difference vs rtl/sdram.sv: one ACTIVATE + one READ(burst=8, auto-precharge) returns the 8
// consecutive words of an aligned line as a 128-bit value, instead of a full row cycle per
// single word. Implements the MANDATORY doc-01 address remap (column = LOW address bits) so the
// hardware burst walks consecutive words.
//
// Channels (minimal, just what the cache/accelerator needs + what the TB needs to measure):
//   - write channel: single 16-bit word (NO_WRITE_BURST), like rtl/sdram.sv ch0
//   - read  channel: burst-8 -> 128-bit aligned line, like doc-01 ch1
//   - auto-refresh when idle
//
// Timing assumes the same MT48LC16M16A2 @ ~114.5MHz as rtl/sdram.sv (RASCAS=3, CAS=3).
//
module sdram_burst #(
    parameter [4:0] RASCAS_DELAY = 5'd3,
    parameter [4:0] CAS_LATENCY  = 5'd3
)(
    inout      [15:0] SDRAM_DQ,
    output reg [12:0] SDRAM_A,
    output            SDRAM_DQML,
    output            SDRAM_DQMH,
    output reg [1:0]  SDRAM_BA,
    output            SDRAM_nCS,
    output reg        SDRAM_nWE,
    output reg        SDRAM_nRAS,
    output reg        SDRAM_nCAS,
    output            SDRAM_CLK,
    output            SDRAM_CKE,

    input             init,
    input             clk,

    // write channel (single word)
    input      [24:1] addrw,
    input             wrlw,
    input             wrhw,
    input      [15:0] dinw,
    input             reqw,
    output reg        ackw,

    // read channel (burst-8 -> 128-bit line; addrr is the line base, low 3 bits ignored)
    input      [24:1] addrr,
    input             reqr,
    output reg        ackr,
    output reg [127:0] doutr
);
    assign SDRAM_nCS  = 0;
    assign SDRAM_CKE  = 1;
    assign SDRAM_CLK  = ~clk;                 // simple sim clock fwd (real core uses altddio)
    assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

    reg [15:0] dq_out; reg dq_oe;
    assign SDRAM_DQ = dq_oe ? dq_out : 16'bzzzz_zzzz_zzzz_zzzz;

    localparam BURST_CODE     = 3'b011;       // burst length 8 (reads)
    localparam NO_WRITE_BURST = 1'b1;         // single-location writes
    localparam [12:0] MODE = {3'b000, NO_WRITE_BURST, 2'b00, CAS_LATENCY[2:0], 1'b0, BURST_CODE};

    // ---- address remap (doc-01): column = LOW bits so a burst walks consecutive words ----
    //   bank = a[24:23], row = a[22:10] (13b), col = a[9:1] (9b)
    function automatic [1:0]  a_bank(input [24:1] a); a_bank = a[24:23];        endfunction
    function automatic [12:0] a_row (input [24:1] a); a_row  = a[22:10];        endfunction
    function automatic [8:0]  a_col (input [24:1] a); a_col  = a[9:1];          endfunction

    // round phases
    localparam [4:0] STATE_IDLE  = 5'd0;
    localparam [4:0] STATE_START = 5'd1;                      // ACTIVATE / AUTO_REFRESH
    localparam [4:0] STATE_CONT  = STATE_START + RASCAS_DELAY;// 4  READ/WRITE
    localparam [4:0] STATE_RDAT0 = STATE_CONT + CAS_LATENCY + 5'd1; // 8  first read beat
    localparam [4:0] STATE_RDATL = STATE_RDAT0 + 5'd7;        // 15 last burst beat
    localparam [4:0] STATE_LAST_RD = STATE_RDATL + 5'd3;      // 18 (tRP/tRC guard)
    localparam [4:0] STATE_LAST_WR = STATE_CONT  + 5'd4;      // 8  (tRC guard, like rtl/sdram.sv)

    localparam CMD_NOP          = 3'b111;
    localparam CMD_ACTIVE       = 3'b011;
    localparam CMD_READ         = 3'b101;
    localparam CMD_WRITE        = 3'b100;
    localparam CMD_PRECHARGE    = 3'b010;
    localparam CMD_AUTO_REFRESH = 3'b001;
    localparam CMD_LOAD_MODE    = 3'b000;

    localparam MODE_NORMAL = 2'b00, MODE_RESET = 2'b01, MODE_LDM = 2'b10, MODE_PRE = 2'b11;

    reg  [4:0] state = STATE_IDLE;
    reg        active = 0;     // 1 = ACTIVATE (vs refresh) this round
    reg        we = 0;         // 1 = write round, 0 = read round (when active)
    reg        is_read = 0;    // current active round is a burst read
    reg [24:1] cur = 0;        // latched address for this round
    reg [15:0] wdata = 0;
    reg  [1:0] wdqm = 0;
    reg        serving_w = 0, serving_r = 0;
    reg [127:0] line;

    // ---- read return path is in the chip model; here we just capture beats ----

    // refresh
    reg [9:0] rfs_cnt = 0; reg rfs = 0;
    always @(posedge clk) begin
        rfs_cnt <= rfs_cnt + 1'd1;
        if (rfs_cnt == 10'd850) begin rfs <= 1; rfs_cnt <= 0; end
    end

    // ---- init sequence (precharge-all -> load-mode), like rtl/sdram.sv ----
    reg [1:0] mode = MODE_RESET;
    reg [4:0] rst = 5'h1f;
    reg       init_old = 0;
    wire [4:0] state_last = (mode != MODE_NORMAL) ? STATE_LAST_WR
                          : is_read ? STATE_LAST_RD : STATE_LAST_WR;
    always @(posedge clk) begin
        init_old <= init;
        if (init_old & ~init) rst <= 5'h1f;
        else if (state == state_last) begin
            if (rst != 0) begin
                rst <= rst - 5'd1;
                if      (rst == 5'd14) mode <= MODE_PRE;
                else if (rst == 5'd3)  mode <= MODE_LDM;
                else                   mode <= MODE_RESET;
            end else mode <= MODE_NORMAL;
        end
    end

    // ---- access manager: pick write > read > refresh when idle ----
    always @(posedge clk) begin
        if (state == STATE_IDLE && mode == MODE_NORMAL) begin
            serving_w <= 0; serving_r <= 0;
            if (ackw != reqw) begin
                cur <= addrw; wdata <= dinw; wdqm <= ~{wrhw,wrlw};
                active <= 1; we <= 1; is_read <= 0; serving_w <= 1;
                state <= STATE_START;
            end else if (ackr != reqr) begin
                cur <= addrr; wdqm <= 2'b00;
                active <= 1; we <= 0; is_read <= 1; serving_r <= 1;
                state <= STATE_START;
            end else if (rfs) begin
                rfs <= 0; active <= 0; we <= 0; is_read <= 0;
                state <= STATE_START;
            end
        end

        // capture burst read beats
        if (mode == MODE_NORMAL && is_read && state >= STATE_RDAT0 && state <= STATE_RDATL)
            line[ {(state - STATE_RDAT0), 4'b0} +: 16 ] <= SDRAM_DQ;

        // complete the round
        if (mode == MODE_NORMAL && serving_r && state == STATE_RDATL) begin
            // publish one cycle later so the last beat is included
            doutr <= { SDRAM_DQ, line[111:0] }; // word7 (this cycle) + words0..6 captured
            ackr  <= reqr;
        end
        if (mode == MODE_NORMAL && serving_w && state == STATE_CONT) begin
            ackw <= reqw;
        end

        // round advance
        if (mode != MODE_NORMAL || state != STATE_IDLE) begin
            state <= state + 5'd1;
            if (state == state_last) begin state <= STATE_IDLE; active <= 0; end
        end
    end

    // ---- command + address output ----
    always @(posedge clk) begin
        if (state == STATE_START) SDRAM_BA <= (mode == MODE_NORMAL) ? a_bank(cur) : 2'b00;

        dq_oe <= 1'b0;
        casex ({active, we, mode, state})
            {2'bXX, MODE_NORMAL, STATE_START}: {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= active ? CMD_ACTIVE : CMD_AUTO_REFRESH;
            {2'b11, MODE_NORMAL, STATE_CONT }: begin {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= CMD_WRITE; dq_out <= wdata; dq_oe <= 1'b1; end
            {2'b10, MODE_NORMAL, STATE_CONT }: {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= CMD_READ;
            {2'bXX, MODE_LDM,    STATE_START}: {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= CMD_LOAD_MODE;
            {2'bXX, MODE_PRE,    STATE_START}: {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= CMD_PRECHARGE;
            default:                            {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} <= CMD_NOP;
        endcase

        if (mode == MODE_NORMAL) begin
            casex (state)
                STATE_START: SDRAM_A <= a_row(cur);
                // col on the command: reads use the line-aligned base (low 3 col bits = 0);
                // writes use the exact column. A10 (the 2'b10) = auto-precharge.
                STATE_CONT:  SDRAM_A <= we ? {wdqm, 2'b10, a_col(cur)}
                                           : {2'b00, 2'b10, a_col(cur)[8:3], 3'b000};
                default: ;
            endcase
        end
        else if (mode == MODE_LDM && state == STATE_START) SDRAM_A <= MODE;
        else if (mode == MODE_PRE && state == STATE_START) SDRAM_A <= 13'b0010000000000;
        else SDRAM_A <= 0;
    end
endmodule
