// Uncomment to enable detailed PRTC protocol tracing
// `define DEBUG_PRTC

module prtc(
  input CLK_14M,
  input cen,
  input reset,
  input addr,
  input [32:0] timestamp,
  input [7:0] din,
  output reg [7:0] dout,
  output reg onesecond_irq,
  output reg qtrsecond_irq,
  input rw,
  input strobe // must be high for one clock enable(cen) only!
);

reg old_strobe;
reg [7:0] pram [255:0];
reg [31:0] clock_data;
reg [7:0] c033, c034;

// Debug: transaction counter for tracing
`ifdef DEBUG_PRTC
reg [15:0] prtc_txn_count = 0;
`endif

initial begin
  // Initialize PRAM from hex file - MAME ROM3 nvram/apple2gs/rtc values
  // Bytes 0x00-0x59: ROM defaults, 0x5A-0xFB: 0xFF, 0xFC-0xFF: checksum
  // Checksum 0x2D36, Complement 0x879C (verified: 0x2D36 XOR 0xAAAA = 0x879C)
  $readmemh("rtl/roms/pram_init.hex", pram);

`ifdef DEBUG_PRTC
  // Debug: verify PRAM initialization
  $display("PRTC INIT: pram[00]=%02x pram[03]=%02x pram[06]=%02x pram[07]=%02x",
           pram[8'h00], pram[8'h03], pram[8'h06], pram[8'h07]);
  $display("PRTC INIT: pram[F0]=%02x pram[F7]=%02x pram[FC]=%02x pram[FF]=%02x",
           pram[8'hF0], pram[8'hF7], pram[8'hFC], pram[8'hFF]);
`endif

`ifdef SIMULATION
  // Seed to deterministic values; CTL starts at 0x00 to match early read
  c033 = 8'h06;   // DATA
  c034 = 8'h00;   // CTL initial read returns 0x00
`else
  c033 = 8'h00;
  c034 = 8'h00;
`endif
end

// calculate checksum, not tested!!
// it will start when checksum_state = 1;

parameter
  IDLE = 3'd0,
  WAIT = 3'd1,
  PRAM = 3'd2,
  CLOCK = 3'd3,
  INTERNAL = 3'd4;



reg [24:0] clock_counter;
reg [24:0] clock_counter2;



reg [2:0] state;
reg [1:0] checksum_state;
reg [1:0] checksum_writes;
reg [31:0] checksum;
reg [7:0] counter;
reg [7:0] clk_reg1;

// Flag to indicate a read result is pending (needs one cycle to propagate to c033)
reg read_pending = 1'b0;
reg [7:0] read_result = 8'h00;

// Combinational signals to detect read-in-progress and provide immediate data
wire pram_read_now = strobe && cen && (addr == 1'b1) && ~rw && din[7] && (state == PRAM) && din[6];
wire clock_read_now = strobe && cen && (addr == 1'b1) && ~rw && din[7] && (state == CLOCK) && din[6];
wire [7:0] pram_read_data = pram[clk_reg1];
wire [7:0] clock_read_data = clock_data[clk_reg1[1:0]*8+:8];

// Combinational output for dout - must be available immediately, not registered
always @(*) begin
  if (addr == 1'b0 && rw) begin
    // Reading C033 (CLOCKDATA)
    if (pram_read_now)
      dout = pram_read_data;
    else if (clock_read_now)
      dout = clock_read_data;
    else if (read_pending)
      dout = read_result;
    else
      dout = c033;
  end else if (addr == 1'b1 && rw) begin
    // Reading C034 (CLOCKCTL)
    dout = c034;
  end else begin
    dout = 8'h00;
  end
end

// State name decoder for debug
`ifdef DEBUG_PRTC
function [7*8:1] state_name;
  input [2:0] st;
  begin
    case (st)
      3'd0: state_name = "IDLE   ";
      3'd1: state_name = "WAIT   ";
      3'd2: state_name = "PRAM   ";
      3'd3: state_name = "CLOCK  ";
      3'd4: state_name = "INTERNAL";
      default: state_name = "UNKNOWN";
    endcase
  end
