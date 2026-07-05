# GEOS mouse — ADB autopoll delivery gap (diagnosis + plan)

**Status: diagnosed; delivery mechanism CONFIRMED and partially working (GEOS consumes the response but a $C026 byte-sequencing bug crashes it); NOT landed.** The GEOS `geos.hdv` desktop cursor does not
respond to mouse movement. This is **not a regression** — verified by building
the pre-ADB-rework commit `76cb8d5` and confirming the cursor doesn't move
there either (byte-identical before/after injection). GEOS mouse has never
worked on this core.

## Root cause (fully traced, register- and ROM-level)

Apps that work (A2Desktop, and the mouse regression test) read the mouse via
the **direct register path**: poll `$C027` bit 7 (mouse-data-valid), then read
`$C024` twice (X, then Y). Our ADB implements this, and it works.

GEOS uses a completely different path. Traced with a `$C0xx` + PC instrument:

1. GEOS sets the mouse to **VBL/transparent mode** — `SetMouse` (Misc ToolSet
   `$FEB2ED`) takes the `DisMouse` branch (`TRB $C027,#$40`, observed write =
   `0x10`), i.e. movement/button interrupts OFF, mouse-interrupt bit 6 CLEAR.
2. GEOS separately writes `$C027 = 0x10`, enabling only the ADB **data
   interrupt** (bit 4).
3. GEOS **never reads `$C024`** (confirmed even via the shadowed `$E0/E1`
   path). Its VBL handler calls the ROM `SERVEMOUSE` (`$C447`), which does
   `BIT $C027; BVC skip` — needs bit 6 (mouse-int) set, which it isn't — so it
   returns "not a mouse interrupt" and never reads the position.

So GEOS expects the mouse delivered through the ADB **autopoll** path: the ADB
microcontroller auto-polls the mouse as an **absolute device** (`ABSBIT`, Bank
FC `adb.asm`), and on movement posts a **RESPONSE** (DATAREG `$C026` status
byte bit 7 set) plus fires the data interrupt (bit 5 + bit 4). The ROM IRQ
handler (`monitor_bram.intr071.asm` `@66`, `$BE5A`) reads `$C026`, sees the
response byte, and calls `INTRSPNS` (`$DB65`), which reads the response bytes
and dispatches to a completion vector that updates the mouse screen holes /
`$E1` mouse locations. GEOS reads those. Our ADB never drives this path for
the mouse.

## Attempts made (this session)

