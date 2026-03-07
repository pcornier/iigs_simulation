# Thexder IIgs WOZ: Boots in vsim, Fails on FPGA with Error $0027

## Error Description

When running `Thexder IIgs.woz` via `--woz`, the simulation (vsim/Verilator) boots successfully. On FPGA, GS/OS boots far enough to attempt launching Thexder, but fails with:

> "Start next program" error $0027 — "Cannot run. Please Try again."

## What Error $0027 Means

Error $0027 is **GS/OS I/O Error** — "Could not read or write disk. The disk may be damaged."

- Defined as `GSOS_IOerror equ $0027` in `IIgsRomSource/GSOS/GSToolbox/ResourceMgr/ResourceMgr.asm:574`
- Full message from `IIgsRomSource/GSOS/PatchToolbox/ts3-Misc.tools.asm:463`:
  `"Could not read or write disk. The disk may be damaged. Error $0027"`
- Also known as `xioerr equ $27` (ProDOS 8) and `IOError equ $27` (SmartPort driver)

The OS booted far enough to try launching Thexder, but the actual program data read failed.

---

## Root Cause Candidates (Ranked by Likelihood)

### 1. ~~Slow RAM `enable_a` Port Missing from `bram.sv`~~ — RED HERRING

**Status: RULED OUT**

**Initial concern:** `rtl/bram.sv` has no `enable_a` port, so `iigs.sv:1982` connecting `.enable_a(slowram_ce)` would be silently dropped, causing ungated slow RAM writes on FPGA.

**Why it's a red herring:** The FPGA build does NOT use `rtl/bram.sv`. Checking `files.qip`:
- Line 29: `#set_global_assignment -name SYSTEMVERILOG_FILE rtl/bram.sv` — **commented out**
- Line 37: `set_global_assignment -name VHDL_FILE rtl/dpram_bram.vhd` — **this is the real FPGA bram**

The actual FPGA `bram` module is `rtl/dpram_bram.vhd`, a VHDL wrapper around Altera's `altsyncram` IP. It **does** have `enable_a` (line 22) and correctly maps it to `clocken0` (line 67) with `clock_enable_input_a => "NORMAL"`. This properly gates all Port A operations.

```vhdl
-- From rtl/dpram_bram.vhd (the actual FPGA bram):
PORT MAP (
    clocken0 => enable_a,   -- line 67: enable_a properly gates Port A
    clocken1 => enable_b,   -- line 68: enable_b properly gates Port B
    ...
);
```

`rtl/bram.sv` is only a Verilator/simulation fallback and is not used in either the current FPGA or vsim builds. No fix needed.

---

### 2. Prologue-Based Window Resync is SIMULATION-Only

**File:** `rtl/iwm_flux.v:785-929`

The entire block from line 785 to line 929 is inside `` `ifdef SIMULATION ``. This includes **functional register assignments** that resync the fractional window counter at D5 AA 96 (address prologue) and D5 AA AD (data prologue) boundaries:

```verilog
// Lines 800-804 and 823-827 — ONLY in simulation:
window_counter    <= base_full_window;
full_window_frac  <= 10'd0;
half_window_frac  <= 10'd0;
sync_run_count    <= 4'd0;
sync_resync_done  <= 1'b0;
```

**On FPGA**, the only window resync mechanism is the **sync-run resync** (`iwm_flux.v:930-951`), which triggers on runs of consecutive 0x96 self-sync bytes between sectors.

For 3.5" disks (`use_fractional_window = IS_35_INCH`, line 225), the fractional window accumulates drift between sync-run boundaries. The prologue resync provides additional mid-sector correction that prevents byte decoding errors.

**Impact:** Accumulated fractional window drift could cause occasional byte decoding errors — enough to corrupt a sector checksum and produce an I/O error on longer reads.

**Fix:** Move the window resync assignments (lines 798-807 and 821-829) outside of the `ifdef SIMULATION` block, keeping only the `$display` statements inside it.

---

### 3. IWM Device Select Timing Differs

**File:** `rtl/iwm_controller.v:441-445`

```verilog
if (DEVICE_SELECT
`ifndef SIMULATION
    && CLK_7M_EN    // FPGA only: gates with 7MHz clock enable
`endif
)
```

In simulation, device select latching is immediate on any `DEVICE_SELECT` assertion. On FPGA, it is gated by `CLK_7M_EN`, adding up to one 7MHz cycle (~143ns) of latency.

**Impact:** If the ROM disk driver has tight timing loops, this delay could cause it to miss IWM data bytes or misalign with the IWM state machine. Could contribute to intermittent read failures.

---

### 4. PRTC Initialization Difference

**File:** `rtl/prtc.v:42-49`

```verilog
`ifdef SIMULATION
  c033 = 8'h06;   // Simulation: DATA register starts at 0x06
`else
  c033 = 8'h00;   // FPGA: DATA register starts at 0x00
`endif
```

Less likely to directly cause disk I/O errors, but could affect early system timing or BRAM address register state.

---

### 5. External SDRAM vs Internal dpram for Fast RAM

On FPGA, fast RAM goes through external SDRAM ports (`iigs.sv:1867-1870`). The Verilator simulation uses an internal `dpram` with zero read latency (`vsim/sim.v:258-265`).

SDRAM controllers introduce variable read latency. If the SDRAM controller has timing issues or doesn't handle back-to-back accesses correctly, CPU reads of fast RAM could return stale or incorrect data.

---

## Recommended Investigation Order

1. ~~Fix `bram.sv` missing `enable_a`~~ — ruled out (FPGA uses `dpram_bram.vhd` which has proper `enable_a`)
2. **Move prologue resync out of `ifdef SIMULATION`** — functional code that should run on FPGA ← START HERE
3. **Test with above fix** — if still failing, investigate IWM device select timing
4. **SDRAM controller review** — if all else checks out, profile fast RAM read latency

## Key Files Reference

| File | Lines | Issue |
|------|-------|-------|
| `rtl/dpram_bram.vhd` | 1-77 | Actual FPGA bram (has `enable_a`, issue #1 ruled out) |
| `rtl/bram.sv` | 3-21 | Sim-only fallback, NOT used in FPGA build |
| `rtl/iwm_flux.v` | 785-929 | SIMULATION-only prologue resync |
| `rtl/iwm_flux.v` | 930-951 | Sync-run resync (works on FPGA) |
| `rtl/iwm_controller.v` | 441-445 | CLK_7M_EN device select gating |
| `rtl/prtc.v` | 42-49 | Init value difference |
| `files.qip` | 29, 36-37 | bram.sv commented out, dpram_bram.vhd is real FPGA bram |