endfunction
`endif

reg [31:0] timestamp_prev;
reg clock_initialized;

always @(posedge CLK_14M) begin

  if (reset) begin
    // Initialize all registers on reset
    clock_data <= 32'd0;
    clock_initialized <= 1'b0;
    c033 <= 8'd0;
    c034 <= 8'd0;
    state <= IDLE;
    checksum_state <= 2'd0;
    checksum_writes <= 2'd0;
    checksum <= 32'd0;
    counter <= 8'd0;
    clk_reg1 <= 8'd0;
    clock_counter <= 25'd0;
    clock_counter2 <= 25'd0;
    timestamp_prev <= 32'd0;
    onesecond_irq <= 1'b0;
    qtrsecond_irq <= 1'b0;
    dout <= 8'd0;
  end
  else begin

    onesecond_irq <= 1'b0;
    qtrsecond_irq <= 1'b0;

    // Initialize clock from timestamp once after reset
    // Use clock_initialized flag instead of checking clock_data==0
    if (!clock_initialized) begin
      clock_data <= timestamp[31:0] + 2082844800; // difference between unix epoch and mac epoch
      timestamp_prev <= timestamp[31:0];
      clock_initialized <= 1'b1;
    end
    // Update clock if timestamp changes (e.g., user sets time)
    else if (timestamp_prev != timestamp[31:0]) begin
      clock_data <= timestamp[31:0] + 2082844800;
      timestamp_prev <= timestamp[31:0];
    end


// Use real hardware timing for both FPGA and simulation
// Modern computers are fast enough to handle this
clock_counter<=clock_counter+1;
clock_counter2<=clock_counter2+1;
if (clock_counter=='d14318181)
begin
	clock_counter<=0;
	onesecond_irq<=1;
	clock_data<=clock_data+1;
	// Note: One-second IRQ fires - omitting log to reduce noise
end
if (clock_counter2=='d3818186)
begin
	clock_counter2<=0;
	qtrsecond_irq<=1;
	// Note: Quarter-second IRQ fires - omitting log to reduce noise
end


  case (checksum_state)
    2'd1: begin
      checksum_state <= 2'd2;
      checksum <= 32'd0;
      counter <= 8'd250;
      checksum_writes <= 2'd0;
    end
    2'd2: begin
      checksum <= checksum[31:16] + { checksum[14:0], 1'b0 } + { pram[counter+1], pram[counter] };
      if (counter == 8'd0) begin
        checksum <= { checksum[15:0] ^ 16'haaaa, checksum[15:0] };
        checksum_state <= 2'd3;
      end
      else begin
        counter <= counter - 8'd1;
      end
    end
    2'd3: begin
      pram[252+checksum_writes] <= checksum[(checksum_writes*8)-1+:8];
      checksum_writes <= checksum_writes + 2'd1;
      if (checksum_writes == 2'd3) checksum_state <= 2'd0;
    end
  endcase


  // c033 (DATA) - dout is now combinationally driven, only handle state updates here
  // Note: read_pending is cleared ONLY when CPU actually reads C033 (strobe && cen)
  if (addr == 1'b0) begin
    if (rw) begin
      // When reading C033, check for pending read result
`ifdef DEBUG_PRTC
      if (strobe && cen)
        $display("PRTC [%0d] C033 READ: state=%s read_pending=%d pram_read_now=%d clock_read_now=%d | read_result=%02x c033=%02x -> dout=%02x",
                 prtc_txn_count, state_name(state), read_pending, pram_read_now, clock_read_now, read_result, c033, dout);
`endif
      // Clear read_pending on actual read transaction (strobe && cen)
      if (read_pending && strobe && cen) begin
`ifdef DEBUG_PRTC
        $display("PRTC [%0d] C033 READ clears read_pending, updating c033 <- %02x", prtc_txn_count, read_result);
`endif
        c033 <= read_result;      // Also update c033 for consistency
        read_pending <= 1'b0;     // Clear ONLY after CPU reads it
      end
    end else begin
`ifdef DEBUG_PRTC
      if (strobe && cen)
        $display("PRTC [%0d] C033 WRITE: %02x (was %02x) state=%s", prtc_txn_count, din, c033, state_name(state));
