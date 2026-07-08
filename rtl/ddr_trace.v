// DDR Signal Trace Recorder
//
// Records signal changes to DDR memory for offline analysis with trace2vcd.
// Only writes records when signals change or cycle counter wraps, minimizing
// memory bandwidth while preserving full timing information.
//
// Record format (64-bit little-endian):
//   [63:64-CYCLE_BITS] - Cycle count at time of change
//   [63-CYCLE_BITS:0]  - Signal data (directly from 'data' input)
//
// Usage:
//   1. Connect signals to trace via 'data' input
//   2. Assert 'trigger' to start recording
//   3. De-assert 'trigger' to stop (waits for FIFO flush, then resets)
//   4. Read RECORDS * 8 bytes from ADDR via /dev/mem or similar

module ddr_trace #(
    parameter CYCLE_BITS = 8,              // Bits for cycle counter (max 2^N cycles between changes)
    parameter FIFO_BITS  = 12,             // Internal FIFO depth (2^N entries)
    parameter [31:0] ADDR = 32'h3000_0000, // DDR base address (must be 8-byte aligned)
    parameter [28:0] RECORDS = 'h100_0000  // Maximum records to capture
)(
    // Trace clock and data
    input                    clk,      // Sample clock - all signals synchronous to this
    input  [63-CYCLE_BITS:0] data,     // Signals to trace (directly mapped to record LSBs)
    input                    trigger,  // High: recording, Low: stop and reset after flush

    // MiSTer DDRAM interface
    output            DDRAM_CLK,      // DDR clock (directly driven by clk)
    input             DDRAM_BUSY,     // High: DDR unavailable, wait to write
    output      [7:0] DDRAM_BURSTCNT, // Burst count (fixed at 1)
    output reg [28:0] DDRAM_ADDR,     // Word address (8-byte aligned)
    output            DDRAM_RD,       // Read strobe (unused, directly tied low)
    output reg [63:0] DDRAM_DIN,      // Write data
    output      [7:0] DDRAM_BE,       // Byte enables (fixed at 0xFF)
    output reg        DDRAM_WE,       // Write enable
    output            dbg_active      // 1 = at least one record captured (debug)
);
    assign dbg_active = (write_ptr != 0);

    assign DDRAM_CLK      = clk;
    assign DDRAM_RD       = 0;
    assign DDRAM_BE       = 8'hFF;
    assign DDRAM_BURSTCNT = 8'h01;

    reg [CYCLE_BITS-1:0] cycle_cnt = 0;

    reg [63:0] fifo[(1 << FIFO_BITS)];

    reg [63-CYCLE_BITS:0] prev_data = 0;
    reg [28:0] write_ptr = 0;  // Next FIFO position to write
    reg [28:0] read_ptr = 0;   // Next FIFO position to send to DDR

    always @(posedge clk) begin
        if (trigger) begin
            if (write_ptr < RECORDS) begin
                cycle_cnt <= cycle_cnt + 1;
                // Record on data change or cycle wrap (cycle_cnt == 0)
                if (cycle_cnt == 0 || prev_data != data) begin
                    fifo[write_ptr[FIFO_BITS-1:0]] <= {cycle_cnt, data};
                    prev_data <= data;
                    write_ptr <= write_ptr + 1;
                end
            end
        end else begin
            // Reset after FIFO has been flushed to DDR
            if (write_ptr == read_ptr) begin
                cycle_cnt <= 0;
                prev_data <= 0;
                write_ptr <= 0;
                read_ptr  <= 0;
            end
        end

        if (~DDRAM_BUSY) begin
            DDRAM_WE <= 0;
            if (read_ptr != write_ptr) begin
                DDRAM_ADDR <= ADDR[31:3] + read_ptr;
                DDRAM_DIN  <= fifo[read_ptr[FIFO_BITS-1:0]];
                DDRAM_WE   <= 1;
                read_ptr   <= read_ptr + 1;
            end
        end
    end

endmodule
