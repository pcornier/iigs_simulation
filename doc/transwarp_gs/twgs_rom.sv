// ============================================================================
// twgs_rom.sv — TransWarp GS 32 KB firmware EPROM (27C256), mapped $BC8000-BCFFFF
//
// Synchronous read (inferred block RAM — M10K on Cyclone). Contents from the
// v1.8s ROM (twgs_rom.hex, generated from digarok/TransWarpGS-ROM
// rom/twgs_1.8s/twgs-rom.bin). Provides the 'TWGS'/'SMJS' detection signature
// at $BCFF00 and the JSL jump table at $BCFF08 — mapping this ROM is all that
// TWGS software detection requires.
//
// addr is the low 15 bits of the CPU address (CPU $BC8000 -> rom index 0).
// Registered output: present the access address (addr_bef) at least one clk
// before the CPU latches. See INTEGRATION.md — classify bank-$BC accesses as
// native-pace ("sync/slow") when accelerated so this latency always has slack
// (the real card runs its own ROM at <=1 MHz anyway).
//
// NOTE: adjust the $readmemh path to wherever twgs_rom.hex lives in your build
// (Verilator: relative to the sim CWD, usually vsim/; Quartus: add to the
// project or use an absolute/qsf-relative path).
// ============================================================================

module twgs_rom (
    input  wire        clk,
    input  wire        ce,            // registers a new byte when high
    input  wire [14:0] addr,          // CPU addr[14:0] (BC8000 -> 0)
    output reg  [7:0]  dout
);
  (* ram_init_file = "twgs_rom.hex" *)   // Quartus hint (optional)
  reg [7:0] rom_data [0:32767];

  initial $readmemh("twgs_rom.hex", rom_data);

  always @(posedge clk)
    if (ce) dout <= rom_data[addr];

endmodule
