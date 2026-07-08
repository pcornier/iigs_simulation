# TextFunk Beam-Race — Issue Summary & LLM Handoff

**Status: SOLVED (2026-07-02, commit `8f5394d`, on master).** Root cause was the
Mega II counter wrap position: it sat only 6 chars before active display instead of
the hardware's 25 HBL chars (Sather/TN.IIGS.039), so every $C02E/$C02F-synced beam
racer ran 19 chars (266 ticks) late vs the beam. Fixed via `H_M2_WRAP=645` in
video_timing.v (CPU-visible counters only; rendering untouched) plus the PH0-to-beam
anchor in clock_divider (default on, `+ph0_anchor=0` to disable). Grid renders clean,
no seam; regression 7 PASS + pre-existing WOZ FAIL; selftest 0B PASS.

Two errors in this doc found during the fix: §2's "5 columns" is actually 5 WORDS =
10 image columns (screen cols 10-19; image occupies screen cols 10-39), and the §6b
logger's `H_CHAR>=7'h58` gate silently cut display columns 0-18, so the measured
"crossing 8" was really 27. Residual imperfection ≈ 1 column at the crossing margin
(sub-char fetch/latch details). Sections below kept for history.

**Last updated:** 2026-07-02

---

## 1. The problem

`textfunk` (Jason Andersen "TextFunk Viewer", 2018) is a single-buffer **beam-racing**
"character-graphics" demo. Source is in the repo top level: **`stack_funk.s`**. Disk:
`vsim/textfunk.po` (auto-boots).

**Technique:** It maps the **CPU stack into text page 1** (`TCS` sets S into `$0400-$07FF`)
and machine-guns unrolled `PEA`/`PHX` pushes to rewrite the text page **once per scanline**,
in lockstep with the raster. It writes chars **right-to-left** (stack grows down) while the
scanner reads **left-to-right**, so the write pointer and the beam **cross** mid-line. The
demo pre-compensates for this crossing in software (see below).

**Symptom:** In the sim, the tunnel/grid **streaks in the center-left**. On **real IIgs
hardware it is clean** (user confirmed; assume the grid = correct target). GSSquared renders
it clean but **only because GSS renders from final memory — it does not beam-race**, so GSS
is *not* a valid oracle for this artifact. Even Clemens (cycle-accurate) lists textfunk as
broken — **no emulator reference exists; only hardware.**

**How to see it:**
```bash
cd vsim && make
./obj_dir/Vemu --disk textfunk.po --screenshot 438 --stop-at-frame 439
# zoom the tunnel center:
convert screenshot_frame_0438.png -crop 130x120+370+55 +repage -filter point -resize 500% center.png
# grid test pattern (better probe): press space 9x to reach it
./obj_dir/Vemu --disk textfunk.po --send-keys "460: " --send-keys "520: " ... (see §6)
```

---

## 2. THE SMOKING GUN (from `stack_funk.s`)

`patch_image` (line ~596, comment *"Patch the image to compensate for crossing the raster
beam"*) pre-rotates the **left 5 columns** of the image up one line (`ldy #5`). **The demo
hard-codes that exactly 5 columns cross the beam** (get drawn one scanline late), and
pre-shifts them so they land correctly.

Our measured crossing is at **char ~8**, not 5 → columns 5,6,7 are also late but the patch
doesn't compensate them → they show the wrong scanline → the streak.

**So the fix = make our beam-race crossing land at exactly column 5.**

Other source facts (verified against our trace):
- Sets **Direct Page = `$C000`** (`pea $c000; pld`), so `$2e/$2f/$34/$36` = `$C02E/$C02F/
  $C034(border, sync markers)/$C036(speed)`.
- Sequence: `trb $36`(→SLOW) → vsync spin `cpx $2e` until `$C02E==$7F` → `lda $2f; sbc #2;
  and #7; asl; tax; jmp (:tbl,x)` **fine-align** → `:do` → 8× `dec/bne` **countdown** (slow)
  → `tsb $36`(→FAST) → border-marker writes → **BLITCODE** (192 `BlitText` macros).
