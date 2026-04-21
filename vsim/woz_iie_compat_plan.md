# WOZ 5.25" Copy-Protection Compatibility Plan

**Context**: After the IIgs core ships, the WOZ floppy support will be lifted into
the MiSTer //e core. On //e (65C02), the common `$FF=NOP` incompatibility goes
away and DOS 3.2 / 13-sector formats are native. Copy-protected 1980–83 titles
become the main use case, so WOZ fidelity matters much more than it does for IIgs.

## Current status (April 2026)

- 8/8 regression disks pass (DOS 3.3, ProDOS, GS/OS, 3.5" WOZ).
- Empty-track flux noise and weak-bit threshold tuning are in place
  (commits `e44e7a6`, `866f23c`, `a192a90`).
- Known-failing 5.25" WOZ titles on our IIgs sim:
  - **Cyclotron**: copy-protection check at $064D–$065B fails; MAME IIe passes.
  - **Apple-Oids & Chip Out**: WOZ capture is missing half-tracks 33–34 that
    the protection scheme reads. File issue, not emulation.
  - **Atlantis**: uses 65C02 `$FF=NOP` trick; 65816 treats it as SBC long,X and
    runs off the end of a jump target. Would work on //e (65C02).
  - **Alice in Wonderland**: 13-sector protection, similar boot loader to Cyclotron.

## Highest-leverage diagnostic

Set up a **byte-level comparison tool** between our IWM and MAME's:

1. Configure MAME IIe with IWM byte-read debug enabled (dump every
   `$C0EC`/`$C08C,X` read value + disk bit position).
2. Add a matching debug print on our side (already prototyped via
   `DEBUG_IWM_BYTES_CYC` in `rtl/iwm_flux.v`).
3. Run both with the same WOZ, same reset point.
4. Diff the byte streams starting at track 0, bit 0.
5. First divergence point tells us exactly which IWM behaviour is wrong.

This is one day of tooling work. It converts "why doesn't this protection
work" into a specific, actionable bug.

## Suspected bug areas (in priority order)

### 1. Shift-register read semantics

Real IWM exposes the current 8-bit shift register value on every `$C0EC`
read. The CPU polls until bit 7 is high, then reads the byte. The register
keeps shifting during and after the read; it does not latch.

Our implementation uses an `m_data_read` flag + edge-triggered
`byte_completing` that returns `$00` between bytes. Copy protections
sometimes rely on catching a byte mid-shift (e.g., reading "half-bytes" on
overlapping cells) — our flag breaks that pattern.

**Fix**: expose the raw shift register on $C0EC reads, not a latched byte.
Let CPU timing loops handle "byte ready" via the MSB bit as real hardware
does.

### 2. Post-read shift behaviour

After the CPU reads a byte with MSB=1, does the shift register:
- Continue shifting from its current state (real IWM)?
- Clear to 0 and resync on next MSB=1 (our current behaviour)?

Protection schemes that count bit cells between specific patterns depend
on the continuous shift. A clear-and-resync introduces ~7 extra bit cells
of latency per byte read, misaligning subsequent reads.

### 3. MSB-held duration

Our `byte_completing` is a single-cycle pulse on MSB rising edge. On real
hardware, MSB stays high for multiple bit cells after detection — until
the 1-bit shifts past position 6. CPU timing loops expect to see the same
byte value on 2–3 consecutive reads, then see the next byte.

### 4. Bit-cell timing drift

5.25" cells: 56 clocks @ 14MHz = 4.000µs exactly. Should be correct.
Verify by measuring total revolution time vs track bit-count:
  51,200 bits × 4µs = 204.8ms = expected rotation time.
If we're even 0.5% off, accumulated drift causes byte-boundary slip after
thousands of bits and breaks sector prologue detection.

### 5. Weak-bit reproducibility

Real drives produce the same flux noise pattern for several revolutions
(head position doesn't change, noise is mostly deterministic). Clemens
uses a 4096-bit pre-computed random table that cycles. We advance the
LFSR every 14MHz cycle — noise is fresh on every bit, which breaks any
protection that reads the same "random" region twice and expects identical
(or correlated) data.

**Fix**: precompute a track-length random bit buffer at track-load time;
replay it on each revolution. Cycle with `bit_position % random_table_len`.

## Estimated effort

- Day 1: MAME side-by-side tooling + first divergence capture.
- Day 2–3: Fix whichever of #1/#2/#3 the divergence points to.
- Day 4: Verify Cyclotron, Alice, and a couple other DOS 3.2 titles boot.
- Day 5: Weak-bit reproducibility fix if still needed.

Likely outcome: 30–60% of currently-failing 5.25" WOZ titles boot on //e,
with the remainder blocked by missing-data issues in WOZ captures or by
extreme timing-dependent protections.

## Testing surface to build

- Regression: the current 8 disks (don't regress).
- Add a "protection gauntlet" set of ~10 WOZ titles with known outcomes:
  - Cyclotron (Broderbund, 13-sector, custom $DB B7 prologue).
  - Alice in Wonderland (custom prologue).
  - Sabotage (DOS 3.2).
  - A few Origin / Broderbund / Sirius titles with bit-timing protections.
- Record expected "reaches title screen" frame for each; regress against it.

## Not worth doing

- Implementing 6502 undefined-opcode-as-NOP in our 65816 core. Atlantis-
  style titles work on real //e but the IIgs genuinely can't run them.
  On the //e core they'll just work natively.

- Patching individual games. We want generic WOZ fidelity, not per-title
  hacks.
