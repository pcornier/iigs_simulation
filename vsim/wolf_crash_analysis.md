# Wolfenstein3D Crash Analysis

## Symptom

Booting `Wolfenstein3D.hdv` ends up in the IIgs ROM monitor at frame **1254**:

```
17/D001: 00 00       BRK 00
A=0002 X=0002 Y=0910 S=17E4 D=0207 P=01 B=00 K=17 M=0C Q=BE L=1 m=0 x=0 e=0
*
```

## Crash path

At `FE:0138 RTL` (the error-recovery exit of the ROM Tool dispatcher), `SP=$17E1`, and the
three bytes popped from `[$17E2..$17E4]` form a bogus 24-bit return of `$17/D000+1 = $17/D001`.
Bank `$17` is 100% empty (only 2 nonzero bytes in all 64 KB), so execution reads `$00` →
BRK → monitor. `BANK_FIRST_EXEC` confirms `$17` is entered for the first time at this RTL.

## Where the three bytes came from (the twist)

Polling `$17E4` for the moment it becomes `$17` reveals they were **not** pushed as a return
address. They were written by two direct-page stores inside the dispatcher itself:

```
FE:0105: sta $05      ; store A (16-bit) at DP+5, DP+6
FE:0107: stx $06      ; store X (16-bit) at DP+6, DP+7
```

At that moment `D = $17DD` (restored from IRQ save at `$E1:0110`), so the DP offsets
resolve to:

```
[$17E2] = A_low  = $00
[$17E3] = X_low  = $D0   (stx overwrites the A_high byte)
[$17E4] = X_high = $17
```

`X = $17D0` because the tool dispatcher at `FC:DBBF` built X as the "tool table pointer"
for the tool being called.

Then at `FE:0138 RTL` with `SP=$17E1`, the CPU pops `[$17E2..$17E4]` — the exact bytes the
dispatcher just wrote — and jumps to that "address".

**This is the classic 65C816 "direct page overlapping the stack" failure.** The ROM's
error-cleanup code does `tsc; clc; adc #$000a; tcs; rtl` expecting a specific stack layout,
but because `D` and `SP` happen to overlap, the direct-page scratch stores at DP+$05/$06/$07
land exactly on top of where RTL will read.

## Why the ROM ended up on the error-recovery path

`FE:0110 cmp [$05]` constructs a long pointer from the A/X just stored in DP:

```
bank   = byte at [DP+7] = X_high = $17
offset = byte at [DP+5..DP+6] = A_low|X_low = $D000
```

So the dispatcher reads a byte at `$17:D000` to validate tool-set metadata. That byte is
`$00` (bank 17 empty). The validator compares it against `A=$92`, gets `C=1`, and
`BCS FE012B` branches to the error cleanup. Cleanup runs into the D⊕SP overlap trap.

## The underlying problem

**Bank `$17` contains no code or data at all.** A write-watch confirmed it: only 2 nonzero
bytes in 64 KB, and they're at `$170000/$170001`.

Tool set `$17` is in the IIgs ROM's **user-defined range** (tool sets 17–32 are reserved
for applications). Wolfenstein3D installs its own private tool set there. The dispatcher's
pointer into bank `$17` is valid in form but the memory is empty, so every lookup comes
back `$00`, the validator fails, and the cleanup code lands on the D⊕SP overlap trap.

The question "why does Wolfenstein3D crash in our sim" resolves to:

> **Why does bank `$17` never get populated with the game's private tool-set code?**

On real hardware (and in other emulators) bank `$17` is populated either by GS/OS OMF
loading the game's segments, or by a Memory Manager allocation the game performs at
startup. In our sim it happens through neither path by frame 1254.

## Things this is *not*

- **Not a CPU bug.** The `PCL=$C8` saved by the IRQ push at `FC:DBC8` is correct for hardware
  IRQ: on RTI, TYA re-runs harmlessly. Fine for 65C816 semantics.
- **Not a disassembler issue.** The `???` log lines (`$2F AND long`, etc.) are just a gap in
  `sim_main.cpp`'s pretty-printer switch; the microcode executes them fine.
- **Not stack corruption from the IRQ.** The ROM IRQ handler at `FF:BC6C`→`FF:BF7D` saves SP
  to `$E1:010E` and restores it correctly.

## Investigation artifacts

The following were added to `sim_main.cpp` for this analysis (still in the file):

