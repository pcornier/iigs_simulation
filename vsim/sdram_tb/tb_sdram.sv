//
// tb_sdram.sv -- standalone Verilator testbench for the REAL rtl/sdram.sv controller driven
// against the behavioral sdram_sim_chip.sv model. Validates that the controller's command
// sequencing + CAS latency line up with a modeled chip (write-then-read-back integrity), and
// exercises the doc-02 timing assertions / measurement counters -- WITHOUT touching the main
// Vemu sim's clock harness.
//
// Build (from vsim/sdram_tb): see build.sh in this directory, then run ./obj_dir/Vtb_sdram
//
module tb_sdram;
    reg clk = 0;
    always #5 clk = ~clk;          // 100 MHz-ish; absolute rate irrelevant for the model

    // ---- controller <-> chip pins ----
    wire [15:0] SDRAM_DQ;
    wire [12:0] SDRAM_A;
    wire        SDRAM_DQML, SDRAM_DQMH;
    wire [1:0]  SDRAM_BA;
    wire        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

    // ---- controller channel signals ----
    reg         init = 0;
    reg  [24:1] addr0=0, addr1=0, addr2=0;
    reg         wrl0=0, wrh0=0, wrl1=0, wrh1=0, wrl2=0, wrh2=0;
    reg  [15:0] din0=0, din1=0, din2=0;
    wire [15:0] dout0, dout1, dout2;
    reg         req0=0, req1=0, req2=0;
    wire        ack0, ack1, ack2;

    sdram dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addr0(addr0), .wrl0(wrl0), .wrh0(wrh0), .din0(din0), .dout0(dout0), .req0(req0), .ack0(ack0),
        .addr1(addr1), .wrl1(wrl1), .wrh1(wrh1), .din1(din1), .dout1(dout1), .req1(req1), .ack1(ack1),
        .addr2(addr2), .wrl2(wrl2), .wrh2(wrh2), .din2(din2), .dout2(dout2), .req2(req2), .ack2(ack2)
    );

    // chip model: row/col split must match the controller (row=a[13:1], col=a[22:14])
    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    integer pass = 0, fail = 0;

    // write one 16-bit word via channel 0 (both byte enables)
    task automatic wr(input [24:1] a, input [15:0] d);
        begin
            @(posedge clk);
            addr0 = a; din0 = d; wrl0 = 1; wrh0 = 1;
            req0  = ~req0;
            @(posedge clk);
            while (ack0 !== req0) @(posedge clk);
            wrl0 = 0; wrh0 = 0;
        end
    endtask

    // read one 16-bit word via channel 1, check against expected
    task automatic rd_chk(input [24:1] a, input [15:0] exp);
        begin
            @(posedge clk);
            addr1 = a; req1 = ~req1;
            @(posedge clk);
            while (ack1 !== req1) @(posedge clk);
            @(posedge clk);                 // let dout1 settle
            if (dout1[15:0] === exp) begin
                pass = pass + 1;
                $display("  PASS  addr=%06h  got=%04h", a, dout1[15:0]);
            end else begin
                fail = fail + 1;
                $display("  FAIL  addr=%06h  got=%04h  exp=%04h", a, dout1[15:0], exp);
            end
        end
    endtask

    integer i;
    reg [24:1] aa;
    reg [15:0] dd;
    initial begin
        // hold init low; controller runs its power-on init (reset countdown) automatically.
        repeat (700) @(posedge clk);

        $display("[tb_sdram] write/read-back integrity:");
        // spread across banks/rows/cols; addr is the 24-bit word address [24:1]
        wr(24'h000010, 16'hA5A5); wr(24'h000011, 16'h1234); wr(24'h00FFEE, 16'hCAFE);
        wr(24'h123456, 16'hBEEF); wr(24'h400010, 16'h0F0F); wr(24'h7FFFFF, 16'hDEAD);

        rd_chk(24'h000010, 16'hA5A5); rd_chk(24'h000011, 16'h1234); rd_chk(24'h00FFEE, 16'hCAFE);
        rd_chk(24'h123456, 16'hBEEF); rd_chk(24'h400010, 16'h0F0F); rd_chk(24'h7FFFFF, 16'hDEAD);

        // a short pseudo-sequential sweep (walks columns within a row after the remap-less map)
        $display("[tb_sdram] sweep:");
        for (i = 0; i < 16; i = i + 1) begin
            aa = 24'h020000 + i;
            dd = 16'h1000 + i[15:0];
            wr(aa, dd);
        end
        for (i = 0; i < 16; i = i + 1) begin
            aa = 24'h020000 + i;
            dd = 16'h1000 + i[15:0];
            rd_chk(aa, dd);
        end

        $display("[tb_sdram] counters: activate=%0d read=%0d write=%0d refresh=%0d read_words=%0d",
                 chip.n_activate, chip.n_read, chip.n_write, chip.n_refresh, chip.read_words);
        $display("[tb_sdram] RESULT: %0d passed, %0d failed", pass, fail);
        if (fail == 0) $display("[tb_sdram] OK");
        else           $display("[tb_sdram] *** FAILURES ***");
        $finish;
    end

    // safety timeout
    initial begin
        repeat (200000) @(posedge clk);
        $display("[tb_sdram] TIMEOUT");
        $finish;
    end
endmodule