`endif
      c033 <= din;
    end
  end

  // c034 - dout is now combinationally driven, only handle state updates here
  if (addr == 1'b1) begin
    if (rw) begin
`ifdef DEBUG_PRTC
      if (strobe && cen)
        $display("PRTC [%0d] C034 READ: %02x state=%s", prtc_txn_count, c034, state_name(state));
`endif
    end else begin
`ifdef DEBUG_PRTC
      if (strobe && cen)
        $display("PRTC [%0d] C034 WRITE: %02x (bit7=%d bit6=%d) state=%s c033=%02x",
                 prtc_txn_count, din, din[7], din[6], state_name(state), c033);
`endif
      c034 <= din[6:0];
    end
  end

`ifdef DEBUG_PRTC
  if (strobe && cen)
    prtc_txn_count <= prtc_txn_count + 1;
`endif

  // old_strobe <= strobe;
  if (strobe && cen) begin

    // write c034 (CTL)
    if (addr == 1'b1 && ~rw) begin

      if (din[7]) begin // start transaction (bit 7 = 1)
`ifdef DEBUG_PRTC
        $display("PRTC [%0d] === EXECUTE: C034 write with bit7=1, c033=%02x, din=%02x (bit6=%d==%s) state=%s ===",
                 prtc_txn_count, c033, din, din[6], din[6] ? "READ" : "WRITE", state_name(state));
`endif
        // FIX: Execute single-step operations immediately in the same cycle.
        // The original code used state transitions (IDLE->PRAM->IDLE) with
        // non-blocking assignments, which meant the target state logic wouldn't
        // execute until another strobe came (which the ROM never sends).
        // Now we execute the operation directly when the command is received.

        case (state)

          IDLE: begin
            // Command byte decoding (based on KEGS/Clemens implementation):
            // - bits 6:4 = operation type (op)
            // - bits 3:2 = register index (for clock) or address (for BRAM)
            // - bit 7 = read flag (z: 1=read, 0=write)
            //
            // op=0 (000): Clock/time registers
            // op=2 (010): BRAM 0x10-0x13
            // op=3 (011): Internal regs (bit3=0) or Extended BRAM (bit3=1)
            // op=4,5,6,7 (1xx): BRAM 0x00-0x0F
`ifdef DEBUG_PRTC
            $display("PRTC [%0d] IDLE: cmd byte c033=%02x (%08b) op[6:4]=%d",
                     prtc_txn_count, c033, c033, (c033>>4)&7);
`endif
            casez (c033)
              8'b?000????: begin // op=0: clock register
                // Two-phase protocol: save register index, transition to CLOCK state
                // The actual read/write happens in CLOCK state based on din[6]
                clk_reg1[1:0] <= c033[3:2]; // clock register index (0-3)
`ifdef DEBUG_PRTC
                $display("PRTC [%0d]   -> CLOCK cmd: reg=%d (seconds byte %0d), next C034 will %s",
                         prtc_txn_count, c033[3:2], c033[3:2], din[6] ? "READ" : "be ignored (need 2nd C034)");