- The **fine-align table** (`:one1`..`:five`) self-compensates the sub-char `$C02F` jitter:
  each entry burns a different #cycles so the blit starts at a fixed beam position regardless
  of where in the 8-char window the vsync-spin exited. **This means the `$C02F` `$49`-vs-`$48`
  difference is already handled by the demo — NOT our bug** (an earlier red herring).

---

## 3. ROOT-CAUSE LEAD (the key finding)

Instrumented the `clock_divider.v` slowMem SYNC path to print the video vs CPU PH0 phase:

```
ph0_phase_vid (Mega II / video beam, = video_timing hsub) = ph0_counter (CPU's PH0) + 8  (mod 14)
```

**The CPU's PH0 is a constant ~8 ticks (>½ char) out of phase with the video beam.**
The FPI is supposed to recreate PH0 from 14M+STRETCH to *match* the Mega II PH0 (per
`doc/fpi_timing.md`). Our SYNC cycles align to the CPU's free-running `ph0_counter`
(`ph0_counter_next==0`), which fires at the **wrong beam phase** → the setup's sync-stretch
lands a few ticks long → the blit starts late → crossing shifts from 5 to 8.

Note: `ph0_counter_next==0` (current sync trigger) ≡ `ph0_phase_vid==7`.

---

## 4. Quantified via a CPU-timing knob

Built `+cpu_knob=N` (plusarg): on the slow→fast transition (the demo's `tsb $36`) it stalls
the CPU N 14M-ticks (holds `ph2_en` low, freezes `ph2_counter`). Verified block0 shifts by
exactly N. Measured the crossing (VGC-read log correlated with CPU-writes, at V=300):

| CPU delay N | crossing char |
|---|---|
| 0  | **8**  |
| 40 | 9  |
| 80 | 10 |

**+40 ticks CPU-delay = +1 char crossing.** Patch wants **5**. So we are ~**3 chars / ~120
ticks too late** → need to **advance** the CPU (shorten the setup / align its PH0). Direction
confirmed; delay makes it worse; large "wrap" delays corrupt the display (blocks draw wrong
lines) so they're not a clean advance test.

**Caveat:** the "char 8 vs 5" rests on an image-column↔visible-char mapping that was never
fully pinned. The true deficit may be smaller than 120 ticks (the sync-stretch excess alone
is ~30-50 ticks). Do not over-trust the exact 120.

---

## 5. VERIFIED CORRECT (ruled out — do not re-chase)

- **Slow-mode timing** = exactly 14 ticks/cycle (checked through the 8× countdown loop).
- **Blit block** = exactly 912 ticks (matches GSS 14M-tick golden).
- **Fine-align table** self-compensates `$C02F` — the `$49`-vs-`$48` is handled by the demo.
- **`$C036` (SPEED)** at 14 ticks in slow mode is *correct* (base speed is 1 MHz; FPI-doc
  "fast" only means no extra sync penalty, relevant in FAST base mode).
- **`$C034` border writes** are consistently **sync** (17-22 ticks) — correct. (An earlier
  "STX=10 fast vs STZ=sync inconsistency" was a MISCOUNT: the 10 was the adjacent NOP's
  internal cycle, not the STX.)
- **FPI register exclusions** ($C035/$C036/$C037 = fast) are present in clock_divider (~L267).
- **Dual-rate / collapsed-clock**: `make DUALRATE=1` (committed) runs video at true 28 MHz
  separate from the 14 MHz CPU. It **boots, changes the beam-race render (8311 px), but does
  NOT fix the streak** → the collapsed clock is NOT the cause. The BRAM read/write path is
  correct (dual-rate proves read-after-write works). It's the CPU-write *schedule* (PH0
  phase), not the memory path.
- Also tried & failed: refresh-defer (uniform-912 blocks, no visual change); slow-mode
  PH0-slave (no effect); `$C02F−1` (no effect); scanline-boundary refresh resets (no effect).

---

## 6. Tools built this session (REVERTED to keep tree clean — re-add to resume)

All were reverted. To re-add:

