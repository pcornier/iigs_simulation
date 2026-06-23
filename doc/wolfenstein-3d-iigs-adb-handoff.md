# Wolfenstein 3D IIgs — ADB fix handoff (restart here)

Branch: **`adb-srq-wolf3d`** (off `master`). Work is **uncommitted in the working tree**:
`rtl/adb.v`, `rtl/iigs.sv`, `vsim/sim_main.cpp`.

## TL;DR

- **Goal:** make Wolfenstein 3D IIgs (1997 Logicware/Ninjaforce, by Eric Shepherd) playable. It
  freezes/hangs because it can't read the keyboard.
- **Root cause FOUND + FIXED (validated):** the ADB command state machine never executed
  CMD-state commands (Set Modes/Clear Modes/Set Config/Sync/Write Mem/LISTEN). So keyboard
  **autopoll could never be disabled**, which the game requires before it reads keys via ADB SRQ.
- **Status:** command-completion fix is **regression-clean** and **ROM1 + ROM3 both boot to the blue
  "Welcome to the IIgs"** (no 911). With the fix Wolf3D now disables autopoll and enters the level,
  but then **wedges** because the SRQ keyboard interrupt isn't serviced by the firmware (see below).
- **Remaining:** make the ADB keyboard SRQ actually get serviced by the IIgs firmware IRQ path
  (currently it just OR's into `cpu_irq`, which the firmware doesn't recognize → wedge). Possibly a
  second blocker: the bank-`$17` private-tool-set issue from `vsim/wolf_crash_analysis.md`.

## The confirmed bug + the fix (already applied)

`rtl/adb.v` has TWO command-completion code paths:
1. **CMD_EXEC state** (`if (state == CMD_EXEC)`, ~line 1150) — the REAL execution path. Originally
   only handled `0x09` (Read Mem); everything else hit `default` (no-op).
2. A **dead** `else` branch in the `$C026` write handler (`cmd_len==0`, ~line 1665) that contains
   `0x04/0x05/0x06/0x07/0x08/LISTEN` handlers but **never runs** (the CMD→CMD_EXEC transition at
   `if (state == CMD && cmd_len == 4'd0)` fires first). Its `0x04` also wrongly used `din`.

**Fix applied:** added `0x04/05/06/07/08/0x11/LISTEN` handlers to the **CMD_EXEC** `case (cmd)`,
using the collected **`cmd_data`** bytes (NOT `din`, which is stale by CMD_EXEC time). Verified by
trace: Set Modes now executes correctly (`|=10`, then `|=01 → adb_mode=11`, i.e. kbd autopoll off).
- 1-byte cmds (04/05/0x11): data in `cmd_data[7:0]`.
- 2-byte (08 Write Mem, LISTEN): byte1→`cmd_data[15:8]`, byte2→`cmd_data[7:0]`.
- 3-byte (06) / 4 or 8-byte (07): positions per the dead branch (copied).

