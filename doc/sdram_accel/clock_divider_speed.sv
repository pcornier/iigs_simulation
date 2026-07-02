//
// clock_divider_speed.sv  --  PROPOSED, NOT WIRED, NOT TESTED
//
// Helper that maps an accelerator speed_code (from zipgs_regs.sv or a config bit) to the
// CLK_14M tick threshold used by rtl/clock_divider.v's fast cycle. Splice the output
// `fast_thresh` in place of the hard-coded `4'd4` at clock_divider.v:377 (and the refresh
// branch). See doc/sdram_accel/03_speed_control_design.md.
//
// Pure combinational LUT; trivial, but kept as a module so the mapping has one home and can be
// lint-checked. fast_thresh = (ph2_counter >= fast_thresh) fires ph2_en, so:
//   thresh 4 -> 5 ticks -> 2.8636 MHz (native, default)
//   thresh 3 -> 4 ticks -> 3.58 MHz
//   thresh 2 -> 3 ticks -> 4.77 MHz
//   thresh 1 -> 2 ticks -> 7.16 MHz
//   thresh 0 -> 1 tick  -> 14.32 MHz
//
module clock_divider_speed (
    input        accel_en,     // 0 -> force native (thresh 4) regardless of speed_code
    input        cpu_fast,     // CYAREG[7]: 0 -> slow path owns it; accel only applies when fast
    input  [2:0] speed_code,   // 0..4
    output [3:0] fast_thresh
);
    reg [3:0] t;
    always @(*) begin
        case (speed_code)
            3'd0:    t = 4'd4;   // 2.86 MHz
            3'd1:    t = 4'd3;   // 3.58 MHz
            3'd2:    t = 4'd2;   // 4.77 MHz
            3'd3:    t = 4'd1;   // 7.16 MHz
            3'd4:    t = 4'd0;   // 14.32 MHz
            default: t = 4'd4;
        endcase
    end
    // Only accelerate when the accelerator is enabled AND the machine is in fast mode;
    // otherwise fall back to the native 5-tick (thresh 4) fast cycle. (When CYAREG[7]=0 the
    // clock_divider's slow path runs instead, so cpu_fast just guards against accelerating a
    // nominally-slow machine.)
    assign fast_thresh = (accel_en && cpu_fast) ? t : 4'd4;
endmodule