**(a) CPU-timing stall knob** — in `rtl/clock_divider.v`:
- Declare near the other regs: `reg [15:0] cpu_knob_val, knob_stall; reg prev_slow_base;
  integer knob_tmp;` and an `initial` reading `$value$plusargs("cpu_knob=%d", knob_tmp);
  cpu_knob_val = knob_tmp[15:0];` (use `reg[15:0]`, **not** `integer`+bit-select — that fails).
- Reset block: `knob_stall<=0; prev_slow_base<=0;`
- In the main `else` branch: `prev_slow_base <= slow; if (prev_slow_base && !slow) knob_stall
  <= cpu_knob_val;`
- **CRITICAL:** the override must go in the **LIVE path**, right after `ph2_sync_pulse <= 1'b0;`
  (before the `\`ifdef DEBUG_VERBOSE`), NOT after `ph2_en_prev <= ph2_en;` (that's inside the
  ifdef and gets compiled out — this wasted an hour):
  ```verilog
  if (knob_stall != 16'd0) begin
      knob_stall <= knob_stall - 16'd1; ph2_en <= 1'b0; ph2_counter <= ph2_counter;
  end
  ```
- CPU is `.CE(phi2)`=`ph2_en` (P65C816, `EN <= RDY_IN and CE`), so holding ph2_en low stalls it.

