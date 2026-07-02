//
// tb_cache.sv -- the accelerator read path end to end:
//   CPU fetch model -> sdram_cache (line buffer) -> sdram_burst (burst-8 ctrl) -> chip model
//
// Measures the number that actually matters for the accelerator: how much SDRAM traffic the
// CPU consumes once a small line buffer absorbs spatial/temporal locality. Reports line fills
// (= SDRAM transactions), hit rate, and effective SDRAM cycles/word for a few workloads.
//
// Build: see build_cache.sh ; run ./obj_dir/Vtb_cache
//
module tb_cache;
    reg clk = 0;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    localparam BURST_CYC = 19;   // measured cycles per 8-word line fill (tb_burst)

    // ---- pins ----
    wire [15:0] SDRAM_DQ;  wire [12:0] SDRAM_A;
    wire SDRAM_DQML, SDRAM_DQMH; wire [1:0] SDRAM_BA;
    wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

    // ---- controller channels ----
    reg         init = 0;
    reg  [24:1] addrw = 0; reg wrlw=0, wrhw=0; reg [15:0] dinw=0; reg reqw=0; wire ackw;
    wire [24:1] addrr;  wire reqr;  wire ackr;  wire [127:0] doutr;

    sdram_burst dut (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addrw(addrw), .wrlw(wrlw), .wrhw(wrhw), .dinw(dinw), .reqw(reqw), .ackw(ackw),
        .addrr(addrr), .reqr(reqr), .ackr(ackr), .doutr(doutr)
    );

    sdram_sim_chip #(.CAS(3), .ROWW(13), .COLW(9), .BANKS(4), .RD_LAT(2), .CHECK(1)) chip (
        .clk(clk), .dq(SDRAM_DQ), .a(SDRAM_A), .ba(SDRAM_BA),
        .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH),
        .ncs(SDRAM_nCS), .nras(SDRAM_nRAS), .ncas(SDRAM_nCAS), .nwe(SDRAM_nWE)
    );

    // ---- cache (8 lines x 8 words = 64-word I/D line buffer) ----
    reg  [24:1] cpu_addr = 0; reg cpu_rd = 0;
    wire [15:0] cpu_data; wire cpu_ready, cpu_stall;
    reg  [24:1] snp_addr = 0; reg [15:0] snp_data = 0; reg [1:0] snp_be = 0; reg snp_stb = 0;

    sdram_cache #(.LINES(8), .LINE_WORDS(8), .ADDR_W(24)) cache (
        .clk(clk), .reset(1'b0),
        .cpu_addr(cpu_addr), .cpu_rd(cpu_rd), .cpu_data(cpu_data),
        .cpu_ready(cpu_ready), .cpu_stall(cpu_stall),
        .wr_addr(snp_addr), .wr_data(snp_data), .wr_be(snp_be), .wr_stb(snp_stb),
        .mem_addr(addrr), .mem_req(reqr), .mem_ack(ackr), .mem_line(doutr)
    );

    // ---- fill counter (watch the cache->controller read request toggle) ----
    integer fills = 0; reg reqr_d = 0;
    always @(posedge clk) begin reqr_d <= reqr; if (reqr !== reqr_d) fills <= fills + 1; end

    // ---- write a word through the controller (and snoop the cache, like real ch0) ----
    task automatic wmem(input [24:1] a, input [15:0] d);
        begin
            @(posedge clk); addrw=a; dinw=d; wrlw=1; wrhw=1; reqw=~reqw;
                            snp_addr=a; snp_data=d; snp_be=2'b11; snp_stb=1;
            @(posedge clk); snp_stb=0; while (ackw!==reqw) @(posedge clk);
            wrlw=0; wrhw=0;
        end
    endtask

    // ---- one CPU fetch through the cache (waits for data) ----
    task automatic fetch(input [24:1] a);
        begin
            @(posedge clk); cpu_addr=a; cpu_rd=1;
            @(posedge clk); cpu_rd=0;
            while (cpu_ready!==1'b1) @(posedge clk);
        end
    endtask

    integer i, k, f0, c0;
    reg [31:0] lcg;
    reg [24:1] pc;
    task automatic report(input [127:0] name, input integer reads, input integer f, input integer c);
        begin
            $display("  %-16s reads=%0d fills=%0d hit=%0d.%0d%%  SDRAMcyc/word=%0d.%02d",
                name, reads, f,
                (100*(reads-f))/reads, ((1000*(reads-f))/reads)%10,
                (f*BURST_CYC)/reads, (((f*BURST_CYC)*100)/reads)%100);
        end
    endtask

    initial begin
        repeat (800) @(posedge clk);                  // power-on init

        // prime three 256-word regions
        for (i=0;i<256;i=i+1) wmem(24'h020000 + i, 16'h0000 + i[15:0]);
        for (i=0;i<256;i=i+1) wmem(24'h021000 + i, 16'h1000 + i[15:0]);
        for (i=0;i<256;i=i+1) wmem(24'h022000 + i, 16'h2000 + i[15:0]);

        $display("[tb_cache] workloads (LINE=8 words, cache=8 lines / 64 words):");

        // 1) cold sequential stream of 64 words (no reuse)
        f0=fills; c0=cyc;
        for (i=0;i<64;i=i+1) fetch(24'h020000 + i);
        report("cold-stream", 64, fills-f0, cyc-c0);

        // 2) hot loop: 32-word body executed 8 times (fits in cache -> reuse)
        f0=fills; c0=cyc;
        for (k=0;k<8;k=k+1) for (i=0;i<32;i=i+1) fetch(24'h021000 + i);
        report("hot-loop x8", 256, fills-f0, cyc-c0);

        // 3) mixed: 256 fetches, mostly sequential with ~12% random jumps in a 128-word window
        f0=fills; c0=cyc; pc=24'h022000; lcg=32'h1234_5678;
        for (i=0;i<256;i=i+1) begin
            fetch(pc);
            lcg = lcg*32'd1103515245 + 32'd12345;
            if (lcg[31:29] == 3'b000)                       // ~1/8 = 12.5% jump
                pc = 24'h022000 + {lcg[10:4]};              // random word in 128-word window
            else
                pc = (pc == 24'h022000 + 127) ? 24'h022000 : pc + 1;
        end
        report("mixed-12%jump", 256, fills-f0, cyc-c0);

        // ---- coherency: write into a cached line, read it back ----
        $display("[tb_cache] coherency check:");
        fetch(24'h021040);                                  // ensure the line is cached
        wmem(24'h021041, 16'hBEEF);                         // write a word in that line (snooped)
        cpu_addr=24'h021041; cpu_rd=1; @(posedge clk); cpu_rd=0;
        while (cpu_ready!==1'b1) @(posedge clk);
        if (cpu_data === 16'hBEEF) $display("  PASS  snoop updated cached word (got BEEF)");
        else                       $display("  FAIL  stale cached word got=%04h exp=BEEF", cpu_data);

        $display("[tb_cache] baseline single-word = 9.00 SDRAM cyc/word (tb_sdram)");
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk);
        $display("[tb_cache] TIMEOUT"); $finish;
    end
endmodule
