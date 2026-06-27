# (c) Cycle-accurate SDRAM model for the Verilator sim

Problem: `vsim/sim.v:312-325` models fast RAM as an **instant-access `dpram`** and does **not
instantiate `rtl/sdram.sv` at all**. So in simulation the SDRAM controller's timing (CAS
latency, tRCD, tRC, refresh, burst, the req/ack round trip) simply doesn't exist — a faster
CPU "works" in sim and then fails on real FPGA. Every claim in doc `01_*` about timing is
therefore **unverifiable in the current sim**. This spec fixes that.

Status: SPEC + RTL SKETCH. The deliverable is a behavioral SDRAM **chip** model plus the wiring
to put the real controller in the loop. Lead implementation is pure SystemVerilog (Verilator
compiles it directly — no DPI, no VHDL). A C++/DPI variant is described as an alternative.

---

## 1. What to model, and where

Model the SDRAM at the **chip pin interface** (SDRAM_DQ / SDRAM_A / SDRAM_BA / nRAS / nCAS /
nWE / CKE / CLK), not at the channel interface. Reason: a pin-level chip model exercises the
*actual* `rtl/sdram.sv` controller — its command sequencing, CAS latency, refresh, and any
future burst/open-row changes from doc `01_*` — so the sim validates the thing you'll ship.
(This mirrors what PSX does with `sdram_model.vhd`, except those models are VHDL and don't even
model tRCD/tRP; we do better and in SV.)

```
   Vemu (Verilator)
     emu / iigs  --(req/ack channels)-->  rtl/sdram.sv  --(SDRAM_* pins)-->  sdram_sim_chip.sv
                                          (REAL controller)                  (behavioral array+timing)
```

Two integration edits (see §4): instantiate the real controller in the sim, and attach the
chip model to its pins. Keep the old instant `dpram` behind a `+define` so existing
regression runs stay fast by default; enable the accurate path when measuring timing.

---

## 2. Behavioral chip model requirements

The model in `doc/sdram_accel/sdram_sim_chip.sv` must:

1. **Decode commands** from {nRAS,nCAS,nWE} each rising `clk`: ACTIVATE, READ, WRITE,
   PRECHARGE, AUTO_REFRESH, LOAD_MODE, NOP, BURST_TERMINATE (same encodings as
   `sdram.sv:207-214`).
2. **Track per-bank open row** and capture the active row on ACTIVATE.
3. **Return read data with the programmed CAS latency** (from the LOAD_MODE value), driving
   SDRAM_DQ on the correct cycle(s); support **burst length** from the mode register so the
   doc `01_*` burst-8 read is exercised.
4. **Honor auto-precharge (A10)** on READ/WRITE.
5. **Model write byte masks** via DQML/DQMH (SDRAM_A[12:11] in this controller, see
   `sdram.sv:76`).
6. **Enforce timing as assertions (optional but recommended)** — flag violations rather than
   silently "working":
   - tRCD: READ/WRITE only allowed >= RASCAS_DELAY cycles after ACTIVATE to that bank.
   - tRP: ACTIVATE only allowed >= tRP cycles after PRECHARGE.
   - tRC / tRAS: ACTIVATE-to-ACTIVATE and ACTIVATE-to-PRECHARGE minimums.
   - tREF: assert that every row is refreshed within the refresh window; warn on miss.
   - Access to a bank with no open row, or a row mismatch, is an error.
   These assertions are the entire point: they turn "silently wrong on HW" into a loud sim
   failure. Gate them behind a parameter so they can be downgraded to warnings.
7. **Back the array** with a Verilator-friendly memory (`reg [15:0] mem [0:DEPTH-1]`), shared
   with the ROM/disk loader so existing image loading still works.

Timing parameters come from the *part the controller assumes* — MT48LC16M16A2 at 114.5 MHz:
CAS=3, tRCD≈3cyc, tRP≈3cyc, tRC≈8cyc, refresh 8192 rows / 64 ms. Parameterize them so a
different clock (e.g. a 100 MHz CAS2 experiment) can be tried.

---

## 3. Measurement hooks (the reason to build this)

Add free-running counters in the chip model (or a small monitor module) and print them at
`--stop-at-frame`, so speed experiments are quantified, not guessed:

- `n_activate`, `n_read`, `n_write`, `n_refresh`, `n_precharge`
- `read_words` (count of words actually delivered — burst beats)
- `stall_cycles`: clk cycles the CPU spent with `RDY_IN=0` waiting on a miss (export from the
  cache / controller)
- derived: **effective MB/s**, **avg cycles/read**, **% row-hits** (once open-row exists),
  **cache hit rate** (from `sdram_cache`).

A regression like `./obj_dir/Vemu --woz <disk> --stop-at-frame 600` should print these so a
before/after burst comparison is a single diff.

---

