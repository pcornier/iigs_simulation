//
// sdram_sim_chip.sv  --  PROPOSED, NOT WIRED, NOT TESTED  (Verilator simulation only)
//
// Behavioral, cycle-accurate model of a single SDRAM chip (MT48LC16M16A2-class: 16-bit data,
// 4 banks, programmable CAS latency / burst length). Attach it to the SDRAM_* pins of the REAL
// rtl/sdram.sv controller inside the Verilator sim so controller timing (CAS, tRCD, tRC,
// refresh, burst, the req/ack round trip) is actually exercised -- instead of the current
// instant-access dpram in vsim/sim.v:312-325, which hides all timing bugs.
//
// Pure SystemVerilog: Verilator compiles it directly (no DPI, no VHDL). Timing checks are
// $error assertions gated by CHECK so they can be downgraded to warnings.
//
// See doc/sdram_accel/02_sim_model_spec.md.
//

module sdram_sim_chip #(
    parameter AW    = 13,        // address pins (row/col multiplexed)
    parameter DW    = 16,        // data width
    parameter BANKS = 4,
    parameter ROWW  = 13,        // row address bits
    parameter COLW  = 9,         // column address bits
    parameter CAS   = 3,         // CAS latency (must match LOAD_MODE the controller programs)
    // timing in clk cycles @ the SDRAM clock (114.5 MHz defaults)
    parameter tRCD  = 3,
    parameter tRP   = 3,
    parameter tRC   = 8,
    parameter RD_LAT= 2,         // delay-line tap so DQ is valid when the controller latches
                                 // at STATE_READY. For this controller (RASCAS=3,CAS=3) = 2.
    parameter CHECK = 1          // 1 = enforce timing as $error; 0 = silent
) (
    input                   clk,
    inout      [DW-1:0]     dq,
    input      [AW-1:0]     a,
    input      [1:0]        ba,
    input                   dqml,
    input                   dqmh,
    input                   ncs,
    input                   nras,
    input                   ncas,
    input                   nwe
);
    localparam DEPTH = (BANKS) * (1<<ROWW) * (1<<COLW);

    // ---- backing store (load ROM/disk images into this elsewhere, or via $readmemh) ----
    // Flat address = {bank, row, col}. Keep the mapping identical to how the controller
    // shreds addr onto RAS/CAS/BA so loads line up.
    reg [DW-1:0] mem [0:DEPTH-1];

    // ---- command decode (matches sdram.sv:207-214) ----
    wire [2:0] cmd = ncs ? 3'b111 : {nras,ncas,nwe};
    localparam CMD_NOP=3'b111, CMD_ACTIVE=3'b011, CMD_READ=3'b101, CMD_WRITE=3'b100,
               CMD_BTERM=3'b110, CMD_PRE=3'b010, CMD_REF=3'b001, CMD_LMR=3'b000;

    // ---- per-bank state ----
    reg              row_open [0:BANKS-1];
    reg [ROWW-1:0]   open_row [0:BANKS-1];
    integer          t_active [0:BANKS-1];   // cycle of last ACTIVATE (for tRC/tRCD)
    integer          t_pre    [0:BANKS-1];   // cycle of last PRECHARGE (for tRP)
    integer          now;

    // programmed burst length from LOAD_MODE (a[2:0]: 0=>1,1=>2,2=>4,3=>8)
    reg [3:0] burst_len;

    // ---- read return: combinational delay line. A read beat injects data at rd_val[RD_LAT];
    // it shifts toward index 0 and is driven on DQ (combinationally) while rd_val[0] is high,
    // so it is the stable pre-edge value the controller samples at STATE_READY.
    localparam PIPE = RD_LAT + 2;
    reg              rd_val [0:PIPE-1];
    reg [DW-1:0]     rd_dat [0:PIPE-1];
    assign dq = rd_val[0] ? rd_dat[0] : {DW{1'bz}};

    // burst counter for an in-progress READ/WRITE
    reg              burst_active;
    reg              burst_we;
    reg [1:0]        burst_ba;
    reg [ROWW-1:0]   burst_row;
    reg [COLW-1:0]   burst_col;
    reg [3:0]        burst_cnt;
    reg              burst_autopre;

    function automatic [31:0] flat(input [1:0] b, input [ROWW-1:0] r, input [COLW-1:0] c);
        flat = (b * (1<<ROWW) * (1<<COLW)) + (r * (1<<COLW)) + c;
    endfunction

    // command decode is gated until the controller has actually driven the bus (a NOP seen).
    // Sim tools power regs up to 0, which reads as a spurious 000=LOAD_MODE at t=0; the real
    // controller returns to NOP (111) between commands very early, so this cleanly skips garbage.
    reg cmd_en;

    integer i;
    initial begin
        now = 0; burst_active = 0; burst_len = 1; cmd_en = 0;
        for (i=0;i<BANKS;i=i+1) begin row_open[i]=0; t_active[i]=-1000; t_pre[i]=-1000; end
        for (i=0;i<PIPE;i=i+1) rd_val[i]=0;
    end

    always @(posedge clk) begin
        now <= now + 1;
        if (cmd == CMD_NOP) cmd_en <= 1'b1;

        // ---------- advance read delay line ----------
        for (i=0;i<PIPE-1;i=i+1) begin rd_val[i] <= rd_val[i+1]; rd_dat[i] <= rd_dat[i+1]; end
        rd_val[PIPE-1] <= 0;

        // ---------- continue an in-flight burst (beats 2..N, only when burst_len>1) ----------
        if (burst_active) begin
            if (burst_we) begin
                if (!dqml) mem[flat(burst_ba,burst_row,burst_col)][7:0]  <= dq[7:0];
                if (!dqmh) mem[flat(burst_ba,burst_row,burst_col)][15:8] <= dq[15:8];
            end else begin
                rd_val[RD_LAT] <= 1;
                rd_dat[RD_LAT] <= mem[flat(burst_ba,burst_row,burst_col)];
            end
            burst_col <= burst_col + 1'b1;
            burst_cnt <= burst_cnt - 1'b1;
            if (burst_cnt == 1) begin
                burst_active <= 0;
                if (burst_autopre) begin row_open[burst_ba] <= 0; t_pre[burst_ba] <= now; end
            end
        end

        // ---------- command decode ----------
        if (cmd_en)
        case (cmd)
        CMD_LMR: begin
            case (a[2:0]) 3'd0:burst_len<=1; 3'd1:burst_len<=2; 3'd2:burst_len<=4;
                          3'd3:burst_len<=8; default:burst_len<=1; endcase
            if (CHECK && a[6:4] != CAS)
                $error("[sdram_sim_chip] LOAD_MODE CAS=%0d != model CAS=%0d", a[6:4], CAS);
        end

        CMD_ACTIVE: begin
            if (CHECK && row_open[ba])
                $error("[sdram_sim_chip] ACTIVATE bank %0d already open (missing PRECHARGE)", ba);
            if (CHECK && (now - t_pre[ba]    < tRP)) $error("[sdram_sim_chip] tRP violation");
            if (CHECK && (now - t_active[ba] < tRC)) $error("[sdram_sim_chip] tRC violation");
            row_open[ba] <= 1; open_row[ba] <= a[ROWW-1:0]; t_active[ba] <= now;
        end

        CMD_READ, CMD_WRITE: begin
            if (CHECK && !row_open[ba])
                $error("[sdram_sim_chip] %s with no open row, bank %0d",
                       (cmd==CMD_READ)?"READ":"WRITE", ba);
            if (CHECK && (now - t_active[ba] < tRCD)) $error("[sdram_sim_chip] tRCD violation");
            // beat 0 happens here; beats 2..N (reads only) continue in the burst block above.
            burst_we      <= (cmd==CMD_WRITE);
            burst_ba      <= ba;
            burst_row     <= open_row[ba];
            burst_col     <= a[COLW-1:0] + 1'b1;          // next column for beat 1
            burst_autopre <= a[10];                        // A10 = auto-precharge
            if (cmd==CMD_WRITE) begin
                // writes are single-location (NO_WRITE_BURST): no continuation
                burst_active <= 0;
                if (!dqml) mem[flat(ba,open_row[ba],a[COLW-1:0])][7:0]  <= dq[7:0];
                if (!dqmh) mem[flat(ba,open_row[ba],a[COLW-1:0])][15:8] <= dq[15:8];
                if (a[10]) begin row_open[ba] <= 0; t_pre[ba] <= now; end
            end else begin
                rd_val[RD_LAT] <= 1; rd_dat[RD_LAT] <= mem[flat(ba,open_row[ba],a[COLW-1:0])];
                if (burst_len > 1) begin
                    burst_active <= 1;
                    burst_cnt    <= burst_len - 1'b1;       // remaining beats
                end else begin
                    burst_active <= 0;
                    if (a[10]) begin row_open[ba] <= 0; t_pre[ba] <= now; end
                end
            end
        end

        CMD_PRE: begin
            // A10=1 precharges all banks, else just `ba`
            if (a[10]) begin for (i=0;i<BANKS;i=i+1) begin row_open[i]<=0; t_pre[i]<=now; end end
            else       begin row_open[ba]<=0; t_pre[ba]<=now; end
        end

        CMD_REF: begin
            if (CHECK) for (i=0;i<BANKS;i=i+1)
                if (row_open[i]) $error("[sdram_sim_chip] AUTO_REFRESH with bank %0d open", i);
            // (a real model would track per-row refresh deadlines; left as a TODO counter)
        end

        default: ; // NOP / BURST_TERMINATE
        endcase
    end

    // ---- measurement counters (print from the C++ harness at stop-frame) ----
    integer n_activate=0, n_read=0, n_write=0, n_refresh=0, read_words=0;
    always @(posedge clk) begin
        case (cmd)
            CMD_ACTIVE: n_activate <= n_activate + 1;
            CMD_READ:   n_read     <= n_read + 1;
            CMD_WRITE:  n_write    <= n_write + 1;
            CMD_REF:    n_refresh  <= n_refresh + 1;
            default: ;
        endcase
        if (rd_val[0]) read_words <= read_words + 1;
    end
endmodule
