//
// zipgs_regs.sv  --  PROPOSED, NOT WIRED, NOT TESTED
//
// ZipGS ($C059-$C05F) accelerator register interface for the IIgs core. Lets period software
// (Zip control panel, ZIP-aware games) detect and set the CPU speed. Bit semantics follow the
// KEGS/GSplus reference: software_emulators/kegs/src/moremem.c:1322-1374, 1949-2015.
//
// Outputs a speed_code that the clock_divider maps to a fast clock-enable threshold (see
// doc/sdram_accel/03_speed_control_design.md and clock_divider_speed.sv). Pure synchronous,
// clock-enable friendly; no gated clocks.
//
// Tap this off the existing $C0xx I/O decode in rtl/iigs.sv (reads ~:864, writes ~:1149).
//

module zipgs_regs (
    input            clk,
    input            reset,

    // I/O access strobes from the $C0xx decoder (one-cycle pulses)
    input      [7:0] io_addr_lo,   // low byte of $C0xx address (0x59..0x5F of interest)
    input            io_sel,       // high when an access to $C05x is happening this cycle
    input            io_we,        // 1 = write, 0 = read
    input      [7:0] io_din,       // CPU write data
    output reg [7:0] io_dout,      // read data back to the CPU (when io_sel & ~io_we)

    // to the speed selector
    output           accel_en,     // 1 = accelerator active (else native 2.86 MHz)
    output     [2:0] speed_code    // 0..4 -> see thresh LUT in clock_divider_speed.sv
);
    // unlock: writes to $C05A with (val&0xF0)==0x50 increment; ==0xA0 reset. >=4 == unlocked.
    reg [2:0] unlock;
    wire      unlocked = (unlock >= 3'd4);

    reg [7:0] reg_c05a;   // speed register (valid when unlocked)
    reg [7:0] reg_c05b;   // bit4 = disable acceleration
    reg [7:0] reg_c059;

    assign accel_en   = ~reg_c05b[4];
    // map the ZipGS speed field (high nibble of $C05A) to our 5 achievable steps.
    // 0=2.86MHz(thresh4) .. 4=14.3MHz(thresh0). Saturate.
    wire [3:0] sp = reg_c05a[7:4];
    assign speed_code = (sp >= 4'd4) ? 3'd4 : sp[2:0];

    always @(posedge clk) begin
        io_dout <= 8'h00;

        if (reset) begin
            unlock   <= 3'd0;
            reg_c05a <= 8'h00;   // power-on: native speed
            reg_c05b <= 8'h10;   // power-on: acceleration disabled (bit4=1) -> behaves native
            reg_c059 <= 8'h00;
        end else if (io_sel) begin
            if (io_we) begin
                case (io_addr_lo)
                8'h5A: begin
                    if      ((io_din & 8'hF0) == 8'h50) unlock <= unlock + 3'd1;  // unlock step
                    else if ((io_din & 8'hF0) == 8'hA0) unlock <= 3'd0;           // relock
                    else if (unlocked)                  reg_c05a <= io_din;       // set speed
                end
                8'h5B: if (unlocked) reg_c05b <= io_din;   // bit4 enable/disable accel
                8'h59: if (unlocked) reg_c059 <= io_din;
                default: ; // $C05C-$C05F reserved
                endcase
            end else begin
                // reads (only meaningful when unlocked, matching KEGS)
                case (io_addr_lo)
                8'h59: io_dout <= unlocked ? reg_c059 : 8'h00;
                8'h5A: io_dout <= unlocked ? reg_c05a : 8'h00;
                8'h5B: io_dout <= unlocked ? reg_c05b : 8'h00;
                default: io_dout <= 8'h00;
                endcase
            end
        end
    end
endmodule
