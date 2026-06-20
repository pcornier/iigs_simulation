# ADB SRQ Interrupt Fix Plan

## Context

Wolfenstein 3D IIgs uses the ADB at a lower level than normal keyboard polling. It disables ADB autopolling, installs an `_SRQPoll` completion routine for keyboard device 2, and expects raw key press/release changes to arrive through ADB service request interrupts.

The current RTL is good enough for basic boot, simple keyboard polling, and the ADB diagnostic cases we have been targeting, but it is missing parts of the interrupt/SRQ behavior that this style of software depends on.

## References

- `doc/wolfenstein-3d-iigs-code-secrets.md`
- `doc/IIGS_adb.md`
- `IIgsRomSource/Bank_FC/adb.asm`
- `software_emulators/gsplus/src/adb.c`
- `software_emulators/gsplus/src/defc.h`
- `software_emulators/clemens_iigs/clem_adb.c`
- `software_emulators/clemens_iigs/docs/Interrupts.md`

Use GSplus as the behavioral baseline for keyboard/autopoll/SRQ semantics. Use Clemens as the structural reference for separate ADB interrupt sources and status bits.

## Current Gaps

1. `rtl/adb.v` computes an `irq` output, but `rtl/iigs.sv` leaves it unconnected.

2. `rtl/iigs.sv` has no effective ADB interrupt source in the CPU IRQ path. The old enum comment lists `IRQS_ADB = 2`, but bit 2 is now used for VGC second interrupt.

3. Keyboard SRQ is not implemented as a real CPU-visible interrupt. Key events set ADB register state, but the ROM's `IRQ_SRQ` path is not triggered.

4. Autopoll mode is not honored cleanly. Wolf3D disables keyboard autopolling, but the current keyboard path continues to feed the normal compatibility path.

5. The ADB keyboard event queue is too shallow for multi-key raw event traffic. It currently has one live register byte plus one staged byte.

6. Some ADB commands needed by this path are suspicious or incomplete:
   - `0x04` Set Modes
   - `0x05` Clear Modes
   - `0x06` Set Config
   - `0x07` Sync
   - `0x08` Write Mem
   - `0x09` Read Mem
   - `0x11` Send Keycode Data

7. `0x11` Send Keycode Data is currently a no-op, but the Wolf3D note forwards selected keys back to ADB with this command.

## Target Behavior

### C026 Command/Data Register

Maintain a real ADB command/status byte:

- Bit 7: response ready
- Bit 6: abort or control-strobe flush condition
- Bit 5: reset key sequence
- Bit 4: buffer flush key sequence
- Bit 3: service request pending
- Bits 2-0: response byte count encoding

Do not use `data <= 32'h00000008` as a persistent idle placeholder for SRQ readiness. SRQ should reflect an actual pending ADB service request.

### C027 Status Register

Preserve the documented status layout:

- Bit 7: mouse data register full
- Bit 6: mouse interrupt enable
- Bit 5: command/data register full
- Bit 4: command/data interrupt enable
- Bit 3: keyboard data register full
- Bit 2: keyboard interrupt enable
- Bit 1: mouse coordinate phase
- Bit 0: command register full

Writable interrupt enable bits should control whether their corresponding ADB source asserts the CPU IRQ line.

### Interrupt Sources

Model at least these ADB interrupt sources separately:

- ADB command/data response interrupt
- ADB keyboard SRQ interrupt
- ADB mouse event interrupt

Keyboard data interrupt through C027 bit 2 is documented but emulator references treat it cautiously. Clemens warns that keyboard interrupts are not supported according to docs, while keyboard SRQ is supported. Prioritize keyboard SRQ, data response, and mouse event interrupts.

## Implementation Plan

### 1. Clean Up ADB Internal State Naming

Split the current mixed concepts into explicit state:

- `c026_status_flags`
- `c027_enable_flags`
- `response_pending`
- `response_count`
- `response_shift`
- `kbd_srq_pending`
- `data_irq_pending`
- `mouse_irq_pending`

This should be a mechanical clarity step before changing behavior.

### 2. Make ADB Command Completion Reliable

Audit and fix command execution so all multi-byte commands execute exactly once after their required data bytes arrive.

Commands to verify:

- `0x04` Set Modes: OR mode bits into ADB mode.
- `0x05` Clear Modes: clear requested mode bits.
- `0x06` Set Config: update keyboard/mouse control addresses and repeat settings.
- `0x07` Sync: update mode/config/repeat/charset/layout fields.
- `0x08` Write Mem: write supported ADB RAM addresses.
- `0x09` Read Mem: return RAM or ROM bytes.
- `0x0A` Read Modes.
- `0x0B` Read Device Info.
- `0x0D` Version.
- `0x11` Send Keycode Data.

The current `CMD_EXEC` path mostly handles `0x09`, while other commands are handled in a different branch. That should be made unambiguous before wiring interrupts.

### 3. Implement Autopoll Mode Semantics

Track keyboard and mouse autopoll independently.

Keyboard autopoll should be considered off when:

- ADB mode bit 0 disables keyboard autopoll, or
- keyboard device address and keyboard control address differ.

Mouse autopoll should be considered off when:

- ADB mode bit 1 disables mouse autopoll, or
- mouse device address and mouse control address differ.

With keyboard autopoll on:

- Continue updating `$C000`, `$C010`, `$C025`, and compatibility keyboard state.
- Continue producing ADB TALK R0 data for diagnostic compatibility as needed.

With keyboard autopoll off:

- Do not depend on `$C000` polling.
- Queue raw ADB key events into keyboard register 0 queue.
- Assert keyboard SRQ if keyboard SRQ is enabled in keyboard register 3.

### 4. Add a Real ADB Keyboard Event FIFO

Replace or supplement the one-live-byte plus one-staged-byte path with a small FIFO for raw ADB register 0 events.

Suggested properties:

- Stores 8-bit ADB key event bytes.
- Bit 7 set means key up, clear means key down.
- Depth at least 8, preferably 16 if resource cost is acceptable.
- FPGA-friendly circular buffer with explicit head, tail, and count.

TALK keyboard register 0 should:

- Return up to two bytes per response.
- Return one real event plus `0xFF` if only one event is available.
- Special-case reset key events as GSplus does.
- Keep SRQ pending until the FIFO is empty.

### 5. Implement Keyboard SRQ

When keyboard autopoll is off and a key event arrives:

1. Push the raw ADB event into the keyboard event FIFO.
2. Set `kbd_srq_pending`.
3. Set C026 bit 3 while SRQ is pending.
4. Assert the ADB IRQ output.

When the ROM/toolbox reads C026:

- Return the SRQ bit if keyboard SRQ is pending.
- If the C026 SRQ status byte is read and the keyboard FIFO still has data, SRQ should remain or reappear, matching GSplus behavior.

When TALK keyboard register 0 drains the FIFO:

- Clear `kbd_srq_pending` only when no queued keyboard events remain.
- Deassert the keyboard SRQ interrupt source when drained.

### 6. Wire ADB IRQ into the Top Level

Connect `adb.irq` in `rtl/iigs.sv`.

Avoid reusing low `irq_pending[7:0]` bits that map to C046-visible flags unless the hardware reference requires it. Safer options:

- OR `adb_irq` directly into `cpu_irq`, or
- allocate an unused high `irq_pending` bit outside C046's low-byte status.

ADB IRQ must not be cleared by `$C047`, which is for Mega II interrupt clearing. ADB IRQ is cleared through ADB protocol side effects: C026 reads, C027 interrupt disable writes, response drains, mouse data drains, and keyboard SRQ queue drains.

### 7. Implement Data Response Interrupts

When an ADB command produces response bytes:

