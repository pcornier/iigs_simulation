//-----------------------------------------------------------------------------
//
// HDD interface
//
// This is a ProDOS HDD interface based on the AppleWin interface.
// Currently, the CPU must be halted during command execution.
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
// C0F8         (r)   NEXT BYTE
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
    sector,
    hdd_read,
    hdd_write,
    hdd_mounted,
    hdd_protect,
    ram_addr,
    ram_di,
    ram_do,
    ram_we
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
    output [15:0]    sector;		// Sector number to read/write
    output reg       hdd_read;
    output reg       hdd_write;
    input            hdd_mounted;
    input            hdd_protect;
    input [8:0]      ram_addr;		// Address for sector buffer
    input [7:0]      ram_di;		// Data to sector buffer
    output reg [7:0] ram_do;		// Data from sector buffer
    input            ram_we;		// Sector buffer write enable
    
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
    reg [8:0]        sec_addr;
    reg              increment_sec_addr;
    reg              select_d;
    
    // Sector buffer: true dual-port RAM (512x8)
    wire [7:0]       sector_dma_q;   // DMA (Port A) read data
    wire [7:0]       sector_cpu_q;   // CPU (Port B, C0F8) read data
    // Stage Port-B q to hide BRAM latency and align NEXT BYTE stream
    reg  [7:0]       next_byte_q;
    reg              cpu_c0f8_we;    // CPU writes to C0F8 during WRITE
    reg  [7:0]       cpu_c0f8_din;
    // First-byte prefetch to cover BRAM read latency on READ command
    reg              prefetch_armed;
    reg              prefetch_valid;
    reg  [7:0]       prefetch_data;
    
    // ProDOS constants
    parameter        PRODOS_COMMAND_STATUS = 8'h00;
    parameter        PRODOS_COMMAND_READ = 8'h01;
    parameter        PRODOS_COMMAND_WRITE = 8'h02;
    parameter        PRODOS_COMMAND_FORMAT = 8'h03;
    parameter        PRODOS_STATUS_NO_DEVICE = 8'h28;
    parameter        PRODOS_STATUS_PROTECT = 8'h2B;
    
    assign sector = {reg_block_h, reg_block_l};
    
    
    always @(posedge CLK_14M)
    begin: cpu_interface
        if (prefetch_armed) begin
            prefetch_data  <= sector_cpu_q;
            prefetch_valid <= 1'b1;
            prefetch_armed <= 1'b0;
