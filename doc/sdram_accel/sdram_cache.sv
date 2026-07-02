//
// sdram_cache.sv  --  PROPOSED, NOT WIRED, NOT TESTED
//
// Small direct-mapped line buffer that sits in the clk_sys (28.6 MHz) domain in front of
// channel 1 (CPU reads) of rtl/sdram.sv, after that controller is given a burst-8 read that
// returns a 128-bit aligned line. See doc/sdram_accel/01_burst_linebuffer_design.md.
//
// Purpose: serve sequential CPU fetches from local registers (a "hit") with no SDRAM
// transaction and no req/ack clock-domain round trip, so the 65C816 can run at 7-14 MHz.
// A "miss" issues ONE burst fill (8 words) and stalls the CPU via RDY_IN until it lands.
//
// Coherency: SDRAM fast RAM (banks 00-7F) is written only by the CPU (ch0 write-through) and
// the ROM uploader (ch2, load-time). Video scans out of BRAM (E0/E1), NOT SDRAM, so a local
// snoop of CPU writes is sufficient -- there is no video/DMA coherency case to handle here.
//
// FPGA-friendly: pure synchronous logic on clk_sys, registered line storage, clock-enable
// style. No gated clocks. Toggle req/ack to the controller (crosses to 114.5 MHz safely).
//

module sdram_cache #(
    parameter LINES      = 4,    // number of cached lines (start small; power of two)
    parameter LINE_WORDS = 8,    // words per line == controller burst length
    parameter ADDR_W     = 24    // word address width into SDRAM (addr[24:1])
) (
    input                       clk,        // clk_sys (28.6 MHz)
    input                       reset,

    // ---- CPU read port ----
    input      [ADDR_W:1]       cpu_addr,   // word address of the requested read
    input                       cpu_rd,     // 1-cycle strobe: a fast-RAM/ROM read is starting
    output reg [15:0]           cpu_data,   // returned word (valid when cpu_ready=1)
    output reg                  cpu_ready,  // 1 = cpu_data valid this cycle (hit, or fill done)
    output                      cpu_stall,  // 1 = miss in progress; drive CPU RDY_IN low with this

    // ---- CPU write snoop (ch0 write-through happens elsewhere; we only watch it) ----
    input      [ADDR_W:1]       wr_addr,
    input      [15:0]           wr_data,
    input      [1:0]            wr_be,      // byte enables {hi,lo}
    input                       wr_stb,     // 1-cycle strobe when a fast-RAM write commits

    // ---- to controller channel 1 (burst read), toggle req/ack ----
    output reg [ADDR_W:1]       mem_addr,   // line base address (low log2(LINE_WORDS) = 0)
    output reg                  mem_req,    // toggle to request a burst fill
    input                       mem_ack,    // toggles to match mem_req when mem_line valid
    input      [16*LINE_WORDS-1:0] mem_line // 128-bit aligned line from controller
);
    localparam LW    = $clog2(LINE_WORDS);      // 3  (word-offset bits within a line)
    localparam IDXW  = $clog2(LINES);           // 2  (index bits)
    localparam TAGW  = ADDR_W - LW - IDXW;       // remaining high bits

    // address decode (cpu_addr is [ADDR_W:1]; treat bit 1 as word LSB)
    wire [LW-1:0]   c_word = cpu_addr[LW:1];
    wire [IDXW-1:0] c_idx  = cpu_addr[LW+IDXW:LW+1];
    wire [TAGW-1:0] c_tag  = cpu_addr[ADDR_W:LW+IDXW+1];

    // line storage
    reg [16*LINE_WORDS-1:0] data [LINES-1:0];
    reg [TAGW-1:0]          tag  [LINES-1:0];
    reg                     valid[LINES-1:0];

    wire hit = valid[c_idx] && (tag[c_idx] == c_tag);

    // miss FSM
    localparam S_IDLE = 1'b0, S_FILL = 1'b1;
    reg        fsm;
    reg [IDXW-1:0]   fill_idx;
    reg [TAGW-1:0]   fill_tag;
    reg [LW-1:0]     fill_word;
    reg              mem_ack_d;

    assign cpu_stall = (fsm == S_FILL);

    integer i;
    always @(posedge clk) begin
        cpu_ready <= 1'b0;
        mem_ack_d <= mem_ack;

        if (reset) begin
            for (i = 0; i < LINES; i = i + 1) valid[i] <= 1'b0;
            fsm     <= S_IDLE;
            mem_req <= 1'b0;
        end else begin
            // ---- write snoop: keep any cached copy coherent (write-through update) ----
            // (the actual SDRAM write is issued by the existing ch0 path in Apple-IIgs.sv)
            if (wr_stb) begin
                if (valid[wr_addr[LW+IDXW:LW+1]] &&
                    tag[wr_addr[LW+IDXW:LW+1]] == wr_addr[ADDR_W:LW+IDXW+1]) begin
                    // update the matching word's enabled bytes in the line
                    if (wr_be[0]) data[wr_addr[LW+IDXW:LW+1]][{wr_addr[LW:1],4'b0} +: 8]      <= wr_data[7:0];
                    if (wr_be[1]) data[wr_addr[LW+IDXW:LW+1]][{wr_addr[LW:1],4'b0}+8 +: 8]    <= wr_data[15:8];
                end
            end

            case (fsm)
            S_IDLE: begin
                if (cpu_rd) begin
                    if (hit) begin
                        cpu_data  <= data[c_idx][{c_word,4'b0} +: 16];
                        cpu_ready <= 1'b1;             // fast path: no SDRAM, no CDC
                    end else begin
                        // launch burst fill for the aligned line
                        fill_idx  <= c_idx;
                        fill_tag  <= c_tag;
                        fill_word <= c_word;
                        mem_addr  <= {c_tag, c_idx, {LW{1'b0}}}; // line base
                        mem_req   <= ~mem_req;        // toggle -> controller
                        fsm       <= S_FILL;
                    end
                end
            end
            S_FILL: begin
                if (mem_ack_d != mem_ack) begin       // controller delivered the line
                    data [fill_idx] <= mem_line;
                    tag  [fill_idx] <= fill_tag;
                    valid[fill_idx] <= 1'b1;
                    cpu_data  <= mem_line[{fill_word,4'b0} +: 16];
                    cpu_ready <= 1'b1;
                    fsm       <= S_IDLE;
                end
            end
            endcase
        end
    end
endmodule
