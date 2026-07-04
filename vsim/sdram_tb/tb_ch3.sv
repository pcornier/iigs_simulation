//
// tb_ch3.sv -- testbench for the PRODUCTION controller rtl/sdram_burst.sv,
// focused on the ch3 single-word read channel (native-speed CPU reads) and
// on ch1 burst reads staying intact alongside it.
//
// Build: ./build_ch3.sh ; run ./obj_dir/Vtb_ch3
//
module tb_ch3;
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
    reg  [24:1] addr0 = 0, addr1 = 0, addr3 = 0;
    reg         wrl0 = 0, wrh0 = 0;
    reg  [15:0] din0 = 0;
    reg         req0 = 0, req1 = 0, req3 = 0;
    wire        ack0, ack1, ack2, ack3;
    wire [127:0] dout1;
    wire [15:0] dout3;

    sdram_burst dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addr0(addr0), .wrl0(wrl0), .wrh0(wrh0), .din0(din0), .dout0(), .req0(req0), .ack0(ack0),
        .addr1(addr1), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(dout1), .req1(req1), .ack1(ack1),
        .addr2(25'd0 >> 1), .wrl2(1'b0), .wrh2(1'b0), .din2(16'd0), .dout2(), .req2(1'b0), .ack2(ack2),
        .addr3(addr3), .dout3(dout3), .req3(req3), .ack3(ack3)
    );

    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    integer pass = 0, fail = 0;
    integer lat, lat_min = 9999, lat_max = 0;

    task automatic wr(input [24:1] a, input [15:0] d);
        begin
            @(posedge clk); addr0 = a; din0 = d; wrl0 = 1; wrh0 = 1; req0 = ~req0;
            @(posedge clk); while (ack0 !== req0) @(posedge clk);
            wrl0 = 0; wrh0 = 0;
        end
    endtask

    // ch3 single-word read; checks data and records req->ack latency
    task automatic rd3(input [24:1] a, input [15:0] exp);
        integer t0;
        begin
            @(posedge clk); addr3 = a; req3 = ~req3; t0 = cyc;
            @(posedge clk); while (ack3 !== req3) @(posedge clk);
            lat = cyc - t0;
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
            if (dout3 === exp) pass = pass + 1;
            else begin
                fail = fail + 1;
                $display("FAIL ch3 rd @%h: got %h want %h (cyc %0d)", a, dout3, exp, cyc);
            end
        end
    endtask

    task automatic rd_line(input [24:1] base, input [127:0] exp);
        begin
            @(posedge clk); addr1 = base; req1 = ~req1;
            @(posedge clk); while (ack1 !== req1) @(posedge clk);
            if (dout1 === exp) pass = pass + 1;
            else begin
                fail = fail + 1;
                $display("FAIL ch1 line @%h:\n got %h\nwant %h", base, dout1, exp);
            end
        end
    endtask

    integer i, j;
    reg [24:1] base;
    reg [127:0] lineexp;

    // watchdog: dump controller state if the run wedges
    initial begin
        #400000;
        $display("WATCHDOG: mode=%0d state=%0d rst=%0d active=%b serving=%0d",
                 dut.mode, dut.state, dut.rst, dut.active, dut.serving);
        $display("  req0=%b ack0=%b req3=%b ack3=%b pass=%0d fail=%0d",
                 req0, ack0, req3, ack3, pass, fail);
        $finish;
    end

    initial begin
        // let the power-up init sequence run
        repeat (600) @(posedge clk);

        // --- fill one aligned 8-word line, plus scattered addresses across banks
        base = 24'h001230 >> 1;  // even byte addr -> word addr; low 3 bits of word 0
        base = {2'b00, 13'h0123, 9'h010};  // bank 0, row 0x123, col 0x10 (aligned)
        for (i = 0; i < 8; i = i + 1)
            wr(base + i, 16'hA500 + i);

        // --- ch3 reads back every word of the line (all column offsets)
        for (i = 0; i < 8; i = i + 1)
            rd3(base + i, 16'hA500 + i);

        // --- ch1 burst still returns the whole line intact
        lineexp = 0;
        for (i = 0; i < 8; i = i + 1)
            lineexp[i*16 +: 16] = 16'hA500 + i;
        rd_line(base, lineexp);

        // --- cross-bank / cross-row ch3 reads
        wr({2'b01, 13'h0456, 9'h1F7}, 16'hBEEF);
        wr({2'b10, 13'h1FFF, 9'h000}, 16'h1234);
        wr({2'b11, 13'h0000, 9'h1FF}, 16'hC0DE);
        rd3({2'b01, 13'h0456, 9'h1F7}, 16'hBEEF);
        rd3({2'b10, 13'h1FFF, 9'h000}, 16'h1234);
        rd3({2'b11, 13'h0000, 9'h1FF}, 16'hC0DE);

        // --- interleave writes and ch3 reads long enough to cross several
        //     refresh periods (rfs fires every 850 cycles)
        for (j = 0; j < 40; j = j + 1) begin
            wr(base + 9'h020 + j, 16'h5A00 ^ j);
            repeat (60) @(posedge clk);
            rd3(base + 9'h020 + j, 16'h5A00 ^ j);
        end

        // --- ch1 after all the ch3 traffic: line still intact
        rd_line(base, lineexp);

        $display("tb_ch3: %0d pass, %0d fail; ch3 req->ack latency min %0d max %0d clk",
                 pass, fail, lat_min, lat_max);
        if (fail == 0) $display("tb_ch3: ALL PASS");
        $finish;
    end
endmodule