`ifdef SIMULATION
            $display("HDD PREFETCH armed -> data=%02h at sec_addr=%03d", sector_cpu_q, sec_addr);
`endif
        end


        begin
            // Default output unless a read path below overrides
            D_OUT <= 8'hFF;

            // Asynchronous read path for slot ROM (C6xx) and a read-only mirror for HDD regs (C0F0–C0FF)
            if (DEVICE_SELECT && RD) begin
                // Mirror register values without side-effects; phi0-gated path handles semantics
                case (A[3:0])
                  4'h0: begin
                    // EXECUTE/STATUS mirror: just return current status (no side-effect here)
                    D_OUT <= reg_status;
                  end
                  4'h1: D_OUT <= reg_status;      // STATUS/ERROR
                  4'h2: D_OUT <= reg_command;     // COMMAND
                  4'h3: D_OUT <= reg_unit;        // UNIT
                  4'h4: D_OUT <= reg_mem_l;       // MEM L
                  4'h5: D_OUT <= reg_mem_h;       // MEM H
                  4'h6: D_OUT <= reg_block_l;     // BLK L
                  4'h7: D_OUT <= reg_block_h;     // BLK H
                  4'h8: D_OUT <= next_byte_q;          // NEXT BYTE mirror (no increment here)
                  default: D_OUT <= 8'hFF;
                endcase
                $display("HDD CPU %s 00:%04h -> %02h (cmd=%02h unit=%02h blk=%04h mem=%04h sec_idx=%03d)",
                         "READ-MIRROR", {12'h0F0, A[3:0]}, D_OUT, reg_command, reg_unit,
                         {reg_block_h, reg_block_l}, {reg_mem_h, reg_mem_l}, sec_addr);
            end else if (IO_SELECT && RD) begin
                // Directly drive slot ROM data
                D_OUT <= rom_dout; // C6xx-C7xx slot ROM reads
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
                sec_addr <= 9'd0;
                increment_sec_addr <= 1'b0;
                hdd_read <= 1'b0;
                hdd_write <= 1'b0;
                cpu_c0f8_we <= 1'b0;
                prefetch_armed <= 1'b0;
                prefetch_valid <= 1'b0;
            end
            else
            begin
                // Create a clean, one-cycle pulse for read/write strobes.
                // De-assert on the cycle after assertion.
                if (hdd_read) hdd_read <= 1'b0;
                if (hdd_write) hdd_write <= 1'b0;
                cpu_c0f8_we <= 1'b0;

                select_d <= DEVICE_SELECT;
                if (DEVICE_SELECT == 1'b1)
                begin
`ifdef SIMULATION
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
                                        // Report mounted status as ok(0) or error(1)
                                        reg_status <= hdd_mounted ? 8'h00 : 8'h01;
                                        D_OUT      <= reg_status;
`ifdef SIMULATION
                                        $display("HDD RD C0F0: STATUS read -> %02h (mounted=%0d unit=%02h)", reg_status, hdd_mounted, reg_unit);
`endif
                                      end
                                      PRODOS_COMMAND_READ: begin
                                        // Initiate read if mounted; otherwise report error immediately
                                        if (hdd_mounted) begin
                                          if (~select_d) hdd_read <= 1'b1;
                                          // Do not change status here; reg_status should be 0x80 after C0F2
                                          D_OUT <= reg_status;
                                        end else begin
                                          reg_status <= 8'h01; // error
                                          D_OUT      <= 8'h01;
                                        end
`ifdef SIMULATION
                                        $display("HDD RD C0F0: READ start (blk=%04h) status=%02h mounted=%0d", {reg_block_h,reg_block_l}, reg_status, hdd_mounted);
`endif
                                      end
                                      PRODOS_COMMAND_WRITE: begin
                                        if (hdd_protect) begin
                                          D_OUT <= PRODOS_STATUS_PROTECT;
                                          reg_status <= 8'h01;
`ifdef SIMULATION
                                          $display("HDD RD C0F0: WRITE protect");
`endif
                                        end else begin
                                          if (hdd_mounted) begin
                                            $display("HDD: WRITE command initiated. Asserting hdd_write.");
                                            D_OUT <= reg_status; // report busy
                                            hdd_write <= 1'b1;
                                          end else begin
                                            reg_status <= 8'h01; D_OUT <= 8'h01;
                                          end
`ifdef SIMULATION
                                          $display("HDD RD C0F0: WRITE (blk=%04h) status=%02h mounted=%0d", {reg_block_h,reg_block_l}, reg_status, hdd_mounted);
`endif
                                        end
                                      end
                                      default: begin
                                        D_OUT <= reg_status; // no change
`ifdef SIMULATION
                                        $display("HDD RD C0F0: unknown cmd %02h -> status %02h", reg_command, reg_status);
`endif
                                      end
                                    endcase
                                end
                            4'h1 :
                                begin D_OUT <= reg_status; `ifdef SIMULATION $display("HDD RD C0F1: status=%02h", reg_status); `endif end
                            4'h2 :
                                begin D_OUT <= reg_command; `ifdef SIMULATION $display("HDD RD C0F2: cmd=%02h", reg_command); `endif end
                            4'h3 :
                                begin D_OUT <= reg_unit; `ifdef SIMULATION $display("HDD RD C0F3: unit=%02h", reg_unit); `endif end
                            4'h4 :
                                begin D_OUT <= reg_mem_l; `ifdef SIMULATION $display("HDD RD C0F4: memL=%02h", reg_mem_l); `endif end
                            4'h5 :
                                begin D_OUT <= reg_mem_h; `ifdef SIMULATION $display("HDD RD C0F5: memH=%02h", reg_mem_h); `endif end
                            4'h6 :
                                begin D_OUT <= reg_block_l; `ifdef SIMULATION $display("HDD RD C0F6: blkL=%02h", reg_block_l); `endif end
                            4'h7 :
                                begin D_OUT <= reg_block_h; `ifdef SIMULATION $display("HDD RD C0F7: blkH=%02h", reg_block_h); `endif end
                            4'h8 :
                                begin
                                    // First-byte guard: if a READ was just armed, return the prefetched byte
                                    // to hide BRAM's 1-cycle latency on Port-B and only then advance.
                                    if (prefetch_valid) begin
                                        D_OUT <= prefetch_data;
                                        prefetch_valid <= 1'b0; // consume prefetch
                                        sec_addr <= sec_addr + 1;
`ifdef SIMULATION
                                        $display("HDD CPU READ C0F8[%03d] -> %02h (prefetch)", sec_addr, prefetch_data);
`endif
                                    end else begin
                                        // Present staged NEXT BYTE on gated path, then increment address
                                        D_OUT <= next_byte_q;
                                        sec_addr <= sec_addr + 1;
`ifdef SIMULATION
                                        $display("HDD CPU READ C0F8[%03d] -> %02h (gated)", sec_addr, next_byte_q);
`endif
                                    end

                                    if (sec_addr == 9'd511) begin
                                        reg_status <= 8'h00; // clear busy at end of sector
`ifdef SIMULATION
                                        $display("HDD: READ complete via NEXT BYTE stream; status cleared");
`endif
                                    end
                                end
                            default :
                                ;
                        endcase
                    else
                        // RD = '0'; 6502 is writing
                        case (A[3:0])
                            4'h2 :
                                begin
                                    hdd_read <= 1'b0;
                                    hdd_write <= 1'b0;
                                    if (D_IN == 8'h02)
                                        sec_addr <= 9'b000000000;
                                    reg_command <= D_IN;
`ifdef SIMULATION
                                    $display("HDD WR C0F2: cmd <= %02h (unit=%02h blk=%04h mem=%04h)", D_IN, reg_unit, {reg_block_h,reg_block_l}, {reg_mem_h,reg_mem_l});
`endif
                                    if (D_IN == PRODOS_COMMAND_READ || D_IN == PRODOS_COMMAND_WRITE) begin
                                        reg_status <= 8'h80; // busy
                                        sec_addr   <= 9'd0;
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
`ifdef SIMULATION
                                $display("HDD WR C0F1 IGNORED (status read-only)");
`endif
                            end
                            4'h3 :
                                begin reg_unit <= D_IN; `ifdef SIMULATION $display("HDD WR C0F3: unit <= %02h", D_IN); `endif end
                            4'h4 :
                                begin reg_mem_l <= D_IN; `ifdef SIMULATION $display("HDD WR C0F4: memL <= %02h (mem=%04h)", D_IN, {reg_mem_h, D_IN}); `endif end
                            4'h5 :
                                begin reg_mem_h <= D_IN; `ifdef SIMULATION $display("HDD WR C0F5: memH <= %02h (mem=%04h)", D_IN, {D_IN, reg_mem_l}); `endif end
                            4'h6 :
                                begin reg_block_l <= D_IN; `ifdef SIMULATION $display("HDD WR C0F6: blkL <= %02h (blk=%04h)", D_IN, {reg_block_h, D_IN}); `endif end
                            4'h7 :
                                begin reg_block_h <= D_IN; `ifdef SIMULATION $display("HDD WR C0F7: blkH <= %02h (blk=%04h)", D_IN, {D_IN, reg_block_l}); `endif end
                            4'h8 :
                                begin
					    //$display("writing D_IN %x to NEXT BYTE at %x",D_IN,sec_addr);
                                    cpu_c0f8_we  <= 1'b1;
                                    cpu_c0f8_din <= D_IN;
                                    sec_addr     <= sec_addr + 1;
`ifdef SIMULATION
                                    $display("HDD CPU WRITE C0F8[%03d] <= %02h", sec_addr, D_IN);
`endif
                                end
                            default :
			    begin
`ifdef SIMULATION
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
        .address_a(ram_addr),
        .data_a(ram_di),
        .q_a(sector_dma_q),
        // Port B: CPU NEXT BYTE (read-only)
        .clock_b(CLK_14M),
        .wren_b(cpu_c0f8_we),
        .address_b(sec_addr),
        .data_b(cpu_c0f8_din),
        .q_b(sector_cpu_q),
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
    /*
    // Dual-ported RAM holding the contents of the sector
    dpram #(
        .width_a(8),
        .widthad_a(9)
    ) sector_ram (
        // Port A: DMA
        .clock_a(CLK_14M),
        .wren_a(ram_we),
        .address_a(ram_addr),
        .data_a(ram_di),
        .q_a(sector_dma_q),
        // Port B: CPU NEXT BYTE (read-only)
        .clock_b(CLK_14M),
        .wren_b(cpu_c0f8_we),
        .address_b(sec_addr),
        .data_b(cpu_c0f8_din),
        .q_b(sector_cpu_q),
        // Unused enables
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .ce_a(1'b1),
        .enable_b(1'b1)
    );
*/
    // Registered DMA readback
    always @(posedge CLK_14M) begin
        ram_do <= sector_dma_q;
        if (ram_we) $display("HDD DMA WRITE: sector_buf[%03h] <= %02h", ram_addr, ram_di);
    end

    // Stage Port-B q so mirror/gated paths return the correct byte with BRAM latency
    always @(posedge CLK_14M) begin
        next_byte_q <= sector_cpu_q;
    end
    // Latch first byte after a READ command to ensure the first C0F8 returns correctly
    always @(posedge CLK_14M) begin
    end
 

      rom #(8,8,"rtl/roms/hdd.hex") hddrom (
           .clock(CLK_14M),
           .ce(1'b1),
           .address(A[7:0]),
           .q(rom_dout)
   );


endmodule
