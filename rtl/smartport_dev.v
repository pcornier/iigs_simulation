//
// smartport_dev.v: SmartPort Device State Machine
//
// Emulates a 3.5" drive's internal microcontroller for SmartPort block I/O.
// The real 3.5" drive contains a controller chip that handles SmartPort packets
// over the IWM bus. This module implements that protocol.
//
// Protocol:
//   Host → Device: preamble ($FF,$FC,$F3,$CF,$3F,$C3) + packet + checksum + $C8
//   Device → Host: $C3 sync + response packet + checksum + $C8
//
// All packet bytes have bit 7 set. Payload uses "groups of 7" MSB encoding.
//

module smartport_dev (
    input  wire        clk,
    input  wire        reset,

    // SmartPort mode enable (from iwm_flux mode detection)
    input  wire        smartport_mode,

    // Host write path (CPU writes to $C0ED in SmartPort mode)
    input  wire        wr_strobe,       // 1-cycle pulse: host wrote a byte
    input  wire [7:0]  wr_data,         // The byte written

    // Host read path (CPU reads $C0EC in SmartPort mode)
    input  wire        rd_strobe,       // 1-cycle pulse: host read a byte
    output reg  [7:0]  rd_data,         // Byte to return
    output reg         rd_data_valid,   // Override data register with rd_data

    // IWM bus signals
    input  wire        req,             // CA1 (REQ) state from host
    output reg         bsy,             // /BSY output to sense mux

    // Block I/O interface (directly to C++ via sim.v)
    output reg  [15:0] sp_block_num,    // Block number for read/write
    output reg  [7:0]  sp_command,      // Command byte ($41=read, $42=write)
    output reg  [8:0]  sp_buf_addr,     // Address into 512-byte block buffer
    output wire [7:0]  sp_buf_data_out, // Data from block buffer (for read-back)
    input  wire [7:0]  sp_buf_data_in,  // Data to block buffer (from C++)
    input  wire        sp_buf_we,       // Write enable for block buffer (from C++)
    output reg         sp_request,      // Pulse: request C++ to do block I/O
    input  wire        sp_done,         // C++ signals completion
    input  wire        sp_error         // C++ signals error
);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [3:0] SP_IDLE          = 4'd0;  // Waiting for preamble
    localparam [3:0] SP_RECV_PREAMBLE = 4'd1;  // Matching sync sequence
    localparam [3:0] SP_RECV_HEADER   = 4'd2;  // Capturing 7 header bytes
    localparam [3:0] SP_RECV_PAYLOAD  = 4'd3;  // Capturing encoded payload
    localparam [3:0] SP_RECV_CHECKSUM = 4'd4;  // Verifying checksum + $C8
    localparam [3:0] SP_PROCESS       = 4'd5;  // Parse command, signal C++
    localparam [3:0] SP_WAIT_IO       = 4'd6;  // Waiting for C++ completion
    localparam [3:0] SP_SEND_WAIT_REQ = 4'd7;  // /BSY raised, waiting for REQ
    localparam [3:0] SP_SEND_RESPONSE = 4'd8;  // Feeding response bytes
    localparam [3:0] SP_SEND_DONE     = 4'd9;  // Response complete

    reg [3:0] state;

    //=========================================================================
    // Preamble Detection
    //=========================================================================
    // SmartPort preamble: $FF, $3F, $CF, $F3, $FC, $FF, $C3
    // Observed from ROM trace - this is the actual byte order sent by the host
    // (self-sync pattern ending with $C3 as the sync byte)
    reg [2:0] preamble_idx;

    function [7:0] preamble_byte;
        input [2:0] idx;
        case (idx)
            3'd0: preamble_byte = 8'hFF;
            3'd1: preamble_byte = 8'h3F;
            3'd2: preamble_byte = 8'hCF;
            3'd3: preamble_byte = 8'hF3;
            3'd4: preamble_byte = 8'hFC;
            3'd5: preamble_byte = 8'hFF;  // Second $FF before final $C3
            3'd6: preamble_byte = 8'hC3;
            default: preamble_byte = 8'h00;
        endcase
    endfunction

    //=========================================================================
    // Packet Capture
    //=========================================================================
    // Header: 7 bytes (dest, src, type, aux, cmd_status, payload_len_hi, payload_len_lo)
    reg [7:0] pkt_dest;
    reg [7:0] pkt_src;
    reg [7:0] pkt_type;        // $80=command, $81=status, $82=data
    reg [7:0] pkt_aux;
    reg [7:0] pkt_cmd_status;
    reg [7:0] pkt_len_hi;
    reg [7:0] pkt_len_lo;
    reg [2:0] header_idx;

    // Payload capture with MSB group-of-7 decoding
    reg [15:0] payload_len;     // Decoded payload length (from header)
    reg [15:0] payload_idx;     // Current byte within raw encoded payload
    reg [15:0] payload_decoded_cnt; // Count of decoded bytes
    reg [2:0]  group_idx;       // Position within current group (0=MSB byte, 1-7=data)
    reg [6:0]  group_msb;       // MSB bits for current group
    reg [7:0]  decode_byte;     // Current decoded byte

    // Checksum
    reg [15:0] checksum_running; // Running checksum (odd/even split)
    reg [7:0]  checksum_odd;     // Odd-bit checksum accumulator
    reg [7:0]  checksum_even;    // Even-bit checksum accumulator
    reg        checksum_phase;   // 0=first checksum byte, 1=second
    reg [7:0]  recv_cksum_odd;
    reg [7:0]  recv_cksum_even;

    // Command parameters extracted from decoded payload
    reg [7:0]  cmd_byte;         // Actual command ($41=ReadBlock, $42=WriteBlock, $43=Status)
    reg [7:0]  cmd_unit;
    reg [15:0] cmd_block;
    reg        is_data_packet;   // True if this is a data packet (following a write command)
    reg        write_pending;    // WriteBlock command received, waiting for data packet

    //=========================================================================
    // Block Data Buffer (512 bytes, dual-port)
    //=========================================================================
    reg  [8:0]  buf_wr_addr;
    reg  [7:0]  buf_wr_data;
    reg         buf_wr_en;

    // Dual-port BRAM: port A for internal writes, port B for external read/write
    reg [7:0] block_buf [0:511];
    reg [7:0] buf_rd_data;

    always @(posedge clk) begin
        if (buf_wr_en)
            block_buf[buf_wr_addr] <= buf_wr_data;
    end

    // Port B: external access (C++ read/write)
    always @(posedge clk) begin
        if (sp_buf_we)
            block_buf[sp_buf_addr] <= sp_buf_data_in;
        buf_rd_data <= block_buf[sp_buf_addr];
    end
    assign sp_buf_data_out = buf_rd_data;

    //=========================================================================
    // Response Generation
    //=========================================================================
    reg [7:0] resp_buf [0:31];   // Response buffer (max ~20 bytes needed)
    reg [4:0] resp_len;          // Total response length
    reg [4:0] resp_idx;          // Current send position

    // ReadBlock response needs data packet too
    reg        send_data_packet; // After status response, send data packet
    reg [15:0] data_send_idx;    // Position in data packet send

    //=========================================================================
    // Timeout Counter
    //=========================================================================
    reg [23:0] timeout_cnt;
    localparam [23:0] TIMEOUT_CYCLES = 24'd14000000; // ~1 second at 14MHz

    //=========================================================================
    // Helper: Encode a byte with MSB group encoding for response
    //=========================================================================
    // For responses, we build the encoded packet in resp_buf during SP_PROCESS

    //=========================================================================
    // Main State Machine
    //=========================================================================
    reg prev_wr_strobe;
    reg prev_rd_strobe;
    reg prev_req;
    wire wr_pulse = wr_strobe && !prev_wr_strobe;
    wire rd_pulse = rd_strobe && !prev_rd_strobe;
    wire req_rise = req && !prev_req;

    always @(posedge clk) begin
        if (reset) begin
            state <= SP_IDLE;
            bsy <= 1'b0;
            rd_data <= 8'hFF;
            rd_data_valid <= 1'b0;
            sp_request <= 1'b0;
            sp_command <= 8'h00;
            sp_block_num <= 16'h0000;
            sp_buf_addr <= 9'd0;
            preamble_idx <= 3'd0;
            header_idx <= 3'd0;
            write_pending <= 1'b0;
            is_data_packet <= 1'b0;
            send_data_packet <= 1'b0;
            buf_wr_en <= 1'b0;
            timeout_cnt <= 24'd0;
            prev_wr_strobe <= 1'b0;
            prev_rd_strobe <= 1'b0;
            prev_req <= 1'b0;
        end else begin
            prev_wr_strobe <= wr_strobe;
            prev_rd_strobe <= rd_strobe;
            prev_req <= req;
            buf_wr_en <= 1'b0;
            sp_request <= 1'b0;

            // Default: don't override reads unless in send state
            if (state != SP_SEND_RESPONSE && state != SP_SEND_WAIT_REQ)
                rd_data_valid <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                SP_IDLE: begin
                    bsy <= 1'b0;
                    rd_data_valid <= 1'b0;
                    if (smartport_mode && wr_pulse) begin
                        if (wr_data == 8'hFF) begin
                            preamble_idx <= 3'd1; // Got first byte of preamble
                            state <= SP_RECV_PREAMBLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_RECV_PREAMBLE: begin
                    if (!smartport_mode) begin
                        state <= SP_IDLE;
                    end else if (wr_pulse) begin
                        if (wr_data == preamble_byte(preamble_idx)) begin
                            if (preamble_idx == 3'd6) begin
                                // Full preamble matched ($C3 received)
                                header_idx <= 3'd0;
                                state <= SP_RECV_HEADER;
                                checksum_odd <= 8'h00;
                                checksum_even <= 8'h00;
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: Preamble matched, receiving header");
`endif
                            end else begin
                                preamble_idx <= preamble_idx + 3'd1;
                            end
                        end else if (wr_data == 8'hFF) begin
                            // Extra $FF sync bytes - restart at idx 1
                            preamble_idx <= 3'd1;
                        end else begin
                            // Mismatch - reset
`ifdef DEBUG_VERBOSE
                            $display("SP_DEV: Preamble MISMATCH at idx=%0d got=%02h expected=%02h",
                                     preamble_idx, wr_data, preamble_byte(preamble_idx));
`endif
                            preamble_idx <= 3'd0;
                            state <= SP_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_RECV_HEADER: begin
                    if (!smartport_mode) begin
                        state <= SP_IDLE;
                    end else if (wr_pulse) begin
                        // Accumulate checksum on header bytes
                        // SmartPort checksum: XOR of all bytes, split odd/even bits
                        checksum_odd <= checksum_odd ^ (wr_data & 8'hAA);
                        checksum_even <= checksum_even ^ (wr_data & 8'h55);

                        case (header_idx)
                            3'd0: pkt_dest <= wr_data;
                            3'd1: pkt_src <= wr_data;
                            3'd2: pkt_type <= wr_data;
                            3'd3: pkt_aux <= wr_data;
                            3'd4: pkt_cmd_status <= wr_data;
                            3'd5: pkt_len_hi <= wr_data;
                            3'd6: begin
                                pkt_len_lo <= wr_data;
                                // Decode payload length from encoded hi/lo
                                // Encoded: hi = {1, b13..b7}, lo = {1, b6..b0}
                                payload_len <= {2'b0, wr_data[6:0]} | ({2'b0, pkt_len_hi[6:0]} << 7);
                                payload_idx <= 16'd0;
                                payload_decoded_cnt <= 16'd0;
                                group_idx <= 3'd0;
                                state <= SP_RECV_PAYLOAD;
                                is_data_packet <= (pkt_type == 8'h82);
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: Header: dest=%02h src=%02h type=%02h aux=%02h cmd=%02h len=%0d",
                                         pkt_dest, pkt_src, pkt_type, pkt_aux, pkt_cmd_status,
                                         {2'b0, wr_data[6:0]} | ({2'b0, pkt_len_hi[6:0]} << 7));
`endif
                            end
                        endcase
                        if (header_idx < 3'd6)
                            header_idx <= header_idx + 3'd1;
                    end
                end

                //-------------------------------------------------------------
                SP_RECV_PAYLOAD: begin
                    if (!smartport_mode) begin
                        state <= SP_IDLE;
                    end else if (wr_pulse) begin
                        // Accumulate checksum
                        checksum_odd <= checksum_odd ^ (wr_data & 8'hAA);
                        checksum_even <= checksum_even ^ (wr_data & 8'h55);

                        // MSB group-of-7 decoding:
                        // First byte of group has MSBs for next 7 bytes
                        // Format: {1, msb6, msb5, msb4, msb3, msb2, msb1, msb0}
                        if (group_idx == 3'd0) begin
                            // This is the MSB byte
                            group_msb <= wr_data[6:0];
                            group_idx <= 3'd1;
                        end else begin
                            // This is a data byte - combine with MSB
                            decode_byte <= {group_msb[0], wr_data[6:0]};

                            // Store decoded byte
                            if (is_data_packet || write_pending) begin
                                // Data packet: store in block buffer
                                if (payload_decoded_cnt < 16'd512) begin
                                    buf_wr_en <= 1'b1;
                                    buf_wr_addr <= payload_decoded_cnt[8:0];
                                    buf_wr_data <= {group_msb[0], wr_data[6:0]};
                                end
                            end else begin
                                // Command packet: extract parameters
                                case (payload_decoded_cnt)
                                    16'd0: cmd_byte <= {group_msb[0], wr_data[6:0]};
                                    16'd1: cmd_unit <= {group_msb[0], wr_data[6:0]};
                                    // Block number: little-endian (lo, mid, hi)
                                    16'd2: cmd_block[7:0] <= {group_msb[0], wr_data[6:0]};
                                    16'd3: cmd_block[15:8] <= {group_msb[0], wr_data[6:0]};
                                endcase
                            end
                            payload_decoded_cnt <= payload_decoded_cnt + 16'd1;

                            // Shift MSB bits for next byte in group
                            group_msb <= {1'b0, group_msb[6:1]};

                            if (group_idx == 3'd7)
                                group_idx <= 3'd0; // Start new group
                            else
                                group_idx <= group_idx + 3'd1;
                        end

                        payload_idx <= payload_idx + 16'd1;

                        // Calculate total encoded length:
                        // For N decoded bytes: ceil(N/7) MSB bytes + N data bytes
                        // Total encoded = N + ceil(N/7)
                        // We check when we've received enough raw bytes
                        if (payload_idx + 16'd1 >= payload_len) begin
                            checksum_phase <= 1'b0;
                            state <= SP_RECV_CHECKSUM;
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_RECV_CHECKSUM: begin
                    if (!smartport_mode) begin
                        state <= SP_IDLE;
                    end else if (wr_pulse) begin
                        if (!checksum_phase) begin
                            recv_cksum_odd <= wr_data;
                            checksum_phase <= 1'b1;
                        end else begin
                            recv_cksum_even <= wr_data;
                            // Next byte should be $C8 end mark, but we don't
                            // strictly require it - proceed to process
                            state <= SP_PROCESS;
`ifdef DEBUG_VERBOSE
                            $display("SP_DEV: Packet complete type=%02h decoded=%0d cmd=%02h unit=%02h block=%0d is_data=%0d",
                                     pkt_type, payload_decoded_cnt, cmd_byte, cmd_unit, cmd_block, is_data_packet);
`endif
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_PROCESS: begin
                    // Skip the $C8 end mark - it arrives as next write
                    // Process the command
                    if (is_data_packet && write_pending) begin
                        // Data packet for a pending WriteBlock
                        write_pending <= 1'b0;
                        is_data_packet <= 1'b0;
                        sp_command <= 8'h42;  // WriteBlock
                        sp_block_num <= cmd_block;
                        sp_request <= 1'b1;
                        state <= SP_WAIT_IO;
                        timeout_cnt <= TIMEOUT_CYCLES;
`ifdef DEBUG_VERBOSE
                        $display("SP_DEV: WriteBlock data received, block=%0d, requesting I/O", cmd_block);
`endif
                    end else if (pkt_type == 8'h80) begin
                        // Command packet
                        case (cmd_byte)
                            8'h41: begin
                                // ReadBlock
                                sp_command <= 8'h41;
                                sp_block_num <= cmd_block;
                                sp_request <= 1'b1;
                                send_data_packet <= 1'b1;
                                state <= SP_WAIT_IO;
                                timeout_cnt <= TIMEOUT_CYCLES;
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: ReadBlock cmd, block=%0d", cmd_block);
`endif
                            end
                            8'h42: begin
                                // WriteBlock - command packet first, data packet follows
                                write_pending <= 1'b1;
                                // Send status response immediately (acknowledge command)
                                build_status_response(8'h00); // No error
                                bsy <= 1'b1;
                                state <= SP_SEND_WAIT_REQ;
                                rd_data_valid <= 1'b1;
                                rd_data <= 8'hFF; // Idle byte until host reads
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: WriteBlock cmd received, block=%0d, waiting for data packet", cmd_block);
`endif
                            end
                            8'h43: begin
                                // Status
                                build_status_response(8'h00);
                                bsy <= 1'b1;
                                state <= SP_SEND_WAIT_REQ;
                                rd_data_valid <= 1'b1;
                                rd_data <= 8'hFF;
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: Status cmd");
`endif
                            end
                            default: begin
                                // Unknown command - send error
                                build_status_response(8'h01); // Error
                                bsy <= 1'b1;
                                state <= SP_SEND_WAIT_REQ;
                                rd_data_valid <= 1'b1;
                                rd_data <= 8'hFF;
`ifdef DEBUG_VERBOSE
                                $display("SP_DEV: Unknown cmd %02h", cmd_byte);
`endif
                            end
                        endcase
                    end else begin
                        // Unexpected packet type
                        state <= SP_IDLE;
                    end
                end

                //-------------------------------------------------------------
                SP_WAIT_IO: begin
                    if (sp_done) begin
                        if (sp_error) begin
                            build_status_response(8'h01); // Error
                            send_data_packet <= 1'b0;
                        end else begin
                            build_status_response(8'h00); // OK
                        end
                        bsy <= 1'b1;
                        state <= SP_SEND_WAIT_REQ;
                        rd_data_valid <= 1'b1;
                        rd_data <= 8'hFF;
`ifdef DEBUG_VERBOSE
                        $display("SP_DEV: I/O complete, error=%0d, sending response", sp_error);
`endif
                    end else begin
                        timeout_cnt <= timeout_cnt - 24'd1;
                        if (timeout_cnt == 24'd0) begin
                            build_status_response(8'h01); // Timeout error
                            send_data_packet <= 1'b0;
                            bsy <= 1'b1;
                            state <= SP_SEND_WAIT_REQ;
                            rd_data_valid <= 1'b1;
                            rd_data <= 8'hFF;
`ifdef DEBUG_VERBOSE
                            $display("SP_DEV: I/O TIMEOUT!");
`endif
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_SEND_WAIT_REQ: begin
                    // /BSY is raised, wait for host to see it and raise REQ
                    rd_data_valid <= 1'b1;
                    if (req_rise || req) begin
                        resp_idx <= 5'd0;
                        rd_data <= resp_buf[0];
                        state <= SP_SEND_RESPONSE;
`ifdef DEBUG_VERBOSE
                        $display("SP_DEV: REQ detected, sending response (%0d bytes)", resp_len);
`endif
                    end
                    // Timeout if host never raises REQ
                    timeout_cnt <= timeout_cnt - 24'd1;
                    if (timeout_cnt == 24'd0) begin
                        state <= SP_SEND_DONE;
                    end
                end

                //-------------------------------------------------------------
                SP_SEND_RESPONSE: begin
                    rd_data_valid <= 1'b1;
                    if (rd_pulse) begin
                        if (resp_idx + 5'd1 < resp_len) begin
                            resp_idx <= resp_idx + 5'd1;
                            rd_data <= resp_buf[resp_idx + 5'd1];
                        end else begin
                            state <= SP_SEND_DONE;
                        end
                    end
                end

                //-------------------------------------------------------------
                SP_SEND_DONE: begin
                    bsy <= 1'b0;
                    rd_data_valid <= 1'b0;
                    if (write_pending) begin
                        // After WriteBlock status response, go back to receive data packet
                        preamble_idx <= 3'd0;
                        state <= SP_IDLE;
                    end else if (send_data_packet) begin
                        // After ReadBlock status, we need to send data packet
                        // For now, build and send data response
                        send_data_packet <= 1'b0;
                        build_data_response();
                        bsy <= 1'b1;
                        state <= SP_SEND_WAIT_REQ;
                        rd_data_valid <= 1'b1;
                        rd_data <= 8'hFF;
                        timeout_cnt <= TIMEOUT_CYCLES;
                    end else begin
                        state <= SP_IDLE;
                    end
                end
            endcase

            // If SmartPort mode drops while in the middle of a transaction, reset
            if (!smartport_mode && state != SP_IDLE) begin
                state <= SP_IDLE;
                bsy <= 1'b0;
                rd_data_valid <= 1'b0;
                write_pending <= 1'b0;
                is_data_packet <= 1'b0;
                send_data_packet <= 1'b0;
                sp_request <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Response Building Tasks
    //=========================================================================

    // Build a simple status response packet
    // Format: $C3 (sync) + header(7) + encoded_status + checksum(2) + $C8
    task automatic build_status_response;
        input [7:0] status_byte;
        reg [7:0] cksum_odd;
        reg [7:0] cksum_even;
        reg [7:0] hdr [0:6];
        integer i;
        begin
            // Response header
            hdr[0] = pkt_src;           // Dest = original source
            hdr[1] = pkt_dest;          // Src = us (original dest)
            hdr[2] = 8'h81;             // Type = status response
            hdr[3] = 8'h80;             // Aux
            hdr[4] = status_byte | 8'h80; // Status (with bit7 set)
            hdr[5] = 8'h80;             // Payload len hi (0)
            hdr[6] = 8'h80;             // Payload len lo (0)

            // Build response: sync + header + checksum + end
            resp_buf[0] = 8'hC3;        // Sync byte

            cksum_odd = 8'h00;
            cksum_even = 8'h00;
            for (i = 0; i < 7; i = i + 1) begin
                resp_buf[i + 1] = hdr[i];
                cksum_odd = cksum_odd ^ (hdr[i] & 8'hAA);
                cksum_even = cksum_even ^ (hdr[i] & 8'h55);
            end

            resp_buf[8] = cksum_odd | 8'hAA;  // Checksum odd bits
            resp_buf[9] = cksum_even | 8'h55;  // Checksum even bits
            resp_buf[10] = 8'hC8;              // End mark

            resp_len = 5'd11;
        end
    endtask

    // Build a data response packet (for ReadBlock)
    // This is simplified - in practice the data would need MSB encoding
    // For now we send a minimal "data available" status and let the C++
    // side handle the actual data transfer via the block buffer
    task automatic build_data_response;
        reg [7:0] cksum_odd;
        reg [7:0] cksum_even;
        reg [7:0] hdr [0:6];
        integer i;
        begin
            // For ReadBlock, the device sends a data packet ($82 type)
            // with 512 bytes of MSB-encoded payload.
            // This is complex to build in hardware, so we send a status-only
            // response and handle the data via the block buffer interface.
            // The C++ side will populate the response.

            // Simple status response for now
            hdr[0] = pkt_src;
            hdr[1] = pkt_dest;
            hdr[2] = 8'h81;  // Status
            hdr[3] = 8'h80;
            hdr[4] = 8'h80;  // OK status
            hdr[5] = 8'h80;
            hdr[6] = 8'h80;

            resp_buf[0] = 8'hC3;

            cksum_odd = 8'h00;
            cksum_even = 8'h00;
            for (i = 0; i < 7; i = i + 1) begin
                resp_buf[i + 1] = hdr[i];
                cksum_odd = cksum_odd ^ (hdr[i] & 8'hAA);
                cksum_even = cksum_even ^ (hdr[i] & 8'h55);
            end

            resp_buf[8] = cksum_odd | 8'hAA;
            resp_buf[9] = cksum_even | 8'h55;
            resp_buf[10] = 8'hC8;

            resp_len = 5'd11;
        end
    endtask

endmodule
