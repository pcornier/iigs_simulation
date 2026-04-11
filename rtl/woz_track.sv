//
// woz_track.sv: WOZ Track Buffer for Flux-Based Disk Interface
//
// This module stores WOZ bit data for a single track and provides
// byte-level access for flux_drive.v to read bits from.
//
// Key differences from floppy35_track.sv:
// - Stores raw WOZ bit data (not decoded nibbles)
// - Provides bit_count metadata for proper track wraparound
// - Uses SD block interface for loading track data from C++
//
// Protocol for loading WOZ track data via SD block:
//   Block 0: Metadata (bytes 0-7: bit_count as 32-bit LE, byte_count as 32-bit LE)
//            Bytes 8-511: First 504 bytes of track bits
//   Block N (N>0): Next 512 bytes of track bits
//
// Maximum track size: 12.5KB = 100,000 bits (for 3.5" outer zone tracks)
// BRAM size: 16KB (13-bit byte address)
//

module woz_track (
    input         clk,
    input         reset,

    // SD Block Interface (for loading track data from C++)
    output [31:0] sd_lba,
    output reg    sd_rd,
    output reg    sd_wr,
    input         sd_ack,

    input   [8:0] sd_buff_addr,
    input   [7:0] sd_buff_dout,
    output  [7:0] sd_buff_din,
    input         sd_buff_wr,

    // Disk mount/change signals
    input         change,
    input         mount,

    // Track request from drive
    input   [6:0] track,        // 7-bit track number (0-159 for 3.5")
    input         side,         // Side select (0 or 1) - combined with track
    output reg    ready = 0,    // Track data is valid
    input         active,       // Drive is accessing data

    // Bit data interface to flux_drive.v
    input  [13:0] bit_byte_addr, // Byte address for bit access
    output  [7:0] bit_byte_data, // Byte data at address
    output [31:0] bit_count,     // Total bits in current track

    // Debug
    output reg    busy
);

    //=========================================================================
    // SD Block Interface
    //=========================================================================

    // Track LBA calculation:
    // For WOZ mode, we use a different LBA scheme than nibble mode
    // LBA = WOZ_DRIVE_BASE + (track_with_side * blocks_per_track)
    // WOZ_DRIVE_BASE is set in C++ (sim_blkdevice.cpp)
    // track_with_side = track | (side << 7) for 0-159 addressing

    localparam BLOCKS_PER_TRACK = 8'd128;  // 64KB / 512 = 128 blocks max

    reg [31:0] lba;
    reg  [6:0] rel_lba;  // 7 bits for up to 128 blocks
    reg [31:0] track_bit_count;
    reg [31:0] track_byte_count;
    reg        mount_pending;

    // Capture metadata bytes as they arrive during SD block 0 transfer
    reg [7:0] meta_byte0, meta_byte1, meta_byte2, meta_byte3;  // bit_count (LE)
    reg [7:0] meta_byte4, meta_byte5, meta_byte6, meta_byte7;  // byte_count (LE)

    assign sd_lba = lba;
    assign bit_count = track_bit_count;
    assign sd_buff_din = 8'h00;  // No write support

    //=========================================================================
    // Dual-Port BRAM for Track Bits (64KB)
    //=========================================================================

    reg [7:0] track_bram [0:65535];  // 64KB for WOZ FLUX tracks

    // Port A: Write from SD buffer (during load)
    // Port B: Read for bit access

    always @(posedge clk) begin
        if (sd_buff_wr && sd_ack) begin
            // Calculate BRAM address based on current block and buffer offset
            // Block 0, bytes 0-7: metadata (skip)
            // Block 0, bytes 8-511: first 504 bytes of track bits
            // Block N, bytes 0-511: next 512 bytes
            if (rel_lba == 0) begin
                // Block 0: skip first 8 bytes (metadata), store rest
                if (sd_buff_addr >= 9'd8) begin
                    track_bram[{7'b0, sd_buff_addr} - 16'd8] <= sd_buff_dout;
                end
            end else begin
                // Blocks 1+: full 512 bytes offset by 504 bytes from block 0
                track_bram[16'd504 + ({rel_lba - 7'd1, sd_buff_addr[8:0]})] <= sd_buff_dout;
            end
        end
    end

    // Port B: Read for flux_drive.v
    assign bit_byte_data = track_bram[bit_byte_addr];

    //=========================================================================
    // Track Loading State Machine
    //=========================================================================

    always @(posedge clk) begin
        reg old_ack;
        reg [6:0] cur_track;
        reg       cur_side;
        reg old_change;

        old_change <= change;
        old_ack <= sd_ack;

        if (sd_ack) sd_rd <= 0;

        // Capture metadata bytes from block 0 header
        if (sd_buff_wr && sd_ack && rel_lba == 0) begin
            case (sd_buff_addr)
                9'd0: meta_byte0 <= sd_buff_dout;
                9'd1: meta_byte1 <= sd_buff_dout;
                9'd2: meta_byte2 <= sd_buff_dout;
                9'd3: meta_byte3 <= sd_buff_dout;
                9'd4: meta_byte4 <= sd_buff_dout;
                9'd5: meta_byte5 <= sd_buff_dout;
                9'd6: meta_byte6 <= sd_buff_dout;
                9'd7: meta_byte7 <= sd_buff_dout;
                default: ; // Other bytes are track data
            endcase
