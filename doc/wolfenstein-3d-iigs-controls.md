# Wolfenstein 3D IIgs — controls & how to test on MiSTer

Wolf3D IIgs (1997 Logicware/Ninjaforce, Eric Shepherd) disables ADB keyboard
autopoll and reads keys **raw** via ADB Service Request (SRQ). This core now
supports that path, so the keyboard works in-game. **Movement is on the numeric
keypad, not the arrow keys.**

## Control map (host key on MiSTer → in-game action)

Source: the official game docs (`Wolf3D.Docs.txt`). The middle column is the
physical key you press on a MiSTer-attached USB keyboard.

| In-game action        | Press this key (MiSTer)      | Game key (docs) | ADB code |
|-----------------------|------------------------------|-----------------|----------|
| Move forward          | **Keypad 8**                 | Keypad 8        | $5B      |
| Move backward         | **Keypad 5**                 | Keypad 5        | $5D      |
| Turn left / right     | **Keypad 4 / Keypad 6**      | Keypad 4 / 6    | $56 / $58|
| Strafe (slide) L / R  | **Keypad 7 / Keypad 9**      | Keypad 7 / 9    | $59 / $5C|
| Strafe modifier       | **Windows / Menu key**       | Option          | $3A      |
| **Fire**              | **Left or Right Ctrl**       | Control         | $36      |
| **Run**               | **Left or Right Shift**      | Shift           | $38      |
| Open door / switch    | **Space**                    | Space Bar       | $31      |
| Select weapon 1–6     | **1 2 3 4 5 6**              | 1–6             | —        |
| Automap               | **Tab**                      | Tab             | $30      |
| Pause                 | **Esc**                      | Escape          | $35      |
| Menu commands         | **Left-Alt + P/Q/S/O**       | Apple-P/Q/S/O   | Cmd $37  |

Notes:
- **Num Lock**: use the real numeric keypad for movement. If the keypad does
  nothing, toggle Num Lock and try again.
- **Option = the Windows/Menu key** on a PC keyboard (that's what maps to ADB
  Option `$3A` in this core). Hold it with Keypad-4/6 to strafe.
- **Command (Open-Apple) = Left/Right Alt** (`$37`) — used for the Apple-letter
  menu shortcuts.
- The docs also list the **arrow keys** for movement. Those are read through the
  IIgs ASCII/$C000 path, which the game does *not* use while autopoll is off, so
  **use the keypad** in-game.

## Why Fire/Run/Strafe needed a fix

Control, Shift and Option are ADB **modifier** keys. A real ADB keyboard emits a
Register-0 make/break keycode for them ($36/$38/$3A) exactly like any other key,
*in addition to* updating the `$C025` modifier byte (confirmed against the gsplus
and Clemens emulators and the Apple "Guide to the Macintosh Family Hardware"
keycode table). Our ADB model previously suppressed modifier keycodes from
Register 0 (only updating `$C025`). Movement keys (regular keypad keys) worked,
but Wolf3D's raw-SRQ reader never saw Fire/Run/Strafe. The fix (in `rtl/adb.v`)
delivers modifier make/break on the Register-0 / SRQ path **when autopoll is off**
(autopoll-on behavior is unchanged). See the ADB handoff doc for details.

## Testing remotely (no physical keyboard at the board)

The MiSTer `remote.sh` service (mrext, port 8182) can inject keys into the core:

```
POST http://<board-ip>:8182/api/controls/keyboard-raw/<linux-input-code>
```

The keycode MUST be in the path (the bare `/api/controls/keyboard-raw` returns
the web-app HTML and does nothing). Useful Linux input codes:

| Action            | code | | Action          | code |
|-------------------|------|-|-----------------|------|
| Keypad 8 (fwd)    | 72   | | Left Ctrl (fire)| 29   |
| Keypad 5 (back)   | 76   | | Left Shift (run)| 42   |
| Keypad 4 (turn L) | 75   | | Space (door)    | 57   |
| Keypad 6 (turn R) | 77   | | Esc (pause)     | 1    |
| Keypad 7 (strafeL)| 71   | | Tab (map)       | 15   |
| Keypad 9 (strafeR)| 73   | | Left Meta (Opt) | 125  |

Example — turn right, walk forward, fire:
```bash
B=<board-ip>:8182
for i in $(seq 1 10); do curl -s -X POST http://$B/api/controls/keyboard-raw/77; done   # turn right
for i in $(seq 1 10); do curl -s -X POST http://$B/api/controls/keyboard-raw/72; done   # forward
for i in $(seq 1 5);  do curl -s -X POST http://$B/api/controls/keyboard-raw/29; done   # fire
curl -s -X POST http://$B/api/screenshots                                               # grab a frame
# newest file: GET http://$B/api/screenshots  → pick latest path → GET /api/screenshots/<path>
```
`keyboard-raw` taps (press+release); held-key behaviour comes from the game
polling the key-state table, so repeated taps accumulate into motion.