- **Raise a mouse SRQ** (mirror the keyboard SRQ): set `$C026` status bit 3 +
  fire the data interrupt on movement. Result: **interrupt storm.** The ROM
  `INTSRQ` polls its SRQ device list, device 3 (mouse) is NOT in it (GEOS uses
  VBL/transparent mode, not SRQ mode), so it hits `OFLIST` ("no device
  returned data → disable SRQs") while our SRQ stays asserted → spins. Wrong
  mechanism. **Reverted.**

## BREAKTHROUGH (2026-07-05): response path confirmed, GEOS consumes it

Also ruled out: **not joystick mode.** Instrumented input-register poll counts
show GEOS reads the mouse status $C027 (183x) and the paddles/joystick
($C064/$C065/$C070) ZERO times. It genuinely uses the ADB mouse.

Implemented the autopoll RESPONSE delivery (uncommitted, reverted): on a mouse
move in keyboard-autopoll mode, arm a flag; one cycle later, from the IDLE
command state, post the mouse data as an unsolicited response
(cmd_response_ready + data={reg[3][1],reg[3][0]} + pending_data=2), and raise
the data IRQ (mouse_resp_pending & data_int). Format per gsplus
adb_response_packet: $C026 status byte = 0x80|(N-1).

**Result — GEOS CONSUMES it (huge progress from "nothing happens"):**
```
MOUSERD $C027 -> b0 PC=ffbe31   ; firmware sees mouse-valid+data-avail+data-int
MOUSERD $C026 -> 81 PC=ffbe67   ; @66 reads DATAREG = 0x81 (response, 2 bytes) -> INTRSPNS
MOUSERD $C027 -> b0 PC=fcdb29   ; INTRSPNS (Bank FC)
MOUSERD $C026 -> bc PC=fcdb30   ; RCVDATA reads a data byte...
MOUSERD $C026 -> bc PC=fcdb30   ; ...and reads the SAME byte again  <-- BUG
```
Then GEOS crashes: "System error near $C002".

**Exact remaining bug:** the $C026 DATA-state does not advance between
INTRSPNS's two `RCVDATA` reads — it returns the X byte (0xbc = {1,60}) twice
instead of the two distinct mouse bytes. The keyboard TALK-R0 path uses the
same `data`/`pending_data`/`cmd_response_ready`/`c026_status_read_with_data`
machinery and works, so the difference is that a **spontaneously-posted**
response (state stays IDLE, posted outside a $C026-write command context)
doesn't sequence the DATA delivery the same way a command-triggered response
does. Likely fix: post the response through the same path the keyboard command
uses (drive the state transition explicitly), or fix the IDLE->DATA hand-off /
strobe-edge advance for a spontaneous post. There may ALSO be a stale
completion-vector (VCTRCPLT) issue behind the crash — verify after the
sequencing is fixed.

Debug build: `\`define DEBUG_MOUSE` in iigs.sv with a trace of ps2_mouse
toggles and $C024/$C026/$C027 reads/writes + opcode-fetch PC (capture
cpu_addr when cpu_vpa && cpu_vda). Key PCs: @66 handler $FFBE67, INTRSPNS
$FCDB29/$FCDB30, GEOS mouse poll SERVEMOUSE $00C447.

## The correct fix (plan)

Deliver mouse movement as an ADB **autopoll absolute-device RESPONSE**, not an
SRQ:

1. On mouse move while keyboard autopoll is on and data_int is enabled, post a
   response: DATAREG (`$C026`) presents a **response status byte** with bit 7
   set and low 3 bits = (byte count − 1); then the mouse data bytes follow on
   subsequent `$C026` reads (`RCVDATA`/`READRSPNS` format, `$DB36`). Set
   `$C027` bit 5 (data available) and fire the data interrupt.
2. The completion vector `INTRSPNS` uses must be the mouse's autopoll
   completion (registered when the mouse firmware turns on `ABSBIT`
   auto-polling). This is the hard part — verify what the ADB tool registers
   as the absolute-device auto-poll completion and that a bare response with
   no pending command (PENDBIT) is dispatched to it. If the ROM requires a
   pending poll context, the model must emulate the uC's autonomous
   absolute-device poll (issue the poll internally, then complete it).
3. Self-clear the response state when drained; make sure no storm (bounded,
   one response per move).

**Reference format** (Bank FC `adb.asm`): `STATUSBIT=$80` (response bit),
`READRSPNS`/`RSPNSINT` at `$DB36`/`$DB47` (low-3-bits count then N+1 bytes),
`INTRSPNS` at `$DB65` (clears PENDBIT, calls `VCTRCPLT`). ABSBIT auto-poll
setup at `$D70E`+ and `$D753`+.

**Risk:** the ADB command/response state machine is the most fragile part of
the core (keyboard, Control Panel CDA, Wolfenstein SRQ all live here) and has
**no automated ADB test besides the new mouse-move cell**. Any change must
keep: regression.sh green (incl. the A2Desktop mouse cell), GEOS/GS-OS boot,
keyboard input, Ctrl-OA-Esc Control Panel, and Wolfenstein keyboard.

## What landed

- **A2Desktop mouse regression cell** (regression.sh): injects mouse on the
  A2Desktop desktop and checks the cursor moves — guards the working direct
  `$C024` mouse path against regressions (which is exactly what an autopoll
  fix would put at risk). Deterministic via `--fixed-time`.

## Debug recipe (to resume)

Add a gated trace in `iigs.sv` after the `video_data`/`shr_bus_byte` wires:
log `ps2_mouse` toggles and CPU reads/writes of `$C024/$C026/$C027` with the
opcode-fetch PC (capture `cpu_addr` when `cpu_vpa && cpu_vda`). Run
`--disk geos.hdv --send-mouse <f>:dx,dy ... --stop-at-frame N`. The GEOS mouse
poll is `SERVEMOUSE` at PC `$00C447`; the autopoll response handler is
`$FFBE5A`/`$FCDB65`.
