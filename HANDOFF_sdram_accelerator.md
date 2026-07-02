# Handoff: SDRAM controller & CPU accelerator (ZipGS/TransWarp) feasibility

## Status: RESEARCH + DESIGN. No production RTL wired yet. Detailed designs and lint-clean
## RTL sketches now exist under `doc/sdram_accel/` (see §6). Reference controllers are checked
## in under `ref/sdram_refs/`. Branch: `feat/sdram-accelerator`.

## Goal
Assess what it would take to add a CPU accelerator (run the 65C816 faster than the
native 2.8 MHz, like a ZipGS or TransWarp GS) to this FPGA core, and whether the SDRAM
controller is the limiting factor. Reference SDRAM controllers from four MiSTer console
cores were pulled into `ref/sdram_refs/` for comparison.

---

## 1. Current speed architecture (what already exists)

The core is already ~80% of the way to an accelerator: `clock_divider.v` already
distinguishes a **fast path** (RAM/ROM) from a **slow/sync path** (slow RAM, I/O), and the
fast/slow decision is made *combinationally from the address* before each access.

- Master clock `CLK_14M` = 14.318 MHz; `CLK_28M`/`clk_sys` = 28.636 MHz (`rtl/iigs.sv:18-20`).
- `rtl/clock_divider.v` produces `phi2` (CPU clock enable). Three modes:
  - **Slow** (`CYAREG[7]==0`): `ph2_en` every 14 CLK_14M ticks → 1.024 MHz (`clock_divider.v:322-336`).
  - **Sync** (slowMem=1): extend to 14-27 ticks to overlap a full PH0 (`clock_divider.v:337-357`).
  - **Fast** (`CYAREG[7]==1`, slowMem=0): 5 ticks → 2.8636 MHz, with a refresh penalty
    every 9th cycle (10 ticks) hidden during ROM access (`clock_divider.v:359-394`).
- Speed register `$C036` (CYAREG), bit 7 = fast/slow (`rtl/iigs.sv:161,864,1149`;
  bit map in `clock_divider.v:55-72`). Cold reset = `8'hC0` (fast).
- CPU: `P65C816 cpu(.CLK(CLK_14M), .CE(phi2), .RDY_IN(~hdd_dma), ...)` (`rtl/iigs.sv:2058-2075`);
  internal gate `EN = RDY_IN & CE & ~WAIExec & ~STPExec` (`rtl/65C816/P65C816.sv:117`).
- `slowMem` predicted combinationally from bank/addr (`clock_divider.v:242-280`): banks
  E0/E1, most of `$C0xx` I/O, and shadowed video writes. A handful of regs stay fast
  ($C035/36/37, $C02D rd, $C068 rd, $C071-7F).
