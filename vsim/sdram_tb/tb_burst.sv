//
// tb_burst.sv -- testbench for the PROTOTYPE burst-8 controller doc/sdram_accel/sdram_burst.sv
// against the behavioral chip model. Verifies 8-word line read-back integrity and measures
// cycles/word for sequential reads (the number that matters for the accelerator).
//
// Build: see build_burst.sh ; run ./obj_dir/Vtb_burst
//
module tb_burst;
    reg clk = 0;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    wire [15:0] SDRAM_DQ;
    wire [12:0] SDRAM_A;
    wire        SDRAM_DQML, SDRAM_DQMH;
    wire [1:0]  SDRAM_BA;
    wire        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

    reg         init = 0;
    reg  [24:1] addrw=0, addrr=0;
    reg         wrlw=0, wrhw=0;
    reg  [15:0] dinw=0;
    reg         reqw=0, reqr=0;
    wire        ackw, ackr;
    wire [127:0] doutr;

    sdram_burst dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addrw(addrw), .wrlw(wrlw), .wrhw(wrhw), .dinw(dinw), .reqw(reqw), .ackw(ackw),
        .addrr(addrr), .reqr(reqr), .ackr(ackr), .doutr(doutr)
    );

    // chip model with burst length 8 enabled via the controller's LOAD_MODE
    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    integer pass = 0, fail = 0;

    task automatic wr(input [24:1] a, input [15:0] d);
        begin
            @(posedge clk); addrw = a; dinw = d; wrlw = 1; wrhw = 1; reqw = ~reqw;
            @(posedge clk); while (ackw !== reqw) @(posedge clk);
            wrlw = 0; wrhw = 0;
        end
    endtask

    // read one 8-word line at base (low 3 bits 0); returns 128-bit line in `line`
    reg [127:0] line;
    task automatic rd_line(input [24:1] base);
        begin
            @(posedge clk); addrr = base; reqr = ~reqr;
            @(posedge clk); while (ackr !== reqr) @(posedge clk);
            line = doutr;
        end
    endtask

    integer i, j;
    integer c0, c1;
    reg [24:1] base;
    reg [15:0] got, exp;
    initial begin
        repeat (800) @(posedge clk);     // power-on init

        // fill 32 words (4 lines) with a recognizable pattern
        for (i = 0; i < 32; i = i + 1) wr(24'h020000 + i, 16'hC000 + i[15:0]);

        // read back as 4 burst lines, check every word
        $display("[tb_burst] burst line read-back:");
        for (j = 0; j < 4; j = j + 1) begin
            base = 24'h020000 + (j*8);
            rd_line(base);
            for (i = 0; i < 8; i = i + 1) begin
                got = line[16*i +: 16];
                exp = 16'hC000 + (j*8 + i);
                if (got === exp) pass = pass + 1;
                else begin
                    fail = fail + 1;
                    $display("  FAIL line%0d word%0d  got=%04h exp=%04h", j, i, got, exp);
                end
            end
            $display("  line%0d @%06h = %032h", j, base, line);
        end

        // ---- measure: cycles to read 64 words as 8 burst lines ----
        c0 = cyc;
        for (j = 0; j < 8; j = j + 1) rd_line(24'h020000 + (j*8));
        c1 = cyc;
        $display("[tb_burst] BURST: %0d cycles for 64 words = %0d.%02d cycles/word",
                 (c1-c0), (c1-c0)/64, (((c1-c0)*100)/64)%100);

        $display("[tb_burst] chip counters: activate=%0d read=%0d write=%0d read_words=%0d",
                 chip.n_activate, chip.n_read, chip.n_write, chip.read_words);
        $display("[tb_burst] RESULT: %0d passed, %0d failed", pass, fail);
        if (fail == 0) $display("[tb_burst] OK"); else $display("[tb_burst] *** FAILURES ***");
        $finish;
    end

    initial begin
        repeat (300000) @(posedge clk);
        $display("[tb_burst] TIMEOUT"); $finish;
    end
endmodule
