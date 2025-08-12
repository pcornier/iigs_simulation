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
    
    // Sector buffer
    // Double-ported RAM for holding a sector
    reg [7:0]        sector_buf[0:511];
    
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
        begin
            // Default output unless a read path below overrides
            D_OUT <= 8'hFF;

            // READ PATH: drive D_OUT regardless of phi0 so CPU sees stable data
            if (DEVICE_SELECT && RD) begin
                case (A[3:0])
                  4'h0: begin
                    // C0F0 EXEC/STATUS returns reg_status (0=ok,1=err) in bit0 after ROR hd_error
                    // Here return 0 to indicate success; write strobes handled below on phi0
                    D_OUT <= 8'h00;
                  end
                  4'h1: D_OUT <= reg_status;      // STATUS/ERROR
                  4'h2: D_OUT <= reg_command;     // COMMAND
                  4'h3: D_OUT <= reg_unit;        // UNIT
                  4'h4: D_OUT <= reg_mem_l;       // MEM L
                  4'h5: D_OUT <= reg_mem_h;       // MEM H
                  4'h6: D_OUT <= reg_block_l;     // BLK L
                  4'h7: D_OUT <= reg_block_h;     // BLK H
                  4'h8: D_OUT <= sector_buf[sec_addr]; // NEXT BYTE
                  default: D_OUT <= 8'hFF;
                endcase
            end else if (IO_SELECT && RD) begin
                // Directly drive slot ROM data
                D_OUT <= rom_dout; // C6xx-C7xx slot ROM reads
            end

            // WRITE/CONTROL PATH: gate side-effects to phi0
            if (phi0) begin
                hdd_read  <= 1'b0;
                hdd_write <= 1'b0;
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
            end
            else
            begin
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
                                    sec_addr <= 9'b000000000;
                                    // For GS/OS probes, report success by default
                                    // and pulse read/write strobes when appropriate.
                                    case (reg_command)
                                      PRODOS_COMMAND_STATUS: begin
                                        reg_status <= 8'h00; // ok
                                        D_OUT <= 8'h00;
`ifdef SIMULATION
                                        $display("HDD RD C0F0: STATUS ok (unit=%02h)", reg_unit);
`endif
                                      end
                                      PRODOS_COMMAND_READ: begin
                                        reg_status <= 8'h00;
                                        D_OUT <= 8'h00;
                                        if (~select_d) hdd_read <= 1'b1;
`ifdef SIMULATION
                                        $display("HDD RD C0F0: READ (blk=%04h) ok", {reg_block_h,reg_block_l});
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
                                          D_OUT <= 8'h00;
                                          reg_status <= 8'h00;
                                          hdd_write <= 1'b1;
`ifdef SIMULATION
                                          $display("HDD RD C0F0: WRITE (blk=%04h) ok", {reg_block_h,reg_block_l});
`endif
                                        end
                                      end
                                      default: begin
                                        reg_status <= 8'h00; D_OUT <= 8'h00;
`ifdef SIMULATION
                                        $display("HDD RD C0F0: unknown cmd %02h -> ok", reg_command);
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
                                    D_OUT <= sector_buf[sec_addr];
				    //$display("reading D_OUT %x to ram %x readonly %x",D_OUT,sec_addr,hdd_protect);
                                    increment_sec_addr <= 1'b1;
`ifdef SIMULATION
                                    $display("HDD RD C0F8[%03d] -> %02h", sec_addr, sector_buf[sec_addr]);
`endif
                                end
                            default :
                                ;
                        endcase
                    else
                        // RD = '0'; 6502 is writing
                        case (A[3:0])
                            4'h2 :
                                begin
                                    if (D_IN == 8'h02)
                                        sec_addr <= 9'b000000000;
                                    reg_command <= D_IN;
`ifdef SIMULATION
                                    $display("HDD WR C0F2: cmd <= %02h", D_IN);
`endif
                                end
                            4'h1 : begin // allow RMW ops (eg. ROR C0F1)
                                reg_status <= D_IN;
`ifdef SIMULATION
                                $display("HDD WR C0F1: status <= %02h", D_IN);
`endif
                              end
                            4'h3 :
                                begin reg_unit <= D_IN; `ifdef SIMULATION $display("HDD WR C0F3: unit <= %02h", D_IN); `endif end
                            4'h4 :
                                begin reg_mem_l <= D_IN; `ifdef SIMULATION $display("HDD WR C0F4: memL <= %02h", D_IN); `endif end
                            4'h5 :
                                begin reg_mem_h <= D_IN; `ifdef SIMULATION $display("HDD WR C0F5: memH <= %02h", D_IN); `endif end
                            4'h6 :
                                begin reg_block_l <= D_IN; `ifdef SIMULATION $display("HDD WR C0F6: blkL <= %02h", D_IN); `endif end
                            4'h7 :
                                begin reg_block_h <= D_IN; `ifdef SIMULATION $display("HDD WR C0F7: blkH <= %02h", D_IN); `endif end
                            4'h8 :
                                begin
 				    //$display("writing D_IN %x to ram %x readonly %x",D_IN,sec_addr,hdd_protect);
                                    sector_buf[sec_addr] <= D_IN;
                                    increment_sec_addr <= 1'b1;
`ifdef SIMULATION
                                    $display("HDD WR C0F8[%03d] <= %02h", sec_addr, D_IN);
`endif
                                end
                            default :
                                ;
                        endcase
                end
                // RD/WR
                else if (DEVICE_SELECT == 1'b0 & select_d == 1'b1)
                begin
			//$display("DEVICE_SELECT==0 select_d==1");
                    if (increment_sec_addr == 1'b1)
                    begin
                        sec_addr <= sec_addr + 1;
                        increment_sec_addr <= 1'b0;
                    end
                end
                // No extra latching required for ROM; D_OUT is driven in read path
            end
        end
end
    end
    // DEVICE_SELECT/IO_SELECT
    // RESET
    // cpu_interface
    
    // Dual-ported RAM holding the contents of the sector
    
    always @(posedge CLK_14M)
    begin: sec_storage
        
        begin
            if (ram_we == 1'b1)
                sector_buf[ram_addr] <= ram_di;
            ram_do <= sector_buf[ram_addr];
        end
    end
 

      rom #(8,8,"rtl/roms/hdd.hex") hddrom (
           .clock(CLK_14M),
           .ce(1'b1),
           .address(A[7:0]),
           .q(rom_dout)
   );


endmodule
