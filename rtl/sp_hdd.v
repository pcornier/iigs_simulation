//-----------------------------------------------------------------------------
//
// SmartPort HDD (IIgs internal Slot 5)
//
// Memory-mapped ProDOS block device registers at $C0D0–$C0DF.
// Implements the standard block-device register set without a slot ROM
// (IIgs system ROM provides SmartPort code for the internal device).
//
// Based on rtl/hdd.v (slot 7 implementation), with address base moved to $C0D0
// and the slot ROM path removed.
//
//-----------------------------------------------------------------------------
// Registers (standard block device)
// C0D0         (r)   EXECUTE AND RETURN STATUS
// C0D1         (r)   STATUS (or ERROR)
// C0D2         (r/w) COMMAND
// C0D3         (r/w) UNIT NUMBER
// C0D4         (r/w) LOW BYTE OF MEMORY BUFFER
// C0D5         (r/w) HIGH BYTE OF MEMORY BUFFER
// C0D6         (r/w) LOW BYTE OF BLOCK NUMBER
// C0D7         (r/w) HIGH BYTE OF BLOCK NUMBER
// C0D8         (r)   NEXT BYTE
//-----------------------------------------------------------------------------

module sp_hdd(
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
    input            IO_SELECT;         // ignored (no slot ROM for internal SmartPort)
    input            DEVICE_SELECT;     // active for $C0D0–$C0DF
    input            RESET;
    input [15:0]     A;
    input            RD;                // 6502 RD/WR
    input [7:0]      D_IN;              // From 6502
    output reg [7:0] D_OUT;             // To 6502
    output [15:0]    sector;            // Sector number to read/write
    output reg       hdd_read;
    output reg       hdd_write;
    input            hdd_mounted;
    input            hdd_protect;
    input [8:0]      ram_addr;          // Address for sector buffer
    input [7:0]      ram_di;            // Data to sector buffer
    output reg [7:0] ram_do;            // Data from sector buffer
    input            ram_we;            // Sector buffer write enable

    // Interface registers
    reg [7:0]        reg_status;
    reg [7:0]        reg_command;
    reg [7:0]        reg_unit;
    reg [7:0]        reg_mem_l;
    reg [7:0]        reg_mem_h;
    reg [7:0]        reg_block_l;
    reg [7:0]        reg_block_h;

    // Internal sector buffer offset counter
    reg [8:0]        sec_addr;
    reg              increment_sec_addr;
    reg              select_d;

    // Sector buffer
    reg [7:0]        sector_buf[0:511];

    // ProDOS constants
    localparam        PRODOS_COMMAND_STATUS = 8'h00;
    localparam        PRODOS_COMMAND_READ   = 8'h01;
    localparam        PRODOS_COMMAND_WRITE  = 8'h02;
    localparam        PRODOS_COMMAND_FORMAT = 8'h03;
    localparam        PRODOS_STATUS_NO_DEVICE = 8'h28;
    localparam        PRODOS_STATUS_PROTECT   = 8'h2B;

    assign sector = {reg_block_h, reg_block_l};

    always @(posedge CLK_14M) begin : cpu_interface
      // Default drive hi-Z value unless a read overrides
      D_OUT <= 8'hFF;

      // READ PATH
      if (DEVICE_SELECT && RD) begin
        case (A[3:0])
          4'h0: begin
            // EXECUTE/STATUS: return 0 (ok)
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
      end

      // WRITE/CONTROL, gated to phi0
      if (phi0) begin
        hdd_read  <= 1'b0;
        hdd_write <= 1'b0;

        if (RESET) begin
          reg_status   <= 8'h00;
          reg_command  <= 8'h00;
          reg_unit     <= 8'h00;
          reg_mem_l    <= 8'h00;
          reg_mem_h    <= 8'h00;
          reg_block_l  <= 8'h00;
          reg_block_h  <= 8'h00;
          sec_addr     <= 9'd0;
          increment_sec_addr <= 1'b0;
        end else begin
          select_d <= DEVICE_SELECT;
          if (DEVICE_SELECT) begin
            if (RD) begin
              case (A[3:0])
                4'h0: begin
                  sec_addr <= 9'd0;
                  case (reg_command)
                    PRODOS_COMMAND_STATUS: begin
                      reg_status <= 8'h00; D_OUT <= 8'h00;
`ifdef SIMULATION
                      $display("SP HDD RD C0D0: STATUS ok (unit=%02h)", reg_unit);
`endif
                    end
                    PRODOS_COMMAND_READ: begin
                      reg_status <= 8'h00; D_OUT <= 8'h00;
                      if (~select_d) hdd_read <= 1'b1;
`ifdef SIMULATION
                      $display("SP HDD RD C0D0: READ (blk=%04h) ok", {reg_block_h,reg_block_l});
`endif
                    end
                    PRODOS_COMMAND_WRITE: begin
                      if (hdd_protect) begin
                        D_OUT <= PRODOS_STATUS_PROTECT; reg_status <= 8'h01;
`ifdef SIMULATION
                        $display("SP HDD RD C0D0: WRITE protect");
`endif
                      end else begin
                        D_OUT <= 8'h00; reg_status <= 8'h00; hdd_write <= 1'b1;
`ifdef SIMULATION
                        $display("SP HDD RD C0D0: WRITE (blk=%04h) ok", {reg_block_h,reg_block_l});
`endif
                      end
                    end
                    default: begin
                      reg_status <= 8'h00; D_OUT <= 8'h00;
`ifdef SIMULATION
                      $display("SP HDD RD C0D0: unknown cmd %02h -> ok", reg_command);
`endif
                    end
                  endcase
                end
                4'h1: begin D_OUT <= reg_status; `ifdef SIMULATION $display("SP HDD RD C0D1: status=%02h", reg_status); `endif end
                4'h2: begin D_OUT <= reg_command; `ifdef SIMULATION $display("SP HDD RD C0D2: cmd=%02h", reg_command); `endif end
                4'h3: begin D_OUT <= reg_unit;    `ifdef SIMULATION $display("SP HDD RD C0D3: unit=%02h", reg_unit); `endif end
                4'h4: begin D_OUT <= reg_mem_l;   `ifdef SIMULATION $display("SP HDD RD C0D4: memL=%02h", reg_mem_l); `endif end
                4'h5: begin D_OUT <= reg_mem_h;   `ifdef SIMULATION $display("SP HDD RD C0D5: memH=%02h", reg_mem_h); `endif end
                4'h6: begin D_OUT <= reg_block_l; `ifdef SIMULATION $display("SP HDD RD C0D6: blkL=%02h", reg_block_l); `endif end
                4'h7: begin D_OUT <= reg_block_h; `ifdef SIMULATION $display("SP HDD RD C0D7: blkH=%02h", reg_block_h); `endif end
                4'h8: begin
                  D_OUT <= sector_buf[sec_addr];
                  increment_sec_addr <= 1'b1;
`ifdef SIMULATION
                  $display("SP HDD RD C0D8[%03d] -> %02h", sec_addr, sector_buf[sec_addr]);
`endif
                end
                default: ;
              endcase
            end else begin
              // writes
              case (A[3:0])
                4'h2: begin
                  if (D_IN == 8'h02) sec_addr <= 9'd0;
                  reg_command <= D_IN;
`ifdef SIMULATION
                  $display("SP HDD WR C0D2: cmd <= %02h", D_IN);
`endif
                end
                4'h1: begin
                  reg_status <= D_IN;
`ifdef SIMULATION
                  $display("SP HDD WR C0D1: status <= %02h", D_IN);
`endif
                end
                4'h3: begin reg_unit    <= D_IN; `ifdef SIMULATION $display("SP HDD WR C0D3: unit <= %02h", D_IN); `endif end
                4'h4: begin reg_mem_l   <= D_IN; `ifdef SIMULATION $display("SP HDD WR C0D4: memL <= %02h", D_IN); `endif end
                4'h5: begin reg_mem_h   <= D_IN; `ifdef SIMULATION $display("SP HDD WR C0D5: memH <= %02h", D_IN); `endif end
                4'h6: begin reg_block_l <= D_IN; `ifdef SIMULATION $display("SP HDD WR C0D6: blkL <= %02h", D_IN); `endif end
                4'h7: begin reg_block_h <= D_IN; `ifdef SIMULATION $display("SP HDD WR C0D7: blkH <= %02h", D_IN); `endif end
                4'h8: begin
                  sector_buf[sec_addr] <= D_IN;
                  increment_sec_addr <= 1'b1;
`ifdef SIMULATION
                  $display("SP HDD WR C0D8[%03d] <= %02h", sec_addr, D_IN);
`endif
                end
                default: ;
              endcase
            end
          end else if (~DEVICE_SELECT && select_d) begin
            if (increment_sec_addr) begin
              sec_addr <= sec_addr + 1; increment_sec_addr <= 1'b0;
            end
          end
        end
      end
    end

    // Sector buffer storage port
    always @(posedge CLK_14M) begin : sec_storage
      if (ram_we) sector_buf[ram_addr] <= ram_di;
      ram_do <= sector_buf[ram_addr];
    end

endmodule

