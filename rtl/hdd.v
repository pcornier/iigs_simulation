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
    PHASE_ZERO,
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
    input            PHASE_ZERO;
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
            D_OUT <= 8'hFF;
	if (PHASE_ZERO  ) begin
            hdd_read <= 1'b0;
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
            end
            else
            begin
                select_d <= DEVICE_SELECT;
                if (DEVICE_SELECT == 1'b1)
                begin
	$display("inside loop, D_IN %x A[3:0] %x RD %x ",D_IN,A[3:0],RD);
                    if (RD == 1'b1)
                        case (A[3:0])
                            4'h0 :
                                begin
                                    sec_addr <= 9'b000000000;
                                    case (reg_command)
                                        PRODOS_COMMAND_STATUS :
                                            if (hdd_mounted == 1'b1 & reg_unit == 8'h70)
                                            begin
                                                reg_status <= 8'h00;
                                                D_OUT <= 8'h00;
                                            end
                                            else
                                            begin
                                                reg_status <= 8'h01;
                                                D_OUT <= PRODOS_STATUS_NO_DEVICE;
                                            end
                                        PRODOS_COMMAND_READ :
                                            if (hdd_mounted == 1'b1 & reg_unit == 8'h70)
                                            begin
	$display("HDD PRODOS COMMAND READ");
						if (~select_d)begin
                                                hdd_read <= 1'b1;
					end
                                                reg_status <= 8'h00;
                                                D_OUT <= 8'h00;
                                            end
                                            else
                                            begin
                                                reg_status <= 8'h01;
                                                D_OUT <= PRODOS_STATUS_NO_DEVICE;
                                            end
                                        PRODOS_COMMAND_WRITE :
                                            if (hdd_mounted == 1'b0 | reg_unit != 8'h70)
                                            begin
                                                D_OUT <= PRODOS_STATUS_NO_DEVICE;
                                                reg_status <= 8'h01;
                                            end
                                            else if (hdd_protect == 1'b1)
                                                D_OUT <= PRODOS_STATUS_PROTECT;
                                            else
                                            begin
	$display("HDD PRODOS COMMAND WRITE");
                                                D_OUT <= 8'h00;
                                                reg_status <= 8'h00;
                                                hdd_write <= 1'b1;
                                            end
                                        default :
                                            ;
                                    endcase
                                end
                            4'h1 :
                                D_OUT <= reg_status;
                            4'h2 :
                                D_OUT <= reg_command;
                            4'h3 :
                                D_OUT <= reg_unit;
                            4'h4 :
                                D_OUT <= reg_mem_l;
                            4'h5 :
                                D_OUT <= reg_mem_h;
                            4'h6 :
                                D_OUT <= reg_block_l;
                            4'h7 :
                                D_OUT <= reg_block_h;
                            4'h8 :
                                begin
                                    D_OUT <= sector_buf[sec_addr];
				    //$display("reading D_OUT %x to ram %x readonly %x",D_OUT,sec_addr,hdd_protect);
                                    increment_sec_addr <= 1'b1;
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
                                end
                            4'h3 :
                                reg_unit <= D_IN;
                            4'h4 :
                                reg_mem_l <= D_IN;
                            4'h5 :
                                reg_mem_h <= D_IN;
                            4'h6 :
                                reg_block_l <= D_IN;
                            4'h7 :
                                reg_block_h <= D_IN;
                            4'h8 :
                                begin
				    //$display("writing D_IN %x to ram %x readonly %x",D_IN,sec_addr,hdd_protect);
                                    sector_buf[sec_addr] <= D_IN;
                                    increment_sec_addr <= 1'b1;
                                end
                            default :
                                ;
                        endcase
                end
                // RD/WR
                else if (DEVICE_SELECT == 1'b0 & select_d == 1'b1)
                begin
                    if (increment_sec_addr == 1'b1)
                    begin
                        sec_addr <= sec_addr + 1;
                        increment_sec_addr <= 1'b0;
                    end
                end
                else if (IO_SELECT == 1'b1)		// Firmware ROM read
                begin
			$display("HDD IO_SELECT A %x rom_dout %x",A,rom_dout);
                    if (RD == 1'b1)
                        D_OUT <= rom_dout;
                end
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
