# Language Card ($C080–$C08F) Register Validation Report

**Date:** 2026-07-06
**Scope:** Validate the RTL Language Card (LC) implementation against reference emulators and
official documentation.

**STATUS UPDATE (same day):** All findings below (F1–F5) have been FIXED, plus a sixth found
during hardware testing:

- **F6 — LC_WE ladder was gated on `phi0`, not `phi2`.** The double-read ladder counted the
  free-running 1MHz Mega II tick instead of the once-per-CPU-access `ph2_en` used by every
  other soft switch. Whether a `ph0_en` pulse lands inside a $C08x access window at
  accelerated speeds (--speed 7.2 / ZipGS) depends on sync-cycle alignment, SDRAM stalls and
  refresh — nondeterministic on the FPGA (deterministic in Verilator). Historically harmless:
  a missed double-read didn't matter while write-protect wasn't enforced (F1) and odd writes
  force-enabled `LC_WE` (F2). Once F1/F2 were fixed, a missed ladder pulse meant LC writes
  got *discarded* → intermittent "bad memory" at 7MHz on the MiSTer board. Fixed by gating
  the ladder on `phi2`.
- Fix locations: `rtl/iigs.sv` ($C08x odd-write handlers, read ladder, reset), `rtl/mmu.sv`
  (`lc_dxxx_fold` bank-1 fold, banks 00/01 write-protect), `vsim/mmu_tb.cpp` (golden model
  toggles D4/D5), `customtests/MMU_TEST.S` (test 26 rewritten to assert the reference linear
  layout: bank 2 at linear $Dxxx, bank 1 at linear $Cxxx under IOLC inhibit).
- Verification: `make mmutest` 48M-case sweep PASS; full `regression.sh` PASS. The MMU-test
  reference image was re-blessed (rewritten test 26 stores one extra scratch byte on the
  text page). The GS/OS test now runs with `--fixed-time`: its frame-320 progress bar
  depends on the wall-clock RTC and sat on a tick boundary after the phi2 change; with the
  deterministic RTC it reproduces the original reference byte-for-byte. Monitor probe reads
  `AA AA` (write-protect held; `STA $C081` did not write-enable) at both 1MHz and 7.2MHz;
  GS/OS boots to the Finder at 2.8 and 7.2MHz (checked through frame 2500); ROM self-test
  clean through the memory/soft-switch tests (status `08000000` at the sound test).

Original analysis follows.

**RTL under review:**
- `rtl/iigs.sv` — $C08x soft-switch state machine (write side ~lines 1088–1191, read side ~lines 1395–1506), $C011/$C012 status (672–673), $C068 STATEREG (1082–1084, 738), reset (782–825)
- `rtl/mmu.sv` — LC address decode: `lc_dxxx_fold` (106–109), `lc_exxx_ram` (113–116), `slowram_we` (136–141), `rom2_ce` (183–204), `rom_writethrough` (207), fast/slow RAM chip enables (227–359)
- `vsim/sim.v:373` — fast-RAM write strobe `wren_a = (we & fastram_ce)`

**References consulted:**
- *Apple IIgs Hardware Reference* ch. 3 (`doc/IIGS_memory.md`) — Table 3-1, reset behavior, $C011/$C012, IOLC
- *Understanding the Apple IIe* (Sather) — MMU equations for BANK1 / HRAMRD / PRE-WRITE / HRAMWRT′ (the definitive gate-level description; the Mega II/FPI reimplement this logic)
- Krue FPI reverse-engineering notes (`doc/2011-krue-fpi.pdf`) — confirms the FPI implements the full LC when I/O shadowing is enabled
- Emulators: **GSplus** (`gsplus/src/moremem.c`), **Clemens** (`clemens_iigs/clem_mmio.c`), **gssquared** (`gssquared/src/devices/languagecard/LanguageCardLogic.hpp`, `src/mmus/mmu_iigs.cpp`)
- IIgs ROM source (`IIgsRomSource/`) — equates and double-read idioms

