# GEOS mouse on the IIgs core — findings

**Question:** why doesn't the mouse move the cursor in `geos.hdv`?

**Verdict:** it is **not fixable at the ADB-hardware level** in this GEOS's
configuration, and it is **not a regression**. In the mode GEOS sets up on
this core, the firmware/software handlers that would consume mouse data are
not installed — so no register-level delivery path can work. This is a
GEOS/firmware-initialization matter, not a bug in the ADB, VGC, or CPU.

The direct-`$C024` mouse path this core implements works for other software
(A2Desktop, and the regression test); GEOS simply doesn't use it.

---

## 1. It is not a regression

Built the pre-ADB-rework commit `76cb8d5` in a worktree and ran the same
mouse injection. The GEOS cursor doesn't move there either — the screenshots
before and after injection are byte-identical. GEOS mouse has never worked on
this core.

## 2. It is not joystick mode

Hypothesis: maybe this GEOS is configured for a joystick, not the mouse.
Ruled out by counting which input registers GEOS polls at the desktop:

| register | meaning | reads |
|---|---|---|
| `$C064`/`$C065` | paddle 0/1 (joystick axes) | **0** |
| `$C070` | paddle trigger | **0** |
| `$C027` | ADB mouse/keyboard status | **183** |
| `$C024` | ADB mouse data | **0** |

GEOS polls the mouse status register and never touches the joystick. It is
genuinely trying to use the ADB mouse.

## 3. How the mouse *should* reach an app (two hardware paths)

The IIgs ADB GLU exposes the mouse two ways:

- **Direct register path.** Poll `$C027` bit 7 (mouse-data-valid), then read
  `$C024` twice (X, then Y). Requires either the dedicated mouse interrupt
  (`$C027` bit 6) or a poller (VBL/firmware) to notice bit 7 and read `$C024`.
  This core implements it; **A2Desktop uses it and it works.**

- **ADB command/response path.** The ADB microcontroller autopolls devices;
  results and command responses arrive through the `$C026` data register with
  the data interrupt (`$C027` bit 4/5). The firmware's IRQ handler decodes the
  `$C026` status byte and dispatches (response / SRQ / keyboard / etc.).

## 4. What GEOS actually does (register + ROM trace)

Instrumented every `$C0xx` mouse access with the opcode-fetch PC and cross-
referenced against the IIgs ROM source in `IIgsRomSource/`:

1. GEOS runs the mouse in **VBL / transparent mode**: `SetMouse` (Misc ToolSet
   `$FEB2ED`) takes the `DisMouse` branch (`TRB $C027,#$40`), leaving the
   mouse-interrupt bit 6 **clear**.
2. GEOS enables **only the ADB data interrupt** (`$C027 = 0x10`, bit 4).
3. GEOS **never reads `$C024`** — confirmed even via the shadowed `$E0/$E1`
   path. Its VBL handler calls the slot-4 `SERVEMOUSE` (`$00C447`), which does
   `BIT $C027; BVC skip` — it needs bit 6 (mouse-int), which is off, so it
   reports "not a mouse interrupt" and never reads the position.

So GEOS expects the mouse delivered through the ADB **autopoll/data-interrupt**
path, and its own slot-4 VBL poll is a no-op because it disabled bit 6.

## 5. The three delivery paths, ruled out with proof

| path | attempt | result |
|---|---|---|
| direct `$C024` | (already implemented) | GEOS never reads `$C024` — unused |
| SRQ (`$C026` bit 3) | raise a mouse SRQ on movement | **interrupt storm** — the ROM `INTSRQ` finds device 3 is not in its SRQ poll list (GEOS uses VBL mode, not SRQ mode), hits `OFLIST` ("no device returned data → disable SRQs") while the SRQ stays asserted |
| RESPONSE (`$C026` bit 7) | post an unsolicited absolute-device response | **crash** — GEOS consumes it (reads the `0x81` status byte, enters `INTRSPNS`) and the byte delivery is correct (`Y=b2`, `X=bc`), but `INTRSPNS` jumps through a **null completion vector** |

