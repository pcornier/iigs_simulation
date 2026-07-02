//
// sdram_burst.sv -- production 3-channel SDRAM controller with a burst-8 read channel.
//
// Drop-in successor to rtl/sdram.sv for the accelerator memory path. Same 3-channel toggle
// req/ack interface and SDRAM pinout, EXCEPT channel 1 (CPU reads) returns a 128-bit aligned
// 8-word line per request instead of a single 16-bit word -- one ACTIVATE + one READ(burst=8,
// auto-precharge) amortizes the row cycle over 8 words (see doc/sdram_accel/01_*). A small line
// buffer (rtl/sdram_cache.sv) sits in front of ch1 and serves most CPU reads with no SDRAM
// access at all.
//
//   ch0 : single-word write (CPU write-through),  highest priority
//   ch1 : burst-8 read  -> dout1[127:0]           (the line the cache fills with)
//   ch2 : single-word write (HPS ROM/disk upload)
//   + auto-refresh when idle
//
// MANDATORY address remap vs rtl/sdram.sv: column = LOW address bits so the hardware burst
// walks consecutive words (rtl/sdram.sv puts the row in the low bits, which defeats bursts).
//   bank = a[24:23], row = a[22:10] (13b), col = a[9:1] (9b)
//
// Targets MT48LC16M16A2 @ ~114.5MHz (RASCAS=3, CAS=3), same part/clock as rtl/sdram.sv.
// FPGA-friendly: pure synchronous, clock-enable style, standard DQ tristate.
//
// Copyright (c) 2018 Sorgelig (base structure); accelerator changes for the Apple IIgs core.
// GPLv3, as rtl/sdram.sv.
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

    // ch0: single-word write
    input      [24:1] addr0, input wrl0, input wrh0, input [15:0] din0,
    output     [15:0] dout0, input req0, output reg ack0,
    // ch1: burst-8 read -> 128-bit line
    input      [24:1] addr1, input wrl1, input wrh1, input [15:0] din1,
    output     [127:0] dout1, input req1, output reg ack1,
    // ch2: single-word write (upload)
    input      [24:1] addr2, input wrl2, input wrh2, input [15:0] din2,
    output     [15:0] dout2, input req2, output reg ack2
);
    assign SDRAM_nCS  = 0;
    assign SDRAM_CKE  = 1;
    assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

    reg [15:0] dq_out; reg dq_oe;
    assign SDRAM_DQ = dq_oe ? dq_out : 16'bzzzz_zzzz_zzzz_zzzz;

    reg [127:0] line;
    assign dout0 = 16'd0;
    assign dout1 = line;
    assign dout2 = 16'd0;

    localparam BURST_CODE     = 3'b011;       // burst length 8 (reads)
    localparam NO_WRITE_BURST = 1'b1;         // single-location writes
    localparam [12:0] MODE = {3'b000, NO_WRITE_BURST, 2'b00, CAS_LATENCY[2:0], 1'b0, BURST_CODE};

    // ---- address remap: column = LOW bits ----
    function automatic [1:0]  a_bank(input [24:1] a); a_bank = a[24:23]; endfunction
    function automatic [12:0] a_row (input [24:1] a); a_row  = a[22:10]; endfunction
    function automatic [8:0]  a_col (input [24:1] a); a_col  = a[9:1];   endfunction

    localparam [4:0] STATE_IDLE  = 5'd0;
    localparam [4:0] STATE_START = 5'd1;
    localparam [4:0] STATE_CONT  = STATE_START + RASCAS_DELAY;       // 4
    localparam [4:0] STATE_RDAT0 = STATE_CONT + CAS_LATENCY + 5'd1;  // 8
    localparam [4:0] STATE_RDATL = STATE_RDAT0 + 5'd7;               // 15
    localparam [4:0] STATE_LAST_RD = STATE_RDATL + 5'd3;            // 18 (tRP/tRC guard)
    localparam [4:0] STATE_LAST_WR = STATE_CONT  + 5'd4;            // 8  (tRC guard)

    localparam CMD_NOP=3'b111, CMD_ACTIVE=3'b011, CMD_READ=3'b101, CMD_WRITE=3'b100,
               CMD_PRECHARGE=3'b010, CMD_AUTO_REFRESH=3'b001, CMD_LOAD_MODE=3'b000;
    localparam MODE_NORMAL=2'b00, MODE_RESET=2'b01, MODE_LDM=2'b10, MODE_PRE=2'b11;

    reg  [4:0] state = STATE_IDLE;
    reg        active = 0, we = 0, is_read = 0;
    reg  [1:0] serving = 2'd0;        // 0=ch0, 1=ch1, 2=ch2 (valid while active)
    reg [24:1] cur = 0;
    reg [15:0] wdata = 0;
    reg  [1:0] wdqm = 0;

    // refresh
    reg [9:0] rfs_cnt = 0; reg rfs = 0;
    always @(posedge clk) begin
        rfs_cnt <= rfs_cnt + 1'd1;
        if (rfs_cnt == 10'd850) begin rfs <= 1; rfs_cnt <= 0; end
    end

    // init sequence
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

    // access manager: ch0 write > ch1 read > ch2 write > refresh
    always @(posedge clk) begin
        if (state == STATE_IDLE && mode == MODE_NORMAL) begin
            if (ack0 != req0) begin
                cur <= addr0; wdata <= din0; wdqm <= ~{wrh0,wrl0};
                active <= 1; we <= 1; is_read <= 0; serving <= 2'd0; state <= STATE_START;
            end else if (ack1 != req1) begin
                cur <= addr1; wdqm <= 2'b00;
                active <= 1; we <= 0; is_read <= 1; serving <= 2'd1; state <= STATE_START;
            end else if (ack2 != req2) begin
                cur <= addr2; wdata <= din2; wdqm <= ~{wrh2,wrl2};
                active <= 1; we <= 1; is_read <= 0; serving <= 2'd2; state <= STATE_START;
            end else if (rfs) begin
                rfs <= 0; active <= 0; we <= 0; is_read <= 0; state <= STATE_START;
            end
        end

        // capture burst read beats
        if (mode == MODE_NORMAL && is_read && state >= STATE_RDAT0 && state <= STATE_RDATL)
            line[ {(state - STATE_RDAT0), 4'b0} +: 16 ] <= SDRAM_DQ;

        // completion acks
        if (mode == MODE_NORMAL && active) begin
            if (is_read && state == STATE_RDATL) ack1 <= req1;
            if (we && state == STATE_CONT) begin
                if (serving == 2'd0) ack0 <= req0;
                else                 ack2 <= req2;
            end
        end

        // round advance
        if (mode != MODE_NORMAL || state != STATE_IDLE) begin
            state <= state + 5'd1;
            if (state == state_last) begin state <= STATE_IDLE; active <= 0; end
        end
    end

    // command + address output
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
                STATE_CONT:  SDRAM_A <= we ? {wdqm, 2'b10, a_col(cur)}
                                           : {2'b00, 2'b10, a_col(cur)[8:3], 3'b000};
                default: ;
            endcase
        end
        else if (mode == MODE_LDM && state == STATE_START) SDRAM_A <= MODE;
        else if (mode == MODE_PRE && state == STATE_START) SDRAM_A <= 13'b0010000000000;
        else SDRAM_A <= 0;
    end

    // DDR clock-forward to the SDRAM_CLK pin (same cell as rtl/sdram.sv). The standalone TB
    // supplies a Verilator stub for altddio_out.
    altddio_out #(
        .extend_oe_disable("OFF"), .intended_device_family("Cyclone V"), .invert_output("OFF"),
        .lpm_hint("UNUSED"), .lpm_type("altddio_out"), .oe_reg("UNREGISTERED"),
        .power_up_high("OFF"), .width(1)
    ) sdramclk_ddr (
        .datain_h(1'b0), .datain_l(1'b1), .outclock(clk), .dataout(SDRAM_CLK),
        .aclr(1'b0), .aset(1'b0), .oe(1'b1), .outclocken(1'b1), .sclr(1'b0), .sset(1'b0)
    );
endmodule
