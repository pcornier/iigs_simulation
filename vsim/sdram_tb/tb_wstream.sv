`timescale 1ns/1ps
//
// tb_wstream.sv -- 1-tick (14.32 MHz) CPU write-stream stress of the PRODUCTION
// accelerator memory path (doc/zipgs-14mhz-plan.md, problem A + C validation).
//
//   CPU/bridge model (mirrors the Apple-IIgs.sv bridge at speed step 4)
//     -> rtl/sdram_cache.sv (write snoop + forwarding, comb hit port)
//     -> rtl/sdram_burst.sv (ch0 single-word writes, ch1 burst-8 line fills)
//     -> sdram_sim_chip.sv  (behavioral chip + timing assertions)
//
// The CPU commits one memory cycle per clk_sys tick (clk_sys = clk_mem/8,
// like the real 14.318/114.5 MHz PLL pair), held only by the combinational
// mem_stall (read miss, or -- with BACKPRESSURE=1 -- a write while the
// previously posted write is still unacknowledged). This reproduces the
// 65C816's worst case: runs of consecutive write cycles (interrupt entry
// pushes 4 bytes back-to-back) at 69.8ns spacing vs the controller's
// ~78.6ns per-write service time, swept across refresh collisions.
//
// BACKPRESSURE=0 models the pre-fix fire-and-forget bridge: wr_req toggles
// while a write is in flight, the controller's "ack0 <= req0" absorbs the
// queued toggle, and the write never reaches SDRAM (the cache snoop masks it
// until eviction). Expect FAILURES. BACKPRESSURE=1 is the production fix:
// expect a clean run. The final check compares the behavioral chip's memory
// directly against a golden model, so no cache coherency can mask a drop.
//
// Run: ./build_wstream.sh   (iverilog; verilator here is 4.204, needs v5)
//
module tb_wstream;
    parameter BACKPRESSURE = 1;   // 0 = pre-fix bridge (expect dropped writes)

    // clk = clk_mem (114.5 MHz model); clk_sys = /8, edge-aligned like the PLL pair
    reg clk = 0; always #5 clk = ~clk;
    reg [2:0] clkdiv = 0;
    always @(posedge clk) clkdiv <= clkdiv + 1'b1;
    wire clk_sys = clkdiv[2];

    // ---- SDRAM pins / controller / chip / cache (production RTL) ----
    wire [15:0] SDRAM_DQ; wire [12:0] SDRAM_A;
    wire SDRAM_DQML, SDRAM_DQMH; wire [1:0] SDRAM_BA;
    wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

    reg         init = 1;
    reg  [24:1] wr_addr = 0;
    reg         wr_wrl = 0, wr_wrh = 0;
    reg  [15:0] wr_din = 0;
    reg         wr_req = 0;
    wire        wr_ack;
    wire [24:1] rd_addr; wire rd_req; wire rd_ack; wire [127:0] rd_line;

    sdram_burst dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addr0(wr_addr), .wrl0(wr_wrl), .wrh0(wr_wrh), .din0(wr_din), .dout0(), .req0(wr_req), .ack0(wr_ack),
        .addr1(rd_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(rd_line), .req1(rd_req), .ack1(rd_ack),
        .addr2(24'd0), .wrl2(1'b0), .wrh2(1'b0), .din2(16'd0), .dout2(), .req2(1'b0), .ack2(),
        .addr3(24'd0), .dout3(), .req3(1'b0), .ack3()
    );

    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    wire [15:0] cpu_data; wire cpu_ready, cpu_stall;
    wire        hit_now;  wire [15:0] cpu_data_now;
    reg         snoop_stb = 0;

    // ---- CPU program: one op per committed CPU cycle ----
    localparam OP_NOP = 2'd0, OP_WR = 2'd1, OP_RD = 2'd2, OP_END = 2'd3;
    localparam PMAX = 16384;
    reg [1:0]  p_op   [0:PMAX-1];
    reg [24:1] p_addr [0:PMAX-1];
    reg [15:0] p_data [0:PMAX-1];   // write data / expected read data
    reg [1:0]  p_be   [0:PMAX-1];
    integer plen = 0;

    reg         run = 0;
    integer     pc  = 0;
    wire [1:0]  op   = p_op[pc];
    wire        we_c = run && (op == OP_WR);
    wire        rd_c = run && (op == OP_RD);
    wire [24:1] a_c  = p_addr[pc];

    reg cache_rst = 1;   // iverilog: cache regs power up X; give it a real reset
    sdram_cache #(.LINES(8), .LINE_WORDS(8), .ADDR_W(24)) cache (
        .clk(clk_sys), .reset(cache_rst), .cache_off(1'b0),
        .cpu_addr(a_c), .cpu_rd(rd_c), .cpu_data(cpu_data),
        .cpu_ready(cpu_ready), .cpu_stall(cpu_stall),
        .hit_now(hit_now), .cpu_data_now(cpu_data_now),
        .wr_addr(wr_addr), .wr_data(wr_din), .wr_be({wr_wrh, wr_wrl}), .wr_stb(snoop_stb),
        .mem_addr(rd_addr), .mem_req(rd_req), .mem_ack(rd_ack), .mem_line(rd_line)
    );

    // ---- bridge (mirrors Apple-IIgs.sv, accel_r=1) ----
    reg  wr_ack_s1 = 0, wr_ack_s2 = 0;
    wire wr_pending = (wr_req != wr_ack_s2);
    wire post_gate  = ~((BACKPRESSURE != 0) & wr_pending);
    // mem_stall mirror: read miss, or (with the fix) write while a post is pending
    wire mem_stall  = (rd_c & ~hit_now) |
                      ((BACKPRESSURE != 0) & we_c & wr_pending);

    always @(posedge clk_sys) begin
        wr_ack_s1 <= wr_ack;
        wr_ack_s2 <= wr_ack_s1;
        if (we_c & post_gate) begin
            wr_addr <= a_c;
            wr_din  <= p_data[pc];
            wr_wrl  <= p_be[pc][0];
            wr_wrh  <= p_be[pc][1];
            wr_req  <= ~wr_req;
        end
        snoop_stb <= we_c & post_gate;
    end

    // ---- CPU commit + read checks ----
    integer pass = 0, fail = 0, fail_shown = 0;
    always @(posedge clk_sys) begin
        if (run && op != OP_END && !mem_stall) begin
            if (rd_c) begin
                if (cpu_data_now === p_data[pc]) pass = pass + 1;
                else begin
                    fail = fail + 1;
                    if (fail_shown < 10) begin
                        fail_shown = fail_shown + 1;
                        $display("  FAIL rd pc=%0d addr=%06h got=%04h exp=%04h",
                                 pc, {a_c, 1'b0}, cpu_data_now, p_data[pc]);
                    end
                end
            end
            pc <= pc + 1;
        end
    end

    // ---- golden model over the test window ----
    localparam [24:1] BASE = 24'h020000;   // word address (bank 0 fast RAM region)
    localparam WIN = 1024;                 // words
    reg [15:0] gm  [0:WIN-1];
    reg        wrt [0:WIN-1];

    // program-builder tasks (gm tracks expected memory as the program is laid out)
    task automatic pw(input [24:1] a, input [15:0] d, input [1:0] be);
        begin
            p_op[plen] = OP_WR; p_addr[plen] = a; p_data[plen] = d; p_be[plen] = be;
            if (be[0]) gm[a - BASE][7:0]  = d[7:0];
            if (be[1]) gm[a - BASE][15:8] = d[15:8];
            wrt[a - BASE] = 1'b1;
            plen = plen + 1;
        end
    endtask
    task automatic pr(input [24:1] a);
        begin
            p_op[plen] = OP_RD; p_addr[plen] = a; p_data[plen] = gm[a - BASE]; p_be[plen] = 2'b11;
            plen = plen + 1;
        end
    endtask
    task automatic pn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                p_op[plen] = OP_NOP; p_addr[plen] = BASE; p_data[plen] = 0; p_be[plen] = 0;
                plen = plen + 1;
            end
        end
    endtask

    integer i, j, k2;
    reg [24:1] wa;
    initial begin
        // pre-load chip + golden with a pattern so cold line fills are checkable
        for (i = 0; i < WIN; i = i + 1) begin
            chip.mem[BASE + i] = 16'hB000 ^ i[15:0];
            gm[i]  = 16'hB000 ^ i[15:0];
            wrt[i] = 1'b0;
        end

        // --- 1) write-forwarding / snoop-lag: read-after-write at 1-cycle spacing ---
        pr(BASE + 8);                          // cache the line
        pw(BASE + 8, 16'hAA55, 2'b11);
        pr(BASE + 8);                          // NEXT cycle: needs comb forwarding
        pw(BASE + 9, 16'h1234, 2'b11);
        pr(BASE + 9);
        pw(BASE + 10, 16'h00EE, 2'b01);        // low-byte-only write
        pr(BASE + 10);
        pw(BASE + 10, 16'hDD00, 2'b10);        // high-byte-only write
        pr(BASE + 10);
        pr(BASE + 12);                         // untouched word of the same line

        // --- 2) interrupt-push pattern: 4 consecutive 1-tick writes, swept across
        //        refresh phase (nop padding varies alignment vs the 850-clk refresh) ---
        for (j = 0; j < 400; j = j + 1) begin
            wa = BASE + 15'h0100 + ((j * 4) % 240);
            pw(wa + 0, 16'h5100 + j[7:0], 2'b11);
            pw(wa + 1, 16'h5200 + j[7:0], 2'b11);
            pw(wa + 2, 16'h5300 + j[7:0], 2'b11);
            pw(wa + 3, 16'h5400 + j[7:0], 2'b11);
            pn(j % 9);
            // occasionally a cold read so miss fills contend with the write channel
            if ((j % 7) == 0) pr(BASE + 15'h0200 + ((j * 8) % 512));
        end

        // --- 3) longer sustained write burst (block-fill style) ---
        for (j = 0; j < 128; j = j + 1)
            pw(BASE + 15'h0300 + j[14:0], 16'h9000 + j[15:0], 2'b11);

        // --- 4) evict everything (8 conflicting tags per index), then read back
        //        the whole window THROUGH SDRAM: a dropped write shows here ---
        for (j = 0; j < 16; j = j + 1) pr(BASE + 15'h1000 + j[14:0] * 64);
        for (j = 0; j < WIN; j = j + 1) if (wrt[j]) pr(BASE + j[14:0]);

        p_op[plen] = OP_END; plen = plen + 1;

        // --- run ---
        @(posedge clk); init = 0;
        repeat (32) @(posedge clk_sys); cache_rst = 0;
        repeat (800) @(posedge clk);           // controller power-on sequence
        @(posedge clk_sys); run = 1;
        while (p_op[pc] != OP_END) @(posedge clk_sys);
        repeat (500) @(posedge clk);           // drain

        // --- 5) direct chip-memory compare (immune to cache masking) ---
        k2 = 0;
        for (i = 0; i < WIN; i = i + 1) begin
            if (wrt[i] && chip.mem[BASE + i] !== gm[i]) begin
                k2 = k2 + 1;
                if (k2 <= 10)
                    $display("  FAIL sdram addr=%06h got=%04h exp=%04h",
                             {BASE + i[14:0], 1'b0}, chip.mem[BASE + i], gm[i]);
            end
        end
        if (k2 != 0) fail = fail + k2;

        $display("[tb_wstream] BACKPRESSURE=%0d: %0d read-checks passed, %0d failures (%0d dropped-write words)",
                 BACKPRESSURE, pass, fail, k2);
        if (fail == 0) $display("[tb_wstream] OK");
        else           $display("[tb_wstream] *** FAILURES ***");
        $finish;
    end

    initial begin repeat (3000000) @(posedge clk); $display("[tb_wstream] TIMEOUT pc=%0d/%0d", pc, plen); $finish; end
endmodule