- **Slow RAM (E0/E1) is on-chip dual-port BRAM** (`rtl/iigs.sv:1825-1846`); video reads on
  a separate port/clock → **video never stalls the CPU**, and an SDRAM-side cache would not
  need to be coherent with video (video doesn't read SDRAM).

### Key insight
Acceleration = make the fast path faster (fewer ticks/cycle) while leaving the sync path at
1 MHz. The fast/slow split you need already exists. On real hardware E0/E1 is slow DRAM that
accelerators must cache; **here E0/E1 is fast BRAM deliberately throttled to 1 MHz** for
video/Mega II/soft-switch timing. The real external-memory pressure is the **SDRAM fast RAM
(banks 00-7F)**, not E0/E1.

---

## 2. The SDRAM controller is the FPGA bottleneck

`rtl/sdram.sv` (Sorgelig base, adapted from Genesis_MiSTer):

- Runs at **114.5 MHz** = exactly **8× CLK_14M** (`sdram.sv:44`). The 8× ratio is cosmetic
  (clean phi2 alignment), not a MiSTer convention — cores pick any mem clock that meets the
  chip's timing (commonly 85-133 MHz).
- **One full row cycle per access**: ACTIVATE at state 1, tRCD=3, READ at state 4, CAS=3+1,
  data at state 8 (`sdram.sv:78-91`). Single word, **no burst** (`BURST_LENGTH=0`,
  `sdram.sv:79`), **no open-row**. Back-to-back accesses are tRC-bound (~66 ns); the round is
  padded to a 9-state/78.6 ns loop to satisfy tRC (`sdram.sv:91`).
- 3 channels (ch0 CPU writes, ch1 CPU reads, ch2 ROM upload), priority writes>reads>upload,
  refresh only when idle (`sdram.sv:122-164`). Refresh every 850 cyc ≈ 7.4 µs — not a
  bottleneck.
- **Toggle req/ack handshake per channel** (`sdram.sv:46-48`) — engineered so requesters in
  the slower CLK_14M domain can talk to the 114.5 MHz controller safely. CPU side toggles in
  `Apple-IIgs.sv:356-377`; read launches one clk_sys after phi2 (`Apple-IIgs.sv:344-348`).

### Corrected timing math (an earlier verbal estimate inverted this)
114.5/14.318 ≈ 8, so **1 CLK_14M tick = 8 controller cycles**; a 5-tick fast cycle = 40
controller cycles. One access ≈ 8 cycles ≈ 70 ns. Budgets:

| CPU speed | cycle time | controller cyc available | one access (~8 cyc + CDC) | verdict |
|---|---|---|---|---|
| 2.86 MHz (5 ticks, today) | 349 ns | 40 | ~70 ns + CDC | tons of slack |
| 7.16 MHz (2 ticks) | 140 ns | 16 | ~70 ns + CDC | tight; limiter is the req/ack CDC + launch delay, not the array |
| 14.3 MHz (1 tick) | 70 ns | 8 | ~70 ns + CDC | not possible as-is (one access eats the whole budget before precharge/refresh) |

So: **7 MHz is mostly reachable by trimming latency; 14 MHz needs a better access pattern.**
Lowering the mem clock to "4×" does NOT help — fewer-but-longer cycles, same nanoseconds,
less bandwidth. The lever is fewer *nanoseconds* per access (open-row page hits, CL2,
burst, bank interleave), or hiding latency behind a cache.

### Sim caveat (important)
`vsim/sim.v:312-325` models fast RAM as an **instant-access `dpram`** — no controller, no
CAS latency, no refresh. A faster CPU will "just work" in Verilator and then fail on real
FPGA. **Before chasing speed, add a cycle-accurate SDRAM model to the sim** (or test on HW).

---

## 3. Reference controllers pulled (in `ref/sdram_refs/`)

Pulled from MiSTer-devel master/main on 2026-06-27:

- `neogeo/` — `sdram.sv`, `sdram_mux.sv`
- `saturn/` — `sdram1.sv`, `sdram2.sv`
- `psx/` — `sdram.sv`, `sdram_model.vhd`, `sdram_model3x.vhd` (last two are sim-only)
- `n64/` — `sdram.sv`, `SDRamMux.vhd`

### Comparison

| | Yours (IIgs) | NeoGeo | PSX | N64 | Saturn1 | Saturn2 |
|---|---|---|---|---|---|---|
| Clock | 114.5 | ~100 | ~100 | ~100 | 128 | 128 |
| CAS | 3 | 2 | 2 | 2 | 3 | 3 |
| Per-access latency | 8-9 | ~7 | ~12 (128-bit line) | ~7 | 8-10 | 9-10 |
| **Burst** | **none** | 4-word | 4×2-word line | 2-word | none | 2-word/continuation |
| Open-row / page | no | no | no | no | no | no |
| Bank interleave | no | no | no | no | no | no |
| Channels | 3 | 2 (+mux→6) | 3+DMA FIFO | 3 (+mux→5) | 3 | 1 |
| Handshake | toggle req/ack | ready/busy pulse | level req+ready | req+reqprocessed+ready | combinatorial latch | `busy` flag |
| Lang | SV | SV | SV | SV (mux VHDL) | SV | SV |

### THE key finding (corrects an earlier claim in this thread)
**None of the four consoles uses open-row/page-mode or bank interleaving.** They are all the
same single-access-per-row Sorgelig state machine this core already uses, at ~7-10 cycles
per access (same ballpark as ours). Their *only* bandwidth advantage is **burst** — they
amortize one ACTIVATE+CAS over multiple words to fill a wide cache line. That's the whole
trick worth transplanting.

### Per-core verdict
- **PSX `sdram.sv`** — best **cache-line burst** reference: explicitly does 4×2-word bursts
  back-to-back to fill a 128-bit line "without latency or bandwidth penalty" (its comment).
  Directly analogous to an accelerator I-cache/D-cache line fill.
- **NeoGeo `sdram.sv`** — closest to our lineage (same Sorgelig base), simplest readable
  4-word burst, CAS2. Best minimal burst reference.
- **Saturn `sdram2.sv`** — cleanest single-channel skeleton; simple `busy` flag + burst-
  continuation trick (`st_num ← 0` skips re-RAS on a continued burst).
- **Saturn `sdram1` + all the muxes** — skip; device-oriented (RAM+VDP+sound), harder than
  ours; muxes wired to each console's clients.
- **PSX sim models** — reference only: VHDL (can't drop into Verilator) AND they don't even
  model tRCD/tRP, just CAS+burst delay. Write a small C++ DPI model instead.

### Can any be used as-is? No.
1. None solves the actual problem — they all share our ~7-10 cycle floor; only **open-row**
   improves random latency and **none of them implements it** (it's net-new work either way).
2. All use ready/busy handshakes in the SDRAM clock domain; ours uses a **toggle req/ack**
   built for the CLK_14M crossing. Importing a foreign controller means re-solving the CDC we
   already solved well → argues for keeping our shell.
3. Multi-channel arbitration is wired to each console's clients — dead weight here.
4. The VHDL bits (N64 mux, PSX sim models) can't go into the Verilator/Verilog sim.

---

## 4. Recommendation

Do **not** swap controllers. Keep `rtl/sdram.sv`'s toggle-req/ack shell (the hard, already-
working part) and graft in, using PSX/NeoGeo burst code as the pattern:

1. **Burst reads into a small line buffer** (= the accelerator cache). Highest-value change;
   gives a fast CPU effective ~1-2 cycles/word on sequential fetch. Coherency is easy here:
   video scans out of BRAM (E0/E1), not SDRAM, so the line buffer only needs invalidation on
   the CPU's own writes (ch0 of the same controller).
2. **Open-row tracking** (skip tRCD on a hit to the currently-open row) — net-new, improves
   *random* latency. Add second, incrementally.

Register/software interface for the accelerator itself (separate from the memory work):
- **ZipGS** ($C059-$C05F unlock + 16-step speed reg) is the well-documented, well-supported
  choice. Clean reference impls in `software_emulators/kegs` (`moremem.c:1322-1374,1949-2015`)
  and `software_emulators/gsplus` (same). GSplus also has a non-authentic TransWarp
  (`#ifdef TRANSWARP`, $C06A-$C06C) — lower value. Clemens and GSSquared implement neither
  (GSSquared just offers arbitrary user speeds 1/2.8/7.1/14.3/ludicrous and notes ZipGS as
  future work).
- Cheapest first step: a GSSquared-style turbo (more `clock_divider` speed steps) to prove
  the clock-enable plumbing, then layer ZipGS registers for real software compatibility.

### Suggested sequence
1. Add a **cycle-accurate SDRAM model** to the sim (C++ DPI; model tRCD/CAS/tRC/refresh) so
   speed experiments are honest. Without this, sim validates nothing about timing.
2. **Trim the req/ack CDC + read-launch latency** → unlocks ~7 MHz on the existing controller.
3. **Burst + line buffer with write-invalidate** → unlocks ~10-14 MHz; this *is* the cache.
4. Add **ZipGS** register interface to make it software-controllable.
5. (Optional) open-row tracking and/or bump mem clock toward 133 MHz for extra margin.

---

## 5. Design artifacts on this branch (`doc/sdram_accel/`)
The recommendation above is worked out in detail in three design docs, each with a lint-clean
(Verilator 5.044) RTL sketch. **All sketches are DESIGN ONLY — not wired, not synthesized, not
tested.** Per doc 02 the sim model (c) must land before (b)/(speed) can be trusted on HW.

- `01_burst_linebuffer_design.md` (b) + `sdram_cache.sv` — burst-8 read + clk_sys line buffer.
  Includes the **mandatory address remap** finding (current mapping puts low addr bits on the
  SDRAM row, which defeats bursts), coherency (CPU-write snoop only; video is on BRAM), and the
  `RDY_IN` stall-on-miss.
- `02_sim_model_spec.md` (c) + `sdram_sim_chip.sv` — put the REAL controller in the Verilator
  sim behind a behavioral SDRAM chip model with timing assertions + measurement counters
  (today's sim uses instant `dpram`, hiding all timing).
- `03_speed_control_design.md` + `clock_divider_speed.sv` + `zipgs_regs.sv` — the speed layer:
  variable clock-enable steps (2.86 / 7.16 / 14.3 MHz), ZipGS `$C059-$C05F` register interface,
  and how a cache hit completes in the fast step while a miss stalls via `RDY_IN`.
- `04_fpga_integration.md` — **production wiring + Quartus bring-up**. The burst+cache path is
  folded into the FPGA build behind `` `ifdef ACCEL_SDRAM `` (default OFF = known-good path):
  `rtl/sdram_burst.sv` (3-channel burst controller), `rtl/sdram_cache.sv` (line buffer), the
  `Apple-IIgs.sv` read-bridge rewire, and `files.qip`. Verified in sim by
  `vsim/sdram_tb/tb_accel.sv` (36/36, mirrors the real bridge); synthesis/timing/HW test are the
  Quartus box's remaining job (enable `VERILOG_MACRO "ACCEL_SDRAM=1"`).

### Verified prototypes / tests (all in `vsim/sdram_tb/`, Verilator)
- `tb_sdram` — real `rtl/sdram.sv` vs chip model: single-word baseline 9.00 cyc/word.
- `tb_burst` — `rtl/sdram_burst.sv`: 2.37 cyc/word (3.8×).
- `tb_cache` — cache+burst locality: hot loop 0.29 cyc/word (31×), coherency PASS.
- `tb_accel` — production controller+cache+bridge integration: 36/36 incl. coherency.

## 6. Pointers
- Current controller: `rtl/sdram.sv`; integration `Apple-IIgs.sv:344-377`; sim model
  `vsim/sim.v:312-325`.
- Clock/speed: `rtl/clock_divider.v`; CYAREG `rtl/iigs.sv:161,864,1149`; CPU CE
  `rtl/iigs.sv:2058-2075`, `rtl/65C816/P65C816.sv:117`.
- References (checked in): `ref/sdram_refs/{neogeo,saturn,psx,n64}/`.
- Accelerator register semantics: `software_emulators/kegs/src/moremem.c` (ZipGS),
  `software_emulators/gsplus/src/moremem.c` (ZipGS + TransWarp).
