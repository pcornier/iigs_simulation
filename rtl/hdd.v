//-----------------------------------------------------------------------------
//
// HDD interface
//
// This is a ProDOS HDD interface based on the AppleWin interface.
//
// Steven A. Wilson
//
//-----------------------------------------------------------------------------
// Registers (per AppleWin source/Harddisk.cpp)
// C0F0         (r)   EXECUTE AND RETURN STATUS
// C0F1         (r)   STATUS (or ERROR)
// C0F2         (r/w) COMMAND
// C0F3         (r/w) UNIT NUMBER
// C0F4         (r/w) LOW BYTE OF MEMORY BUFFER
// C0F5         (r/w) HIGH BYTE OF MEMORY BUFFER
// C0F6         (r/w) LOW BYTE OF BLOCK NUMBER
// C0F7         (r/w) HIGH BYTE OF BLOCK NUMBER
// C088         (r)   NEXT BYTE (legacy port; no longer supported with DMA)
// C089         (r)   LOW BYTE OF DISK IMAGE SIZE IN BLOCKS
// C08A         (r)   HIGH BYTE OF DISK IMAGE SIZE IN BLOCKS
//-----------------------------------------------------------------------------

module hdd(
    CLK_14M,
    phi0,
    IO_SELECT,
    DEVICE_SELECT,
    RESET,
    A,
    RD,
    D_IN,
    D_OUT,
    DMA,
    DMA_ADDR,
    DMA_WE,
    sector,
    hdd_read,
    hdd_write,
    hdd_unit,
    hdd_mounted,
    hdd_protect,
    hdd0_size,
    hdd1_size,
    hps_ram_addr,
    ram_di,
    ram_do,
    ram_we,
    sd_ack
);
    input            CLK_14M;
    input            phi0;
    input            IO_SELECT;		// e.g., C600 - C6FF ROM
    input            DEVICE_SELECT;		// e.g., C0E0 - C0EF I/O locations
    input            RESET;
    input [15:0]     A;
    input            RD;		// 6502 RD/WR
    input [7:0]      D_IN;		// From 6502
    output reg [7:0] D_OUT;		// To 6502
    output reg       DMA;
    output reg [15:0] DMA_ADDR;
    output reg       DMA_WE;
    output [15:0]    sector;		// Sector number to read/write
    output reg       hdd_read;
    output reg       hdd_write;
    output           hdd_unit;		// Which unit (0-1) is being accessed (directly from bit 7)
    input [1:0]      hdd_mounted;	// Per-unit mounted status (active high)
    input [1:0]      hdd_protect;	// Per-unit write protect (active high)
    input [63:0]     hdd0_size;
    input [63:0]     hdd1_size;
    input [8:0]      hps_ram_addr;	// Address for sector buffer
    input [7:0]      ram_di;		// Data to sector buffer
    output reg [7:0] ram_do;		// Data from sector buffer
    input            ram_we;		// Sector buffer write enable
    input [1:0]      sd_ack;

    wire [7:0]       sector_dout;
    wire [7:0]       rom_dout;
    
    // Interface registers
    reg [7:0]        reg_status;
    reg [7:0]        reg_command;
    reg [7:0]        reg_unit;
    reg [7:0]        reg_mem_l;
    reg [7:0]        reg_mem_h;
    reg [7:0]        reg_block_l;
    reg [7:0]        reg_block_h;
   
    reg PHASE_ZERO_r; 
    // Internal sector buffer offset counter; incremented by
    // access to C0F8 and reset when a command is written to
    // C0F2.
    reg [8:0]        a2_ram_addr;
    reg              select_d;

    // Sector buffer: true dual-port RAM (512x8)
    wire [7:0]       sector_dma_q;   // DMA (Port A) read data
    wire [7:0]       sector_cpu_q;   // CPU (Port B, C0F8) read data
    // Stage Port-B q to hide BRAM latency and align NEXT BYTE stream
    reg  [7:0]       next_byte_q;
    reg              a2_ram_we;    // A2-side write to sector buffer
    reg  [7:0]       cpu_c0f8_din;
    // First-byte prefetch to cover BRAM read latency on READ command
    reg              prefetch_armed;
    reg              prefetch_valid;
    reg  [7:0]       prefetch_data;
    
    // ProDOS constants
    localparam       PRODOS_COMMAND_STATUS = 8'h00;
    localparam       PRODOS_COMMAND_READ = 8'h01;
    localparam       PRODOS_COMMAND_WRITE = 8'h02;
    localparam       PRODOS_COMMAND_FORMAT = 8'h03;
    localparam       PRODOS_STATUS_NO_DEVICE = 8'h28;
    localparam       PRODOS_STATUS_PROTECT = 8'h2B;
    
    assign sector = {reg_block_h, reg_block_l};

    // Unit selection from reg_unit (ProDOS format: bit 7=drive select)
    // For slot 7: $70=unit0 (bit7=0), $F0=unit1 (bit7=1)
    assign hdd_unit = reg_unit[7];

    // DMA state machine
    // "RD" and "WR" here are in the sense of disk read/write.
    // For disk read, the HPS DMA happens first, then the A2 DMA.
    // For disk write, the A2 DMA happens first, then the HPS DMA.
    localparam ST_IDLE   = 3'd0; // No DMA transfer in progress
    localparam ST_RD_ACK = 3'd1; // Wait for HPS DMA to start
    localparam ST_RD_HPS = 3'd2; // HPS reading from SD
    localparam ST_RD_A2  = 3'd3; // Writing A2 RAM
    localparam ST_WR_A2  = 3'd4; // Reading A2 RAM
    localparam ST_WR_ACK = 3'd5; // Wait for HPS DMA to start
    localparam ST_WR_HPS = 3'd6; // HPS writing to SD

    reg [2:0]  dma_state;
    reg        dma_req_rd; // Read requested by CPU
    reg        dma_req_wr; // Write requested by CPU
    reg [7:0]  a2_ram_din;

    //assign DMA_ADDR = {reg_mem_h, reg_mem_l} + {7'b0, a2_ram_addr};

    always @(posedge CLK_14M) begin: dma_proc
        DMA_ADDR <= {reg_mem_h, reg_mem_l} + {7'b0, a2_ram_addr};
        case (dma_state)
          ST_IDLE: begin
              if (dma_req_rd) begin
                  dma_state <= ST_RD_ACK;
                  DMA <= 1'b1;
                  DMA_WE <= 1'b0;
                  hdd_read <= 1'b1;
              end
              else if (dma_req_wr) begin
                  dma_state <=  ST_WR_A2;
                  DMA <= 1'b1;
                  DMA_WE <= 1'b0;
                  a2_ram_din <= D_IN;
                  a2_ram_addr <= 9'd0;
                  a2_ram_we <= 1'b1;
              end
          end // case: ST_IDLE
          ST_RD_ACK: begin
              hdd_read <= 1'b0;
              if (sd_ack[hdd_unit]) dma_state <= ST_RD_HPS;
          end
          ST_RD_HPS: begin
              if (!sd_ack[hdd_unit] & phi0) begin
                  a2_ram_addr <= 9'd0;
                  dma_state <= ST_RD_A2;
                  DMA_WE <= 1'b1;
              end
          end
          ST_RD_A2: begin
              if (phi0) begin
                  a2_ram_addr <= a2_ram_addr + 9'b1;
                  if (a2_ram_addr == 9'd511) begin
                      dma_state <= ST_IDLE;
                      DMA_WE <= 1'b0;
                      DMA <= 1'b0;
                  end
              end
          end
          ST_WR_A2: begin
              a2_ram_we <= 1'b0;
              if (phi0) begin
                  a2_ram_we <= 1'b1;
                  a2_ram_addr <= a2_ram_addr + 9'b1;
                  a2_ram_din <= D_IN;
                  if (a2_ram_addr == 9'd511) begin
                      dma_state <= ST_WR_ACK;
                      hdd_write <= 1'b1;
                      a2_ram_we <= 1'b0;
                  end
              end
          end
          ST_WR_ACK: begin
              hdd_write <= 1'b0;
              if (sd_ack[hdd_unit]) dma_state <= ST_WR_HPS;
          end
          ST_WR_HPS: begin
              hdd_write <= 1'b0;
              if (!sd_ack[hdd_unit]) begin
                  dma_state <= ST_IDLE;
                  DMA <= 1'b0;
              end
          end
          default: begin
              dma_state <= ST_IDLE;
`ifdef HDD_DEBUG
              $error("%m: Invalid DMA state");
`endif
          end
        endcase // case (dma_state)

        if (RESET) begin
            dma_state <= ST_IDLE;
            hdd_read <= 1'b0;
            hdd_write <= 1'b0;
            DMA <= 1'b0;
            DMA_ADDR <= 16'h0000;
            DMA_WE <= 1'b0;
            a2_ram_addr <=16'h000;
            a2_ram_we <= 1'b0;
            // dma_req_rd reset by CPU interface
            // dma_req_wr reset by CPU interface
        end
    end // block: dma_proc

    // Helper wires for checking mounted/protect status of current unit
    wire current_unit_mounted = hdd_mounted[hdd_unit];
    wire current_unit_protect = hdd_protect[hdd_unit];
    // Check if any unit is mounted (for ROM visibility)
    wire any_unit_mounted = |hdd_mounted;

    always @(posedge CLK_14M)
    begin: cpu_interface
        begin
            // Default output unless a read path below overrides
            D_OUT <= 8'hFF;

            // Asynchronous read path for slot ROM (C6xx) and a read-only mirror for HDD regs (C0F0–C0FF)
            if (DMA && DMA_WE) begin
                D_OUT <= sector_dout;
            end else if (DEVICE_SELECT && RD) begin
                // Mirror register values without side-effects; phi0-gated path handles semantics
                case (A[3:0])
                  4'h0: begin
                    // EXECUTE/STATUS mirror: return 0 for success since DMA completes instantly
                    // For STATUS command, return mounted status; for READ/WRITE, return 0 (success)
                    D_OUT <= (reg_command == PRODOS_COMMAND_STATUS) ?
                             (current_unit_mounted ? 8'h00 : 8'h01) : 8'h00;
                  end
                  4'h1: D_OUT <= reg_status;      // STATUS/ERROR
                  4'h2: D_OUT <= reg_command;     // COMMAND
                  4'h3: D_OUT <= reg_unit;        // UNIT
                  4'h4: D_OUT <= reg_mem_l;       // MEM L
                  4'h5: D_OUT <= reg_mem_h;       // MEM H
                  4'h6: D_OUT <= reg_block_l;     // BLK L
                  4'h7: D_OUT <= reg_block_h;     // BLK H
                  //4'h8: D_OUT <= next_byte_q;     // NEXT BYTE mirror (no increment here)
                  4'h9: D_OUT <= hdd_unit ? hdd1_size[16:9] : hdd0_size[16:9];
                  4'ha: D_OUT <= hdd_unit ? hdd1_size[24:17] : hdd0_size[24:17];
                  default: D_OUT <= 8'hFF;
                endcase
                $display("HDD CPU %s 00:%04h -> %02h (cmd=%02h unit=%02h blk=%04h mem=%04h sec_idx=%03d)",
                         "READ-MIRROR", {12'h0F0, A[3:0]}, D_OUT, reg_command, reg_unit,
                         {reg_block_h, reg_block_l}, {reg_mem_h, reg_mem_l}, a2_ram_addr);
            end else if (IO_SELECT && RD) begin
                // Directly drive slot ROM data only if any HDD unit is mounted
                // Otherwise return $FF (empty slot) so boot search skips this slot
                D_OUT <= any_unit_mounted ? rom_dout : 8'hFF;
            end

            // WRITE/CONTROL PATH: gate side-effects to phi0
            if (phi0) begin
                if (RESET == 1'b1)
            begin
                reg_status <= 8'h00;
                reg_command <= 8'h00;
                reg_unit <= 8'h00;
                reg_mem_l <= 8'h00;
                reg_mem_h <= 8'h00;
                reg_block_l <= 8'h00;
                reg_block_h <= 8'h00;
                prefetch_armed <= 1'b0;
                prefetch_valid <= 1'b0;
            end
            else
            begin
                // Create a clean, one-cycle pulse for read/write strobes.
                // De-assert on the cycle after assertion.
                dma_req_rd <= 1'b0;
                dma_req_wr <= 1'b0;

                select_d <= DEVICE_SELECT;
                if (DEVICE_SELECT == 1'b1)
                begin
`ifdef DEBUG_HDD
	//$display("HDD DEVSEL: D_IN %02h Alo %1h RD %1b", D_IN, A[3:0], RD);
`endif
                    if (RD == 1'b1)
                        case (A[3:0])
                            4'h0 :
                                begin
                                    // For GS/OS probes, report success by default
                                    // and pulse read/write strobes when appropriate.
				    $display("HDD: reg_command %x",reg_command);
                                    case (reg_command)
                                      PRODOS_COMMAND_STATUS: begin
                                        // Report mounted status as ok(0) or error(1) for current unit
                                        // Use direct value for D_OUT to avoid non-blocking assignment delay
                                        reg_status <= current_unit_mounted ? 8'h00 : 8'h01;
                                        D_OUT      <= current_unit_mounted ? 8'h00 : 8'h01;
`ifdef DEBUG_HDD
                                        $display("HDD RD C0F0: STATUS read -> %02h (mounted=%0d unit=%02h hdd_mounted=%b)",
                                                 current_unit_mounted ? 8'h00 : 8'h01, current_unit_mounted, reg_unit, hdd_mounted);
`endif
                                      end
                                      PRODOS_COMMAND_READ: begin
                                        // Initiate read if current unit is mounted; otherwise report error immediately
                                        if (current_unit_mounted) begin
                                          if (~select_d) dma_req_rd <= 1'b1;
                                          // Return 0 (success) since our emulation completes the DMA instantly.
                                          // The slot ROM saves this value and returns it to ProDOS; non-zero = error.
                                          reg_status <= 8'h00;
                                          D_OUT <= 8'h00;
                                        end else begin
                                          reg_status <= 8'h01; // error
                                          D_OUT      <= 8'h01;
                                        end
`ifdef DEBUG_HDD
                                        $display("HDD RD C0F0: READ start (blk=%04h) status=%02h mounted=%0d unit=%02h", {reg_block_h,reg_block_l}, reg_status, current_unit_mounted, reg_unit);
`endif
                                      end
                                      PRODOS_COMMAND_WRITE: begin
                                        if (current_unit_protect) begin
                                          D_OUT <= PRODOS_STATUS_PROTECT;
                                          reg_status <= 8'h01;
`ifdef DEBUG_HDD
                                          $display("HDD RD C0F0: WRITE protect unit=%02h", reg_unit);
`endif
                                        end else begin
                                          if (current_unit_mounted) begin
                                            $display("HDD: WRITE command initiated for unit %02h. Asserting dma_req_wr.", reg_unit);
                                            // Return 0 (success) since our emulation completes the DMA instantly.
                                            reg_status <= 8'h00;
                                            D_OUT <= 8'h00;
                                            dma_req_wr <= 1'b1;
                                          end else begin
                                            reg_status <= 8'h01; D_OUT <= 8'h01;
                                          end
`ifdef DEBUG_HDD
                                          $display("HDD RD C0F0: WRITE (blk=%04h) status=%02h mounted=%0d unit=%02h", {reg_block_h,reg_block_l}, reg_status, current_unit_mounted, reg_unit);
`endif
                                        end
                                      end
                                      default: begin
                                        D_OUT <= reg_status; // no change
`ifdef DEBUG_HDD
                                        $display("HDD RD C0F0: unknown cmd %02h -> status %02h", reg_command, reg_status);
`endif
                                      end
                                    endcase
                                end
                            4'h1 :
                                begin D_OUT <= reg_status; `ifdef DEBUG_HDD $display("HDD RD C0F1: status=%02h", reg_status); `endif end
                            4'h2 :
                                begin D_OUT <= reg_command; `ifdef DEBUG_HDD $display("HDD RD C0F2: cmd=%02h", reg_command); `endif end
                            4'h3 :
                                begin D_OUT <= reg_unit; `ifdef DEBUG_HDD $display("HDD RD C0F3: unit=%02h", reg_unit); `endif end
                            4'h4 :
                                begin D_OUT <= reg_mem_l; `ifdef DEBUG_HDD $display("HDD RD C0F4: memL=%02h", reg_mem_l); `endif end
                            4'h5 :
                                begin D_OUT <= reg_mem_h; `ifdef DEBUG_HDD $display("HDD RD C0F5: memH=%02h", reg_mem_h); `endif end
                            4'h6 :
                                begin D_OUT <= reg_block_l; `ifdef DEBUG_HDD $display("HDD RD C0F6: blkL=%02h", reg_block_l); `endif end
                            4'h7 :
                                begin D_OUT <= reg_block_h; `ifdef DEBUG_HDD $display("HDD RD C0F7: blkH=%02h", reg_block_h); `endif end
                            4'h9 :
                                D_OUT <= hdd_unit ? hdd1_size[16:9] : hdd0_size[16:9];
                            4'ha :
                                D_OUT <= hdd_unit ? hdd1_size[24:17] : hdd0_size[24:17];
                           default :
                                ;
                        endcase
                    else
                        // RD = '0'; 6502 is writing
                        case (A[3:0])
                            4'h2 :
                                begin
                                    reg_command <= D_IN;
`ifdef DEBUG_HDD
                                    $display("HDD WR C0F2: cmd <= %02h (unit=%02h blk=%04h mem=%04h)", D_IN, reg_unit, {reg_block_h,reg_block_l}, {reg_mem_h,reg_mem_l});
`endif
                                    if (D_IN == PRODOS_COMMAND_READ || D_IN == PRODOS_COMMAND_WRITE) begin
                                        reg_status <= 8'h80; // busy
                                        // Arm prefetch for first NEXT BYTE on READ to cover BRAM latency
                                        prefetch_armed <= (D_IN == PRODOS_COMMAND_READ);
                                        prefetch_valid <= 1'b0;
                                    end else begin
                                        reg_status <= 8'h00;
                                        prefetch_armed <= 1'b0;
                                        prefetch_valid <= 1'b0;
                                    end
                                end
                            4'h1 : begin // ignore writes to status
`ifdef DEBUG_HDD
                                $display("HDD WR C0F1 IGNORED (status read-only)");
`endif
                            end
                            4'h3 :
                                begin reg_unit <= D_IN; `ifdef DEBUG_HDD $display("HDD WR C0F3: unit <= %02h", D_IN); `endif end
                            4'h4 :
                                begin reg_mem_l <= D_IN; `ifdef DEBUG_HDD $display("HDD WR C0F4: memL <= %02h (mem=%04h)", D_IN, {reg_mem_h, D_IN}); `endif end
                            4'h5 :
                                begin reg_mem_h <= D_IN; `ifdef DEBUG_HDD $display("HDD WR C0F5: memH <= %02h (mem=%04h)", D_IN, {D_IN, reg_mem_l}); `endif end
                            4'h6 :
                                begin reg_block_l <= D_IN; `ifdef DEBUG_HDD $display("HDD WR C0F6: blkL <= %02h (blk=%04h)", D_IN, {reg_block_h, D_IN}); `endif end
                            4'h7 :
                                begin reg_block_h <= D_IN; `ifdef DEBUG_HDD $display("HDD WR C0F7: blkH <= %02h (blk=%04h)", D_IN, {D_IN, reg_block_l}); `endif end
                            default :
			    begin
`ifdef DEBUG_HDD
                                    $display("HDD DEFAULT WR A[%x] D_IN  %02h", A[3:0], D_IN);
`endif
				end
                        endcase
                end
                // RD/WR
                else if (DEVICE_SELECT == 1'b0 & select_d == 1'b1)
                begin
			//$display("DEVICE_SELECT==0 select_d==1");
                end
                // No extra latching required for ROM; D_OUT is driven in read path
            end
        end
end
    end
    // DEVICE_SELECT/IO_SELECT
    // RESET
    // cpu_interface
`ifdef VERILATOR
dpram #(.widthad_a(9),.prefix("hdd"),.p(" a")) sector_ram
`else
bram #(.widthad_a(9)) sector_ram
`endif
(
        // Port A: DMA
        .clock_a(CLK_14M),
        .wren_a(ram_we),
        .address_a(hps_ram_addr),
        .data_a(ram_di),
        .q_a(sector_dma_q),
        // Port B: CPU NEXT BYTE (read-only)
        .clock_b(CLK_14M),
        .wren_b(a2_ram_we),
        .address_b(a2_ram_addr),
        .data_b(a2_ram_din),
        .q_b(sector_dout),
        // Enables (keep Port A always enabled; Port B read always enabled)
`ifdef VERILATOR
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .ce_a(1'b1),
        .enable_b(1'b1)
`else
        .enable_a(1'b1),
        .enable_b(1'b1)
`endif
);

    // Registered DMA readback
    always @(posedge CLK_14M) begin
        ram_do <= sector_dma_q;
        if (ram_we) $display("HDD DMA WRITE: sector_buf[%03h] <= %02h", hps_ram_addr, ram_di);
    end

    // Stage Port-B q so mirror/gated paths return the correct byte with BRAM latency
    always @(posedge CLK_14M) begin
        next_byte_q <= sector_cpu_q;
    end


   rom #(8,8,"rtl/roms/hdd.hex") hddrom (
           .clock(CLK_14M),
           .ce(1'b1),
           .address(A[7:0]),
           .q(rom_dout)
   );
endmodule
