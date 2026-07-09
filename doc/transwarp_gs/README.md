# TransWarp GS — Hardware Reference & Core-Integration Guide

**Purpose.** Everything needed to decide on and implement Applied Engineering
**TransWarp GS** (TWGS) acceleration in this FPGA IIgs core, derived from
primary sources — the release schematic, the complete v1.8s ROM disassembly
(assembles bit-exact), and a full decode of the card's on-board FPGA bitstream.

This is a companion to the existing accelerator docs — [`../zipgs_speed.md`](../zipgs_speed.md),
[`../accelerator-architecture.md`](../accelerator-architecture.md),
[`../zipgs-14mhz-plan.md`](../zipgs-14mhz-plan.md), and [`../sdram_accel/`](../sdram_accel/).
Where those describe the speed/cache engine you already built (now running at a
verified **14.32 MHz** via stall-on-miss), this doc describes the *other* period
accelerator and how to expose it on top of that same engine.

## Sources

| Source | What it gave us |
|---|---|
| `2016-01-17 … Transwarp GS … Schematic Release 1.pdf` (ReActiveMicro / Geoff Body) | Board topology, chip list, FPGA (U64) pinout |
| TransWarp GS ROM v1.8s disassembly (`digarok/TransWarpGS-ROM`, `src/twgs_1.8s/twgs*.s`) | The complete software-visible contract (all `file:line` cites below) |
| The card's FPGA config bitstream (`FPGA_Config` in the ROM) | Decoded to logic — see [Appendix A](#appendix-a-the-xc2064-fpga-decoded) |
| `apple-iigs.info` — *AE TransWarp GS Programmer Reference* | Cross-check of the public API |