- Expanded `BANK_FIRST_EXEC` postmortem dump (REGS, stack window `$17C0..$17E8`, full
  IRQ-save area `$E1:0108..011F`, and a 2048-entry ifetch ring with per-fetch SP and X).
- `BANK17_NONZERO` sweep that reports how much of bank 17 is populated when first entered.
- `STK_WATCH` poll that logs when `$17E4` becomes `$17`.

These can be left in place — they only fire at the crash point or on specific conditions.

## Next steps

1. Add a "first write to any `$17:xxxx` address" tracer. If **zero** writes happen during
   the whole boot, the loader/memory-manager never touched bank 17. That points to the GS/OS
   `Loader` or `MemoryMgr` path.
2. If writes **do** happen but get overwritten, find who cleared them.
3. Also worth watching writes to the tool-set dispatch vector table at `$E1:03C0..03FF`:
   the game calls `TLStartUp`/`SetTSPtr` to install tool set `$17`. If a pointer *is*
   installed but the bank it points at is unbacked, the bug is on the Memory Manager
   allocation path rather than the loader.

## Results from the tracers

### Bank 17 write history

A `BANK17_WRITE` tracer polling every 64 ifetches across the whole 1254-frame boot caught
exactly **two writes to bank 17**:

```
BANK17_WRITE #1: $17:0000 00->E8 at near FC:0316 SP=01AB frame=49
BANK17_WRITE #2: $17:0001 00->FF at near FC:0316 SP=01AB frame=49
```

Both are the early ROM memory-sizing probe at `FC:0316` (IIgs ROM writes `$E8 $FF` to
offset `$0000/$0001` of each RAM bank, then reads back, to detect how much fast RAM is
present). **Nothing ever writes bank 17 again**, up to and including the crash.

### Fast-RAM census at crash time

Sweeping banks `$02..$20` when bank 17 is first touched:

```
BANK_CENSUS 02: 54805 nonzero bytes, $02:0000..$02:FFFB
BANK_CENSUS 03: 54629 nonzero bytes, $03:0000..$03:FF7C
BANK_CENSUS 04: 53003 nonzero bytes, $04:0000..$04:FCE9
BANK_CENSUS 05: 50004 nonzero bytes, $05:0000..$05:FCE5
BANK_CENSUS 06: 55623 nonzero bytes, $06:0000..$06:FA8B
BANK_CENSUS 07: 41068 nonzero bytes, $07:0000..$07:C4A4
BANK_CENSUS 08: 48382 nonzero bytes, $08:0000..$08:D39C
BANK_CENSUS 09: 16956 nonzero bytes, $09:0001..$09:FCEE
BANK_CENSUS 0A: 17532 nonzero bytes, $0A:0000..$0A:6EFF
BANK_CENSUS 0B: 63568 nonzero bytes, $0B:0280..$0B:FFFF
BANK_CENSUS 0C: 64256 nonzero bytes, $0C:0101..$0C:FFFF
BANK_CENSUS 0D..20: 2 bytes each (the early ROM RAM-sizing probe, nothing else)
```

**The loader stopped after bank `$0C`.** Banks `$02..$0C` hold the game's OMF segments —
banks `$0B/$0C` are almost full (>63 KB each). Everything from `$0D` up is blank.

`BANK_FIRST_EXEC` confirms the game *did* execute in banks `$02..$0A` before dying:

```
bank 02 at PC=151F frame=140
bank 03 at PC=000E frame=245
bank 04 at PC=B141 frame=367
bank 05 at PC=007C frame=465
bank 06 at PC=51B5 frame=620
bank 07 at PC=0062 frame=854
bank 08 at PC=0000 frame=1024
bank 09 at PC=EB38 frame=1024
bank 0A at PC=00A8 frame=1169
bank 17 at PC=D001 frame=1254    ← CRASH
```

Progression is steady (roughly one new bank every 100–150 frames), then bank 17 is
touched ~85 frames after bank `$0A`.

### Tool-set vector table at crash time

At `$E1:03C0..03FF` (4 bytes per tool set), the snapshot is:

```
[00]=19FD7F00 [01]=6902FE00 [02]=3CFF7F00 [03]=38FF7F00 [04]=00000000 ... [07]=5C000000 ...
[10]=00000000 ... [17]=00000000 ... [1F]=00000000
```