`ifdef SIMULATION
            if (sd_buff_addr < 9'd8) begin
                $display("WOZ_TRACK: Metadata byte[%0d] = %02h", sd_buff_addr, sd_buff_dout);
            end
`endif
        end

        // Handle mount/change
        if (~old_change && change) begin
            ready <= 1'b0;
            mount_pending <= mount;
            cur_track <= 7'b1111111;
            cur_side <= 1'b0;
            busy <= 0;
            sd_rd <= 0;
            track_bit_count <= 32'd0;
            track_byte_count <= 32'd0;
`ifdef SIMULATION
            $display("WOZ_TRACK: change -> mount_pending=%0d", mount);
`endif
        end else if (reset) begin
            ready <= 0;
            mount_pending <= 0;
            cur_track <= 7'b1111111;
            cur_side <= 1'b0;
            busy <= 0;
            sd_rd <= 0;
            track_bit_count <= 32'd0;
            track_byte_count <= 32'd0;
        end else

        // Loading state machine
        if (busy) begin
            if (old_ack && ~sd_ack) begin
                // Block transfer complete

                // Extract metadata from first block using captured bytes
                if (rel_lba == 0) begin
                    // Reconstruct 32-bit little-endian values from captured bytes
                    track_bit_count <= {meta_byte3, meta_byte2, meta_byte1, meta_byte0};
                    track_byte_count <= {meta_byte7, meta_byte6, meta_byte5, meta_byte4};
`ifdef SIMULATION
                    $display("WOZ_TRACK: Block 0 loaded, bit_count=%0d byte_count=%0d",
                             {meta_byte3, meta_byte2, meta_byte1, meta_byte0},
                             {meta_byte7, meta_byte6, meta_byte5, meta_byte4});
`endif
                end

                if (rel_lba < BLOCKS_PER_TRACK - 1) begin
                    // More blocks to load
                    lba <= lba + 1'd1;
                    rel_lba <= rel_lba + 1'd1;
                    sd_rd <= 1;
`ifdef SIMULATION
                    $display("WOZ_TRACK: Loading block %0d (LBA=%0d)", rel_lba + 1, lba + 1);
`endif
                end else begin
                    // Track loading complete
                    busy <= 0;
                    ready <= mount_pending;
`ifdef SIMULATION
                    $display("WOZ_TRACK: Track %0d load complete, ready=%0d", cur_track, mount_pending);
`endif
                end
            end
        end else if ((mount_pending || ready) && !active) begin
            // Check if track changed
            if ((cur_track != track) || (cur_side != side)) begin
                // Start loading new track
                cur_track <= track;
                cur_side <= side;

                // Calculate starting LBA for this track
                // Use track_with_side = track | (side << 7)
                lba <= {17'b0, side, track, 5'b0};  // Simplified: track * 32 blocks
                rel_lba <= 5'd0;
                busy <= 1;
                sd_rd <= 1;
                ready <= 0;  // Mark not ready during load
`ifdef SIMULATION
                $display("WOZ_TRACK: Starting load track=%0d side=%0d LBA=%0d",
                         track, side, {17'b0, side, track, 5'b0});
`endif
            end
        end
    end

`ifdef SIMULATION
    // Debug: monitor bit access
    reg [13:0] prev_bit_addr;
    always @(posedge clk) begin
        if (active && bit_byte_addr != prev_bit_addr) begin
            if (bit_byte_addr < 14'd16) begin
                $display("WOZ_TRACK: Bit read byte_addr=%04h data=%02h (first 16 bytes)",
                         bit_byte_addr, bit_byte_data);
            end
            prev_bit_addr <= bit_byte_addr;
        end
    end
`endif

endmodule