---

## 1. Executive summary

The RTL gets the visible register interface right: **the 16-address decode, the $C011/$C012
status reads, the $C068 state-register bit layout, the read-side double-read (pre-write)
ladder, the reset state, and the IOLC (shadow bit 6) gating all match the Hardware Reference.**
The read-side pre-write implementation is actually *more* faithful than two of the three
reference emulators.

Three genuine deviations from real hardware were found, in decreasing severity:

| # | Finding | Severity |
|---|---------|----------|
| F1 | LC **write-protect is not enforced** for banks $00/$01 fast RAM (writes while `LC_WE=0` land in LC RAM instead of being discarded) | **High** |
| F2 | A **write** to an odd $C08x address **immediately write-enables** LC RAM (real HW: writes never set write-enable; they clear the pre-write latch) | Medium |
| F3 | The $D000 **bank fold is inverted**: RTL stores bank 2 at physical $Cxxx; all references store **bank 1** there (observable through the shadow-bit-6 linear window) | Medium-Low |
| F4/F5 | Minor pre-write model nits (reset value of `LC_WE_PRE`, odd-read `LC_WE <= LC_WE_PRE` semantics) — currently masked, but become live bugs if F2 is fixed naively | Low |

---

## 2. What was validated as CORRECT

### 2.1 The 16-address decode

All sources agree on the decode (HW Ref Table 3-1; Sather; all three emulators), and the RTL
matches it exactly, including the $C084–$C087 / $C08C–$C08F echoes:

| Addr | Bank ($D000) | Read source | Write (after 2 reads) | RTL (`RDROM`,`LCRAM2`) |
|------|------|------|------|------|
| $C080/4 | 2 | RAM | protect | 0,1 ✓ |
| $C081/5 | 2 | ROM | enable  | 1,1 ✓ |
| $C082/6 | 2 | ROM | protect | 1,1 ✓ |
| $C083/7 | 2 | RAM | enable  | 0,1 ✓ |
| $C088/C | 1 | RAM | protect | 0,0 ✓ |
| $C089/D | 1 | ROM | enable  | 1,0 ✓ |
| $C08A/E | 1 | ROM | protect | 1,0 ✓ |
| $C08B/F | 1 | RAM | enable  | 0,0 ✓ |

Decode rule (Sather): A3 selects the bank ($C080–87 → bank 2), A0==A1 selects RAM read,
A0=1 is the write-enable candidate. Bank select and read source update **unconditionally on
every access** — RTL does this correctly.

### 2.2 Status reads — correct

- `$C011` (RDLCBNK2) returns `{LCRAM2, 7'h00}` (`iigs.sv:672`): bit 7 = 1 ⇔ bank 2. Matches
  HW Ref and all three emulators. ✓
- `$C012` (RDLCRAM) returns `{~RDROM, 7'h00}` (`iigs.sv:673`): bit 7 = 1 ⇔ LC RAM read-enabled.
  Matches all sources. ✓
- (Footnote: on real hardware the low 7 bits of $C01x reads carry keyboard data; all three
  emulators also return 0 there, so the RTL is in good company.)

### 2.3 $C068 state register — correct

Bit layout used by the RTL — `{ALTZP, PAGE2, RAMRD, RAMWRT, RDROM, LCBNK2, ROMBANK, INTCXROM}`
(bit 3 = RDROM, bit 2 = LCBNK2, 1 = bank 2) — matches GSplus `defc.h`, Clemens
`_clem_mmio_statereg_c068`, gssquared `mmu_iigs.hpp`, and the ROM diagnostics
(`Bank FF/diag.tests.asm:558` ties STATE bit 3 to LCBANK1/LCBANK2/RDLCBNK2). ✓

Note: the Hardware Reference's own Table 3-2 prose ("1 = bank 1") is a **known misprint** —
it contradicts the book's Table 3-1 and every implementation. The RTL uses the correct
polarity.