The RESPONSE path got the furthest: the response byte format (per gsplus
`adb_response_packet`: `$C026` status = `0x80|(N-1)`) is right, GEOS's ROM
handler `INTRSPNS` (`$FCDB65`) runs and reads both mouse bytes. Then it calls
its completion vector and dies with "System error near `$C002`".

## 6. The decisive evidence — the handler vectors are not installed

Dumped the ADB interrupt/completion vectors from E1 RAM after GEOS boots:

```
IRQ_VBL      $E10030 -> $FFBA18   SECRTL  (SEC; RTL — a DO-NOTHING stub)
IRQ_MOUSE    $E10034 -> $FFBA18   SECRTL  (same do-nothing stub)
IRQ_RESPONSE $E10040 -> $FCDB65   INTRSPNS (valid)
IRQ_SRQ      $E10044 -> $FCD83A   INTSRQ   (valid)
VCTRCPLT     $E103DC -> JML $000000        (NULL — INTRSPNS jumps here -> crash)
```

`$FFBA18` is `SECRTL` in the ROM: `SEC; RTL`, a stub that does nothing. So:

- The **VBL** and **mouse-interrupt** handlers are the do-nothing stub — even
  if the mouse interrupt fired (bit 6), nothing would read `$C024`.
- The autopoll **response completion vector** is null — posting a response
  jumps to `$000000` → garbage → the "$C002" crash.
- GEOS's slot-4 `SERVEMOUSE` VBL poll needs bit 6, which GEOS left off.

**No installed handler consumes mouse data.** That is why no ADB delivery can
work: the software side isn't wired up. On a working system the Tool
Locator / GS/OS / the mouse driver installs a real `IRQ_VBL`/`IRQ_MOUSE`
handler (or registers the absolute-poll completion vector). This GEOS setup
does not.

## 7. Why "another GEOS worked"

A GEOS build whose mouse works almost certainly differs in one of:

- runs the mouse in **interrupt mode** (`$C027` bit 6 set) with a real
  `IRQ_MOUSE` handler installed (not the `$FFBA18` stub), or
- installs a VBL mouse-service handler / registers the poll completion vector,
- or is simply configured for the mouse where this image is not.

Fastest way to confirm: boot the working GEOS, dump `$E10030`, `$E10034`,
`$E103DC` (as in §6), and compare. If those vectors point at real handlers,
that build installs the mouse service and this one doesn't — nothing to fix
on the hardware.

## 8. What was landed

- **A2Desktop mouse regression cell** (`vsim/regression.sh`): injects mouse
  movement on the A2Desktop desktop (which uses the direct `$C024` path) and
  checks the cursor moves. Guards the working mouse path against regressions
  (exactly what any future ADB mouse work would put at risk). Deterministic
  via `--fixed-time`. Suite is 10/10.
- No RTL change — every mouse-delivery attempt was reverted (the SRQ stormed,
  the RESPONSE crashed; neither is shippable).

## 9. Reproduce / resume

Debug build: add `` `define DEBUG_MOUSE `` in `rtl/iigs.sv` and a trace of
`ps2_mouse` toggles + reads/writes of `$C024/$C026/$C027` with the opcode-fetch
PC (latch `cpu_addr` when `cpu_vpa && cpu_vda`). Then:

```
cd vsim
./obj_dir/Vemu --disk geos.hdv --send-mouse 810:60,50 --stop-at-frame 818
# vectors:
./obj_dir/Vemu --disk geos.hdv --memory-dump 800 --stop-at-frame 800 --quiet
#   read $E10030/$E10034/$E10040/$E10044/$E103DC from memdump_frame_0800_slowram.bin (E1 at +0x10000)
```

Key PCs: GEOS mouse poll `SERVEMOUSE` `$00C447`; ROM IRQ data handler `@66`
`$FFBE67`; response handler `INTRSPNS` `$FCDB65`; SRQ handler `INTSRQ`
`$FCD83A`. Reference for the response byte format: gsplus
`software_emulators/gsplus/src/adb.c` `adb_response_packet()`.