Only tool sets `$00` (Tool Locator), `$01` (Memory Mgr), `$02` (Misc Tools), `$03`
(QuickDraw II), and `$07` are installed — those are all built-in ROM tool sets. **Tool set
`$17` has `00000000` installed, i.e. never registered.** So the crash is *not* caused by
a bad tool-set pointer we installed; it's the dispatcher working with a zeroed vector,
falling into the "no such tool set" error path.

### HDD activity at the crash

The last HDD-controller traffic at the crash point shows the game is still in the middle
of a block read:

```
HDD CPU READ-MIRROR 00:0f01 -> 00 (cmd=01 unit=70 blk=1794 mem=aa00 sec_idx=000)
... (polling)
HDD CPU READ-MIRROR 00:0f02 -> 01 (cmd=01 unit=70 blk=1794 mem=aa00 sec_idx=000)
```

Block 1794 was queued for read into memory `$aa00` (the exact bank is elsewhere in the
controller state). So the game's loader is active and reading the disk at the moment it
crashes — it hasn't finished loading the whole file yet.

## Revised conclusion

This is **not** "the game loaded its tool set into a dead bank". It's:

1. The GS/OS loader is reading the game's OMF file and progressively loading segments
   into banks `$02..$0C`.
2. Somewhere around frame 1254, the game (running in its own code in banks `$02..$0A`)
   calls into the ROM Tool dispatcher. That call flows through `FC:DBxx` → `FE:0100`
   tool-locator code.
3. The tool being invoked is in tool set `$17` (or the dispatcher *thinks* it is), but
   nothing has registered a vector for tool set `$17`.
4. The dispatcher's zero vector makes `cmp [$05]` read from `$17:D000` — which is `$00`
   because bank 17 was never even allocated — and fail the range check.
5. The error cleanup path at `FE:012B..0138` executes `tsc; clc; adc #$000a; tcs; rtl`
   with `D = SP` (because the tool dispatcher does `tsc; phd; tcd` to use the stack via
   DP). With the dispatcher's preceding `sta $05 / stx $06` having written `$00 $D0 $17`
   to `DP+$05..DP+$07` as part of building the (failed) tool pointer, the RTL pops those
   same bytes from the stack — which the DP aliases. Crash lands at `$17:D001`.

So the *crash mechanism* is "dispatcher error path trips over its own DP-aliased stack
when the tool set isn't registered". That's a generic ROM-dispatcher failure mode, but
the **real question** is why tool set `$17` is being invoked at all, and why isn't it
registered.

Two plausible upstream bugs:

**A. The game's boot is supposed to `TLStartUp` tool set `$17` before calling it**, and
something in its own init code hasn't run yet. The game might be calling it in an
interrupt or async callback that happens before initialization completes. In our sim the
sequencing differs from real hardware because of (for example) timing differences, and
the call happens "too early".