Writing $C068 updates RDROM/LCBNK2 but **not** the write-enable — correct; STATEREG has no
write-enable bit (confirmed by Clemens, GSplus, and TN.IIGS.030). ✓

### 2.4 Reset state — correct

HW Ref: "the bank switches are initialized for reading from the ROM and writing to the RAM,
using the second bank of RAM." RTL resets `RDROM=1, LCRAM2=1, LC_WE=1` and
`STATEREG=$0D` (`iigs.sv:782, 798–800, 822–824`). ✓ Clemens and gssquared agree
(gssquared uses $0C — same LC bits). GSplus is the outlier (resets to read-RAM/bank 1) and
is wrong per the documentation.

### 2.5 Read-side double-read (pre-write) ladder — correct, and better than 2 of 3 emulators

`iigs.sv:1408–1421` etc.: an odd **read** does `LC_WE <= LC_WE_PRE; LC_WE_PRE <= 1`; any even
access clears both. This matches Sather's PRE-WRITE/HRAMWRT′ rules for read sequences,
including the subtlety that the two reads need not be back-to-back (unrelated non-$C08x
accesses do not clear pre-write) and need not hit the same address ($C081 then $C085 enables).

For comparison: **GSplus has no pre-write at all** (single access enables), and **Clemens**
requires the two accesses to be immediately consecutive *and to the exact same address* (too
strict) and lets writes count as the second access (too loose). Only **gssquared** implements
Sather exactly — and it is the model to compare against for any fix.

### 2.6 IOLC / shadow bit 6 — correct

