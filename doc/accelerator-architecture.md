# IIgs Accelerator & Memory-Path Architecture

How the ZipGS-style CPU acceleration works in this core, and how the SDRAM
read cache works, in detail. Companion documents: `doc/zipgs_speed.md`
(feature/protocol history), `doc/zipgs-14mhz-plan.md` (the 14.3 MHz failure
analysis and fixes), `doc/sdram_accel/01..04` (original design notes),
`doc/fpi_timing.md` (stock FPI timing the native mode reproduces).

```
                 ┌────────────────────────── iigs.sv ───────────────────────────┐
 OSD speed ──────►  zipgs_regs ($C058-5F)  ─── speed_code ──┐                   │
 $C05x software ─►  (unlock/enable/speed)                   ▼                   │
                 │                       fast_thresh = 4-code (hold-offs force 4)│
                 │                                           │                   │
                 │   clock_divider ◄─────────────────────────┘                   │
                 │   (PH0 grid, fast/slow/sync cycles, eff_thresh latch,         │
                 │    fast_escape gate)──► ph2_en ──► CPU CE                     │
                 │                                    ▲                          │
                 │                    RDY_IN = ~hdd_dma & ~mem_stall             │
                 └───────────────────────────────────┼───────────────────────────┘
                                                     │ mem_stall
        ┌── Apple-IIgs.sv bridge ────────────────────┴─────────────────────────┐
        │ accel_r (phi2-latched datapath select)                               │
        │   0: ch3 single-word registered read (native, never stalls)          │
        │   1: ch1 burst-8 line fill ──► sdram_cache (comb hit) ── stall-on-miss│
        │ ch0: posted single-word writes + wr_pending back-pressure + snoop    │
        │ ch2: HPS ROM upload (ioctl_wait throttled)                           │
        └───────────────► sdram_burst (clk_mem 114.5 MHz) ───► SDRAM chip      │
```

---

## 1. What is being emulated

A ZipGS/TransWarp-class accelerator: a faster 65C816 with a small cache in
front of motherboard RAM, which

- runs **CPU fast cycles** at an accelerated rate,
- leaves **everything the Mega II side owns at stock speed**: I/O ($C0xx),
  banks $E0/$E1, shadowed-video writes, and (configurably) slot ROM space —
  these still take authentic 1 MHz sync cycles,
- **overrides the motherboard speed switch**: with the accelerator engaged,
  clearing CYAREG bit 7 ($C036) does *not* slow the CPU (real Zip behavior —
  its own software depends on this during speed self-tests),
- drops to **native speed around floppy work** (IWM hold-off ~2 ms per
  $C0E0-EF access, plus motor-on spans) and during **HDD DMA**, like real
  cards that can't accelerate mechanical timing,
- exposes the **ZipGS register file at $C058-$C05F** after the 4×-$5x unlock
  sequence, with KEGS/GSplus-verified semantics ($C05D write sets speed,
  $C05A disables, $C05B enables, $C05A bit7 = 1 ms timebase the Zip CDA and
  CDev poll). While locked, those addresses remain the annunciators.

Speed steps (fast-cycle length in 14.318 MHz ticks):

| step | ticks | MHz   | source                     |
|------|-------|-------|----------------------------|
| 0    | 5     | 2.864 | native (accelerator off)   |
| 1    | 4     | 3.58  | OSD / $C05D                |
| 2    | 3     | 4.77  | OSD / $C05D                |
| 3    | 2     | 7.16  | OSD / $C05D (Zip rated max)|
| 4    | 1     | 14.32 | OSD only (host overclock)  |

`fast_thresh = ticks - 1` is the value the clock divider actually consumes.

---

## 2. The clock divider (`rtl/clock_divider.v`)

The CPU has no clock of its own; it runs on `ph2_en` clock-enable pulses in
the 14.318 MHz domain. One pulse = one CPU bus cycle completes. The divider
schedules pulses according to the *class* of the access on the bus:

