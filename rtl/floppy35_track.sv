//
// Apple IIgs 3.5" floppy track read/write interface
//
// Based on floppy_track.sv but adapted for 3.5" disk geometry:
// - 80 tracks per side (7-bit track number)
// - 8-12 sectors per track depending on zone
// - 20 sectors maximum (10240 bytes) per track for padding
// - Side select for double-sided disks
//
// Copyright (c) 2016 Sorgelig (original floppy_track)
// Modified 2024 for 3.5" support
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//

module floppy35_track
(
	input         clk,
	input         reset,

	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         change,
	input         mount,
	input   [6:0] track,      // 7-bit for 80 tracks per side
	input         side,       // Side select (0 or 1)
	output reg    ready = 0,
	input         active,

	input  [13:0] ram_addr,   // 14-bit for 10240-byte tracks
	output  [7:0] ram_do,
	input   [7:0] ram_di,
	input         ram_we,
	output reg    busy
);

assign sd_lba = lba;

// Track layout for 3.5" disk:
// - 80 tracks per side, 2 sides = 160 tracks total
// - Each track is padded to 20 sectors (10240 bytes)
// - Track LBA = (side * 80 + track) * 20
// Total image size: 160 * 20 * 512 = 1,638,400 bytes (1.6MB)

reg  [31:0] lba;
reg   [4:0] rel_lba;        // 5-bit for 20 sectors per track
reg         mount_pending;  // Track that we need to set ready after first load

always @(posedge clk) begin
	reg old_ack;
	reg [6:0] cur_track;
	reg       cur_side;
	reg old_change;
	reg saving;
	reg dirty;

	old_change <= change;
	old_ack <= sd_ack;

    if(sd_ack) {sd_rd,sd_wr} <= 0;

    if(ready && ram_we) dirty <= 1;

`ifdef SIMULATION
    if (sd_buff_wr & sd_ack) begin
        $display("FLOPPY35 DMA: write rel_lba=%0d addr=%03h data=%02h", rel_lba, sd_buff_addr, sd_buff_dout);
    end
`endif
`ifdef SIMULATION
    if (change && ~old_change) begin
        $display("FLOPPY35: change edge detected (mount=%0d)", mount);
    end
`endif

    if(~old_change & change) begin
        // Don't set ready yet - wait for first track to load
        // This prevents reading uninitialized BRAM data
        ready <= 1'b0;
        mount_pending <= mount;  // Remember we want to be ready after load
        cur_track <= 7'b1111111;
        cur_side <= 1'b0;
        busy  <= 0;
        sd_rd <= 0;
        sd_wr <= 0;
        saving<= 0;
        dirty <= 0;
`ifdef SIMULATION
        $display("FLOPPY35: change-> mount_pending=%0d (ready deferred until track loaded)", mount);
`endif
    end
	else
	if(reset) begin
		cur_track <= 7'b1111111;
		cur_side <= 1'b0;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
		dirty <= 0;
		ready <= 0;
		mount_pending <= 0;
	end
	else

    if(busy) begin
        if(old_ack && ~sd_ack) begin
            if(rel_lba != 5'd19) begin    // 20 sectors per track (0-19)
                lba <= lba + 1'd1;
                rel_lba <= rel_lba + 1'd1;
                if(saving) sd_wr <= 1;
                    else sd_rd <= 1;
            end
            else
            if(saving && ((cur_track != track) || (cur_side != side))) begin
                saving <= 0;
                cur_track <= track;
                cur_side <= side;
                rel_lba <= 0;
                // LBA = (side * 80 + track) * 20
                lba <= ({24'd0, side} * 32'd80 + {25'd0, track}) * 32'd20;
                sd_rd <= 1;
            end
            else
            begin
                busy <= 0;
                dirty <= 0;
                // If this was the initial track load after mount, now set ready
                if (mount_pending) begin
                    ready <= 1'b1;
                    mount_pending <= 1'b0;
`ifdef SIMULATION
                    $display("FLOPPY35: Track loaded, now setting ready=1");
`endif
                end
            end
        end
    end
    else
    // Only reload track when:
    // 1. Disk just mounted and cur_track is invalid (initial load) - use mount_pending for this
    // 2. Dirty and inactive (save modified data) - use ready for this
    if((mount_pending && cur_track == 7'b1111111) || (ready && dirty && ~active))
        if (dirty && cur_track != 7'b1111111) begin
            saving <= 1;
            // LBA = (cur_side * 80 + cur_track) * 20
            lba <= ({24'd0, cur_side} * 32'd80 + {25'd0, cur_track}) * 32'd20;
            rel_lba <= 0;
            sd_wr <= 1;
            busy <= 1;
`ifdef SIMULATION
            $display("FLOPPY35: SAVE side=%0d track=%0d (LBA base=%0d) dirty=%0d active=%0d",
                     cur_side, cur_track,
                     (cur_side * 80 + cur_track) * 20, dirty, active);
`endif
        end
        else
        begin
            saving <= 0;
            cur_track <= track;
            cur_side <= side;
            rel_lba <= 0;
            // LBA = (side * 80 + track) * 20
            lba <= ({24'd0, side} * 32'd80 + {25'd0, track}) * 32'd20;
            sd_rd <= 1;
            busy <= 1;
            dirty <= 0;
`ifdef SIMULATION
            $display("FLOPPY35: load side=%0d track=%0d (LBA base=%0d) cur_track=%0d dirty=%0d active=%0d",
                     side, track, (side * 80 + track) * 20, cur_track, dirty, active);
`endif
        end
end

// 14-bit BRAM for 10240-byte tracks (actually 16384 bytes due to 2^14)
bram #(.width_a(8), .widthad_a(14)) floppy35_dpram
(
        .clock_a(clk),
        .address_a({rel_lba, sd_buff_addr}),  // 5-bit rel_lba + 9-bit sd_buff_addr = 14 bits
        .wren_a(sd_buff_wr & sd_ack),
        .data_a(sd_buff_dout),
        .q_a(sd_buff_din),

        .clock_b(clk),
        .address_b(ram_addr),
        .wren_b(ram_we),
        .data_b(ram_di),
        .q_b(ram_do),
        .enable_a(1'b1),
        .enable_b(1'b1)
);

`ifdef SIMULATION
reg [13:0] prev_ram_addr;
reg [13:0] prev2_ram_addr;  // 2-cycle delay to match BRAM latency
reg prev_ram_we;
always @(posedge clk) begin
    prev_ram_addr <= ram_addr;
    prev2_ram_addr <= prev_ram_addr;
    prev_ram_we <= ram_we;
    // Debug track memory reads (show prev2 address with current data due to BRAM 1-cycle latency)
    if (prev_ram_addr != prev2_ram_addr && !prev_ram_we) begin
        $display("FTRACK35: READ addr=%04h -> %02h", prev_ram_addr, ram_do);
    end
    // Debug track memory writes
    if (ram_we && !prev_ram_we) begin
        $display("FTRACK35: WRITE addr=%04h <- %02h", ram_addr, ram_di);
    end
end
`endif

endmodule