- shadow[6]=1 disables LC behavior in banks $00/$01 (fold off, ROM windows off, linear
  writable RAM): `mmu.sv:109,116,184–199`. Matches the Krue FPI notes ("the bit which enables
  I/O SHADOWING also enables LANGUAGE CARD behavior") and all emulators. ✓
- Banks $E0/$E1 keep LC mapping regardless of shadow[6] ("In banks $E0 and $E1, language-card
  mapping, I/O space, and display buffers are always active" — HW Ref). ✓

### 2.7 Write-through state ($C081 ×2: read ROM, write RAM) — correct

`lc_dxxx_fold` includes `(LC_WE && we)` so LC writes fold to the RAM window even while reads
come from ROM, and `rom_writethrough` (`mmu.sv:207`) unblocks the $E000+ RAM path. ✓

---

## 3. Findings (deviations from real hardware)

### F1 — LC write-protect is not enforced for banks $00/$01 (High)

**The rule:** with write-enable off (`LC_WE=0` — e.g. after `LDA $C080`, `LDA $C082`,
`LDA $C088`, `LDA $C08A`, or any single read of an odd switch), writes to $D000–$FFFF must be
**discarded**. All three emulators enforce this (GSplus routes writes to a trap page, Clemens
clears `WRITEOK`, gssquared maps the write page to NONE).

**The RTL:** the fast-RAM write strobe is `wren_a = we & fastram_ce` (`vsim/sim.v:373`) with
no `LC_WE` term, and `mmu.sv` only kills `fastram_ce` for the case
`RDROM && addr >= $E000` (`mmu.sv:249,277`). Consequently, in banks $00/$01:

| LC state | Write to $D000–$DFFF | Write to $E000–$FFFF |
|----------|----------------------|----------------------|
| read RAM, WP ($C080/$C088) | **lands in LC RAM** (should discard) | **lands in LC RAM** (should discard) |
| read ROM, WP ($C082/$C08A) | **lands in the *other* bank's RAM** (no fold ⇒ physical $Dxxx) | correctly discarded (RDROM guard) |
| read ROM, WE ($C081 ×2) | correct (write-through) | correct |
| read RAM, WE ($C083 ×2) | correct | correct |

Banks $E0/$E1 are **not** affected — `slowram_we` correctly requires `LC_WE` for ≥$D000
(`mmu.sv:136–141`).

**Why it matters:** ProDOS-8 deliberately write-protects the LC after boot (`romin=$C082
"swap rom in, write protect ram"` — `GSOS/P8/MliSrc1.asm:337`). The HW Ref states the *only*
way software can test write-enable is to attempt a write and check it didn't stick — i.e.
diagnostics and copy-protection do exactly the operation that misbehaves here. The
$C082-state case is worse than a missing protect: the stray write corrupts the *opposite*
$D000 bank.

Note: `vsim/mmu_tb.cpp`'s golden model replicates the RTL decode verbatim (line 96 onward),
so the MMU regression cannot catch this — it validates self-consistency, not reference
semantics.

### F2 — Writes to odd $C08x addresses immediately write-enable (Medium)

**The rule (Sather, quoted verbatim in gssquared):** "write access to an odd address in the
$C08X range controls HRAMRD **without affecting the state of HRAMWRT′**", and **any** write
access in $C08x clears PRE-WRITE. So `STA $C081` selects ROM-read/bank 2 but must leave
write-enable exactly as it was; a write can never be half of the enabling double-access.

**The RTL** (`iigs.sv:1101–1113` and the three sibling cases): a single **write** to
$C081/$C083/$C089/$C08B (and echoes) sets `LC_WE <= 1; LC_WE_PRE <= 1` — marked
"FIX: Enable writing (was 1'b0)", introduced during selftest bring-up (commit `aa50363`,
Aug 2025). This matches **GSplus** (which has no pre-write model at all) but contradicts
Sather, the HW Ref's "RR" (read twice) notation, and gssquared.

**Failure scenario:** software in the write-protected state does `STA $C081` (a legitimate
idiom to flip to ROM-read without touching write-enable) → RTL becomes write-enabled → later
stray/probe writes to $D000–$FFFF modify LC RAM that real hardware would protect.

**Correct behavior per Sather:** on a $C08x **write**: update RDROM/LCRAM2 by address as now,
clear `LC_WE_PRE`, set `LC_WE <= 0` only for **even** addresses, and leave `LC_WE` unchanged
for odd addresses.

**Caution before fixing:** the change was made for the ROM selftest. Real hardware passes the
selftest with Sather semantics by definition, so if reverting breaks the selftest it means
some *other* discrepancy was being compensated — re-run `--selftest` and `regression.sh`
after any change and investigate rather than re-applying this workaround.

### F3 — $D000 bank fold is inverted: bank 2 stored at physical $Cxxx (Medium-Low)

**The references:** every source that expresses a physical layout puts **bank 1** at physical
$C000–$CFFF and treats **bank 2 as the primary bank at physical $D000**:
- Sather: "Bank 2 is the primary bank; it is selected by system resets" (the A12 fold applies
  to bank 1).
- HW Ref: "If the language card is not enabled, the first of these blocks of RAM, **block 1,
  occupies address space from $C000 to $CFFF**."
- GSplus: `if (!LCBANK2) wrptr -= 0x1000` (bank 1 → $Cxxx).
- Clemens: bank 1 → pages $C0–$CF; bank 2 identity; **NIOLC forces $Dx→$Dx identity**, i.e.
  the linear window shows bank 2 at $Dxxx.
- gssquared: `bankd0offset = FF_BANK_1 ? 0xC000 : 0xD000`.

**The RTL:** `lc_dxxx_fold` fires when `LCRAM2` (= bank **2**) is selected (`mmu.sv:106–109`),
so bank 2 lives at physical $Cxxx and bank 1 at physical $Dxxx — the mirror image.

**Observability:** invisible during normal LC operation (the two 4K blocks are symmetric),
but the shadow-bit-6 linear window exposes physical addresses directly: with IOLC inhibited,
real hardware shows **bank 2 at $D000–$DFFF and bank 1 at $C000–$CFFF**; the RTL shows the
opposite. Software that stores data in one LC bank and then flips shadow[6] (GS/OS manipulates
the shadow register) reads the wrong 4K. Also relevant to future save-state/NVRAM work: the
physical layout differs from every emulator's.

**Fix shape (when desired):** fold on `~LCRAM2` instead of `LCRAM2` in `lc_dxxx_fold` and in
the E0/E1 path; update `vsim/mmu_tb.cpp` to match. (GSplus's linear-mode handling disagrees
with Clemens + the HW Ref here; follow the HW Ref / Clemens / Sather majority.)

### F4/F5 — Pre-write model nits (Low; coupled to F2)

- **F4:** RTL resets `LC_WE_PRE=1` (`iigs.sv:800`); Sather says PRE-WRITE is *reset* (0) by
  a system reset. Currently unobservable (LC_WE is also 1 at reset and any even access clears
  both), but wrong if F2 is fixed.
- **F5:** the odd-read ladder `LC_WE <= LC_WE_PRE` *disables* write-enable when PRE=0, but
  Sather's HRAMWRT′ can only be **set toward enabled** by an odd read — an odd read must never
  disable writing. Today the state (LC_WE=1, PRE=0) is unreachable so the flaw is masked; the
  moment F2 is fixed (odd write → PRE=0, LC_WE unchanged), a subsequent single `LDA $C083`
  would wrongly drop write-enable. The correct ladder is
  `if (LC_WE_PRE) LC_WE <= 1; LC_WE_PRE <= 1;` — fix F2, F4, F5 together.

---

## 4. Points where references disagree (RTL position defensible)

### E0/E1 language card: ROM reads and write-protect

- **GSplus:** banks $E0/$E1 $D000–$FFFF are always RAM and always writable; only the bank-2
  fold applies.
- **Clemens:** never ROM-sourced in E0/E1; fold applies.
- **gssquared:** full LC semantics including ROM reads (its Mega-II map sources $Dxxx/$Exxx
  from SYS_ROM under RDROM).
- **RTL:** full LC semantics — ROM reads under RDROM (`mmu.sv:204`, added deliberately,
  matching gssquared) and write-protect via `slowram_we` (`mmu.sv:136–141`).

The HW Ref's "language-card mapping … always active" note for E0/E1 supports the RTL/gssquared
reading, and the RTL's E0/E1 ROM mapping was added to fix an observed misbehavior (stale LC
RAM reads). **Verdict: keep as is**; if E0/E1 LC issues ever surface, this two-vs-two split
among emulators is the place to look.

### Vector pulls forced to ROM

`mmu.sv:170–172, 184, 198` force ROM reads during 65C816 vector-pull cycles (`~vpb_n`)
regardless of RDROM. **None** of the three emulators model this (none emulate the VP pin) and
the local documentation set doesn't mention it. It is plausibly modeled on real FPI behavior,
but it is not corroborated by any source in this repo — flagged for independent verification
(e.g. against the FPI section of the full Hardware Reference or hardware testing), not as a
defect.

---

## 5. Suggested verification (future work, no code changed now)

1. **Write-protect probe test** (catches F1): from the selftest or `--send-keys` monitor
   entry: `LDA $C083 ×2` → write $AA to $D17B → `LDA $C080` → write $55 to $D17B →
   `LDA $C083 ×2` → read $D17B; must be $AA. Repeat for $E000 region and for the $C082 state
   (then verify bank 1 unharmed).
2. **Sather Table 5.5 sequence test** (catches F2/F4/F5): drive the exact
   read/write/odd/even sequences (`STA $C081` alone must not enable; `LDA $C081, STA $D000,
   LDA $C081` must not enable; `LDA $C081, LDA $C085` must enable) and compare against
   gssquared, which implements the gate equations verbatim.
3. **Linear-window test** (catches F3): write distinct tags to bank 1 $D000 and bank 2 $D000,
   set shadow[6]=1, verify $C000 reads the bank-1 tag and $D000 the bank-2 tag.
4. Extend `vsim/mmu_tb.cpp` with these as *reference* assertions (not copies of the RTL
   expressions), so the golden model can actually disagree with the DUT.