**B. The OMF loader is failing to load one of the game's segments that was supposed to
populate bank 17 or the tool-set vector**. Banks `$0B/$0C` are packed with content (the
game's OMF ended mid-load there?), but nothing later. If a later segment was supposed to
contain bank-17 code + `TLStartUp` glue, it never ran.

The HDD is still actively reading at the crash moment (block 1794), so the loader
*process* is alive — this suggests (A) more than (B). The game's own code ran, tried a
premature tool call, and fell into the dispatcher error.

To narrow further, the next useful experiment is:

1. **Log every `TLStartUp` / tool-set vector installation** during boot. That's a write
   to `$E1:03C0 + ts*4`. Watch the whole range and log PC + new value for every write.
   This tells us which tool sets the game actually tries to install before the crash.
2. **Log the tool-number/set of the failing call**. The dispatcher entry (probably
   `FE:00C5` or similar) reads tool set # from the caller. Log the first 20–30 tool calls
   in the ring with their set/number, to see exactly which call is the killer one.

Both are small add-ons to the existing instrumentation.

## Cross-comparison with Clemens (which boots successfully)

Clemens 3 GB CSV trace (`wolf_clements_trace.csv`) of the same disk image shows:

- **Bank 17 is also written only twice**, same two locations (`$17:0000=E8`, `$17:0001=FF`)
  at the same ROM probe (`FC:0312`). So "bank 17 is empty" is not the distinguishing bug —
  Clemens has exactly the same bank-17 state and boots fine.
- **Clemens never executes in bank 17 at all.** Same as ours. The empty bank is expected.
- Both sims call the tool-dispatcher epilogue at `FC:DBB9` exactly **9 times** during boot.
  The first 8 succeed in both; the 9th is the one we crash on.

Looking at Clemens's 9th `FC:DBB9` call in the CSV and comparing against ours:

```
Clemens: stx $14 at FC:DBB7 writes to $00:17C5/17C6  → DP+$14 = $17C5 → D = $17B1
Our sim: stx $06 at FE:0107 writes to $17E3/17E4      → DP+$06 = $17E3 → D = $17DD
```

**Our sim's direct-page register is $17DD, Clemens's is $17B1 — an offset of exactly +$2C
(44 bytes).**

The `adc $14 / adc #$4 / tax` sequence then computes X from A (which came from SP after
a `tcs`), so X in our sim ends up 44 bytes higher than Clemens's. When `TXS` at `FC:DBCC`
sets SP from X and `FC:DBCD RTL` pops 3 bytes, we read `[$17D1..$17D3]` instead of the
bytes 44 bytes lower. Those happen to hold `$02 $01 $FE` (from an earlier direct-page
store that aliased into the stack through the same overlapping-D trick), so RTL returns
to `$FE:0103` — the *main body* of the FE:0100 tool-locator instead of its final `$FE:0138
RTL` trampoline. From `$FE:0103` we fall into the parameter-validation branch, which
correctly detects failure and takes the error-cleanup path at `$FE:012B`. That path does
`pla; pld; tsc; adc #$000a; tcs; rtl`, which with `D` still overlapping SP lands on the
DP-aliased bytes `$17E2..$17E4` we described before. Crash.

## Revised root cause

**Our simulator's register state has drifted by +$2C (44 bytes) in `D` relative to
Clemens by the time of the 9th `FC:DBB9` call.** That drift means `D = $17DD` in our
sim where Clemens has `D = $17B1`, and since the FC:DBxx tool epilogue computes X from
SP (via `tsc; adc #imm; tcs`), X is also off by the same amount. `TXS` then points the
stack into the wrong place, the RTL pops the wrong bytes, and the rest of the collapse
happens mechanically.

The `+$2C` drift most likely comes from **one or more earlier pushes that happened in
our sim but not in Clemens, or pushes that happened in both but weren't popped in ours**.
Over a 1254-frame boot, an extra interrupt that doesn't cleanly return, or a tool call
taking one more level of recursion than it should, would accumulate exactly this kind of
offset.

## What's next

This is now a *stack divergence* bug, not a "bank 17 empty" bug, not a CPU op bug, not
an IRQ save/restore bug.

To bisect, the next practical experiment is **sync-point SP comparison**:

1. Pick a reference PC early in the boot where both sims definitely execute (e.g.
   `FE:0030` for the tool-vector install block — both sims hit it).
2. In our sim, snapshot SP/D/DBR at each hit of that PC.
3. In Clemens's CSV, extract the same snapshots (simple `awk` filter on `pc` and `pbr`).
4. Diff the two sequences. The first mismatch pinpoints where our state first drifts.

Once you have that first divergence, you can look at the immediately preceding code in
our sim and see what extra work it's doing (extra push, extra subroutine call, extra
interrupt taken, etc.). That's likely the real bug.

## ADB decoding bug (fixed, but not the root cause of the crash)

Comparing the 3 GB Clemens trace at the equivalent boot point, Clemens decodes ADB GLU
device commands by **high nibble** while our `rtl/adb.v` decoded them by **low 2 bits**:

```
Clemens:
  device_command = adb->cmd_reg & 0xf0;   // $C0=POLL0, $D0=POLL1, $E0=POLL2, $F0=POLL3
  device_address = adb->cmd_reg & 0x0f;

Our sim (old):
  case (din[1:0]) 01=FLUSH / 10=LISTEN / 11=TALK
```

So when the ROM sends `$F2` (`POLL_3` keyboard = read keyboard register 3 = handler ID)
during boot, our sim decodes it as `LISTEN device $F reg $0`, routes to a non-existent
device, and returns no data. The ROM then polls `$C027` bit 5 for "data ready" and never
sees it set — it spins 7500 times in the `FC:DB26..DB2E` loop until X decrements to 0,
then exits via the timeout path.

**Fix applied to `rtl/adb.v`**: added explicit handling for `$F0..$FF` that returns the
device-register-3 contents directly via `state <= DATA`. With this fix, `$F2` returns
2 bytes (`$02 $22` for keyboard) and bit 5 of `$C027` goes set immediately, so the
ROM's poll loop exits on the first iteration.

