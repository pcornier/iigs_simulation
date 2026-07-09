# ZipGS compatibility delays, self-test & Apple keys

How the ZipGS's *compatibility delays* (the DIP-switch behaviors that keep
timing-sensitive software/hardware working while accelerated) map onto this
core — what we implement, what we miss, and how the software emulators compare.

Companion to [`zipgs_speed.md`](zipgs_speed.md) (the speed engine) and
[`transwarp_gs/README.md §4.9`](transwarp_gs/README.md) (the transparent
auto-slowdown mechanism, shared by ZipGS and TransWarp).

**Sources:** [`ZipGS_Manual.md`](ZipGS_Manual.md) (DIP switches SW1/SW2),
the KEGS/GSplus ZipGS implementations under `software_emulators/`, and our
`rtl/zipgs_regs.sv` / `rtl/clock_divider.v` / `rtl/iigs.sv`.

---

## 1. The core idea

An accelerator runs the CPU fast but must **drop to ~1 MHz around a handful of
timing-sensitive accesses**, because the affected timing is produced by
cycle-counted software loops *around* the access (see `transwarp_gs/README.md
§4.9` for the full "why"). The ZipGS exposes these as DIP switches (SW1/SW2),
mirrored by software registers (`$C059`/`$C05C`). Each is a "delay" you can
enable/disable.

**Key architectural note:** the software emulators (KEGS/GSplus) model the Zip
as a *coarse whole-CPU speed multiplier* decoupled from wall-clock, so nearly
all these per-access delays are **no-ops** there — they don't need them. Our
FPGA core runs in **real time**, so it genuinely needs them. That's why we build
the delay windows and the software emulators mostly don't (see §5).

---

## 2. DIP switches → behavior → our status

| Switch | Behavior | Default | Our status |
|---|---|---|---|
| **SW1/1** Cxxx/Dxxx cache disable | cache-coherency escape for shadow flips (`$C059`-ish) | disabled | register exists; cache is a no-op in our SDRAM core |
| **SW1/2** Joystick/paddle delay | 1 MHz around `$C070`/`$C064-7` paddle access | *enabled* | ✅ **implemented** (`pdl_holdoff`, branch `transwarp`) |
| **SW1/3** AppleTalk delay | drop to native during interrupts (AppleTalk timing) | disabled | ❌ missing (no interrupt-service slowdown) |
| **SW1/4** Counter delay | 1 MHz on `$C02E/$C02F` (VERTCNT/HORIZCNT) access → **self-test 05 passes** | *enabled* | ✅ **implemented** — see §3 |
| **SW1/5** CPS follow | Zip drops to 1 MHz when the IIgs is at 1 MHz (`$C036` bit7=0) → **Apple keys + floppy** | *enabled* | ✅ OSD toggle (default OFF) — see §4 |
| **SW1/6** Disable | power up disabled (slow) | disabled (i.e. powers up **enabled**) | we power up **native/disabled** — deliberate default difference |
| **SW1/7-8** Cache size | 8/16/32/64 KB | 8K/16K | cache is a no-op; size reporting only |
| **SW2/1-7** Slot delay | per-slot 1 MHz for `$Cn00` (SW2/2, SW2/6 default slow) | mixed | we over-slow **all** slots when accelerated (safe; `$C05C` mask stored, not applied) |
| **SW2/8** Speaker delay | 1 MHz around `$C030` | *enabled* | ✅ **implemented** (`beep_holdoff`, branch `transwarp`) |

Legend: ✅ done · ⚠️ intentional divergence · ❌ not implemented.

---

## 3. Self-test — Counter Delay (SW1/4)

The IIgs internal diagnostic times the video counter. **SW1/4 (default
enabled)** "creates a delay whenever the horizontal counter register is
accessed," which lets **self-test `05XXXXXX` pass** while accelerated.

The manual is explicit about the rest:

> *"Unless the ZipGS is disabled, it will at times fail the Apple IIGS internal
> test `0BXXXXXX` (as this test depends on 2.8 MHz speed). The ZipGS will also
> fail internal test `0CXXXXXX`. **THIS IS NOT AN ERROR.**"*