**(b) VGC text-page read logger** — in `rtl/iigs.sv` after `wire [7:0] video_data;` (~L1882):
```verilog
`ifdef DEBUG_VGC_TXT
always @(posedge clk_vid) if (ce_pix && video_addr[16:0]>=17'h00400 && video_addr[16:0]<17'h00800
                              && V>=10'd300 && V<=10'd305 && H_CHAR>=7'h58)
   $display("VGCRD,%0d,%0d,%0d,%05x", V, H, H_CHAR, video_addr[16:0]);
`endif
```
Makefile: `ifeq ($(VGCTXT),1)` → `V_DEFINE += +define+DEBUG_VGC_TXT`. Build `make VGCTXT=1`
(touch a source first — define changes alone don't trigger a rebuild).

**(c) crossing measurement** — run `+cpu_knob=N --beam-trace 439,439 --stop-at-frame 440
--no-cpu-log 2>/dev/null | grep ^VGCRD > vg.csv` (and copy `beam_trace.csv`). Python: build
`H_CHAR→hcount` map (`hc=350+(H_CHAR-88)*14`) from VGCRD V=300 reads; for each addr both read
(min hcount) and CPU-written at V=300 (`beam_trace` D,W, col9=addr, col11=V, col12=H_CHAR);
crossing = count of addrs where `write_hc >= read_hc` (PREV/stale) = char index of the flip.

**(d) grid probe** — `--send-keys "F: "` (LITERAL space; the space-key fix `6f825b2` was
required — `\x20` collides with the Open-Apple marker). Space 9× reaches a clean grid test
pattern that shows the defect sharply:
```bash
args=(--disk textfunk.po --no-cpu-log); f=460
for i in $(seq 1 9); do args+=(--send-keys "${f}: "); f=$((f+60)); done
args+=(--screenshot 970 --stop-at-frame 1000)
./obj_dir/Vemu "${args[@]}"   # run ONE foreground process; overlapping bg runs fight over screenshot files
```

---

## 7. THE NEXT STEP (what to actually do)

The fix is to **align the CPU's `ph0_counter` phase to the video beam (`ph0_phase_vid`) by
~8 ticks**, so SYNC cycles fire on the beam's PH0 edge like hardware — **without**
destabilizing the 912-tick block.

**Why it's hard (read before trying):** re-anchoring `ph0_counter` to the video is documented
to break Total Replay / GS/OS and corrupt the fast-refresh + PH0-long-cycle accounting keyed
off `ph0_counter` (see `memory` notes). Firing the SYNC on the video phase directly
(`+sync_vid` experiment) only perturbed timing — it re-introduced the 907/917 block
oscillation and outliers, render unchanged. So a naive swap does NOT work.

**Approaches to try (regression-gate EVERY step: `cd vsim && ./regression.sh`, expect 7 PASS +
pre-existing WOZ FAIL):**
1. **Get the author's answer first (BLOCKING QUESTION, see §8).** If the 8-tick offset is a
   bug (should be aligned), correcting it is very likely the fix and avoids guessing.
2. A *phase-only* correction: keep `ph0_counter` driving the fast/refresh/long-cycle logic,
   but derive the SYNC's PH0-edge reference from `ph0_phase_vid` (beam) — carefully, so the
   block stays 912 and the oscillation doesn't return. The failed `+sync_vid` attempt shows
   the trap: aligning the sync trigger alone shifts block boundaries and re-breaks the
   refresh cadence. Likely need to co-adjust the refresh phase and the long-cycle anchor to
   the same beam reference.
3. Use `+cpu_knob` + the crossing measurement to verify any change moves the crossing toward
   5 BEFORE judging visually (the visual change per char is subtle).

**Success criteria:** grid (space 9×) and tunnel center are clean/crisp like real hardware;
crossing measures at char ~5; regression stays 7 PASS + WOZ; `--dump` other timing-tuned
titles (Total Replay, GS/OS) unchanged.

---

## 8. BLOCKING QUESTION FOR THE DEMO/GSS AUTHOR (relay via Discord)

> On real IIgs hardware, is the FPI's recreated PH0 **phase-aligned** with the Mega II's PH0
> (the one driving the video scanner + `$C02E`/`$C02F`), or is there a known fixed **sub-char
> offset** between them? Concretely: when the CPU does a **SYNC cycle** (shadowed write / I/O)
> and the FPI stretches PH2 to the next PH0 edge, is that the *same* edge the video scanner is
> on? In my sim they're **8 of 14 ticks (~½ char) out of phase** and I can't tell if that's my
> bug or authentic. Bonus: exact cost in 14M ticks of a fast-mode (2.8 MHz) `$C0xx` sync write?

If aligned → correct the 8-tick offset. If an offset is real → match it.

---

## 9. Key files / references

- **Demo source:** `stack_funk.s` (repo top level) — `patch_image` (§2), `BlitText` macro,
  vsync/fine-align/countdown/blit sequence (~L164-534).
- **`rtl/clock_divider.v`** — PH0 gen, `ph0_counter`, `scanline_ph0_ctr`, slowMem SYNC path
  (`ph0_counter_next==0 && ph2_counter>=13`, ~L405), FPI-reg exclusions (~L267),
  `ph0_phase_vid`/`ph0_stb_vid` inputs (wired, unused — the alignment hook).
- **`rtl/video_timing.v`** — `hsub`=`ph0_phase`, `hchar`=`$C02F`, `HIDX_AT_H0` (=0; earlier fix).
- **`rtl/iigs.sv`** — CPU `.CE(phi2)`; dpram (E0/E1) port A=CPU@CLK_14M, port B=VGC@clk_vid;
  video read path (`video_addr`/`video_data`).
- **`rtl/dpram.sv`** — true dual-port BRAM (read-before-write on same edge = the collapsed-clock
  behavior; dual-rate separates it but doesn't fix the streak).
- **`doc/fpi_timing.md`** — Kruszyna FPI doc: fast=5, refresh=10, sync=14-27, sync-stretch=16-29;
  "FPI recreates PH0 from 14M + STRETCH"; FPI-only regs (SHADOW/SPEED/DMA) = fast.
- **`doc/core-timing-plan.md`** — staged plan / prior findings.
- **Committed this session:** `6f825b2` (`--send-keys` space fix — 0x20 collided with OA
  marker), `734d12f` (`make DUALRATE=1` gated dual-rate infra).
- **Full running notes:** the auto-memory `textfunk-beam-race.md`.

## 10. Process gotchas (save time)
- `make DUALRATE=1` / `make VGCTXT=1` are **no-ops if no source changed** since the last build
  (make tracks timestamps, not defines) — `touch` a source to force a rebuild.
- Overlapping background `./obj_dir/Vemu` runs **fight over screenshot filenames** — run one
  foreground process for screenshot sweeps.
- Verilator plusargs (`+cpu_knob=N`) work because `sim_main.cpp` calls
  `Verilated::commandArgs(argc, argv)`.
- `--no-cpu-log` disables the in-memory CPU log but **stdout still prints**; redirect for speed.
- Regression `./regression.sh` detaches (nohup); poll for the process to actually finish.
