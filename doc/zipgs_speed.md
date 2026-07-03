# ZipGS-compatible CPU speed control

The core has a ZipGS-style accelerator: the fast (2.86 MHz) CPU cycle can be
shortened to 3.58 / 4.77 / 7.16 MHz. Slow (1 MHz) and sync cycles — I/O,
banks E0/E1, shadowed-video writes — are untouched, exactly like a real
ZipGS/TransWarp, so video timing, beam-racing I/O and Mega II behavior stay
correct while ordinary code runs faster.

Three interfaces share ONE state (`rtl/zipgs_regs.sv`), so they always agree:

| interface | how |
|---|---|
| simulator | `./obj_dir/Vemu --speed <0-3 \| 2.8/3.6/4.8/7.2>` |
| MiSTer OSD | "CPU Speed" menu (status[14:12]) — native-only unless built with `ACCEL_SDRAM` |
| software (ZipGS) | $C058-$C05F protocol, KEGS/GSplus semantics (verified against both) |

## ZipGS protocol (what period software does)

- Locked (power-on): $C058-$C05F are the ordinary annunciators (AN3 = video).
- Unlock: write $5x to $C05A four times; $Ax relocks.
- Unlocked: write $C05D = speed (high nibble, 0=100%..$F=6.25%); any other
  write to $C05A disables acceleration, any write to $C05B enables it;
  $C05B reads: bit7 = ~1ms toggle, bit4 = disabled. $C05C = delay mask (stored).
- Read $C05A returns {speed nibble, $F}. An OSD/--speed change updates these
  registers, so software polling the Zip sees the host-selected speed.

Quick test from BASIC:
```
FOR I=1 TO 4:POKE 49242,80:NEXT   ( unlock: 4x $50 -> $C05A )
POKE 49245,0                      ( $C05D = 0 -> 100% speed )
POKE 49243,0                      ( any write $C05B -> enable )
```
The sim prints `ZIPGS: UNLOCKED` / `ZIPGS: speed_code ...` on transitions.

## Speed mapping

"100%" = 7.16 MHz (our rated speed, TransWarp-class). Zip percentages map to
the largest achievable clock-enable step at or below them; the 14.32 MHz
single-tick step is RESERVED until stall-on-miss exists (see below).

## Correctness guards (rtl/clock_divider.v)

All three are no-ops at the native step — native timing is bit-identical
(regression suite verified byte-for-byte):

1. `fast_thresh` shortens only the fast cycle; refresh penalty applies only
   at native (accelerated steps model the Zip cache hiding refresh).
2. `dma_active` (HDD DMA) forces native pace — the DMA data path is a
   2-edge registered chain that corrupts below 3-tick cycles.
3. `slot_access` (mmu slot_ce) classifies external-slot accesses
   ($C100-$C7FF) as sync cycles when accelerated — a real ZipGS keeps slots
   at stock speed too. Plus `slow_class_now`: a combinational mirror of the
   slowMem classification that holds a fast fire at accelerated speeds until
   the registered slowMem reroutes the access to a sync cycle (at 2-tick
   cycles the registered classification lands on the same edge the cycle
   would end — found via the slot-7 HDD C7xx ROM probe reading stale bytes).

## Limits / next steps

- **14.32 MHz needs stall-on-miss.** At a 1-tick cycle the BRAM/SDRAM read
  latency has zero slack; the CPU must stall on misses. That is the
  `ACCEL_SDRAM` burst+cache work (doc/sdram_accel/) — once `cache_stall` is
  wired to the CPU's RDY_IN, unclamp speed code 4 in `rtl/zipgs_regs.sv`.
- **FPGA**: `accel_capable` (0 unless built with `ACCEL_SDRAM`) hard-gates
  the speed mux inside iigs.sv, so neither the OSD nor ZipGS software can
  over-clock the plain single-word SDRAM path (an un-stalled fetch at short
  cycles is silent corruption). The Zip registers still respond, like a real
  card with the acceleration jumper off. Bring-up order in
  HANDOFF_quartus_accelerator.md.
- $C05C per-slot delay semantics are stored but not yet applied (we slow all
  external-slot accesses when accelerated, which matches Zip defaults).
- A TransWarp GS detection shim (fake 'TWGS' vector table at $BC/FF00 +
  $C06A-$C06D, GSplus-style) is a straightforward follow-on for TWGS-aware
  games; the mmu makes the $BC/FFxx decode trivial.