`endif
                state <= CLOCK;
              end
              8'b?010????: begin // op=2: BRAM 0x10-0x13
                // Two-phase: save address, transition to PRAM state
                clk_reg1 <= {6'b000100, c033[3:2]}; // address 0x10-0x13
`ifdef DEBUG_PRTC
                $display("PRTC [%0d]   -> PRAM 0x10-0x13 cmd: addr=$%02x, next C034 will %s",
                         prtc_txn_count, {6'b000100, c033[3:2]}, din[6] ? "READ" : "be ignored");
`endif
                state <= PRAM;
              end
              8'b?0110???: begin // op=3, bit3=0: internal registers
`ifdef DEBUG_PRTC
                $display("PRTC [%0d]   -> INTERNAL cmd: c033=%02x (test/write-protect)", prtc_txn_count, c033);
`endif
                // Internal registers are mostly no-ops (test reg, write protect)
                state <= INTERNAL;
              end
              8'b?0111???: begin // op=3, bit3=1: BRAM extended (first byte)
`ifdef DEBUG_PRTC
                $display("PRTC [%0d]   -> EXTENDED PRAM (phase 1): high_addr[7:5]=%d, waiting for phase 2",
                         prtc_txn_count, c033[2:0]);
`endif
                // Three-phase: save high address bits, wait for second byte
                clk_reg1[7:5] <= c033[2:0];
                state <= WAIT;
              end
              8'b?1??????: begin // op=4,5,6,7: BRAM 0x00-0x0F
                // Two-phase: save address, transition to PRAM state
                clk_reg1 <= {4'b0, c033[5:2]}; // address 0x00-0x0F
`ifdef DEBUG_PRTC
                $display("PRTC [%0d]   -> PRAM 0x00-0x0F cmd: addr=$%02x, next C034 will %s",
                         prtc_txn_count, {4'b0, c033[5:2]}, din[6] ? "READ" : "be ignored");
`endif
                state <= PRAM;
              end
            endcase
          end

          WAIT: begin // BRAM extended address - second byte received
            // Three-phase protocol:
            // Phase 1: First cmd byte -> WAIT state, save high addr bits
            // Phase 2: Second cmd byte -> PRAM state, save low addr bits (DON'T execute yet)
            // Phase 3: Final C034 write with bit6=read flag -> PRAM state executes read/write
            //
            // Save the full address and transition to PRAM state for final execution
            clk_reg1 <= {clk_reg1[7:5], c033[6:2]}; // full 8-bit address
`ifdef DEBUG_PRTC
            $display("PRTC [%0d] WAIT (phase 2): low_addr from c033=%02x -> full_addr=$%02x, next C034 will execute",
                     prtc_txn_count, c033, {clk_reg1[7:5], c033[6:2]});
`endif
            state <= PRAM;
          end

          // PRAM state: execute the extended BRAM read/write
          // din[6] (c034 bit 6): 1=read, 0=write
          PRAM: begin
            state <= IDLE;
            if (din[6]) begin // read (c034 bit 6 = 1)
              // Set read_result and flag so CPU can read immediately
              read_result <= pram[clk_reg1];
              read_pending <= 1'b1;
`ifdef DEBUG_PRTC
              $display("PRTC [%0d] PRAM EXECUTE READ: addr=$%02x -> data=$%02x (setting read_pending=1)",
                       prtc_txn_count, clk_reg1, pram[clk_reg1]);
`endif
            end else begin
`ifdef DEBUG_PRTC
              $display("PRTC [%0d] PRAM EXECUTE WRITE: addr=$%02x <- data=$%02x (was $%02x)",
                       prtc_txn_count, clk_reg1, c033, pram[clk_reg1]);
`endif
              pram[clk_reg1] <= c033;
            end
          end

          CLOCK: begin
            // Execute clock read/write based on din[6] (c034 bit 6)
            state <= IDLE;
            if (din[6]) begin // read (c034 bit 6 = 1)
              // Set read_result and flag so CPU can read immediately
              read_result <= clock_data[clk_reg1[1:0]*8+:8];
              read_pending <= 1'b1;
`ifdef DEBUG_PRTC
              $display("PRTC [%0d] CLOCK EXECUTE READ: reg=%d -> data=$%02x (setting read_pending=1)",
                       prtc_txn_count, clk_reg1[1:0], clock_data[clk_reg1[1:0]*8+:8]);
`endif
            end else begin // write (c034 bit 6 = 0)
`ifdef DEBUG_PRTC
              $display("PRTC [%0d] CLOCK EXECUTE WRITE: reg=%d <- data=$%02x",
                       prtc_txn_count, clk_reg1[1:0], c033);
`endif
              clock_data[clk_reg1[1:0]*8+:8] <= c033;
            end
          end

          INTERNAL: begin
`ifdef DEBUG_PRTC
            $display("PRTC [%0d] INTERNAL: no-op, returning to IDLE", prtc_txn_count);
`endif
            state <= IDLE;
            // Internal registers are no-ops
          end

        endcase

      end else begin
`ifdef DEBUG_PRTC
        $display("PRTC [%0d] C034 write with bit7=0 (no execute), just updating border/ctrl bits", prtc_txn_count);
`endif
      end

    end

  end

  end // else !reset

end

endmodule
