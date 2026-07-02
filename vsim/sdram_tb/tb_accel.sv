//
// tb_accel.sv -- integration test of the PRODUCTION accelerator memory path, mirroring the
// exact Apple-IIgs.sv bridge so it validates what will synthesize for the FPGA:
//
//   bridge (ch0 write / ch1 read-via-cache / ch2 upload)
//     -> rtl/sdram_cache.sv (line buffer on the read path)
//     -> rtl/sdram_burst.sv (3-channel burst controller)
//     -> sdram_sim_chip.sv  (behavioral chip + timing assertions)
//
// Verifies: ch2 upload writes, ch0 CPU writes, ch1 cached reads (incl. read-after-write
// hazard and write-snoop coherency), across the same address formation Apple-IIgs.sv uses.
//
module tb_accel;
    reg clk = 0; always #5 clk = ~clk;

    wire [15:0] SDRAM_DQ; wire [12:0] SDRAM_A;
    wire SDRAM_DQML, SDRAM_DQMH; wire [1:0] SDRAM_BA;
    wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

    // controller channels (names mirror Apple-IIgs.sv)
    reg         init = 1;
    reg  [24:1] wr_addr=0, up_addr=0; reg wr_wrl=0,wr_wrh=0,up_wrl=0,up_wrh=0;
    reg [15:0]  wr_din=0, up_din=0; reg wr_req=0, up_req=0; wire wr_ack, up_ack;
    wire [24:1] rd_addr; wire rd_req; wire rd_ack; wire [127:0] rd_line;

    sdram_burst dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addr0(wr_addr), .wrl0(wr_wrl), .wrh0(wr_wrh), .din0(wr_din), .dout0(), .req0(wr_req), .ack0(wr_ack),
        .addr1(rd_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(rd_line), .req1(rd_req), .ack1(rd_ack),
        .addr2(up_addr), .wrl2(up_wrl), .wrh2(up_wrh), .din2(up_din), .dout2(), .req2(up_req), .ack2(up_ack)
    );

    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    // CPU read port + write snoop into the cache (snoop driven from ch0 writes, like the plan)
    reg  [24:1] cpu_addr=0; reg cpu_rd=0; wire [15:0] cpu_data; wire cpu_ready, cpu_stall;
    reg  [24:1] snp_addr=0; reg [15:0] snp_data=0; reg [1:0] snp_be=0; reg snp_stb=0;

    sdram_cache #(.LINES(8), .LINE_WORDS(8), .ADDR_W(24)) cache (
        .clk(clk), .reset(1'b0),
        .cpu_addr(cpu_addr), .cpu_rd(cpu_rd), .cpu_data(cpu_data),
        .cpu_ready(cpu_ready), .cpu_stall(cpu_stall),
        .wr_addr(snp_addr), .wr_data(snp_data), .wr_be(snp_be), .wr_stb(snp_stb),
        .mem_addr(rd_addr), .mem_req(rd_req), .mem_ack(rd_ack), .mem_line(rd_line)
    );

    integer pass=0, fail=0;
    task automatic chk(input [127:0] what, input [15:0] got, input [15:0] exp);
        begin if (got===exp) pass=pass+1; else begin fail=fail+1;
            $display("  FAIL %-20s got=%04h exp=%04h", what, got, exp); end end
    endtask

    // ch2 upload write (single word) -- mirrors Apple-IIgs.sv ch2
    task automatic upload(input [24:1] a, input [15:0] d);
        begin @(posedge clk); up_addr=a; up_din=d; up_wrl=1; up_wrh=1; up_req=~up_req;
              @(posedge clk); while (up_ack!==up_req) @(posedge clk); up_wrl=0; up_wrh=0; end
    endtask
    // ch0 CPU write (single word) + cache snoop -- mirrors Apple-IIgs.sv ch0 + planned snoop
    task automatic cpuwrite(input [24:1] a, input [15:0] d);
        begin @(posedge clk); wr_addr=a; wr_din=d; wr_wrl=1; wr_wrh=1; wr_req=~wr_req;
              snp_addr=a; snp_data=d; snp_be=2'b11; snp_stb=1;
              @(posedge clk); snp_stb=0; while (wr_ack!==wr_req) @(posedge clk); wr_wrl=0; wr_wrh=0; end
    endtask
    // CPU read through the cache
    task automatic cpuread(input [24:1] a);
        begin @(posedge clk); cpu_addr=a; cpu_rd=1; @(posedge clk); cpu_rd=0;
              while (cpu_ready!==1'b1) @(posedge clk); end
    endtask

    integer i;
    initial begin
        @(posedge clk); init=0;                      // release init; controller runs power-on seq
        repeat (800) @(posedge clk);

        // 1) upload (ch2) a region, read it back through the cache (ch1 burst)
        for (i=0;i<32;i=i+1) upload(24'h040000 + i, 16'h7000 + i[15:0]);
        $display("[tb_accel] ch2 upload -> ch1 cached read:");
        for (i=0;i<32;i=i+1) begin cpuread(24'h040000 + i); chk("upload-rd", cpu_data, 16'h7000 + i[15:0]); end

        // 2) ch0 CPU writes, read back (with snoop keeping cached lines coherent)
        $display("[tb_accel] ch0 write -> ch1 cached read (coherency):");
        cpuread(24'h040008);                          // cache the line first
        cpuwrite(24'h040008, 16'hAA55);               // overwrite a word in the cached line
        cpuwrite(24'h04000B, 16'h1234);
        cpuread(24'h040008); chk("snoop-w0", cpu_data, 16'hAA55);
        cpuread(24'h04000B); chk("snoop-w3", cpu_data, 16'h1234);
        cpuread(24'h04000A); chk("snoop-untouched", cpu_data, 16'h700A);

        // 3) write a fresh (uncached) location then read it -> fill sees new data
        cpuwrite(24'h041000, 16'hC0DE);
        cpuread(24'h041000); chk("write-then-fill", cpu_data, 16'hC0DE);

        $display("[tb_accel] chip: activate=%0d read=%0d write=%0d refresh=%0d",
                 chip.n_activate, chip.n_read, chip.n_write, chip.n_refresh);
        $display("[tb_accel] RESULT: %0d passed, %0d failed", pass, fail);
        if (fail==0) $display("[tb_accel] OK"); else $display("[tb_accel] *** FAILURES ***");
        $finish;
    end
    initial begin repeat (300000) @(posedge clk); $display("[tb_accel] TIMEOUT"); $finish; end
endmodule