## 4. Integration into the sim

### 4a. Put the real controller in the loop (`vsim/sim.v`)
Replace (under a `+define` switch) the fast `dpram` (`vsim/sim.v:312-325`) with:
```verilog
`ifdef SDRAM_ACCURATE
   sdram sdram_i (
       .clk   (clk_mem),          // need a 114.5 MHz sim clock (see 4c)
       .init  (sdram_init),
       // ch0 CPU writes, ch1 CPU reads (burst), ch2 ROM upload -- wire from existing nets
       .addr0(wr_addr), .din0(wr_din), .wrl0(wr_wrl), .wrh0(wr_wrh), .req0(wr_req), .ack0(wr_ack),
       .addr1(rd_addr), .req1(rd_req), .ack1(rd_ack), .dout1(rd_line /*128b*/),
       .addr2(up_addr), .din2(up_din), .wrl2(up_wrl), .wrh2(up_wrh), .req2(up_req), .ack2(up_ack),
       .SDRAM_DQ(s_dq), .SDRAM_A(s_a), .SDRAM_BA(s_ba),
       .SDRAM_DQML(s_dqml), .SDRAM_DQMH(s_dqmh),
       .SDRAM_nCS(s_ncs), .SDRAM_nWE(s_nwe), .SDRAM_nRAS(s_nras), .SDRAM_nCAS(s_ncas),
       .SDRAM_CLK(), .SDRAM_CKE()
   );
   sdram_sim_chip #(.CAS(3)) chip_i (
       .clk(clk_mem), .dq(s_dq), .a(s_a), .ba(s_ba),
       .dqml(s_dqml), .dqmh(s_dqmh),
       .ncs(s_ncs), .nras(s_nras), .ncas(s_ncas), .nwe(s_nwe)
   );
`else
   // existing instant-access dpram (default; keeps regression fast)
`endif
```
This is also the moment to validate the doc `01_*` burst changes: with `SDRAM_ACCURATE`
defined and the burst controller in, run the cache + measure.

### 4b. `altddio_out` in `rtl/sdram.sv`
The controller instantiates `altddio_out` (`sdram.sv:244-267`) for `SDRAM_CLK`. Verilator
can't compile the Altera primitive. Provide a sim stub (a `altddio_out` shim that just forwards
the clock) under the sim include path, or `ifdef VERILATOR` it out inside the controller. The
chip model doesn't need SDRAM_CLK (it uses `clk` directly), so a no-op stub is fine.

### 4c. The 114.5 MHz sim clock
The C++ harness (`vsim/sim_main.cpp`) currently toggles the sim's clocks. Add a `clk_mem`
toggling at 8× `CLK_14M` (the controller is `8× CLK_14M`). Either generate it in the C++ tick
loop alongside the existing clocks, or derive it in `sim.v` from a faster base. Keep the
req/ack toggles crossing CLK_14M↔clk_mem exactly as on HW so the CDC is exercised.

### 4d. Makefile / flags
- Add `-DSDRAM_ACCURATE` opt-in (e.g. `make SDRAM=accurate`).
- Default build keeps the instant `dpram` so `regression.sh` stays fast and unchanged.
- Add the new sources to the Verilator file list only under the accurate build.

---

## 5. Validation plan
1. Build `make SDRAM=accurate`; boot a known-good disk; confirm identical screenshots to the
   instant-`dpram` build at several frames (proves the accurate path is functionally correct
   before trusting its timing).
2. Turn on the timing assertions; boot again; expect **zero** violations with the *current*
   single-word controller (it's already spec-correct on HW). Any assertion firing = a model or
   wiring bug to fix before proceeding.
3. Apply the doc `01_*` burst controller + `sdram_cache`; re-run; assertions must stay clean.
4. Bump `clock_divider` to 2-tick (7.16 MHz) then 1-tick (14.3 MHz); watch `stall_cycles`,
   cache hit rate, and assertions. This is the real go/no-go for each speed step.

---

## 6. Why SystemVerilog, not the PSX VHDL models or DPI
- **VHDL** (`ref/sdram_refs/psx/sdram_model*.vhd`): Verilator can't compile it; and those
  models skip tRCD/tRP anyway. Reference only.
- **C++/DPI**: viable and fast for a huge array, but adds DPI plumbing and you lose the
  free SystemVerilog timing assertions. Worth it only if the SV array hurts sim performance.
  If chosen: expose `sdram_read(addr)`, `sdram_write(addr,data,be)` and a per-clock
  `sdram_tick(cmd,a,ba)` that returns DQ with modeled latency; keep the same assertions in C++.
- **SystemVerilog** (this spec): compiles in Verilator, models timing, gives free
  `assert`/`$error` timing checks, and lives next to the RTL. Recommended.

See `doc/sdram_accel/sdram_sim_chip.sv` for the skeleton.
