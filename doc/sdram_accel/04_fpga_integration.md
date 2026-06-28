# (FPGA) Accelerator memory path integration — Quartus bring-up

This is the production wiring of the burst+cache memory path into the FPGA build, plus what the
Quartus box must do to synthesize, close timing, and validate on hardware. The logic is
verified in simulation at the module + bridge level (`vsim/sdram_tb/tb_accel.sv`, 36/36); it is
**not** synthesized or HW-tested yet — that is this doc's job for whoever runs Quartus.

## What is wired (all behind `` `ifdef ACCEL_SDRAM ``, default OFF)

- `rtl/sdram_burst.sv` — 3-channel controller, ch1 = burst-8 read → 128-bit line. Same pinout,
  clock (`clk_mem`=114.5 MHz), `init`, and toggle req/ack as `rtl/sdram.sv`. Implements the
  mandatory address remap (column = low bits).
- `rtl/sdram_cache.sv` — 8-line × 8-word line buffer on the CPU read path (clk_sys domain).
- `Apple-IIgs.sv` — under `ACCEL_SDRAM`: instantiates `sdram_burst` + `icache`, routes CPU
  reads through the cache, snoops ch0 writes for coherency. **Default (macro undefined) is the
  original single-word `sdram` path, byte-for-byte unchanged** — current bitstreams are unaffected.
- `files.qip` — adds `rtl/sdram_burst.sv` and `rtl/sdram_cache.sv` (harmless when the macro is
  off; unused modules are dropped by synthesis).

## How to enable
Add the Verilog macro in `Apple-IIgs.qsf` (or pass to Quartus):
```
set_global_assignment -name VERILOG_MACRO "ACCEL_SDRAM=1"
```
Then recompile. To roll back, remove the macro (instant return to the known-good path).

## What is verified vs not
- **Verified (Verilator):** controller command sequencing + CAS alignment, burst-8 read-back
  integrity, ch0/ch2 single-word writes, ch1 cached reads, write-snoop coherency, write-then-
  fill hazard — all against a behavioral chip model with tRCD/tRP/tRC/refresh assertions.
  Measured 3.8× (raw burst) and up to 31× less SDRAM traffic on hot loops (docs 01).
- **NOT verified here:** synthesis, Fmax/timing closure at 114.5 MHz, real-chip electrical
  timing, and booting GS/OS on hardware through the accel path. Do these on the Quartus box.

## Quartus bring-up checklist
1. **Synthesize with `ACCEL_SDRAM=1`.** Expect `sdram_burst` + `sdram_cache` to elaborate;
   `altddio_out` resolves to the same Altera megafunction `rtl/sdram.sv` already uses.
2. **Timing (`sys/sys_top.sdc`, `timing_paths.tcl`).** The burst controller's per-cycle logic
   is comparable to `sdram.sv` (same RAS/CAS, same 114.5 MHz `clk_mem`); the read *round* is
   longer (≈19 vs 9 cycles) but each cycle does no more work. Confirm `clk_mem` Fmax still
   meets 114.5 MHz and the SDRAM_DQ/-A/-cmd output/ input timing constraints pass. The 128-bit
   `rd_line` bus and the cache BRAM (8×128b data + tags) are new — check the cache infers BRAM
   and meets clk_sys (14.3 MHz, easy) timing.
3. **CDC review.** `sdram_cache` runs in clk_sys; it samples the controller's `ack1` (clk_mem
   domain) with a single FF (`mem_ack_d`), matching the original bridge's practice. For
   robustness consider a 2-FF synchronizer on `mem_ack` into clk_sys before taping out.
4. **Functional HW test (native 2.8 MHz first).** Boot the regression set (GS/OS, Total Replay,
   Arkanoid, BASIC, WOZ 3.5"). Behavior must match the non-accel build exactly — at 2.8 MHz a
   cache miss (one ~19-cycle clk_mem burst ≈ 2.4 clk_sys) completes within a CPU cycle, so **no
   CPU stall is needed and none is wired**. If anything misbehaves, suspect: address remap
   bijection, the write-snoop timing (`snoop_stb` is one clk_sys late, when `wr_addr`/`wr_din`
   hold the committed write), or the cache CDC.
5. **Then measure / go faster.** With the accel path stable at 2.8 MHz, add the higher clock
   steps (doc 03): drive `cache_stall` into the CPU `RDY_IN` (currently `~hdd_dma` inside
   `rtl/iigs.sv`), then shorten the `clock_divider` fast cycle (2 ticks = 7.16 MHz, 1 = 14.3).
   A miss MUST stall at those speeds; verify stall coverage before trusting it.

## Key correctness notes
- **Address remap is internal and consistent.** `sdram_burst` shreds the flat 24-bit word
  address onto RAS/CAS/BA differently than `sdram.sv` (column = low bits, required for bursts).
  This is invisible to the rest of the system because **all** channels — ch0 write, ch1 read,
  ch2 upload — use the same `a_bank/a_row/a_col`, so ROM/disk images load and read back
  consistently. It must remain a bijection over the used address space.
- **Coherency scope.** The cache only needs to snoop CPU writes (ch0) because video scans out
  of BRAM (E0/E1), not SDRAM. The snoop updates any cached copy of a written word (handles
  self-modifying code / data writes). ch2 (upload) happens before normal execution.
- **No benefit at 2.8 MHz, by design.** At native speed the SDRAM already keeps up, so the
  accel path should be *functionally identical* and no faster — it is the substrate that makes
  the doc-03 clock steps possible. The win appears only once the CPU clock is raised.

## Reproduce the sim verification
```
cd vsim/sdram_tb
./build_accel.sh && ./obj_dir/Vtb_accel    # production controller+cache+bridge: 36/36
./build_cache.sh && ./obj_dir/Vtb_cache    # locality/bandwidth numbers
```
