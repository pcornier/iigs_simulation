# PRAM / NVRAM Save & Restore — Handoff

**Status:** Planned, not yet implemented. Research complete; design chosen.
**Goal:** Persist the Apple IIgs battery-backed PRAM (256 bytes) across power cycles
using the standard MiSTer save mechanism (an `hps_io` SD virtual-disk slot).

---

## Summary of the decision

Adopt the **X68000_MiSTer model**: keep the internal PRAM power-on defaults, add a
dedicated mountable SD slot for the PRAM save file, and add two OSD commands —
**Load PRAM from SD** and **Save PRAM to SD** — that drive a single-block transfer to/from
a new backup DMA port on `prtc.v`.

- No PRAM file is required to boot. Internal defaults (`rtl/roms/pram_init.hex`) stand
  until the user (or the frontend) explicitly loads a file.
- Loading only overwrites the array on an explicit Load / mount — defaults are never
  clobbered unless a real save exists.
- The clock is **not** persisted — it is regenerated from the host `TIMESTAMP` each boot.
- Transfer is a single 512-byte block (`sd_lba = 0`); only the first 256 bytes are used.

### Why this model
- **X68000_MiSTer** persists its battery-backed config SRAM exactly this way
  (mountable `SC3` slot + `RD`/`RE` "Load/Save SRAM from/to SD Card" commands,
  `sramld = status[13]`, `sramst = status[14]`). It is the closest computer-core precedent
  and directly analogous to IIgs PRAM.
- **Gameboy/NES/SNES** use the same `sd_lba` + `bk_state` machine but tie it to per-game
  battery SRAM (auto-load on cart download, autosave on OSD close). Our PRAM is *global*
  core NVRAM, not per-disk, so the manual X68000 trigger model fits better.
- **MacPlus_MiSTer** (closest Apple relative, also has hardware PRAM) does **not** persist
  PRAM at all — so this feature would put the IIgs core ahead of it.

---

## Current state of the code (verified)

### PRAM lives inside `rtl/prtc.v`
- `reg [7:0] pram [255:0];` — 256 bytes.
- Initialized via `$readmemh("rtl/roms/pram_init.hex", pram)` (ROM3 defaults + checksum).
- The reset block (`always @(posedge CLK_14M)` under `if (reset)`) **does not** clear `pram`,
  so a loaded image already survives warm/cold reset — correct NVRAM behavior.
- PRAM reads/writes happen in the PRTC protocol FSM:
  - write:  `pram[clk_reg1] <= c033;`  (PRAM state, `din[6]==0`, ~line 373)
  - read:   `read_result <= pram[clk_reg1];` (~line 362)
- Instantiated in `rtl/iigs.sv` at **line ~2286** (`prtc prtc(...)`).

### The SD interface is already 4-wide and fully used
In `Apple-IIgs.sv` (top level), `hps_io #(...,.VDNUM(4))`:
- `sd_lba[4]`, `sd_rd[3:0]`, `sd_wr[3:0]`, `sd_ack[3:0]`, `sd_buff_din[4]`, etc.
- Slot **0** = HDD unit 0, **1** = HDD unit 1, **2** = WOZ 3.5", **3** = WOZ 5.25".
- `sd_buff_addr` is 9 bits `[8:0]`; `sd_buff_dout`/`din` are 8-bit (WIDE not set).
- `img_readonly` and `img_size` already wired.

The framework `sys/hps_io.sv` supports `VDNUM` up to 10 and default `BLKSZ=2` (512-byte blocks).

### CONF_STR (in `Apple-IIgs.sv`, ~line 46)
```
localparam CONF_STR = {
    "Apple-IIgs;UART19200:9600:4800:2400:1200:300;",
    "-;",
    "O[122:121],Aspect ratio,...;",
    "-;",
    "S0,HDVPO 2MG;",
    "S1,HDVPO 2MG;",
    "S2,WOZPO 2MG,WOZ 3.5;",
    "S3,WOZDSKDO PO NIB2MG,WOZ 5.25;",
    "-;",
    "OA,Force Self Test,OFF,ON;",
    "OB,ROM Version,ROM1,ROM3;",
    "O[14:12],CPU Speed,...;",
    "O[15],ZipGS Registers,Enabled,Disabled;",
    "-;",
    "R0,Warm Reset;",
    "R1,Cold Reset;",
    "JA,Fire 1,Fire 2,Fire 3;",
    ...
};
```
Note: uses both legacy (`OA`, `R0`) and new-style (`O[14:12]`) status notation. Pick free
status bits that don't collide (existing users: bits 0,1,10,11,12–14,15,121,122).

---

## Implementation plan (file by file)

### 1. `rtl/prtc.v` — add a backup DMA port
Add to the module port list:
```verilog
input  [7:0] bk_addr,   // byte address 0..255 into pram
input        bk_wr,     // write strobe (from SD load)
input  [7:0] bk_data,   // byte to write
output [7:0] bk_q       // pram[bk_addr] (combinational, for SD save)
```
- `assign bk_q = pram[bk_addr];`
- Fold the write into the **existing** `always @(posedge CLK_14M)` block (single writer —
  no second driver, FPGA-safe). Give `bk_wr` priority; it will not collide with the PRTC
  protocol write in practice because loads happen at mount/idle:
  ```verilog
  if (bk_wr) pram[bk_addr] <= bk_data;
  ```
  Place it so it wins over `pram[clk_reg1] <= c033;` for the same cycle, or simply rely on
  loads only occurring while the CPU is held/idle.
- **Optional dirty flag:** expose `output reg pram_dirty` set whenever the protocol path
  writes `pram[...]`, cleared by a `bk_clear_dirty` input. Only needed if autosave is added
  later.

