
module woz_floppy_controller #(
    parameter IS_35_INCH = 0
) (
    input             clk,
    input             reset,

    // SD Block Device Interface
    output reg [31:0] sd_lba,
    output reg        sd_rd,
    output reg        sd_wr,
    input             sd_ack,
    input      [8:0]  sd_buff_addr,
    input      [7:0]  sd_buff_dout,
    output     logic [7:0]  sd_buff_din,
    input             sd_buff_wr,

    // Disk Status
    input             img_mounted,
    input             img_readonly,
    input      [63:0] img_size,

    // Drive Interface
    input      [7:0]  track_id,      // TMAP Index: 3.5"={track[6:0],side}, 5.25"={2'b0,qtr_track}
    output reg        ready,         // High when valid WOZ loaded and track ready
    output wire       disk_mounted,  // High when valid WOZ is loaded (stays high, doesn't toggle during seeks)
    output reg        busy,          // High during load/save operations
    input             active,        // Motor active (used for save triggers)

    // Bitstream Interface (to IWM)
    output wire [31:0] bit_count,    // Number of bits in current track (combinational mux)
    input      [13:0] bit_addr,      // Read address
    output     [7:0]  bit_data,      // Read data
    input      [7:0]  bit_data_in,   // Write data
    input             bit_we,        // Write enable (sets dirty)

    // Track load notification (for flux_drive to reset position)
    output reg        track_load_complete  // Pulses high for 1 cycle when physical track finishes loading
);

    //=========================================================================
    // Internal State
    //=========================================================================
    
    // Meta RAM: 2KB (Stores Blocks 0-3 of WOZ file)
    // - Header: 0-11
    // - INFO: 20-79
    // - TMAP: 88-247
    // - TRKS: 256-1535 (160 entries * 8 bytes)
    reg  [10:0] meta_addr;
    wire [7:0]  meta_dout;
    reg         meta_we;
    reg  [7:0]  meta_din;
    
    bram #(.width_a(8), .widthad_a(11)) meta_ram (
        .clock_a(clk),
        .address_a(meta_addr),
        .wren_a(meta_we),
        .data_a(meta_din),
        .q_a(meta_dout),
        .clock_b(clk),
        .address_b(meta_read_addr), // Port B used for lookups
        .wren_b(1'b0),
        .data_b(8'h00),
        .q_b(meta_read_data)
    );

    // Track RAM: 16KB per side (3.5") (Stores bitstream)
    //
    // IMPORTANT: On the IIgs, the Sony protocol uses HDSEL/SEL (bit7 of $C031) as both:
    // - the "SEL" bit in the 4-bit command/address nibble, and
    // - the physical head select.
    //
    // The ROM frequently toggles SEL as part of status reads (e.g. /READY is addr $0B),
    // which would cause a naïve SD-backed loader to thrash-reload side 0/1 repeatedly.
    // Real hardware switches heads instantly; emulate that by caching each side's track
    // bitstream independently and just muxing the output on SEL changes.
    reg  [13:0] track_load_addr;
    reg         track_load_we;
    reg  [7:0]  track_load_data;
    wire [7:0]  track_ram_dout0;
    wire [7:0]  track_ram_dout1;
    wire [7:0]  bit_data0;
    wire [7:0]  bit_data1;
    reg         load_side;   // Which side is currently being DMA-loaded/saved (3.5" only)
    reg         track_load_side; // Side captured with track_load_* for synchronous BRAM write

    // Dual port RAM for Track Data (Side 0)
    bram #(.width_a(8), .widthad_a(14)) track_ram_side0 (
        .clock_a(clk),
        .address_a(track_load_addr),
        .wren_a(track_load_we && (!IS_35_INCH || (track_load_side == 1'b0))),
        .data_a(track_load_data),
        .q_a(track_ram_dout0),

        .clock_b(clk),
        .address_b(bit_addr),
        .wren_b(bit_we && (!IS_35_INCH || (track_id[0] == 1'b0))),
        .data_b(bit_data_in),
        .q_b(bit_data0)
    );

    // Dual port RAM for Track Data (Side 1) - only meaningful for 3.5"
    bram #(.width_a(8), .widthad_a(14)) track_ram_side1 (
        .clock_a(clk),
        .address_a(track_load_addr),
        .wren_a(track_load_we && (IS_35_INCH && (track_load_side == 1'b1))),
        .data_a(track_load_data),
        .q_a(track_ram_dout1),

        .clock_b(clk),
        .address_b(bit_addr),
        .wren_b(bit_we && (IS_35_INCH && (track_id[0] == 1'b1))),
        .data_b(bit_data_in),
        .q_b(bit_data1)
    );

    assign bit_data = (IS_35_INCH && track_id[0]) ? bit_data1 : bit_data0;

    // bit_count: Return the correct bit_count for the requested track.
    //
    // The single-track-per-side BRAM cache means only ONE track per side is stored.
    // When seeking to a new track, we need to return the CORRECT bit_count:
    //
    // 1. If requested track matches cached track → return cached bit_count (correct data in BRAM)
    // 2. If currently loading a track → return the pending track's bit_count (trk_bit_count)
    //    This gives flux_drive a reasonable bit_count during loading (data is garbage anyway)
    // 3. Otherwise → return cached side's bit_count (best effort for rapid SEL toggles)
    //
    // The key insight: returning bit_count=0 causes no flux transitions, which makes
    // the ROM timeout waiting for data. Returning a reasonable non-zero value lets
    // flux_drive generate flux (even from garbage data) which keeps the ROM responsive.
    //
    // After track load completes, current_track_id_sideX is updated and the correct
    // bit_count is returned for subsequent reads.
    wire track_side0_match = (current_track_id_side0 == track_id);
    wire track_side1_match = (current_track_id_side1 == track_id);
    wire selected_track_match = (IS_35_INCH && track_id[0]) ? track_side1_match : track_side0_match;
    wire [31:0] selected_bit_count = (IS_35_INCH && track_id[0]) ? bit_count_side1 : bit_count_side0;
    wire is_loading = (state == S_SEEK_LOOKUP) || (state == S_READ_TRACK);
    // During loading, use the pending track's bit_count (or cached if not yet known)
    wire [31:0] loading_bit_count = (trk_bit_count > 0) ? trk_bit_count : selected_bit_count;
    assign bit_count = woz_valid ? (selected_track_match ? selected_bit_count :
                                    (is_loading ? loading_bit_count : selected_bit_count)) : 32'd0;

    // State Machine
    localparam S_INIT        = 0;
    localparam S_DETECT      = 1;
    localparam S_SCAN_WOZ    = 2; // Scan header + chunks to cache INFO/TMAP/TRKS
    localparam S_IDLE        = 3;
    localparam S_SEEK_LOOKUP = 4;
    localparam S_READ_TRACK  = 5;
    localparam S_SAVE_TRACK  = 6;

    reg [3:0] state = S_INIT;
    reg [7:0] current_track_id_side0;
    reg [7:0] current_track_id_side1;
    reg [7:0] pending_track_id;
    reg       dirty;
    reg       woz_valid;
    reg       old_ack;

    // For 3.5" dual-side loading: load both sides when physical track changes
    reg       loading_second_side;    // Set after side 0 loaded, cleared after side 1
    reg [6:0] target_physical_track;  // Physical track being loaded (track_id[7:1])

    reg [31:0] bit_count_side0;
    reg [31:0] bit_count_side1;

    // Debug
    reg [7:0] last_debug_track_id;

    // disk_mounted is a stable "media present" signal and should go true as soon as the
    // image is mounted. The old C++ WOZ path reported media present immediately; delaying
    // until the metadata scan completes can cause ROM timeouts while it polls /DIP.
`ifdef WOZ_DISK_MOUNTED_AFTER_PARSE
    assign disk_mounted = img_mounted && woz_valid;
`else
    assign disk_mounted = img_mounted && !scan_failed;
`endif

    // WOZ Parsing
    reg [10:0] meta_read_addr;
    wire [7:0] meta_read_data;

    localparam [10:0] META_TMAP_BASE = 11'd0;
    localparam [10:0] META_TRKS_BASE = 11'd256;

    // Streaming WOZ parser: caches INFO/TMAP/TRKS by scanning file chunks (WOZ1/WOZ2).
    reg        have_info;
    reg        have_tmap;
    reg        have_trks;
    reg [15:0] scan_blocks;

    // WOZ header is 12 bytes:
    // 4 bytes signature ("WOZ1"/"WOZ2"), 4 bytes 0xFF 0x0A 0x0D 0x0A, 4 bytes CRC32.
    reg  [3:0] hdr_pos;          // 0..11
    reg  [2:0] chunk_hdr_pos;    // 0..7  (chunk header is 8 bytes)
    reg [31:0] chunk_id;
    reg [31:0] chunk_size_acc;
    reg [31:0] chunk_left;
    reg [31:0] chunk_index;

    // INFO fields (mostly for debug)
    reg  [7:0] info_version;
    reg  [7:0] info_disk_type;
    reg  [7:0] info_bit_timing;

    wire parser_done = have_info && have_tmap && have_trks;
    localparam [15:0] SCAN_BLOCK_LIMIT = 16'd256; // safety: stop scanning after 128KB
    reg scan_failed;
    
    // Current Track Info
    reg [15:0] trk_start_block;
    reg [15:0] trk_block_count;
    reg [31:0] trk_bit_count;
    
    // SD Operation
    reg [15:0] blocks_processed;
    
    // Mount Edge Detection
    reg prev_mounted;

    // Track active transfers to filter spurious sd_ack falling edges
    // transfer_active is set when sd_ack rises after sd_rd/sd_wr was asserted
    // It's cleared when the transfer completes (sd_ack falls)
    reg transfer_active;

    always @(posedge clk) begin
        old_ack <= sd_ack;

        // Track when a real transfer is in progress
        // Rising edge of sd_ack after we asserted sd_rd/sd_wr means transfer started
        if (!old_ack && sd_ack && (sd_rd || sd_wr)) begin
            transfer_active <= 1'b1;
        end
        // Falling edge of sd_ack means transfer complete - clear for next one
        if (old_ack && !sd_ack) begin
            transfer_active <= 1'b0;
        end

	        if (reset) begin
	            state <= S_INIT;
	            ready <= 0;
	            busy <= 0;
	            woz_valid <= 0;
	            prev_mounted <= 0;
	            sd_rd <= 0;
	            sd_wr <= 0;
	            dirty <= 0;
            current_track_id_side0 <= 8'hFF;
            current_track_id_side1 <= 8'hFF;
	            pending_track_id <= 8'h00;
	            load_side <= 1'b0;
	            track_load_side <= 1'b0;
            old_ack <= 1'b0;
            transfer_active <= 1'b0;
            loading_second_side <= 1'b0;
            target_physical_track <= 7'h7F;
	            bit_count_side0 <= 32'd0;
	            bit_count_side1 <= 32'd0;
            track_load_complete <= 1'b0;
	            // bit_count is now a wire (combinational mux), no reset needed
	            sd_buff_din <= 8'h00;
	            have_info <= 1'b0;
	            have_tmap <= 1'b0;
	            have_trks <= 1'b0;
	            scan_blocks <= 16'd0;
	            hdr_pos <= 4'd0;
	            chunk_hdr_pos <= 3'd0;
	            chunk_id <= 32'd0;
	            chunk_size_acc <= 32'd0;
	            chunk_left <= 32'd0;
	            chunk_index <= 32'd0;
	            info_version <= 8'd0;
	            info_disk_type <= 8'd0;
	            info_bit_timing <= 8'd0;
	            scan_failed <= 1'b0;
	        end else begin

            // Default signals
            meta_we <= 0;
            track_load_we <= 0;
            track_load_complete <= 1'b0;  // Default low, pulse high when track load finishes
            // SD requests are level-based in the MiSTer-style block device interface.
            // Assert a request only while we are waiting for `sd_ack` to go high, then
            // deassert during the transfer to avoid re-triggering when the transfer ends.
            sd_rd <= 1'b0;
            sd_wr <= 1'b0;
            sd_buff_din <= 8'h00;

            // bit_count is now combinational (assigned above), no registered assignment needed

            // Debug: show bit_count selection when track_id changes
            if (IS_35_INCH && track_id != last_debug_track_id) begin
                $display("WOZ_BIT_COUNT: track_id=%0d track_id[0]=%0d -> selecting %s (side0=%0d side1=%0d)",
                         track_id, track_id[0],
                         track_id[0] ? "side1" : "side0",
                         bit_count_side0, bit_count_side1);
                last_debug_track_id <= track_id;
            end

            // Default: ready when the selected side is cached for the current track_id
            if (IS_35_INCH) begin
                ready <= woz_valid && (state == S_IDLE) &&
                         ((track_id[0] ? current_track_id_side1 : current_track_id_side0) == track_id);
            end else begin
                ready <= woz_valid && (state == S_IDLE) && (current_track_id_side0 == track_id);
            end
            
	            // Mount detection
	            if (img_mounted && !prev_mounted) begin
	                state <= S_DETECT;
	                ready <= 0;
	                busy <= 1;
	                woz_valid <= 0;
	                dirty <= 0;
	                current_track_id_side0 <= 8'hFF;
	                current_track_id_side1 <= 8'hFF;
	                bit_count_side0 <= 32'd0;
	                bit_count_side1 <= 32'd0;
	                // We will load the requested track after parsing metadata.
	                pending_track_id <= track_id;
	                load_side <= track_id[0];
	                loading_second_side <= 1'b0;
	                target_physical_track <= track_id[7:1];
	                track_load_side <= 1'b0;
	                have_info <= 1'b0;
	                have_tmap <= 1'b0;
	                have_trks <= 1'b0;
	                scan_blocks <= 16'd0;
	                hdr_pos <= 4'd0;
	                chunk_hdr_pos <= 3'd0;
	                chunk_id <= 32'd0;
	                chunk_size_acc <= 32'd0;
	                chunk_left <= 32'd0;
	                chunk_index <= 32'd0;
	                info_version <= 8'd0;
	                info_disk_type <= 8'd0;
	                info_bit_timing <= 8'd0;
	                scan_failed <= 1'b0;
	            end
	            // Unmount: drop validity immediately.
	            if (!img_mounted && prev_mounted) begin
	                woz_valid <= 1'b0;
	                ready <= 1'b0;
	                busy <= 1'b0;
	                current_track_id_side0 <= 8'hFF;
	                current_track_id_side1 <= 8'hFF;
	                bit_count_side0 <= 32'd0;
	                bit_count_side1 <= 32'd0;
	                track_load_side <= 1'b0;
	                have_info <= 1'b0;
	                have_tmap <= 1'b0;
	                have_trks <= 1'b0;
	                state <= S_INIT;
	                scan_failed <= 1'b0;
	            end
	            prev_mounted <= img_mounted;
            
            // Set dirty flag on bit writes
            if (bit_we) dirty <= 1;
            
            // State Machine
            case (state)
	                S_INIT: begin
	                    busy <= 0;
	                    ready <= 0;
	                    if (img_mounted && !scan_failed) begin
	                        state <= S_DETECT;
	                        $display("WOZ_CTRL: Mount detected, starting WOZ scan");
	                    end
	                end
	                
	                S_DETECT: begin
	                    // Prepare to scan WOZ header/chunks from start of file.
	                    state <= S_SCAN_WOZ;
	                    sd_lba <= 32'd0;
	                    scan_blocks <= 16'd0;
	                    if (!sd_ack) sd_rd <= 1'b1;
	                end

	                S_SCAN_WOZ: begin
	                    // Assert sd_rd while waiting for ack, but NOT when completing a transfer
	                    // (completing happens when sd_ack just fell, sd_ack is 0 but we shouldn't
	                    // trigger another read immediately)
	                    if (!sd_ack && !(old_ack && transfer_active)) begin
	                        sd_rd <= 1'b1;
	                    end
	                    // Only count block completion if we had an active transfer
	                    if (old_ack && !sd_ack && transfer_active) begin
	                        scan_blocks <= scan_blocks + 1'd1;
	                        if (parser_done) begin
	                            woz_valid <= 1'b1;
	                            busy <= 0;
	                            state <= S_IDLE;
	                            $display("WOZ_CTRL: Parsed INFO/TMAP/TRKS (ver=%0d type=%0d timing=%0d), entering IDLE",
	                                     info_version, info_disk_type, info_bit_timing);
	                            pending_track_id <= track_id;
	                            load_side <= track_id[0];
	                        end else if (scan_blocks >= SCAN_BLOCK_LIMIT) begin
	                            woz_valid <= 1'b0;
	                            busy <= 0;
	                            state <= S_INIT;
	                            scan_failed <= 1'b1;
	                            $display("WOZ_CTRL: ERROR: WOZ scan limit reached without required chunks (INFO=%0d TMAP=%0d TRKS=%0d)",
	                                     have_info, have_tmap, have_trks);
	                        end else begin
	                            sd_lba <= sd_lba + 1'd1;
	                        end
	                    end
	                end
                
                S_IDLE: begin
                    busy <= 0;

                    // Check for Track Change
                    if (IS_35_INCH) begin
                        // 3.5" DUAL-SIDE LOADING:
                        // When physical track changes (track_id[7:1]), load BOTH sides.
                        // When only side bit changes (SEL toggle), use cached data - no load.
                        // This prevents thrashing when ROM polls status via SEL toggles.

                        reg [6:0] requested_physical;
                        reg [6:0] cached_physical_s0;
                        reg [6:0] cached_physical_s1;
                        reg       side0_cached;
                        reg       side1_cached;
                        reg       both_sides_cached;

                        requested_physical = track_id[7:1];
                        cached_physical_s0 = current_track_id_side0[7:1];
                        cached_physical_s1 = current_track_id_side1[7:1];

                        // Track-side cache validity
                        side0_cached = (current_track_id_side0 == {requested_physical, 1'b0});
                        side1_cached = (current_track_id_side1 == {requested_physical, 1'b1});
                        both_sides_cached = side0_cached && side1_cached;

                        if (!both_sides_cached) begin
                            // Physical track change - need to load both sides
                            target_physical_track <= requested_physical;
                            loading_second_side <= 1'b0;
                            // If the requested side is already cached, load the other side first.
                            // This avoids overwriting the active side while the ROM is reading it.
                            if (side0_cached && !side1_cached) begin
                                pending_track_id <= {requested_physical, 1'b1};
                                load_side <= 1'b1;
                            end else if (side1_cached && !side0_cached) begin
                                pending_track_id <= {requested_physical, 1'b0};
                                load_side <= 1'b0;
                            end else begin
                                // Neither side cached: start with the requested side
                                pending_track_id <= track_id;
                                load_side <= track_id[0];
                            end
                            $display("WOZ_CTRL: Physical track change: %0d -> %0d (loading both sides)",
                                     cached_physical_s0, requested_physical);

                            // If dirty, save first (writes not used in current sim, but keep behavior)
                            if (dirty && woz_valid) begin
                                state <= S_SAVE_TRACK;
                                busy <= 1;
                                sd_lba <= {16'b0, trk_start_block};
                                blocks_processed <= 0;
                                old_ack <= sd_ack;  // Prevent spurious falling edge detection
                                sd_wr <= 1;
                                $display("WOZ_CTRL: Track dirty, saving before seek");
                            end else begin
                                state <= S_SEEK_LOOKUP;
                                busy <= 1;
                                blocks_processed <= 0;
                            end
                        end
                        // else: both sides cached, SEL toggle just uses mux - no action needed
                    end else begin
                        // 5.25" SINGLE-SIDED:
                        // Only one side, simpler logic
                        if (track_id != current_track_id_side0) begin
                            pending_track_id <= track_id;
                            load_side <= 1'b0;
                            loading_second_side <= 1'b0;  // Not used for 5.25" but keep clean
                            $display("WOZ_CTRL: Seek request: %0d -> %0d", current_track_id_side0, track_id);

                            // If dirty, save first
                            if (dirty && woz_valid) begin
                                state <= S_SAVE_TRACK;
                                busy <= 1;
                                sd_lba <= {16'b0, trk_start_block};
                                blocks_processed <= 0;
                                old_ack <= sd_ack;  // Prevent spurious falling edge detection
                                sd_wr <= 1;
                                $display("WOZ_CTRL: Track %0d is dirty, saving before seek", current_track_id_side0);
                            end else begin
                                state <= S_SEEK_LOOKUP;
                                busy <= 1;
                                blocks_processed <= 0;
                            end
                        end
                    end
                end
                
                // Lookup TMAP and TRKS
	                S_SEEK_LOOKUP: begin
	                    case (blocks_processed)
	                        0: begin
	                             // Set Addr for cached TMAP
	                             // For both 3.5" and 5.25" disks: track_id IS the TMAP index
	                             // (The IIgs sends the TMAP index directly, not {cylinder,side})
	                             meta_read_addr <= META_TMAP_BASE + {3'b0, pending_track_id};
	                             blocks_processed <= 1;
	                        end
                        1: begin // RAM is fetching TMAP
                             blocks_processed <= 2;
                        end
                        2: begin
                             // meta_read_data is TMAP[id]
                             reg [7:0] trks_index;
                             trks_index = meta_read_data;
                             
                             if (trks_index == 8'hFF) begin
                                 $display("WOZ_CTRL: Track %0d is empty (FF in TMAP)", pending_track_id);
                                 trk_block_count <= 0;
                                 trk_bit_count <= 0;
                                 // Store empty track info to appropriate side
                                 if (IS_35_INCH && pending_track_id[0]) begin
                                     current_track_id_side1 <= pending_track_id;
                                     bit_count_side1 <= 32'd0;
                                 end else begin
                                     current_track_id_side0 <= pending_track_id;
                                     bit_count_side0 <= 32'd0;
                                 end
                                 dirty <= 0;

                                 // 3.5" DUAL-SIDE: Even for empty tracks, need to check/load side 1
                                 if (IS_35_INCH && !loading_second_side) begin
                                     loading_second_side <= 1'b1;
                                     pending_track_id <= {target_physical_track, 1'b1};
                                     load_side <= 1'b1;
                                     blocks_processed <= 0;
                                     $display("WOZ_CTRL: Side 0 empty, checking side 1 for physical track %0d",
                                              target_physical_track);
                                     // Stay in S_SEEK_LOOKUP, will restart from step 0
                                 end else begin
                                     state <= S_IDLE;
                                     busy <= 0;
                                     loading_second_side <= 1'b0;
                                 end
	                             end else begin
	                                 $display("WOZ_CTRL: Track %0d maps to TRKS entry %0d", pending_track_id, trks_index);
	                                 // Start reading TRK entry (StartBlock, BlockCount, BitCount)
	                                 meta_read_addr <= META_TRKS_BASE + {trks_index, 3'b000}; // Byte 0
	                                 blocks_processed <= 3;
	                             end
	                        end
                        3: begin // Wait for TRK entry read (StartBlock LSB)
                             blocks_processed <= 4;
                        end
                        4: begin
                             trk_start_block[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 1
                             blocks_processed <= 5;
                        end
                        5: begin // Wait for Byte 1
                             blocks_processed <= 6;
                        end
                        6: begin
                             trk_start_block[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 2
                             blocks_processed <= 7;
                        end
                        7: begin // Wait for Byte 2
                             blocks_processed <= 8;
                        end
                        8: begin
                             trk_block_count[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 3
                             blocks_processed <= 9;
                        end
                        9: begin // Wait for Byte 3
                             blocks_processed <= 10;
                        end
                        10: begin
                             trk_block_count[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 4
                             blocks_processed <= 11;
                        end
                        11: begin // Wait for Byte 4
                             blocks_processed <= 12;
                        end
                        12: begin
                             trk_bit_count[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 5
                             blocks_processed <= 13;
                        end
                        13: begin // Wait for Byte 5
                             blocks_processed <= 14;
                        end
                        14: begin
                             trk_bit_count[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 6
                             blocks_processed <= 15;
                        end
                        15: begin // Wait for Byte 6
                             blocks_processed <= 16;
                        end
                        16: begin
                             trk_bit_count[23:16] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1; // -> Byte 7
                             blocks_processed <= 17;
                        end
                        17: begin // Wait for Byte 7
                             blocks_processed <= 18;
                        end
                        18: begin
                             trk_bit_count[31:24] <= meta_read_data;
                             
                             // Done reading
                             blocks_processed <= 19;
                        end
                        19: begin
                             $display("WOZ_CTRL: Track Info: StartBlock=%0d BlockCount=%0d BitCount=%0d",
                                      trk_start_block, trk_block_count, trk_bit_count);
                             // Start Loading Track
                             state <= S_READ_TRACK;
                             sd_lba <= {16'b0, trk_start_block};
                             blocks_processed <= 0; // Reset for block counting
                             old_ack <= sd_ack;  // Prevent spurious falling edge detection on state entry
                             track_load_side <= load_side; // Latch side before DMA begins
                             if (!sd_ack) sd_rd <= 1'b1;
                        end
                    endcase
                end
                
                S_READ_TRACK: begin
                    // IMPORTANT: Do NOT abort track loads when physical track changes!
                    // During fast seeks (boot-time seeking from track 0 to ~45), the ROM
                    // steps rapidly through intermediate tracks. If we abort and restart
                    // on each step, we never complete any load and the boot hangs.
                    //
                    // Instead, continue loading the current track. When the load completes
                    // (in S_IDLE), we'll see the new track_id and start loading it.
                    // The ROM doesn't expect valid data while stepping anyway - it only
                    // reads after settle time. bit_count returning 0 for non-cached tracks
                    // is fine during the seek phase.
                    //
                    // (The old abort logic is commented out below for reference)
                    // if (IS_35_INCH && (track_id[7:1] != target_physical_track) && (track_id != pending_track_id)) begin
                    //     $display("WOZ_CTRL: Track change during load (pending=%0d target_phys=%0d -> req=%0d), aborting load",
                    //              pending_track_id, target_physical_track, track_id);
                    //     ...
                    // end
                    // If only the side bit changes while loading the same physical track:
                    // ONLY restart if the requested side is NOT already cached.
                    // The ROM frequently toggles SEL to read status; if the requested side
                    // is already cached, just continue loading the other side.
                    // This prevents thrashing where side changes cause endless restarts.
                    if (IS_35_INCH && (track_id[7:1] == target_physical_track) && (track_id != pending_track_id)) begin
                        // Check if the requested side is already cached
                        reg requested_side_cached;
                        requested_side_cached = (track_id[0] == 1'b0) ? (current_track_id_side0 == track_id)
                                                                      : (current_track_id_side1 == track_id);
                        if (!requested_side_cached) begin
                            $display("WOZ_CTRL: Side change during load (pending=%0d -> req=%0d), restarting load",
                                     pending_track_id, track_id);
                            pending_track_id <= track_id;
                            load_side <= track_id[0];
                            loading_second_side <= 1'b0;
                            state <= S_SEEK_LOOKUP;
                            busy <= 1'b1;
                            sd_rd <= 1'b0;
                            blocks_processed <= 0;
                            old_ack <= sd_ack;
                            transfer_active <= 1'b0;
                        end
                        // else: requested side is cached, continue loading the other side
                    end

                    // Assert sd_rd while waiting for ack, but NOT when completing a transfer
                    if (!sd_ack && !(old_ack && transfer_active)) begin
                        sd_rd <= 1'b1;
                    end
                    // Only count block completion if we had an active transfer
                    // This prevents spurious falling edge detection on state entry
                    if (old_ack && !sd_ack && transfer_active) begin
                        // Block complete
                        $display("WOZ_DMA: Block %0d complete for track %0d (lba=%0d)",
                                 blocks_processed, pending_track_id, sd_lba);
                        blocks_processed <= blocks_processed + 1;
                        if (blocks_processed + 1 >= trk_block_count) begin
                            // Track load complete - store to appropriate RAM
                            $display("WOZ_CTRL: Track %0d load complete (%0d blocks)", pending_track_id, blocks_processed + 1);

                            if (IS_35_INCH && pending_track_id[0]) begin
                                current_track_id_side1 <= pending_track_id;
                                bit_count_side1 <= trk_bit_count;
                                $display("WOZ_CTRL: Stored track %0d to side1 RAM, bit_count=%0d", pending_track_id, trk_bit_count);
                            end else begin
                                current_track_id_side0 <= pending_track_id;
                                bit_count_side0 <= trk_bit_count;
                                $display("WOZ_CTRL: Stored track %0d to side0 RAM, bit_count=%0d", pending_track_id, trk_bit_count);
                            end

                            // 3.5" DUAL-SIDE: After first side, load the other side
                            if (IS_35_INCH && !loading_second_side) begin
                                // First side done, now load the opposite side
                                loading_second_side <= 1'b1;
                                pending_track_id <= {target_physical_track, ~pending_track_id[0]};
                                load_side <= ~pending_track_id[0];
                                state <= S_SEEK_LOOKUP;
                                blocks_processed <= 0;
                                $display("WOZ_CTRL: First side complete, starting other side load for physical track %0d",
                                         target_physical_track);
                            end else begin
                                // 5.25" single-sided OR 3.5" side 1 complete - done!
                                state <= S_IDLE;
                                busy <= 0;
                                loading_second_side <= 1'b0;
                                track_load_complete <= 1'b1;  // Pulse to signal flux_drive to reset position
                                if (IS_35_INCH) begin
                                    $display("WOZ_CTRL: Both sides loaded for physical track %0d", target_physical_track);
                                end else begin
                                    $display("WOZ_CTRL: Track %0d loaded (5.25\")", pending_track_id);
                                end
                            end
                            dirty <= 0;
                        end else begin
                            // Next block
                            sd_lba <= sd_lba + 1;
                        end
                    end
                end
                
                S_SAVE_TRACK: begin
                    // Assert sd_wr while waiting for ack, but NOT when completing a transfer
                    if (!sd_ack && !(old_ack && transfer_active)) begin
                        sd_wr <= 1'b1;
                    end
                    // Only count block completion if we had an active transfer
                    if (old_ack && !sd_ack && transfer_active) begin
                        // Block saved
                        blocks_processed <= blocks_processed + 1;
                        if (blocks_processed + 1 >= trk_block_count) begin
                            // Done saving
                            dirty <= 0;
                            // Proceed to Seek the NEW track
                            state <= S_SEEK_LOOKUP; 
                            blocks_processed <= 0; // Reset for lookup
                        end else begin
                            // Next block
                            sd_lba <= sd_lba + 1;
                        end
                    end
                end
                
            endcase
            
            // Data Loading/Saving DMA
            // This runs in parallel with state machine waiting for sd_ack
	            if (sd_ack) begin
	                if (sd_buff_wr) begin // Reading from SD -> RAM
	                     if (state == S_SCAN_WOZ) begin
	                         // Streaming parser: process file bytes sequentially.
	                         reg [7:0] b;
	                         b = sd_buff_dout;

	                         if (hdr_pos < 4'd12) begin
	                             // Header format:
	                             // 0..3  = "WOZ1"/"WOZ2"
	                             // 4..7  = 0xFF 0x0A 0x0D 0x0A
	                             // 8..11 = CRC32 (ignored)
	                             // 12..15 = reserved (ignored)
	                             hdr_pos <= hdr_pos + 1'd1;
	                         end else begin
	                             // Parse chunks: [id:4][size:4][data:size]
	                             if (chunk_left == 32'd0) begin
	                                 // Chunk header
	                                 if (chunk_hdr_pos < 3'd4) begin
	                                     chunk_id <= {chunk_id[23:0], b};
	                                     chunk_hdr_pos <= chunk_hdr_pos + 1'd1;
	                                 end else begin
	                                     // size is little-endian
	                                     chunk_size_acc <= chunk_size_acc | ({{24{1'b0}}, b} << ((chunk_hdr_pos - 3'd4) * 8));
	                                     chunk_hdr_pos <= chunk_hdr_pos + 1'd1;
	                                     if (chunk_hdr_pos == 3'd7) begin
	                                         chunk_left <= chunk_size_acc | ({{24{1'b0}}, b} << 24);
	                                         chunk_index <= 32'd0;
	                                         chunk_hdr_pos <= 3'd0;
	                                         chunk_size_acc <= 32'd0;
	                                     end
	                                 end
	                             end else begin
	                                 // Chunk data
	                                 if (chunk_id == "INFO") begin
	                                     if (chunk_index == 32'd0) begin
	                                         info_version <= b;
	                                         have_info <= 1'b1;
	                                     end
	                                     if (chunk_index == 32'd1) info_disk_type <= b;
	                                     // WOZ2: bit_timing byte is at offset 39 within INFO chunk:
	                                     // ver(0), disk_type(1), wp(2), sync(3), cleaned(4), creator(5..36),
	                                     // sides(37), boot_type(38), bit_timing(39)
	                                     if (chunk_index == 32'd39) info_bit_timing <= b;
	                                 end else if (chunk_id == "TMAP") begin
	                                     if (chunk_index < 32'd160) begin
	                                         meta_addr <= META_TMAP_BASE + chunk_index[10:0];
	                                         meta_din <= b;
	                                         meta_we <= 1'b1;
	                                         // Debug: show first few TMAP entries and entry 80
	                                         if (chunk_index < 5 || chunk_index == 80) begin
	                                             $display("TMAP_SCAN: TMAP[%0d] = %0d (0x%02X)", chunk_index, b, b);
	                                         end
	                                         if (chunk_index == 32'd159) have_tmap <= 1'b1;
	                                     end
	                                 end else if (chunk_id == "TRKS") begin
	                                     if (chunk_index < 32'd1280) begin
	                                         meta_addr <= META_TRKS_BASE + chunk_index[10:0];
	                                         meta_din <= b;
	                                         meta_we <= 1'b1;
	                                         if (chunk_index == 32'd1279) have_trks <= 1'b1;
	                                     end
	                                 end

	                                 chunk_index <= chunk_index + 1'd1;
	                                 chunk_left <= chunk_left - 1'd1;
	                                 if (chunk_left == 32'd1) begin
	                                     // End of chunk; next bytes start a new header.
	                                     chunk_id <= 32'd0;
	                                     chunk_hdr_pos <= 3'd0;
	                                     chunk_size_acc <= 32'd0;
	                                 end
	                             end
	                         end
	                     end else if (state == S_READ_TRACK) begin
	                         // Track RAM Address: (blocks_processed * 512) + sd_buff_addr
	                         // blocks_processed is 16-bit, sd_buff_addr is 9-bit
	                         track_load_addr <= {blocks_processed[4:0], sd_buff_addr};
	                         track_load_data <= sd_buff_dout;
	                         track_load_we <= 1;
	                         // Debug: log first/last bytes of each block and bytes around problem areas
	                         if (sd_buff_addr == 9'd0 || sd_buff_addr == 9'd511 ||
	                             sd_buff_addr == 9'd1 || sd_buff_addr == 9'd510) begin
	                             $display("WOZ_DMA_DBG: blk=%0d buf_addr=%0d track_addr=%0d data=%02X track=%0d side=%0d",
	                                      blocks_processed, sd_buff_addr,
	                                      {blocks_processed[4:0], sd_buff_addr},
	                                      sd_buff_dout, pending_track_id, load_side);
	                         end
	                         // Debug block 16 (addresses 8192+) where we saw 0x69 issues
	                         if (blocks_processed == 16 && (sd_buff_addr >= 9'd40 && sd_buff_addr <= 9'd60)) begin
	                             $display("WOZ_DMA_BLK16: buf_addr=%0d track_addr=%0d data=%02X",
	                                      sd_buff_addr, {5'd16, sd_buff_addr}, sd_buff_dout);
	                         end
	                     end
	                end else begin // Writing RAM -> SD
                    if (state == S_SAVE_TRACK) begin
                         track_load_addr <= {blocks_processed[4:0], sd_buff_addr}; 
                         if (IS_35_INCH && load_side) begin
                             sd_buff_din <= track_ram_dout1;
                         end else begin
                             sd_buff_din <= track_ram_dout0;
                         end
                    end
                end
            end
        end
    end

endmodule