So a faithful accelerator: **makes `05` pass** (counter delay) and **accepts
`0B`/`0C` failing** (they measure the real 2.8 MHz clock and can't be fixed).

**Our implementation** (branch `transwarp`, `rtl/iigs.sv`): a retriggerable
native-speed window on any access to `$C02E/$C02F` (`counter_holdoff`, 1 ms),
folded into `io_slow_holdoff` alongside speaker/paddle — the same mechanism as
`transwarp_gs/README.md §4.9`. Gated by the OSD slowdown control (Auto = on).
**No software emulator implements this** (see §5), so here we are strictly more
faithful than KEGS/GSplus.

> **Verification status:** built, boots, and the accelerated self-test
> (`--selftest --speed 3`) runs without an obvious `05` halt — but a *conclusive*
> test-05 pass/fail read (catching + interpreting the diagnostic result frame,
> and an A/B with the delay off) is **not yet done**. The window length (1 ms)
> may need tuning against the real test-05 access pattern. Treat as
> implemented-per-spec, runtime-unconfirmed.

---

## 4. Apple keys — CPS Follow (SW1/5)

**SW1/5 (default enabled)** makes the Zip drop to system speed whenever the
IIgs enters 1 MHz mode (`$C036` CYAREG bit7 = 0). The manual:

> *"If this option is disabled … you will not have the use of the Open or Closed
> Apple keys at power-up or reset."*  · *"Floppy drives will not function
> properly when this option is disabled."*

**We deliberately do the opposite.** `rtl/clock_divider.v` keeps accelerating
"regardless of `$C036` bit 7," with the rationale that *the Zip CDA's speed
self-test clears `CYAREG[7]` before measuring* — following it there would lose
acceleration and (we found) hang the Zip cdev's poll loop.

Consequences vs. the manual:
- **Floppy** — fine anyway, covered by our separate `iwm_holdoff` + motor-detect.
- **Open/Closed Apple keys at boot/reset** — work *in practice* only because we
  **power up native** (Zip disabled by default), so boot is 1 MHz. If you boot
  *with* acceleration engaged, those keys won't read correctly.

**KEGS/GSplus prove CPS-follow is compatible** and are the reference: they
implement it (default ON, `$C059` bit 3) — `sim65816.c`:
`zip_follow_cps = (g_zipgs_reg_c059 & 0x8)`,
`fast = c036.bit7 || (zip_en && !zip_follow_cps)` — while their Zip CDA reads
speed from the **synthetic 1 ms clock bit in `$C05B` reads**, *not* by staying
fast during the bit-7 clear. We already generate that same 1 ms bit in
`zipgs_regs.sv`.

> **✅ Implemented as an OSD toggle** (branch `transwarp`): "CPS Follow (1MHz
> sync)" (`Apple-IIgs.sv status[19]` → `cps_follow`). ON adds
> `&& (CYAREG[7] || !cps_follow)` to `fast_thresh` (`rtl/iigs.sv`): when the
> system enters 1 MHz mode (`$C036` bit7=0) the accelerator goes native, and the
> existing `clock_divider` `slow_request` takes the CPU to 1 MHz.
> **Default OFF** — deliberately, because our `clock_divider` note warns the Zip
> CDA clears `$C036` bit7 while measuring speed, and following it there could
> make the CDA read 1 MHz. Default-off is a provable no-op (the gate is
> `(x || 1) = 1`), so it changes nothing until you enable it. **Verify on real
> hardware:** with it ON, confirm (a) Open/Closed-Apple keys work while
> accelerated, and (b) the Zip CDA speed readout is still correct (KEGS's 1 ms
> approach says it should be). If (b) breaks, that's the lockup to solve before
> defaulting ON.

---

## 5. What the software emulators implement

| Behavior | KEGS | GSplus | clemens | gssquared |
|---|---|---|---|---|
| `$C05x` register protocol | Full | Full (KEGS fork) | ❌ annunciators | ❌ game AN |
| **Counter delay `$C02E/F` / self-test 05** | **❌** | **❌** | ❌ | ❌ |
| Self-test 05/0B/0C special-case | ❌ | ❌ | ❌ | ❌ |
| **CPS follow / 1 MHz drop** | **✅** | **✅** | ❌ | ❌ |
| Speaker/paddle/slot/AT delay windows | ❌ no-ops | ❌ | ❌ | ❌ |
| Power-up state | Enabled | Enabled | — | — |

Only **KEGS and GSplus** implement ZipGS at all (GSplus is a KEGS fork;
clemens_iigs and gssquared treat `$C05x`/`$C02E-F` as plain annunciators / video
counters). Details:

- **Counter delay: nobody.** KEGS even has the config bit (`$C059` bit 4,
  commented `"5ms c02e enab"`) but never wires it to a delay; `$C02E/$C02F` reads
  go straight to `read_vid_counters`. So there was no reference to crib — we
  built it from the manual (§3).
- **CPS follow: KEGS + GSplus only** (identical code; the *one* slowdown window
  they model). Default ON because `$C059` powers up `0x5f`.
- **All fine per-access delays are no-ops** in KEGS/GSplus — timing is a speed
  multiplier (`g_zip_pmhz = 8·(16−nibble)/16`), decoupled from wall-clock, so
  the delays aren't needed. This is exactly why the software emulators are *not*
  a useful reference for the delay features, but *are* for CPS follow.
- **Power-up:** KEGS/GSplus default **enabled** (`c05b=0x40`); we default
  **disabled**.
- Aside: GSplus adds a `$C06A-$C06D` speed shim + `GetMaxSpeed = 8000` — that's
  the "GSplus-style `$C06x`" referenced elsewhere; it's a GSplus convenience,
  not real ZipGS hardware (the real card uses `$C05x`).

---

## 6. Status & plan

| Item | Status |
|---|---|
| Speaker delay (`$C030`), paddle delay (`$C070`/`$C064-7`) | ✅ done (`transwarp`) |
| **Counter delay (`$C02E/$C02F`) → self-test 05** | ✅ implemented (`transwarp`); test-05 pass runtime-unconfirmed (§3) |
| CPS follow (`$C036` bit7 → 1 MHz) → Apple keys while accelerated | ✅ OSD toggle (`transwarp`, default OFF); verify Zip CDA readout on HW before defaulting ON |
| Per-slot delay granularity (`$C05C` applied) | ❌ future (we over-slow all slots) |
| AppleTalk/interrupt delay (drop to native in ISRs) | ❌ future |
| Power-up-enabled default (match real Zip) | ❌ deliberate divergence |