The dead branch (~1665-1745) still exists with duplicate handlers — **TODO: delete it** so there's
one unambiguous path (low priority; it's dead).

## The SRQ work (implemented, but causes a wedge — needs integration)

The game disables kbd autopoll (`adb_mode[0]=1`) then expects raw key up/down events via ADB
**Service Request (SRQ)** interrupts (see `doc/wolfenstein-3d-iigs-code-secrets.md` Part 2 and
`doc/adb_srq_interrupt_fix_plan.md`). Implemented in `rtl/adb.v` / `rtl/iigs.sv`:
- `reg kbd_srq_pending`, `wire kbd_autopoll_off = adb_mode[0]`.
- On a key press/release while autopoll off → set `kbd_srq_pending`.
- `$C026` IDLE read returns bit 3 (`0x08`) when `kbd_srq_pending`.
- Cleared when TALK keyboard R0 drains the last event.
- New output `kbd_srq_irq = kbd_srq_pending`, OR'd directly into `cpu_irq` in `rtl/iigs.sv`.

**Why it wedges:** with autopoll off, my SRQ asserts `cpu_irq`, but the IIgs **firmware never
services it** — during the wedge it does NOT read `$C026`/`$C027`, and the CPU spins in the tool
dispatcher (`FE:0138`, the same error-recovery exit as the old bank-`$17` crash). So OR-ing into
`cpu_irq` is not how the firmware detects an ADB interrupt; the SRQ must be presented through the
status the firmware's IRQ dispatch actually polls. **This is the key remaining task.**

### Next-step ideas for SRQ
- Find the IIgs ROM IRQ-dispatch path for ADB (read `IIgsRomSource/Bank_FC/` — NOT in this clone;
  grab it from a sibling clone or the repo) to learn which register the handler checks to attribute
  an interrupt to ADB, and make SRQ set that.
- Cross-check `software_emulators/gsplus/src/adb.c` (in sibling `iigs_simulation.save1/`):
  `adb_add_kbd_srq` / `adb_clear_kbd_srq` / `adb_read_c026` — gsplus relies on the firmware doing
  TALK-R0 to drain; mirror exactly how the interrupt is surfaced.
- Watch for an **interrupt storm**: SRQ is level-asserted and only cleared on TALK-R0 drain
  (`ADB_SRQ_DRAIN`). If the firmware doesn't drain, `cpu_irq` stays high → storm.
- The wedge at `FE:0138` may ALSO be the bank-`$17` "private tool set never populated" issue
  (`vsim/wolf_crash_analysis.md`) surfacing once input works — verify separately.

## Validation already done

- `cd vsim && make` then `./regression.sh` → **7 PASS / 1 FAIL**. The 1 FAIL is `WOZ 3.5" Arkanoid
  IIgs`, which **fails on clean `master` too** (disk/timing mismatch, NOT this change). Treat 7/1 as
  the green baseline.
- ROM3 boot: GS/OS welcome (regression GS/OS PASS).
- ROM1 boot: `./obj_dir/Vemu --rom 1 --disk gsos.hdv --screenshot 1200 --stop-at-frame 1220` →
  blue "Welcome to the IIgs", **no 911**.

## How to reproduce / test Wolf3D in the sim

Disk: **`vsim/wolftest3.hdv`** (autoboots; created by the user — has all the level files).
ROM is runtime: add `--rom 1` for ROM1 (default ROM3).

Launch sequence into a level (space past each splash, then Return/Return):
```
cd vsim
./obj_dir/Vemu --disk wolftest3.hdv --no-cpu-log \
  --send-keys 2000:" " --send-keys 2400:" " --send-keys 2800:" " --send-keys 3200:" " \
  --send-keys 3600:" " --send-keys 4000:" " --send-keys 4400:" " --send-keys 4800:" " \
  --send-keys 5300:"\n" --send-keys 5600:"\n" \
  --screenshot 5000,9000 --stop-at-frame 9020
```
- ~frame 5000 = "SELECT A SCENARIO" menu; ~frame 9000 = 3D level (FLOOR 1-1, HEALTH 100%).
- Movement test: inject arrows `--send-keys 9000:"\U"` etc. **Currently the player does NOT move**
  (wedge). A working fix = the 3D view changes when you inject movement.

### `--send-keys` helpers I added to `vsim/sim_main.cpp` (test-only)
- `\oX` = Open-Apple + X (e.g. `\oo` = Apple-O "Open" in the GS/OS Finder).
- `\U \D \L \A` = Up/Down/Left/Right arrow keys (extended PS/2 scancodes).
- (Existing: `\n` Enter, `\e` Esc, `\C` caps, `\R` Ctrl+F11 reset, `\xNN` hex.)

### Debug `$display` traces I added to `rtl/adb.v` (REMOVE before commit)
Grep `ADB_KEYEV`, `ADB_SETMODE`, `ADB_CLRMODE`, `ADB_SYNC`, `ADB_SRQ_SET`, `ADB_SRQ_DRAIN`,
`ADB_EXEC`. Useful greps in a run log:
- `ADB_SETMODE` / `adb_mode` value → is autopoll getting disabled? (`autopoll_off=1` good)
- `ADB_SRQ_SET` vs `ADB_SRQ_DRAIN` → SRQ fires but never drains = the wedge.
- `ADB_KEYEV` → every key event + current `adb_mode`.
- The C++ side prints `ADB_R`/`ADB_W` for `$C026`/`$C027` accesses (see `sim_main.cpp`).

## Key facts / gotchas

- **Right game/version confirmed:** Wolfenstein 3D v1.1 (1997, Logicware, FW) — Eric Shepherd's
  KansasFest code-secrets talk is about this exact game; it DOES use the ADB SRQ multi-key trick.
- **Autopoll-off gate:** `adb_mode[0]` (Set Modes bit 0). The SRQ path is gated on this, so normal
  use (autopoll on — boot, Finder, all regression tests) is unaffected by the SRQ code.
- **Two ROMs differ:** `--rom 1` (ROM1, VERSION=5, Sync=4 bytes) vs `--rom 3` (ROM3, VERSION=6,
  Sync=8 bytes). Test both — they treat ADB differently. Both must reach the blue welcome, not 911.
- **`gsos.hdv` mutates across runs** (the sim writes to it), so its boot screenshot can differ by a
  frame; don't treat tiny GS/OS diffs as regressions — compare against a fresh pre-change run.
- Reference emulators (`software_emulators/`) and `IIgsRomSource/` are NOT in this fresh clone but
  exist in sibling clones (e.g. `/home/alans/mister/iigs_simulation.save1/`).

## UPDATE (2026-06-23 session): SRQ now drains end-to-end — root causes found & fixed

The "wedge" was **not** just SRQ delivery. Tracing `$C026/$C027` while the SRQ is
asserted (added an SRQ-pending-gated CPU trace + ADB register trace in `sim_main.cpp`)
revealed a chain of three RTL bugs in `rtl/adb.v`, all in the autopoll-off command path
that **regression never exercises** (normal boot/Finder use the autopoll path: C000 key
data + C024 mouse + valid_kbd — NOT multi-byte C026 TALK responses). All three are fixed:

1. **`$C027` bit 7 (MOUSE_DATA) wrongly included `pending_data>0`.** The ROM IRQ
   dispatcher (`FF:BE31 lda KMSTATUS; asla; bpl/bcc; jsl Mouse interrupt`) reads bit7+bit6
   and routes to the **mouse** handler. A pending command/keyboard response leaking into
   bit7 made the firmware misroute *every* ADB IRQ to the mouse handler and never check the
   keyboard/data path. Fixed: bit7 = `valid_mouse_data` only (gsplus signals response data
   via bit5 DATA_VALID). Also set bit5 = `(pending_data>0) | kbd_srq_pending`.
2. **C026 IDLE→DATA transition was gated on `cen & strobe & ~strobe_prev` and silently
   missed** (header `0x81` returned forever, `cmd_response_ready`/`pending_data` stuck). The
   mouse C024 path uses a robust strobe **falling-edge** handler — mirrored that for C026
   (set `c026_status_read_with_data` on the header read, transition on the falling edge).
3. **Device TALK/LISTEN bit layout was wrong.** The general decoder used `din[7:4]`=device
   `din[1:0]`=command, but the IIgs GLU uses **bits7-6=cmd, bits5-4=reg, bits3-0=device**
   (gsplus: `0xC0-0xCF` = TALK reg0, `dev = cmd & 0xf`). So `0xC2` (TALK keyboard R0, the
   command the ROM ADB-SRQ handler `FC:D83A` issues) was decoded as device-12 LISTEN and
   ignored. Added explicit `$C0-$CF` TALK-reg0 case (device = low nibble), returning the
   keyboard event as **2 bytes** (key, then `$FF` filler — a 1-byte response encodes header
   `$80`/count 0 and the ROM reads no key bytes), and draining the SRQ on consume.

**Validated:** `ADB_SRQ_DRAIN` fires for both the press (`key=31`) and release (`key=b1`)
of an injected space. Full ROM path exercised: `$C026`→`08` (SRQ marker) → ROM
`jsl ADB SRQ int` (`FC:D83A`) → writes `0xC2` (TALK kbd R0) → reads header `0x81` → reads
2 key bytes. Regression was **7 PASS / 1 FAIL** (WOZ Arkanoid, pre-existing) after the
bit7 fix; needs re-run after the falling-edge + TALK-R0 changes.

Regression **re-run after all three fixes = 7 PASS / 1 FAIL** (WOZ Arkanoid only — the
known pre-existing failure). All three ADB fixes are regression-clean.

### Movement NOT yet working — a SEPARATE blocker (the SRQ is fixed)

End-to-end run: game boots → all splashes advance (injected spaces) → enters the 3D level
(FLOOR 1-1, HEALTH 100%) → injected Up/Right arrows are **delivered and drained** via the
SRQ (`key=3e`=Up, `key=3c`=Right, each with a repeat — confirming the game sees the key
held). BUT holding **Up** for ~230 frames OR holding **Right** (turn) for ~230 frames
leaves the 3D view **byte-identical** (same screenshot md5). Turning can't be "blocked by a
wall," so this is NOT a facing-a-wall artifact.

**Narrowed it down (this is NOT a wedge and NOT wrong controls):**
- **Main loop is ALIVE.** Added a PCSAMPLE probe (sim_main.cpp, `DumpInstruction` fast-path,
  frame≥9000) → 212 samples at the level spread across the GAME banks `06/07/08/0E` (Wolf3D
  engine/render/logic), only 6+6 in ROM (FE/FF interrupt handlers), NO concentration at a
  single spin address and nothing at `FE:0138`. So it is **not** wedged (rules out the
  bank-`$17` theory for this state) — the 3D engine renders every frame.
- **Arrow keys ARE valid controls.** Wolf3D IIgs manual (Wolf3D.Docs.txt): default keys are
  numeric keypad (8/5/4/6 move/turn, 7/9 strafe) OR **arrow keys** (Up=fwd, Down=back,
  Left/Right=turn), Option=strafe-modifier, Shift=run, Ctrl=fire, Space=open door. The ADB
  keycodes we deliver are correct: Up=`$3e`, Right=`$3c`, Down=`$3d`, Left=`$3b`.

**So the remaining problem: the keys are delivered+drained by the ROM SRQ handler, but the
GAME's movement logic never acts on them.**

- **Hypothesis #1 (auto-repeat) TESTED → not the cause, but fixed anyway.** Our ADB ran
  key-repeat even in autopoll-off mode (held Right drained as `key=3c` TWICE). Gated repeat
  off when `kbd_autopoll_off` (rtl/adb.v ~line 980, matches gsplus which doesn't repeat in
  SRQ mode). Re-test: drains are now clean (`key=3c`×1 down + `key=bc`×1 up, no double) — but
  the 3D view is STILL byte-identical. So repeat was not the movement blocker. Keep the fix
  (correct + cleaner SRQ stream; only affects autopoll-off so regression-safe — re-verify).
- **Hypothesis #2 (ROM→game key delivery) is now the prime suspect.** The ROM SRQ handler
  (`FC:D83A`) issues TALK R0 (`0xC2`) and the response-byte handler (`FC:DB65`) reads the 2
  key bytes — i.e. the **ROM** consumes the key. Where does `FC:DB65` deliver it? Trace it to
  see whether it posts to the Event Manager / a keyboard buffer / a game vector that the
  game's input routine actually polls. Eric Shepherd's multi-key SRQ trick may have the GAME
  read keyboard reg0 directly to get all simultaneously-held keys; if so, the ROM draining
  the event first leaves the game's read empty (contention). Verified NOT-causes: the ADB
  keycodes are correct (Up=`$3e`, Right=`$3c`, Down=`$3d`, Left=`$3b`), and arrows are valid
  Wolf3D controls.

Since gsplus runs this exact game+ROM playably, the guide is to match gsplus's reg0 / TALK-R0
semantics exactly (esp. the 2-byte multi-key drain and how many events it returns per poll),
and confirm the ROM's response-byte handler delivers to wherever the game reads.

Test helpers added in `sim_main.cpp` for this (held arrows, since `--send-keys \U` sends an
instant down+up and Wolf3D moves only while a key is HELD): `\h`/`\H` = Up down/release,
`\k`/`\K` = Right down/release (markers 0x10-0x17 = arrow down/release-only).

**Debug instrumentation still in tree (REMOVE before commit):** `sim_main.cpp` —
SRQ-pending-gated CPU trace (`SRQTRACE`, in `writeLog` + `DumpInstruction` fast-path),
widened `ADB_R`/`ADB_W` logging gated on `kbd_srq_pending` (state/crr/pd/data fields),
held-arrow test markers `\h\H\k\K`. `rtl/iigs.sv` — per-cycle `cpu_irq` `$display` gated
behind `` `ifdef DEBUG_IRQ`` (it floods because the VGC scanline IRQ holds cpu_irq high).
ADB `$display` traces (`ADB_SRQ_SET/DRAIN`, `ADB_SETMODE`, …) still unconditional.

**Still to validate:** why injected arrow movement/turn isn't acted on (controls vs main-loop
wedge); re-run regression + selftest on ROM1 **and** ROM3.

## Suggested order for the next session

1. Re-confirm green: `make && ./regression.sh` (expect 7/1), ROM1+ROM3 blue-screen boot.
2. Decide SRQ delivery: read the ROM IRQ-dispatch + gsplus, make the SRQ recognized/serviced
   (drained via TALK-R0) without storming. Re-run the Wolf3D launch above and confirm the player
   moves with injected arrows.
3. If still wedging at `FE:0138`, investigate the bank-`$17` tool-set issue separately.
4. Re-run `./regression.sh` AND `./selftest.sh` on **both** `--rom 3` and `--rom 1` after every change
   (ADB is easy to break). Selftest is a manual-review of `selftest2.txt` + screenshots.
5. Remove the debug `$display` traces, delete the dead duplicate command branch in `adb.v`, commit.