Companion files:
- **Implemented tier-B RTL (now live in `rtl/`, branch `transwarp`):**
  `../../rtl/twgs_regs.sv`, `twgs_nvram.sv`, `twgs_rom.sv`, `twgs_card.sv`
  (lint-clean under Verilator `-Wall`), firmware at `../../rtl/roms/twgs_rom.hex`
  (+ `vsim/rtl/roms/` mirror). Wired into `rtl/iigs.sv` + `Apple-IIgs.sv` (OSD
  "TransWarp GS" toggle); see [`INTEGRATION.md`](INTEGRATION.md) and [§5](#5-implementing-twgs-in-this-core).
- **Reverse-engineering evidence (in this folder):** `fpga_pinmap.md` (U64 pin→net),
  `decode.py` (validated XC2064 decoder), `decoded_clbs.txt` +
  `twgs_fpga_clbs.v` (decoded controller logic).
- **Binary artifacts:** `twgs_rom.hex` (the TransWarp GS v1.8s firmware, for
  `twgs_rom.sv`'s `$readmemh` — Applied Engineering released their firmware
  publicly), `fpga_config.bin` / `fpga_mask.bin` (extracted bitstream +
  readback mask), and `schematic_fpga_{left,right}.png` (ReActiveMicro
  schematic-release crops).

---

## 1. Executive summary & recommendation

**The TWGS is now a fully-specified, low-risk target for this core**, and — key
point — **you have already built the hard 90%.** Your `clock_divider.v` speed
engine, `sdram_cache.sv`/`sdram_burst.sv` cache path, `zipgs_regs.sv` register
pattern, and MMU bank decode are exactly the substrate a TWGS needs. What TWGS
adds on top is small:

1. an **8-bit latch at `$BC0000`** whose bit 2 drives your existing
   `speed_code` (accelerate on/off), and
2. the card's **ROM mapped in bank `$BC`** so its `'TWGS'` signature + jump
   table exist (that's all detection requires), and
3. a **tiny serial NVRAM** (Xicor X2444) on `$BC4000/1`.

**The single biggest realization for an *integrated* core:** the real card is a
*replacement-CPU board* — separate 65C816 + cache SRAM + FPGA — that snoops the
motherboard bus. Its 64-CLB FPGA (100% utilized, all-registered, single clock —
see Appendix A) exists almost entirely to solve problems you **do not have**:
bus snooping, cache coherency against real DRAM, fast/slow bus muxing, Mega-II
wait-state generation. **None of that transfers.** You implement the
*software-visible contract*, not the controller.

### Recommendation

Pick by how much authenticity you want vs. how much you'll touch the boot path:

| Tier | Effort | Touches boot? | You get |
|---|---|---|---|
| **A — keep ZipGS only** | none | no | What you have today. ZipGS is the more common detection target and needs no ROM. |
| **B — TWGS-lite** *(recommended)* | small | **no** | `'TWGS'` detection + full `JSL` speed/cache API + 3-tier speed, reusing your speed engine. No card CDA. |
| **C — full TWGS** | medium | yes (reset overlay) | Tier B **+ the genuine "TransWarp GS" control-panel CDA** auto-installs at boot. |

**Do both A and B** — they coexist cleanly (ZipGS lives at `$C05x`, TWGS at
`$BC`; a TWGS-aware title and a Zip-aware title each find their card, both
driving your one speed engine). Go to C only if you specifically want AE's
control panel. See [§5](#5-implementing-twgs-in-this-core) for the wiring.

> ⚠️ **Correction to a note in `zipgs_speed.md`.** That doc mentions a
> "GSplus-style" TWGS shim at *"`$BC/FF00` + `$C06A-$C06D`."* The `$BC/FFxx`
> signature is correct and authoritative. The **`$C06x` part is a GSplus
> convenience, not real hardware** — the real card decodes `$C05x/$C06x/$C07x`
> only as *page strobes for slot-slowdown detection* (see [§4.7](#47-c0xx-strobes-the-card-snoops)), never as a
> detection/ID register. Detection is 100% the `$BC/FFxx` ROM signature + jump
> table. Don't build a `$C06x` ID register expecting real software to use it.

---

## 2. Board architecture (real hardware)

```
        Apple IIgs backplane (CPU socket)
                    │  GS_A0-15, GS_D0-7, GS_PH2, GS_RW,
                    │  GS_IRQ/NMI/RESET/BE/ABORT/VP, CYAREG.fast
        ┌───────────┴────────────────────────────────────────┐
        │                 TransWarp GS card                   │
        │                                                     │
        │   W65C816 (fast)      XC2064 FPGA (U64)             │
        │   CPU_PH2/RW/…  ◄────► "system controller":         │
        │                        bus bridge, address decode,  │
        │                        cache control, wait-states,  │
        │                        speed/slot-slowdown logic     │
        │                          │        │        │        │
        │                 27C256 EPROM   32KB cache   X2444    │
        │                 (32KB ROM)     SRAM         NVRAM    │
        │                 @ $BC8000     ($BE/$BF win) (serial) │
        └─────────────────────────────────────────────────────┘
```

Chip list from the schematic: `W65C816S6PL-S` (CPU), `XC2064-PLC68` (U64,
FPGA), `27C256` (EPROM), cache SRAM, `X2444P` (U37, NVRAM), plus 74Fxx glue
(a `74F138` decodes `$C0xx` page strobes, `74F04` inverters, a `74F74`).

The card claims **bank `$BC`** for its ROM + registers (bank `$BC` is normally
empty on a IIgs — no populated RAM/ROM there — so the overlay is safe) and
overlays the reset/NMI vectors momentarily at power-on.

**Why this topology inverts for you:** in this core the CPU, RAM (SDRAM), and
Mega-II timing are all in one FPGA and the fast CPU already exists. So "being a
TWGS" = presenting the contract in §4, mapped onto the engine you already have.

---

## 3. The XC2064 controller (why it doesn't port)

The FPGA is decoded in full in [Appendix A](#appendix-a-the-xc2064-fpga-decoded).
Summary: it's a **100%-utilized, all-registered, single-clock synchronous state
machine** — a maxed-out 1985 gate array doing bus arbitration, address decode,
cache control, and wait-state sequencing for a *card snooping a real
motherboard*. Reproducing its netlist in modern RTL would be pointless: the
behaviors it implements are either free in your core (fast CPU) or handled by
your existing logic (`clock_divider` slow/sync cycles, MMU shadow, SDRAM
cache). Keep the decode only as a **ground-truth reference** if you ever need
the card's exact bus timing for tier C.

---

## 4. The software-visible contract

All cites are `src/twgs_1.8s/…` in the `TransWarpGS-ROM` disassembly.

### 4.1 Memory / register map (bank `$BC`)

The complete set of card-decoded addresses:

| Address | R/W | Name | Meaning |
|---|---|---|---|
| `$BC0000` | R/W | `TWGS_Config` (twgs.s:123) | **Control latch** (8-bit). Bit layout §4.5. |
| `$BC4000` | R/W | `TWGS_Serial_Data` (twgs.s:124) | Serial data — X2444 NVRAM + FPGA readback share it. MSB-first. |
| `$BC4001` | R/W | `TWGS_Serial_Control` (twgs.s:125) | Serial control / chip-select / readback trigger (§4.6). |
| `$BC8000-$BCFFFF` | R (exec) | EPROM | 32 KB firmware (`org $BC8000`, twgs.s:41). |
| `$BCFF00-$BCFF07` | R | signature | ASCII `'TWGS'` then `'SMJS'` (twgs.3.s:2222). |
| `$BCFF08-$BCFF5B` | R (exec) | jump table | 21 `JSL` entry points (§4.2). |
| `$BCFFEA/EB`, `$BCFFFC/FD` | R | NMI / reset vectors | overlay (twgs.3.s:2249,2258). |
| `$BE0000+`, `$BF0000-$BF7FFF` | R/W | cache SRAM window | cache diagnostics only (§4.4). |

**Access rule:** every routine that writes `$BC0000` first drops to 1 MHz
(clears `CYAREG.7`), writes, then restores speed (`SET_TW_CONFIG` twgs.s:553,
`TWGS_ON/OFF` twgs.s:512/529). You need not enforce it; just tolerate the
sequence.

### 4.2 Detection / identification

Detection is purely static: the `'TWGS'`/`'SMJS'` bytes at `$BCFF00` plus a live
`JSL` jump table. **No unlock sequence** (unlike ZipGS). TWGS-aware software
checks the signature, then calls the table in full native mode:

```
$BCFF08 GetTWInfo      $BCFF24 SetCurSpeed    $BCFF40 SetTWConfig
$BCFF0C ResetTW        $BCFF28 GetCurISpeed   $BCFF44 GetCacheSize
$BCFF10 GetMaxSpeed    $BCFF2C SetCurISpeed   $BCFF48 EnableDataCache
$BCFF14 GetNumISpeed   $BCFF30 FlushCache     $BCFF4C DisableDataCache
$BCFF18 Freq2Index     $BCFF34 DisableIRQLogic$BCFF50 Run_Diagnostic_Tests
$BCFF1C Index2Freq     $BCFF38 EnableIRQLogic $BCFF54 TWGS_Failed
$BCFF20 GetCurSpeed    $BCFF3C GetTWConfig    $BCFF58 (measure speed kHz)
```
(twgs.3.s:2226-2246.) **Mapping the ROM makes all of this exist for free** —
signature and executable table both live in the image.

**Boot bypass:** at reset the ROM reads `$E0C062` (Option/solid-apple, bit7);
if pressed it skips all card init and chains to the GS ROM (twgs.3.s:2015,2028).

Version string the CDA shows: *"TransWarp GS version 8/32S", "Revision 1.8S"*
(twgs.3.s:1839) — "8/32S" = 8 MHz-class, 32 KB cache.

### 4.3 Speed control — three tiers → your `speed_code`

Speed is two bits forming three discrete steps (not a continuous register):

| `CYAREG $C036`.7 (Fast) | `$BC0000`.2 (Accel) | TWGS tier | This core's step |
|---|---|---|---|
| 0 | x | ~1.0 MHz | your slow/sync cycle (untouched) |
| 1 | 0 | ~2.6 MHz (stock "fast") | `speed_code = 0` (native 2.86) |
| 1 | 1 | full TransWarp (~7–8 MHz) | `speed_code = 3` (7.16, your "100%") |

So **`$BC0000` bit 2 selects between your native step and the OSD turbo
ceiling** (`twgs_regs.turbo_code = host_speed`) — authentically that ceiling is
7.16 (`speed_code 3`), but since the core now runs a verified **14.32 MHz**
(`speed_code 4`), setting the OSD there lets the TWGS accel bit engage 14.32 too
(shares the 14.3 wedge still being chased). Simpler than ZipGS's 16-step nibble.
`GetCurISpeed` decodes exactly this: `CYAREG.7==0`→0,
else `$BC0000 & $04 ? 2 : 1` (twgs.3.s:2146). Frequency table
(`_frequencyTable`, twgs.3.s:2109): `1024`, `2600`, `7000` kHz — but index 2's
real figure comes from the NVRAM-stored *measured* max, not the table
(`Index2Freq_L` twgs.3.s:2091). Boot measures the clock against video timing
(`Time_Active_Screen` twgs.s:1205, `LA8CB` twgs.s:3574) and stores it via
`NVRAM_Write_Speed`.

Your `zipgs_regs.sv` already rates "100%" = 7.16 MHz as "TransWarp-class" — TWGS
tier 2 lands exactly on your existing `speed_code = 3`.

### 4.4 Cache — maps to your SDRAM burst+cache

- **Enable bit:** `$BC0000` **bit 1** (`ENABLE/DISABLE_DATA_CACHE`, twgs.s:1179/1192).
- **Size probe** (`Check_Cache_Size` twgs.s:700): writes `$A55A`→`$BF0000`,
  `$5AA5`→`$BF2000` (8 KB apart), re-reads `$BF0000`; unchanged ⇒ 32 KB, aliased
  ⇒ 8 KB. `GetCacheSize` returns 8 or 32.
- **Flush** (`FlushCache_L` twgs.3.s:2177): an `MVN $BC,$BC` self-copy of
  `$8000` bytes to walk the cache.

**For this core:** functionally a **no-op latch**. Your `sdram_cache.sv` is the
real thing; TWGS bit 1 can gate nothing (report "cache on, 32 KB"). If you *skip
diagnostics* via the NVRAM trick (§4.6) the cache tests never run, so you don't
even need the `$BE/$BF` window. If you don't, back `$BF0000-$BF7FFF` with 32 KB
that does **not** alias at 8 KB so `Check_Cache_Size` reports 32.

### 4.5 `$BC0000` control-latch bit layout

Only these bits are touched by firmware; it's a plain readable latch:

| Bit | Mask | Meaning | Set/clear |
|---|---|---|---|
| 1 | `$02` | data cache enable | `ENABLE/DISABLE_DATA_CACHE` (twgs.s:1179/1192) |
| 2 | `$04` | **accelerate** (drives speed tier) | `TWGS_ON/OFF` (twgs.s:529/512); read by `GetCurISpeed` |
| 3 | `$08` | IRQ-logic **disable** (1 = auto-slowdown off) | `DISABLE/ENABLE_IRQ_LOGIC` (twgs.s:1161/1170) |
| 0,4-7 | — | not written by firmware | — |

(Distinct from the software *preference byte* `TWGS_Config_Byte`, DP `$0E`,
persisted in NVRAM word 2, default `$0D` = accel+graphics+sound on — the CDA
edits it and maps its low 2 bits into `$BC0000` bits 2-3 via
`CONFIG_TW_MODE_KEEP_CACHE`, twgs.s:598. You only need the hardware latch.)

### 4.6 NVRAM (Xicor X2444) — protocol, map, and the boot short-circuit

16 words × 16 bits, bit-serial over `$BC4000/1`, MSB-first.

`$BC4001` control values: `$00` deselect · `$80` write/shift-out · `$81`
read · `$01` **FPGA readback trigger** (rising edge = "M0/RTRIG"). X2444 command
bytes (`NVRAM_CMD_*`, twgs.s:67): `$80` Disable-Write, `$81` Store, `$83`
Write-RAM, `$84` Enable-Write, `$85` Recall, `$86` Read-RAM; RAM commands OR the
4-bit word address into bits 6-3.

Word map (from `NVRAM_Validate`/`CONFIG_TW_From_NVRAM`/`NVRAM_*_Speed`):

| Word | Contents |
|---|---|
| 0 | `$AE` validity magic |
| 1 | `$01` version |
| 2 | config byte (=`TWGS_Config_Byte`) |
| 6 | `$AE` **"card initialized" flag** |
| 7,8 | measured max speed (kHz, lo/hi) |
| `$0F-$11` | 24-bit save counter |

> 🔑 **The one trick that makes boot trivial.** `NVRAM_Active_Check`
> (twgs.s:638) returns carry-clear when **word 6 == `$AE`**, and reset does
> `JSR NVRAM_Active_Check / BCC …` (twgs.3.s:2026). **If word 6 is already
> `$AE`, the ROM skips ALL diagnostics, the ADB probe, and the startup intro**,
> going straight to flush → apply-config → enable-cache. Pre-seed the NVRAM
> (`w0=$AE, w1=$01, w2=$0D, w6=$AE, w7/8=$1B58`≈7000) and the whole boot
> collapses to a handful of instructions.

> **FPGA readback:** on `$BC4001=$01` then `$BC4000` reads, return bytes so
> `FPGA_Init_Readback` sees the stop bit (bit7 of the 8th byte) **clear** → it
> returns carry-clear → the ROM **skips** `FPGA_Check_Readback` (twgs.s:1039).
> Simplest: return `$00` on `$BC4000` reads. Avoids `TWGS_Failed`.

### 4.7 `$C0xx` strobes the card snoops

The FPGA taps the GS's own I/O to decide *when to slow down*; it exposes **no
new `$C0xx` registers**. Its input pins include the decoded soft-switch page
strobes `C00X..C07X` (from a 74F138) — and the timing-critical ones are wired in
by name: **`C03X` (`$C03x`, speaker), `C06X` (`$C06x`, paddle read), `C07X`
(`$C07x`, paddle trigger)**. That is the hardware hook for the transparent
auto-slowdown detailed in **[§4.9](#49-transparent-auto-slowdown--the-timing-sensitive-locations)** — the single most important behavior for
compatibility, and the reason the boot beep / joysticks misbehave without it.

Other snooped signals:
- `CYAREG $E0C036`: bit7 Fast (§4.3), bit4 shadow-all (preserved), bits0-3
  disk-detect → slots run at normal speed (`Test_Slot_Slowdown` twgs.s:1648).
- Disk-motor soft switches `$C0C8/9,$C0D8/9,$C0E8,$C0F8/9` — when a motor is on,
  drop to normal speed during that I/O (read at reset twgs.3.s:2022).
- `SLTROMSEL $E0C02D` cleared at reset (twgs.3.s:2020).

**There is no per-slot speed-mask register on the card** (that's a ZipGS
feature — your `slot_delay`). TWGS slot slowdown is entirely CYAREG-disk-bits +
motor snooping. Your `slot_ce`/`iwm_holdoff`/`floppy_motor_on` logic in
`iigs.sv` already models exactly this behavior — reuse it unchanged.

### 4.8 IRQ / reset / NMI / CDA

- **IRQ logic** = `$BC0000` bit 3 (`TWGS_IRQ=$08`). Enabled (bit3=0) ⇒ the card
  auto-drops to normal speed during interrupt service / timing-sensitive I/O.
  Your `iwm_holdoff` + slow/sync-cycle classification already achieves the same
  end. Model bit 3 as a stored no-op.
- **Reset** `$BCFFFC`→`LFA9A` (twgs.3.s:2258,2010): card ROM runs first, inits,
  switches to emulation mode, reads the **real** GS reset vector at `$00FFFC`,
  and `RTL`s into it — chaining to normal IIgs boot. So the overlay is
  momentary and `$00FFFC` must still hold the genuine ROM vector. **Only tier C
  needs this.**
- **NMI** `$BCFFEA`→`LFA2F` (twgs.3.s:2249,1954): the hook used to defer
  CDA installation until the toolbox is up.
- **CDA** "TransWarp GS" (`CDA_Install_Hdr` twgs.s:237, installed via
  `_InstallCDA` in `LFA88` twgs.3.s:2001): a Classic Desk Accessory with Speed /
  Configure / Self-Test / About menus that edits the pref byte, pushes it to
  `$BC0000`, and `NVRAM_Save`s. **Requires tier C** (the ROM must run at boot to
  install it).

### 4.9 Transparent auto-slowdown — the timing-sensitive locations

This is separate from the speed *registers* and is the behavior that actually
keeps the **boot beep, joysticks, disk and interrupts** correct. Both cards
continuously snoop the address bus and, on accesses to a handful of
timing-critical soft switches, transparently drop the CPU to ~1 MHz **for a
short retriggerable window** — not just for the single I/O cycle.

**Why a window, not just the one cycle:** the affected timing is produced by
cycle-counted software loops *around* the access, which are ordinary RAM/CPU
cycles that otherwise run at full turbo. A speaker tone's pitch is the delay
loop *between* `$C030` toggles; a joystick value is the count of a loop polling
`$C064` after a `$C070` strobe. Slowing only the `$C030`/`$C070` access itself
(a "sync cycle") does **not** fix them — the loop must run at 1 MHz too. So each
access *reloads a down-counter*; while it is nonzero the whole CPU runs native,
and repeated accesses keep it armed for the duration of the sound / paddle scan.
(This is exactly the `iwm_holdoff` pattern already in `iigs.sv:2617` — 2 ms of
forced-native after any IWM touch — generalized to more addresses.)

**The locations** (times at the 14.318 MHz master clock; tune to taste):

| Soft switch | Address | Why cycle-sensitive | Suggested native window | Retriggered by |
|---|---|---|---|---|
| **Speaker** | `$C030` (SPKR) | tone pitch/length = delay loop between toggles | ~1–2 ms | each `$C030` |
| **Paddle trigger** | `$C070-$C07F` (PTRIG) | starts the analog one-shots; read loop then counts cycles | ~3–4 ms | `$C070` + the reads |
| **Paddle read** | `$C064-$C067` (PADDL0-3) | count until bit7 flips = stick position | (extends paddle window) | each `$C064-7` |
| **Video counter** | `$C02E/$C02F` (VERTCNT/HORIZCNT) | timing loops read the beam; IIgs self-test 05 times it (ZipGS SW1/4) | ~1 ms *(done: `counter_holdoff`)* | each `$C02E/F` read |
| **Disk / IWM** | `$C0E0-$C0EF` (+3.5/SmartPort) | bit-cell + motor timing is cycle-counted | ~2 ms *(done: `iwm_holdoff`)* | each IWM touch, motor-on |
| **Interrupt service** | *(not an address)* IRQ/NMI entry → RTI | ISRs (VBL, mouse, players) assume real-time | hold across the ISR | — |

> **Decode precisely, not by page.** The `$C03x` page also holds `CYAREG`
> (`$C036`, the *speed* register itself), the SCC (`$C038-B`), the RTC
> (`$C033`), and the **Ensoniq** sound registers (`$C03C-F`). The DOC has its
> own oscillator and is *not* CPU-timed, so do **not** slow the whole page —
> decode `$C030` (speaker) exactly. The FPGA can: it has the full `GS_A0-A15`
> bus, so the coarse `C03X` page strobe is only its trigger hint, refined by the
> address bits. If some of your sounds are already correct (GS/OS `SysBeep`, DOC
> music) and only the classic `$C030` beep is fast, that confirms this split.

**Uncatchable case:** a pure software delay loop that touches *no* I/O (a game's
homebrew `for`-delay) leaves no bus signature and cannot be auto-detected — that
is what the global OSD "CPU Speed" (or a manual "compatibility" slow) is for.

#### ZipGS vs TWGS policy — the key difference

| | Speaker / paddle slowdown | User control |
|---|---|---|
| **ZipGS** | **conditional — only if the delay setting is on** | per-category, via `$C05C` (your `slot_delay`): bit 0 = speaker delay, bits 1-7 = per-slot; the Zip menu / cdev toggles them |
| **TWGS** | **automatic — always on in hardware while accelerating** | *none for speaker/paddle* — its CDA exposes only Speed / AppleTalk-IRQ / Startup-gfx-sound; the only slowdown category it lets you toggle is **IRQ-logic** (`$BC0000` bit 3) |

So the model you guessed is right: **ZipGS gates each slowdown on a setting;
TWGS just always does it.** The practical consequence for the core: for a
ZipGS-front-end access, arm the window only when the corresponding
`slot_delay` bit is set; for a TWGS-front-end access (`twgs_present` &
accelerating), arm it unconditionally.

> Confidence: the "TWGS always slows" conclusion is inferred, not proven from
> gates — from (a) the CDA menu having no speaker/paddle delay items and (b) the
> FPGA dedicating `C03X`/`C06X`/`C07X` input pins to exactly those pages. The
> precise per-page window lengths live in the routing we did not decode; the
> table's durations are standard-practice values, not measured from the card.
> `INTEGRATION.md §7` gives the implementation.

#### ✅ Implemented (branch `transwarp`)

Landed in `rtl/iigs.sv`: `$C030` (speaker, 2 ms), `$C070-$C07F` + `$C064-$C067`
(paddle, 4 ms), and `$C02E/$C02F` (video counter / ZipGS SW1/4, 1 ms)
retriggerable native-speed windows (`beep_holdoff` / `pdl_holdoff` /
`counter_holdoff`), folded into `fast_thresh` via `io_slow_holdoff`. The full
ZipGS DIP-switch mapping and emulator comparison live in
[`../zipgs_compatibility.md`](../zipgs_compatibility.md). Because Auto/Off/ZipGS
all matter, the on/off control is a **3-way OSD option** "Beep/Paddle Slowdown"
(`Apple-IIgs.sv` `status[17:16]` → `beep_fix_mode`):

| Mode | `beep_fix_mode` | Behavior |
|---|---|---|
| **Auto** (default) | 0 | always slow at speaker/paddle when accelerating — the beep/joystick fix, and the TWGS-style "always" |
| **Off** | 1 | never slow — raw speed, wrong beep/paddle |
| **ZipGS** | 2 | gate on the ZipGS `$C05C` speaker-delay bit (`zip_slot_delay[0]`) — software/ZipDA-driven, authentic ZipGS |

Auto is the default (not ZipGS) on purpose: `$C05C` powers on as `0` and is
rarely written, so ZipGS-gating would leave the beep broken by default. The
window only affects `fast_thresh` while accelerating, so native regression
timing is untouched. Interrupt-service slowdown (§4.9 last row) is not yet
implemented — add if music-player / mouse ISRs run fast.

---

## 5. Implementing TWGS in this core

### 5.1 What you already have (reuse, don't rebuild)

| TWGS need | Your existing asset |
|---|---|
| accelerate on/off + speed step | `zipgs_regs.sv` `speed_code`/`accel_en` → `fast_thresh` → `clock_divider.v` |
| data cache | `sdram_cache.sv` / `sdram_burst.sv` (always on) |
| slot / disk / IRQ slowdown | `slot_ce`, `iwm_holdoff`, `floppy*_motor_on` in `iigs.sv` |
| bank `$BC` decode | `mmu.sv` (+ `{bank,addr}` / `{bank_bef,addr_bef}` in `iigs.sv:365,408`) |
| host/OSD speed override | `host_speed` (`Apple-IIgs.sv:210`, `status[14:12]`) |
| register-module template | `zipgs_regs.sv` structure & CDC discipline |

### 5.2 New RTL (tier B) — ✅ implemented (branch `transwarp`)

These modules are in `rtl/` and wired into the core (read overlay, fastest-wins
speed combine, bank-`$BC` native-pace guard) behind the OSD "TransWarp GS"
toggle (default Off). Verilator build + boot verified with the card both off and
on. Detection (`'TWGS'` at `$BCFF00`) is wired but not yet runtime-verified —
needs software that probes the signature/`JSL` table. See [`INTEGRATION.md`](INTEGRATION.md).

| File (`rtl/`) | Role |
|---|---|
| `twgs_card.sv` | Top wrapper: bank-`$BC` decode + read mux + `sel`/`dout`/`accel`/`speed` |
| `twgs_regs.sv` | `$BC0000` control latch → speed tier (`bit2`+`CYAREG.7`) |
| `twgs_nvram.sv` | Xicor X2444 serial NVRAM on `$BC4000/1`, pre-seeded (boot short-cut) |
| `twgs_rom.sv` + `twgs_rom.hex` | 32 KB firmware @ `$BC8000` (signature + `JSL` API) |

The sketch below is what `twgs_regs.sv` implements (kept for reference):

```systemverilog
// twgs_regs.sv — TransWarp GS control latch + speed mapping ($BC0000)
// Parallels zipgs_regs.sv; drives the SAME clock_divider speed step.
module twgs_regs (
    input  wire       clk,          // CLK_14M
    input  wire       reset,
    // one pulse per CPU write to $BC0000 (gate with phi2 in the caller)
    input  wire       cfg_wr_stb,
    input  wire [7:0] cfg_wr_data,
    output reg  [7:0] cfg_reg,       // read back at $BC0000
    input  wire       cyareg7,       // CYAREG.7 (Fast)
    output wire       accel_en,      // 1 = TWGS acceleration engaged
    output wire [2:0] speed_code,    // 0 = native .. 3 = 7.16 MHz
    output wire       cache_enable,  // $BC0000.1 (advisory; your cache is real)
    output wire       irq_logic_en   // ~$BC0000.3 (advisory; slowdown already modeled)
);
  always @(posedge clk)
    if (reset)            cfg_reg <= 8'h00;
    else if (cfg_wr_stb)  cfg_reg <= cfg_wr_data;

  wire accel = cfg_reg[2];                 // $BC0000 bit2
  assign accel_en     = cyareg7 & accel;   // engage only when both fast + accel
  assign speed_code   = accel_en ? turbo_code : 3'd0;  // OSD ceiling vs native
  assign cache_enable = cfg_reg[1];
  assign irq_logic_en = ~cfg_reg[3];
endmodule
```

> The authoritative versions are the `.sv` files in this folder +
> [`INTEGRATION.md`](INTEGRATION.md); the snippets below are illustrative.
> `turbo_code` is the OSD "CPU Speed" ceiling — the accel bit only gates it
> (see §2 answers), so the OSD sets the speed and the card turns it on/off.

Wiring in `iigs.sv` (mirrors the ZipGS block at `iigs.sv:2551-2631`):

```systemverilog
// $BC0000 write strobe — bank-BC absolute decode (not $C0xx I/O)
wire twgs_cfg_sel = (bank_bef == 8'hBC) && (addr_bef == 16'h0000);
wire twgs_cfg_wr  = we && phi2 && twgs_cfg_sel;   // memory write, not IO

wire       twgs_accel_en;  wire [2:0] twgs_speed_code;  wire [7:0] twgs_cfg_rd;
twgs_regs twgs (
  .clk(CLK_14M), .reset(reset),
  .cfg_wr_stb(twgs_cfg_wr), .cfg_wr_data(dout), .cfg_reg(twgs_cfg_rd),
  .cyareg7(CYAREG[7]),
  .accel_en(twgs_accel_en), .speed_code(twgs_speed_code),
  .cache_enable(/*advisory*/), .irq_logic_en(/*advisory*/)
);

// Combine the two accelerators into the one speed engine. Both can be active
// at once (Zip @ $C05x, TWGS @ bank $BC — disjoint). Fastest-wins:
wire       eff_accel_en   = twgs_accel_en | zip_accel_en;
wire [2:0] eff_speed_code = (twgs_speed_code > zip_speed_code) ? twgs_speed_code
                                                              : zip_speed_code;
// then feed eff_* into the existing fast_thresh expression at iigs.sv:2627
//   (replace zip_accel_en / zip_speed_code there with eff_*).
```

Plus:
- **MMU:** overlay bank `$BC` — route `$BC8000-$BCFFFF` reads to the 32 KB TWGS
  ROM image, `$BC0000` R/W to `twgs_regs`, `$BC4000/1` to `twgs_nvram`. (Your
  note "the mmu makes the `$BC/FFxx` decode trivial" — this is that.)
- **`twgs_nvram.sv`:** an MSB-first serial FSM over a 16×16 memory
  pre-initialized with `w0=$AE,w1=$01,w2=$0D,w6=$AE,w7=$1B58`; `$BC4000` reads
  return `$00` after a `$BC4001=$01` (readback → skip). ~50 lines.
- **`$BC0000` read path:** mux `twgs_cfg_rd` into your CPU read data when
  `twgs_cfg_sel && !we` (same pattern as the ZipGS read overlay at
  `iigs.sv` `zip_rdata`).

### 5.3 Tier C delta (only for the AE control panel)

Add the **reset overlay**: on machine reset, enter the CPU at the `$BCFFFC`
vector so the TWGS ROM runs first; keep `$00FFFC/FD` = the genuine GS ROM
vector so the hand-off (`LFB07`, twgs.3.s:2054) chains to normal boot; wire the
`$BCFFEA` NMI overlay for the CDA-install deferral. With the NVRAM pre-seeded
(word6=`$AE`) the ROM's boot work is minimal, so the overlay is cheap at
runtime — the cost is purely in touching your reset/vector logic.

### 5.4 Bottom line

Tier B is a couple hundred lines (`twgs_regs` + `twgs_nvram` + MMU overlay + a
read mux) that **reuse your entire speed/cache/slowdown engine**. It gives you a
second, fully-authentic accelerator identity alongside ZipGS at essentially no
runtime cost. Add tier C later if you want AE's on-screen control panel.

---

## Appendix A — The XC2064 FPGA, decoded

The card's controller is a **Xilinx XC2064** (U64, `XC2064-PLC68`) — the first
FPGA ever shipped (1985). Its configuration bitstream is stored in the EPROM
(`FPGA_Config`, extracted here as `fpga_config.bin`, 1506 bytes) and the ROM
verifies it at boot by *readback* (the `FPGA_*` routines, comparing against
`FPGA_Mask` = `fpga_mask.bin`).

**Bitstream verified genuine:** LSB-first, `0010` preamble, 24-bit length count
= 12045 (matches the XC2064's ~12,038-bit config).

**Decoded** with `decode.py` (a Python-3 port of Ken Shirriff's `reverse.py` +
`karnaugh.js`, validated bit-exact against his golden `TEST1.RBT`→`TEST1.LCA`).
Result (`decoded_clbs.txt`, rendered as Verilog in `twgs_fpga_clbs.v`):

| Metric | Value |
|---|---|
| CLBs configured | **64 / 64** (100%) |
| Registers used | 64 (35 flip-flops + 29 latches) |
| Clock domains | **1** — every CLB on the global `K` clock |
| Async set/reset | none |
| LUT modes | 40 dual-3-input, 16 four-input, 8 muxed |

Interpretation: a maxed-out, all-registered single-clock synchronous
controller. **What's not decoded:** inter-CLB routing (the wires between
blocks/pins) — the part even Shirriff's tool leaves unfinished. That's fine:
`twgs_fpga_clbs.v` is per-block logic for *reference only*; you do not
reimplement it (see §3).

`fpga_pinmap.md` + the `schematic_fpga_*.png` crops give the U64 pin→net map:
the FPGA bridges the GS backplane (`GS_A/D/PH2/RW/IRQ/…`) to the accelerator
CPU (`CPU_*`), drives the EPROM + cache SRAM (`A0-15`, `ROM_D0-7`,
`ROM/RAM-OE/WE`), decodes `$C0xx` page strobes (`C00X-C07X` via a 74F138), and
carries the config pins (`CCLK`, `DOUT`, `M0/RTRIG=CPU_RESET`, `DONE`, `LDC`).

## Appendix B — Key source citations

**TWGS ROM (`TransWarpGS-ROM/src/twgs_1.8s/`):** equates twgs.s:50-72,123-134;
FPGA routines twgs.s:991-1128; speed twgs.s:490-546, twgs.3.s:2091-2160; cache
twgs.s:700,1179-1203, twgs.3.s:2177-2211; config twgs.s:512-634; NVRAM
twgs.s:248-446,638-689; reset/vectors/CDA twgs.3.s:1663-1839,2001-2258.

**This repo:** speed engine `rtl/clock_divider.v`, `rtl/zipgs_regs.sv`
(instantiated `rtl/iigs.sv:2566`, fed to `fast_thresh` at `iigs.sv:2627`);
cache `rtl/sdram_cache.sv`, `rtl/sdram_burst.sv`; bank/addr `iigs.sv:365,408`;
host speed `Apple-IIgs.sv:210`; MMU `rtl/mmu.sv`; prior ZipGS notes
`doc/zipgs_speed.md`, SDRAM accel `doc/sdram_accel/`.