Before the fix the poll loop spun ~7500 times per call; after, it exits in 1 iteration.
This changes timing but **does not fix the crash** — the 9th `FC:DBB9` call still ends
up with the same off-by-one `D` register value.

## Bisect with Clemens

Diff of `D` register at each of the 9 hits of `FC:DBB9` between the two sims
(our sim measured with `DBB9_HIT` trace, Clemens measured by reading the `stx $14`
destination bytes in the CSV):

| Call | Ours D | Ours SP | Clemens D | Clemens SP | Match |
|------|--------|---------|-----------|------------|-------|
| 1 | 01BC | 01BB | 01BC | — | ✓ |
| 2 | 01BC | 01BB | 01BC | — | ✓ |
| 3 | 01BC | 01BB | 01BC | — | ✓ |
| 4 | 17C2 | 17C1 | 17C2 | — | ✓ |
| 5 | BB87 | BB86 | BB87 | — | ✓ |
| 6 | BBAD | BBAC | BBAD | — | ✓ |
| 7 | 1749 | 1748 | 1749 | — | ✓ |
| 8 | 17AD | 17AC | 17AD | — | ✓ |
| 9 | **17B2** | **17B0** | **17B1** | **17B0** | **OFF BY 1** |

**Calls 1–8 match exactly. Call 9 has `D` one byte higher in our sim.** That +1 cascades
through the dispatcher's `tsc; clc; adc #$16; tcs; adc $14; adc #$4; tax` sequence,
making X point 1 byte off. Then at `FC:DBCC TXS` our SP lands at $17D0 instead of $17CF,
and `RTL` at $FC:DBCD pops `[$17D1..$17D3]` instead of the correct `[$17D0..$17D2]`,
reading `$02 $01 $FE` instead of the bytes that would have been there with a correct SP.
Everything downstream is mechanical from that point.

## What causes the +1 D drift between calls 8 and 9

Between call 8 (frame 1251) and call 9 (frame 1254), `D` increases by 5 in our sim
(`$17AD → $17B2`) but only by 4 in Clemens (`$17AD → $17B1`). Since `D` is reloaded from
`SP` via `tdc; sbc #$0009; tcd`, the discrepancy comes from an SP that's 1 byte lower
than it should be at the moment the `tdc` runs. **One extra stack byte** that was pushed
but not popped in our sim between those two calls.

That extra byte could be:

1. A single-byte push (PHB/PHK/PHP/PHA-in-8-bit-mode) that happens in our sim but not
   in Clemens — i.e., a code path divergence.
2. A CPU-level off-by-one in some instruction that writes one byte too many to the stack
   (harder — would likely break many other things).
3. An RTS/RTL/PLA that pops one byte too few (equally unlikely to be silent).

Since calls 1–8 match `D` exactly, the issue is specifically **during the few thousand
instructions between call 8 and call 9**. The ADB fix above changes the flow during this
window (the ROM no longer spins in the KMSTATUS timeout loop), but the `D` value at call
9 comes out the same either way — which implies the divergence is on a different code
path entirely, not inside the KMSTATUS poll region.

## What to try next

1. **Targeted diff of stack activity between calls 8 and 9.** Instrument our sim to log
   every stack write (PC, SP, value) starting at the end of call 8 and stopping at call 9.
   Extract the same from Clemens's CSV (it records every write with `a_bank=00` and
   `a_adr` in the stack range). Diff the two byte-for-byte — the first extra write in
   our sim is the bug.
2. **Watch `D` during the window directly.** Add a hook that logs every `TCD`/`PLD` with
   PBR:PC, before-value, after-value between call 8 and call 9, in both sims. The first
   difference pinpoints the code doing the extra work.
3. **Verify the ADB-fix progression.** Even if the crash still reproduces, the fix makes
   our ADB command-processing path match Clemens byte-for-byte for the `$F2` sequence.
   This is worth keeping; leave it in `rtl/adb.v`.

## Instrumentation now in sim_main.cpp

- `BANK_FIRST_EXEC` with postmortem (regs, stack dump, IRQ-save dump, tool-set vector
  dump, 2048-entry ifetch ring with SP/X, bank-17 nonzero scan).
- `STK_WATCH` for `$17E4` becoming `$17`.
- `BANK17_WRITE` running write-watch over the whole bank.
- `BANK_CENSUS` one-shot fast-RAM bank sweep when bank 17 is first touched.
- `TS_VECTORS` snapshot of `$E1:03C0..043F` in the postmortem.

All fire automatically and all are safe to leave in place.