1. Set response-ready state.
2. Set C027 bit 5.
3. If C027 bit 4 is enabled, assert ADB data IRQ.

When response bytes are consumed through C026:

- Clear response-ready state after the last byte.
- Clear C027 bit 5.
- Clear the ADB data IRQ source.

This matches GSplus `adb_response_packet()` and `adb_add_data_int()` behavior.

### 8. Implement Mouse Event IRQs

When mouse data becomes valid:

1. Set C027 bit 7.
2. If C027 bit 6 is enabled, assert ADB mouse IRQ.

When mouse data is consumed:

- Clear C027 bit 7 after the required X/Y reads or TALK register 0 response.
- Clear the ADB mouse IRQ source.

Do not mix mouse SRQ with keyboard SRQ initially. Clemens notes mouse SRQs are not supported per hardware reference; mouse event IRQ via C027 is the important path.

### 9. Implement `0x11` Send Keycode Data

Wolf3D forwards selected keys back to ADB using the `keyCode` command.

Implement enough of `0x11` to pass a single ADB keycode into the normal system path when appropriate. This likely means:

- Interpret the command byte as an ADB key event.
- Update the compatibility key/modifier path if the event is acceptable.
- Avoid duplicating events already being delivered through SRQ.

This should be tested carefully because it can create key echo or double-release bugs if it overlaps with the physical event path.

## Verification Plan

### Phase 1: Existing Behavior

Run:

```bash
cd vsim
make
./regression.sh
```

Also repeat:

- Basic boot.
- ADB keyboard diagnostic.
- Caps Lock simulation test.
- Mouse movement/click smoke test.

### Phase 2: Minimal SRQ Harness

Create or use a small IIgs test that:

1. Calls Set Modes to disable keyboard autopoll.
2. Installs `_SRQPoll` completion routine for device 2.
3. Injects one key down and one key up.
4. Verifies the CPU takes an IRQ.
5. Verifies ROM enters the `IRQ_SRQ` path.
6. Verifies TALK keyboard register 0 returns the key event bytes.

Useful trace points:

- Writes to `$C026`.
- Reads from `$C026`.
- Reads/writes to `$C027`.
- CPU IRQ line transitions.
- Execution near ROM `IRQ_SRQ` / `INTSRQ`.
- ADB keyboard FIFO enqueue/dequeue.

### Phase 3: Multi-Key Raw Input

Test:

- Press W.
- Press A while W is still down.
- Release W.
- Release A.

Expected raw ADB events:

- W down
- A down
- W up
- A up

No dropped events, no reordered events, no duplicate releases.

### Phase 4: Wolf3D Path

Run Wolf3D or a Wolf3D-style harness.

Expected:

- Game can observe multiple simultaneous movement keys.
- System does not slow or wedge from uncleared ADB IRQ.
- Completion routine keeps receiving events after TOBRAMSETUP-related resets if applicable.

## Risks

- ADB timing is sensitive. Changing command/data status handling may affect boot ROM assumptions.
- Keyboard SRQ and C026 response-ready share the same register surface, so stale flags can wedge the ROM.
- Over-eager IRQ assertion can cause interrupt storms.
- Under-clearing C026/C027 status can make the ROM believe a command is still pending.
- Over-clearing SRQ can drop multi-key transitions.
- `0x11` key forwarding may double-inject events if not separated from physical input events.

## Suggested Order of Work

1. Add observability around current C026/C027/IRQ behavior.
2. Make command completion deterministic.
3. Add explicit ADB IRQ source state inside `adb.v`, but keep it unconnected.
4. Implement keyboard event FIFO and SRQ pending state.
5. Connect `adb_irq` to CPU IRQ through a high/non-C046 bit or direct OR.
6. Implement data response IRQ clearing.
7. Implement mouse IRQ clearing.
8. Implement `0x11` key forwarding.
9. Run full regression and Wolf3D-style SRQ tests.