- **Fast cycle** — `eff_thresh+1` ticks. At native, every 9th fast RAM cycle
  stretches to 10 ticks (FPI DRAM refresh steal; ROM hides it). Accelerated
  steps skip the refresh model (a real Zip's cache hides refresh). One fast
  cycle per scanline absorbs a +2 tick NTSC stretch so the CPU scanline is
  exactly 912 ticks, phase-anchored to the VGC beam.
- **Slow cycle** — pure 1.023 MHz mode (motor-on waits at native): one pulse
  per PH0 period.
- **Sync cycle** — an access the Mega II owns. The cycle is stretched until
  it contains a full PH0 period (14-27 ticks), firing on the PH0 boundary,
  exactly like the FPI. Classification (`slow_class_now`, and its registered
  twin `slowMem`):
  - banks $E0/$E1,
  - $C0xx I/O in banks 0/1 when IOLC shadowing is on (with the HW-ref
    exceptions that are always fast: $C035-37, $C071-7F, reads of
    $C02D/$C068),
  - shadowed-video writes (text/hires/SHR ranges, per shadow register),
  - slot space $C100-C7FF when accelerated (real-Zip default slot delay),
  - **except** $C058-5F while the Zip registers are unlocked (on-card
    registers respond at full speed — the Zip CDA's speed measurement polls
    $C05A in a tight loop).

Acceleration shortens **only fast cycles**. Slow/sync cycles are untouched,
which is why I/O-heavy code sees much less than the headline speedup.

### 2.1 Two-flop classification and the 1-tick problem

`slowMem` is registered (one tick after the address), which is fine at
native (the decision point is 3 ticks before the cycle ends). At 2-tick
cycles the comb mirror `slow_class_now` holds the fast-cycle fire until
`slowMem` reroutes the access. At **1-tick cycles there is no spare edge**:
the enable that completes a cycle was registered before that cycle's address
existed. Two mechanisms close this:

- **`fast_escape` output gate**: `ph2_en = ph2_en_r & ~fast_escape`, where
  `fast_escape = (eff_thresh != 4) && !dma && !slow && !slowMem &&
  slow_class_now`. A slow-classified access's premature pulse is suppressed
  combinationally; the access stays uncommitted (the CPU's CE never sees the
  pulse) and the registered `slowMem` reroutes it to a proper sync cycle one
  tick later. Provably a no-op at native and at ≥2-tick steps (the fire-hold
  already prevents the pulse there).
- The only same-cycle control at 1 tick is the CPU's **RDY** input
  (`EN = RDY_IN & CE` in P65C816) — everything that must react to the
  *current* address within the same tick (cache miss, write back-pressure)
  goes through `mem_stall` → RDY, never through the registered enable.

### 2.2 The latched cycle-length threshold (`eff_thresh`)

`fast_thresh` changes combinationally (IWM hold-off expiry, HDD-DMA end,
$C05D/OSD writes). If the in-flight cycle's fire compare consumed it live, a
native→fast transition would *shorten the cycle already in progress* — while
the top level's datapath select (`accel_r`, §4) is still latched at native.
Result: 1-tick reads served by the never-stalling native read path with a
cold data register — stale bytes, no stall, no error. (This was the 14.3 MHz
GS/OS boot corruption; boot toggles hold-offs on every floppy scan and HDD
sector.)

Therefore the divider latches the threshold **on each gated `ph2_en` fire**:

```verilog
reg [3:0] eff_thresh = 4'd4;              // reset = native
always @(posedge clk_14M)
    if (reset)       eff_thresh <= 4'd4;
    else if (ph2_en) eff_thresh <= (dma_active ? 4'd4 : fast_thresh);
```

Apple-IIgs.sv latches `accel_r` on the same edge (`if (phi2) accel_r <=
accel_active`), so **cycle length and datapath selection always change as a
matched pair**, and no cycle can shorten mid-flight. Speed changes take
effect at the next cycle boundary — which is also what real hardware does.

### 2.3 ZipGS behavioral overrides

- `slow_request` ignores CYAREG[7] while accelerated (Zip overrides the
  motherboard switch; its own software clears $C036 before measuring speed).
- 5.25" motor-on detect ($C0x8/9 + CYAREG[0:3]) still forces slow mode.
- `dma_active` (HDD DMA) forces the native 5-tick pace — the DMA engine's
  registered data paths are tuned for it.

---

## 3. Speed control plumbing

One state, three writers, all agreeing:

- **OSD "CPU Speed"** (`status[14:12]`) → `host_speed` → drives
  `zipgs_regs.speed_code` directly. Step 4 (14.3) is OSD-only.
- **ZipGS software protocol** (`rtl/zipgs_regs.sv`): unlock = 4 consecutive
  $5x writes to $C05A; then $C05D bits 7:4 set speed (software caps at step
  3 = 100% of a real Zip's rating), $C05A write disables, $C05B write
  enables. $C05A bit 7 always toggles at 1 ms (the CDA/CDev timebase).
  Percent-of-rated is how Zip software *displays* speed — at step 4 it still
  shows ~6.7-6.9 MHz because it clamps at 100% of the 7.16 rating.
- **OSD "ZipGS Registers" toggle** (`status[15]`): Disabled = stock IIgs
  (unlock ignored, software sees no Zip; OSD speed still works as a
  host-only turbo).

`fast_thresh` is then `4 - speed_code`, overridden to 4 (native) while:
floppy motor is on, any $C0E0-EF (IWM) access happened in the last ~2 ms, or
HDD DMA is active. `accel_active = (fast_thresh != 4) && !hdd_dma` feeds the
top-level datapath latch.

---

## 4. The memory datapath (`Apple-IIgs.sv` bridge)

Fast RAM (banks $00-$7F) and ROM live in SDRAM. The bridge between the CPU
and the SDRAM controller selects one of two read paths by the **phi2-latched
`accel_r`**:

### 4.1 Native read path (ch3) — `accel_r = 0`

One registered single-word read per cycle: launched at `phi2_d` (one tick
after the cycle starts, when the address has settled), the controller
answers with first-beat-early ack in 10-18 clk_mem (1.25-2.25 ticks), and
the byte is registered continuously into `nat_data` — arriving well before
the native 5-tick sample point. **Never stalls, cycle-exact** — this is what
preserves beam-racing timing at native (the burst+cache path's miss stalls
broke textfunk/FTA cycle-exactness, which is why the path is speed-selected
at all).

The corollary: `nat_data` is **cold while accelerated** (no ch3 launches
happen when `accel_r=1`) and its data is only valid for ≥2-tick cycles. Both
facts are why the §2.2 latch pairing matters.

### 4.2 Accelerated read path (ch1 + cache) — `accel_r = 1`

Reads are served by `sdram_cache` (§5). On a hit, data is combinational and
meets a 1-tick deadline. On a miss, one burst-8 line fill is launched and
the CPU is held via RDY:

```
mem_stall = accel_r & ~we & (fastram_ce | rom_ce) & ~cache_hit_now   // read miss
          | accel_r &  we &  fastram_ce & wr_pending                 // write buffer full
```

The stall is combinational off the *current* address; the CPU samples it
through RDY at the cycle-ending edge, so it is self-covering at every speed
step including 1-tick.

### 4.3 Write path (ch0) — posted, snooped, back-pressured

Writes are posted at the phi2 edge (the same point a real 65816 bus latches
write data): address/data/byte-lane registered, `wr_req` toggled. ch0 has
**top arbitration priority** in the controller, so a read fill launched by
the *next* cycle can never be served ahead of a write posted this cycle
(read-after-write ordering is structural).

One controller write takes ~9 clk_mem ≈ 78.6 ns; a 1-tick CPU can commit a
write per 69.8 ns. Without back-pressure a second `wr_req` toggle lands
while the first write is in flight and the controller's `ack0 <= req0`
absorbs it — the write silently never reaches SDRAM (and the cache snoop
masks the loss until eviction: delayed corruption). Hence:

- `wr_pending = (wr_req != wr_ack_s2)` (2-FF synchronized ack),
- a new write **stalls via RDY while a post is pending** (accelerated only —
  a native write retires in ~1.2 ticks of its 5-tick cycle),
- the post and the snoop strobe are gated identically, so a stalled cycle
  posts exactly once when it actually commits.

### 4.4 Upload path (ch2)

HPS ROM downloads, throttled by `ioctl_wait` (one in-flight word). Load-time
only.

### 4.5 HDD DMA

The DMA engine doesn't honor RDY; it is paced by `phi2 & ~mem_stall` and the
whole system drops to native for its duration (`fast_thresh` hold-off +
`accel_active` excludes `hdd_dma`, so `accel_r=0` and DMA reads use ch3).
DMA writes go through the same ch0 post + snoop as CPU writes, at native
pace. The CPU is frozen by RDY for the whole transfer, so DMA never overlaps
CPU-initiated cache activity.

---

## 5. The cache (`rtl/sdram_cache.sv`) in detail

A small **direct-mapped line buffer**, not a general cache:

| parameter | value | note |
|-----------|-------|------|
| lines     | 8     | `LINES` |
| line size | 8 words = 16 bytes | == controller burst length |
| total     | 128 bytes | deliberately tiny: it's a prefetch buffer |
| indexing  | word addr bits [6:4] | 128-byte stride between conflicts |
| tag       | addr bits [24:7] (18 bits) + valid | |
| domain    | clk_sys (14.318 MHz), pure synchronous, clock-enable style | |

Address decode for `cpu_addr[24:1]` (word address): `c_word = [3:1]`,
`c_idx = [6:4]`, `c_tag = [24:7]`.

### 5.1 Hit path (combinational)

```verilog
hit_now      = valid[c_idx] && (tag[c_idx] == c_tag);
cpu_data_now = data[c_idx][{c_word,4'b0} +: 16];      // async array read
```

`hit_now`/`cpu_data_now` are combinational off the current CPU address —
this is the port that meets the data deadline at **every** clock-enable
step, including 1-tick. Glitches don't matter: the CPU samples through RDY
synchronously. (A registered `cpu_data/cpu_ready` pair exists for
compatibility/testbenches; it lands 1-2 clk after the strobe, too late below
5-tick cycles, and is not used by the production datapath.)

### 5.2 Miss FSM and the fill

On `cpu_rd` (strobed from `phi2_d` while accelerated) with `hit_now=0`:

1. capture `fill_idx/fill_tag/fill_word`, set `mem_addr` to the aligned line
   base, toggle `mem_req` → S_FILL. The top-level `mem_stall` already holds
   the CPU (comb), so the address is frozen for the duration.
2. the controller does one ACTIVATE + READ burst-8 (~19 clk_mem ≈ 166 ns)
   and toggles `mem_ack` with the 128-bit line held stable until the next
   request.
3. `mem_ack` is brought into clk_sys through a **2-FF synchronizer** and
   edge-detected on the synchronized copy. (History: a single-FF sample
   compared against the raw async signal let metastable captures corrupt
   fills — harmless at 2.8 MHz, the cause of intermittent 7.16 boot crashes.
   Never edge-detect across a CDC on the raw signal.)
4. on the synced edge: `data/tag/valid[fill_idx]` updated, FSM → S_IDLE.
   `hit_now` rises, the stall drops, and the comb port serves the fill data.

Because the CPU is stalled for the whole S_FILL, **no CPU access (read or
write) can commit while a fill is in flight** — a load-bearing invariant for
coherency (§5.4). The only other bus master (HDD DMA) runs with `accel_r=0`,
where no fills are ever launched.

### 5.3 Write-through snoop + forwarding

The cache is never written by the CPU directly; SDRAM is written by ch0 and
the cache **snoops** the committed write one cycle later (`snoop_stb`, when
`wr_addr/wr_din` hold the posted values): if the line is valid and the tag
matches, the enabled byte lanes of the matching word are updated in place.
Lines that aren't present are not allocated on writes (no write-allocate) —
a later miss refetches from SDRAM, which ch0 ordering guarantees is current.

**Forwarding window:** the snoop lands at the *end* of the cycle after the
write. At 1-tick cycles, a read of the just-written address can commit on
that same edge and would sample the pre-write array. During the one
`wr_stb` cycle the pending write is combinationally forwarded:

```verilog
fwd_hit      = wr_stb && (wr_addr == cpu_addr);
cpu_data_now = { fwd byte-lanes from wr_data where enabled, else array };
```

### 5.4 Coherency invariants (why this is safe with no invalidation logic)

1. **Single writer**: SDRAM fast RAM is written only by ch0 (CPU + DMA
   writes) and ch2 (load-time upload). Video scans out of E0/E1 BRAM, not
   SDRAM — there is no third-party writer to snoop.
2. **Order**: ch0 has top priority at the controller's IDLE arbitration, and
   a fill triggered by cycle N+1 toggles its request ≥1 clk_sys (≈8 clk_mem)
   after cycle N's write — the write always dispatches first, so any fill's
   burst data includes every earlier committed write.
3. **No overlap**: a fill implies a stalled CPU (§5.2), so no write can
   commit mid-fill; a pending write implies a stalled next-write (§4.3), so
   posts are serialized and `wr_addr/wr_din` always describe the most recent
   committed write.
4. **Visibility**: every committed write is either snooped into a valid
   matching line (same-tick reads covered by forwarding), or the line is
   absent and a future fill refetches post-write SDRAM.
5. **Pairing**: cycle length (latched `eff_thresh`) and datapath select
   (latched `accel_r`) change on the same phi2 edge, so a 1-tick cycle can
   never execute against the native path and a native cycle never depends on
   comb-hit timing.

Eviction is trivially safe: replaced lines are clean by construction
(write-through), so a fill just overwrites.

### 5.5 `cache_off` ($C059 bit 7, "C/D cache disable")

Intentionally a no-op. Forcing `hit=0` wedges the machine (the stall rule is
`reading && !hit_now`, so RDY would never release after the fill lands), and
the write-through+snoop design cannot hold stale data in normal operation.
The Zip checkbox is cosmetic until a real bypass-and-serve path is wanted.

---

## 6. Timing budgets per step

Per fast cycle, with the deadline being the cycle-ending phi2 edge:

| step | cycle | read hit | read miss | write |
|------|-------|----------|-----------|-------|
| native 5t (349ns) | ch3 registered ~phi2+3t | n/a (no cache) | n/a | posted, retires in ~1.2t |
| 7.16 2t (140ns) | comb, same-tick | stall ≈ fill 166ns + sync ≈ 2-3 cycles | ~2× headroom vs 78.6ns service |
| 14.32 1t (70ns) | comb, same-tick | stall, same absolute latency | back-pressure stalls streaks (writes outrun service by 8.8ns/write) |

The controller runs at 114.545 MHz (8× clk_sys, same PLL, edge-aligned).
Burst read = ~19 clk_mem; single write = ~9 clk_mem; refresh = every 850
clk_mem, taking one ~8-cycle slot.

---

## 7. Failure modes found on the road to 14.3 (and their fixes)

Full narratives in `doc/zipgs-14mhz-plan.md`. Summary — each was invisible
at ≥2-tick cycles and fatal at 1-tick:

| # | bug | fix |
|---|-----|-----|
| A | write channel fire-and-forget: `ack0<=req0` absorbs queued toggles → silently dropped SDRAM writes, masked by the snoop until eviction | `wr_pending` back-pressure through RDY; post/snoop gated identically |
| B | slow/fast classification decided one edge before the address exists → first access of each slow run escaped as a 69ns fast cycle | `fast_escape` comb gate on the `ph2_en` output |
| C | snoop lands one cycle after the write → 1-tick read-after-write sampled pre-write array | comb write-forwarding during the `wr_stb` cycle |
| D | (sim) instant-BRAM fastram has a registered read, 1 tick late → sim "worked" at 14.3 only as an artifact, then instantly BRK-looped once modeled properly | `dpram sim_async_a` comb mirror muxed by live `accel_active`; and the real fix: `make SDRAM=sim` (§8) |
| E | speed transitions (IWM hold-off expiry, DMA end) shortened the in-flight cycle combinationally while `accel_r` was still native → 1-tick reads through cold, never-stalling ch3 | latched `eff_thresh` paired with `accel_r` (§2.2) |

Also fixed en route: the fill-ack CDC metastability (§5.2), and the LC
$C08x ladder being phi0- instead of phi2-gated (see `lc-register-audit`).

---

## 8. Verification tooling

- **`vsim/sdram_tb/`** (iverilog): `tb_wstream.sv` — a cycle-paced mirror of
  the bridge driving 1-tick write streaks, interrupt-push patterns swept
  across refresh phase, MVN-style alternating R/W, conflict evictions, and
  read-after-write races, with a golden model checked on every read AND a
  direct chip-memory compare at the end (immune to snoop masking). Runs both
  `BACKPRESSURE=0` (reproduces bug A: dropped words) and `=1` (must be
  clean). Plus `tb_accel.sv` (bridge integration), `tb_ch3.sv` (native
  channel), `tb_cache.sv`, `tb_burst.sv`.
- **`make SDRAM=sim`** (Verilator, ~6× slower): the full Vemu sim with the
  production `sdram_burst` + `sdram_cache` + behavioral chip model
  (`doc/sdram_accel/sdram_sim_chip.sv`, with timing assertions) glued by a
  verbatim copy of the Apple-IIgs.sv bridge; `clk_mem_ext` driven at 8× by
  sim_main. A **golden-model coherency checker** mirrors every committed
  byte and prints `SDRAMSIM_VIOLATION addr/got/exp/accel_r/hit_now/...` the
  moment any committed CPU read returns stale data. This is the tool that
  root-caused bug E deterministically, and closes the "works in sim, fails
  on FPGA" gap for the memory path. Note `sim_bus.cpp` now emits
  HPS-accurate one-shot `ioctl_wr` strobes (held-level breaks req/ack
  consumers).
- **Regression**: `vsim/regression.sh` must stay byte-identical at native —
  every accelerator feature is gated to be a structural no-op with the
  accelerator off. (Gotcha: GS/OS boot *writes* to gsos.hdv; boot
  experiments shift the blessed frame-320 screenshot — verify two identical
  native boots before re-blessing.)

---

## 9. File map

| file | role |
|------|------|
| `rtl/clock_divider.v` | cycle scheduling: PH0 grid, fast/slow/sync, eff_thresh latch, fast_escape |
| `rtl/zipgs_regs.sv` | $C058-5F protocol, unlock, speed_code, 1 ms timebase |
| `rtl/iigs.sv` | fast_thresh formation (hold-offs), accel_active, RDY_IN, DMA pacing |
| `Apple-IIgs.sv` | bridge: accel_r mux, ch0 post + back-pressure + snoop, ch3 launch, mem_stall |
| `rtl/sdram_burst.sv` | 4-channel controller @114.5 MHz: ch0 write > ch3 read > ch1 burst > ch2 upload > refresh |
| `rtl/sdram_cache.sv` | 8×16B direct-mapped line buffer: comb hit, miss FSM, snoop + forwarding |
| `rtl/dpram.sv` | sim BRAM (with `sim_async_a` comb mirror for the non-SDRAM_SIM sim) |
| `vsim/sim.v` | `SDRAM_SIM` integration + golden coherency checker |
| `doc/sdram_accel/sdram_sim_chip.sv` | behavioral SDRAM chip with timing assertions |