### 2. `rtl/iigs.sv` — pass the port through
- Add the same 4 signals (`bk_addr`, `bk_wr`, `bk_data`, `bk_q`) to the `iigs` module port
  list (top of file, ~line 21).
- Wire them to the `prtc prtc(...)` instance at ~line 2286.

### 3. `Apple-IIgs.sv` — framework glue (bulk of the work, ~40 lines)

**a. Widen hps_io to 5 slots:**
- `hps_io #(...,.VDNUM(4))` → `.VDNUM(5)`.
- Widen the arrays: `sd_lba[5]`, `sd_buff_din[5]`, and `sd_rd/sd_wr/sd_ack/img_mounted` to
  `[4:0]`. Slot **4** = PRAM NVRAM.
- Route the `iigs` module's `bk_*` port out to the top level.

**b. CONF_STR — mirror X68000:**
```
"-;",
"S4,NV PRAM,PRAM;",          // mountable slot; adjust extension label to taste
"RG,Save PRAM to SD;",       // pick a free status bit for the save command
"RH,Load PRAM from SD;",     // pick a free status bit for the load command
```
(Choose actual free bits; `G`/`H` are placeholders. Could also nest under a "P1,Storage;"
page like X68000 does.)

**c. The single-block `bk_state` machine** (adapted from Gameboy.sv lines 1059–1099,
simplified to one block at `sd_lba[4]=0`):
```verilog
wire bk_save = status[/*G*/];
wire bk_load = status[/*H*/] | (mount_rising_edge_of_slot4 /* optional auto-load */);

reg        bk_state = 0;
reg        bk_loading = 0;
reg  [8:0] bk_cnt;        // 0..255 byte counter
reg        old_load, old_save, old_ack;

always @(posedge clk_sys) begin
    old_load <= bk_load;
    old_save <= bk_save;
    old_ack  <= sd_ack[4];

    if (~old_ack & sd_ack[4]) {sd_rd[4], sd_wr[4]} <= 0;

    if (!bk_state) begin
        if ((~old_load & bk_load) | (~old_save & bk_save)) begin
            bk_state   <= 1;
            bk_loading <= bk_load;   // load has priority if both
            sd_lba[4]  <= 32'd0;
            sd_rd[4]   <=  bk_load;
            sd_wr[4]   <= ~bk_load & bk_save;
        end
    end else begin
        if (old_ack & ~sd_ack[4]) begin
            // single 512-byte block covers all 256 PRAM bytes -> done
            bk_state   <= 0;
            bk_loading <= 0;
        end
    end
end
```

**d. Buffer <-> PRAM byte routing:**
```verilog
// address into PRAM = low 8 bits of sd_buff_addr (block 0)
assign bk_addr        = sd_buff_addr[7:0];
assign bk_data        = sd_buff_dout;
assign bk_wr          = bk_state & bk_loading & sd_buff_wr & sd_ack[4]
                        & (sd_buff_addr < 9'd256);   // ignore bytes 256..511
assign sd_buff_din[4] = bk_q;                        // pad 256..511 with FF if desired
```
The `bk_q` combinational read of `pram[sd_buff_addr[7:0]]` supplies save data; bytes
256–511 can return `8'hFF` (harmless padding in the file).

**e. Optional (later) — guarded auto-load + autosave:**
- Auto-load: trigger `bk_load` on the rising edge of `img_mounted[4]`. **Guard it** — only
  apply if the loaded image is non-blank / passes the PRAM checksum at `$FC–$FF`, so a
  freshly frontend-created blank file cannot clobber good defaults. (Simplest guard: load
  into a shadow, verify checksum, only then commit — or just start with manual-only.)
- Autosave: use `prtc.pram_dirty` + `OSD_STATUS` rising edge to auto-fire `bk_save`
  (Gameboy pattern), gated by an "Autosave" OSD toggle.

---

## Verification

### Simulation (do this first)
- The Verilator harness (`vsim/sim.v`) already backs the `hps_io` SD path. Add a hook to
  map slot-4 reads/writes to a host file (e.g. `--pram-file gs2-pram.bin`), mirroring how
  HDD/WOZ images are backed.
- Test flow:
  1. Boot, open Control Panel, change a persistent setting (e.g. display border color or
     boot slot) — this writes PRAM.
  2. Fire "Save PRAM to SD".
  3. Reboot the sim with the same PRAM file.
  4. Fire "Load PRAM from SD" (or auto-load) and confirm the setting persisted.
- Run `vsim/regression.sh` — confirm **no** video/PNG regressions (this change touches only
  PRTC + top-level plumbing, so it should be clean).

### FPGA (per `memory/fpga-test-rig.md`)
- Mount a PRAM file in slot 4, change a Control Panel setting, Save, power-cycle, Load,
  confirm persistence. SignalTap not expected to be needed.

---

## Status-bit budget (fill in when implementing)
Currently used status bits: 0 (warm reset), 1 (cold reset), 10 (self test?), 11 (ROM ver),
12–14 (CPU speed), 15 (ZipGS), 121–122 (aspect). **Verify** the exact map before picking
bits for Save/Load/Autosave — grep `status\[` in `Apple-IIgs.sv`.

---

## References
- `MiSTer-devel/X68000_MiSTer` — `X68000.sv` CONF_STR lines 75–78, `sramld/sramst`
  (status[13]/[14]) — the primary precedent (computer core, battery SRAM).
- `MiSTer-devel/Gameboy_MiSTer` — `Gameboy.sv` lines 1029–1141 — the canonical `bk_state`
  save/restore machine (with RTC extra-block handling we don't need).
- `sys/hps_io.sv` — `VDNUM` (1..10), `BLKSZ` (default 512), SD port definitions.
- Related memory: `memory/fpga-test-rig.md`.
