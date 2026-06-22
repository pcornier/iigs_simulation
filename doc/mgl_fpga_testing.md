# Running & debugging on the FPGA with MGL files

How to launch disks/games on a real MiSTer (Apple-IIgs core) **remotely** — no physical keyboard
needed — and how to capture what's on screen. This is the workflow that confirmed Lode Runner's
copy protection boots on hardware (see [`loderunner_fpga_debug.md`](loderunner_fpga_debug.md)).

It exists because the bare `load_core <rbf>` path **does not mount disk images** — only the MGL
menu-launch path does. Getting the MGL right (absolute path, correct slot, trailing reset) is the
whole trick.

---

## TL;DR

```bash
# 1. write an MGL on the MiSTer (note: ABSOLUTE path, type="s", index=3 for 5.25")
ssh root@<mister-ip> 'cat > /run/lr.mgl <<EOF
<mistergamedescription>
 <rbf>Apple-IIgs</rbf>
 <file path="/media/fat/games/Apple-IIgs/Lode Runner.woz" delay="2" type="s" index="3" />
 <reset delay="3" hold="1" />
</mistergamedescription>
EOF'

# 2. launch it
ssh root@<mister-ip> 'echo "load_core /run/lr.mgl" > /dev/MiSTer_cmd'

# 3. wait for boot, take a screenshot, copy it back
ssh root@<mister-ip> 'sleep 25; curl -s -X POST http://localhost:8182/api/screenshots'
scp "root@<mister-ip>:/media/fat/screenshots/Apple-IIgs/$(ssh root@<mister-ip> 'ls -t /media/fat/screenshots/Apple-IIgs/*.png | head -1' | xargs basename)" .
```

Test setup used here: `ssh root@192.168.1.196` (password `1`), JTAG via Altera USB Blaster,
[mrext](https://github.com/wizzomafizzo/mrext) `remote` service on port **8182**.

---

## How `load_core` + MGL actually works (Main_MiSTer)

1. `echo "load_core /path/x.mgl" > /dev/MiSTer_cmd` → `input.cpp` → `xml_load()`.
2. MiSTer **re-execs itself** with the MGL as an argument and cold-boots the core.
3. `mgl_parse()` (`support/arcade/mra_loader.cpp`) reads each `<file>` / `<reset>` element.
4. A state machine in `menu.cpp` runs the core's **OSD menu** for you: it finds the slot whose
   `(type, index)` matches a `CONF_STR` `S`/`F` entry, opens the file browser, and "selects" the
   file — i.e. it drives the same menu you'd use by hand.

Consequences worth knowing:
- `load_core <rbf>` (no MGL) loads the core but mounts **nothing**.
- If the `(type, index)` doesn't match a menu entry, the item is **silently dropped**
  (`menu.cpp`: *"F/S option not found -> deactivate mgl"*). No error on screen.
- Each `load_core` re-execs MiSTer, which **discards** any block-buffered stdout — see *Debugging*.

---

## The MGL file

```xml
<mistergamedescription>
 <rbf>Apple-IIgs</rbf>
 <file path="/media/fat/games/Apple-IIgs/Lode Runner.woz" delay="2" type="s" index="3" />
 <reset delay="3" hold="1" />
</mistergamedescription>
```

### `<rbf>` — which core
Path relative to `/media/fat`, no `.rbf` extension. `Apple-IIgs` → `/media/fat/Apple-IIgs.rbf`.

### `<file>` — mount/load an image
| attr | meaning |
|------|---------|
| `path` | **Use an ABSOLUTE path** (leading `/`). A relative path is resolved against `HomeDir()` = the core's games dir (`/media/fat/games/Apple-IIgs`), so `games/Apple-IIgs/x.woz` becomes `…/games/Apple-IIgs/games/Apple-IIgs/x.woz`, the file isn't found, and the mount **silently fails**. This is the #1 gotcha. |
| `type` | `s` = mount an SD/block image (floppies, HDDs, CDs). `f` = load directly to memory (ROMs/carts). |
| `index` | The slot number — the digit in the core's `CONF_STR` `S`/`F` entry. **0-based.** |
| `delay` | Seconds to wait before mounting (lets the core finish coming up). `1`–`2` is fine. |

### `<reset>` — re-reset after mounting
The IIgs 5.25" boot is one-shot: the cold-boot disk scan runs *before* the delayed mount completes,
so without a reset you land on the blue **"Check startup device!"** screen with a perfectly-mounted
disk. Add a trailing reset so the ROM re-scans with the disk present:

```xml
<reset delay="3" hold="1" />
```
`delay` counts from when the previous item finished (so here: ~2 s after the mount). `hold` = seconds
to hold reset (`user_io_set_kbd_reset`). This is a warm reset, which is enough to re-run the boot.

---

## Apple-IIgs slot map

From `Apple-IIgs.sv` `CONF_STR`:

| `CONF_STR` | `index` | `type` | accepts |
|-----------|---------|--------|---------|
| `S0,HDV PO 2MG` | `0` | `s` | hard-disk image (SmartPort/slot 7) |
| `S1,HDV PO 2MG` | `1` | `s` | hard-disk image (2nd) |
| `S2,WOZ PO 2MG, WOZ 3.5` | `2` | `s` | 3.5" floppy |
| `S3,WOZ DSK DO PO NIB 2MG, WOZ 5.25` | `3` | `s` | **5.25" floppy** (Lode Runner) |

> Re-check `CONF_STR` if the core is rebuilt — slot order/indices come straight from it.
> The HDD slots (0/1) auto-boot via the SmartPort scan and usually need **no** `<reset>`;
> the 5.25"/3.5" floppy slots do.

---

## Taking screenshots

The mrext `remote` service captures the **core's scaler output** (HDMI) to a PNG.

```bash
# trigger a capture (run on the MiSTer, or curl the MiSTer IP:8182 from your machine)
curl -s -X POST http://<mister-ip>:8182/api/screenshots
# newest file:
ssh root@<mister-ip> 'ls -t /media/fat/screenshots/Apple-IIgs/*.png | head -1'
# copy it back
scp "root@<mister-ip>:/media/fat/screenshots/Apple-IIgs/<name>.png" .
```

Caveats:
- **The OSD overlay is NOT in the screenshot** — only the core video plane. You can't visually
  verify in-core OSD navigation this way.
- The **Menu core's** own video *is* captured (useful for verifying keyboard reaches MiSTer).
- Compare two captures a few seconds apart (`md5sum`) to tell "live/animating" from "frozen".

---

## Keyboard & reset control (no physical keyboard)

mrext exposes a uinput virtual keyboard. Send **Linux input keycodes** (held together as a combo):

```bash
curl -s -X POST http://<mister-ip>:8182/api/controls/keyboard-raw \
     -H 'Content-Type: application/json' -d '{"keys":[29,56,100]}'
```

Useful keycodes / combos:

| action | keys | codes |
|--------|------|-------|
| Open OSD | F12 | `88` |
| Navigate OSD | Up/Down/Enter | `103`/`108`/`28` |
| MiSTer USER button = warm reset | LCtrl+LAlt+RAlt | `29,56,100` |
| IIgs warm reset (Ctrl-Reset) | LCtrl+F11 | `29,87` |
| IIgs cold reset (Ctrl-OpenApple-Reset) | LCtrl+LAlt+F11 | `29,56,87` |

Notes:
- On the IIgs core, **Open-Apple = Left Alt**, Closed-Apple = Right Alt, the reset key = F11
  (see `rtl/adb.v` / `rtl/iigs.sv`). Cold reset needs all three: `keyboard_cold_reset =
  reset_key & ctrl & open_apple`.
- Prefer the `<reset>` MGL element over key combos for scripted boots — it's deterministic.

---

## Debugging: seeing MiSTer's own log

MiSTer's `printf`s (mount/convert messages, `MGL …`, `action=load … valid=…`, input events) go to
**stdout**, normally the serial console (`ttyS0`), which you can't read over the network. Two
caveats make redirection tricky:

1. **Block buffering.** If stdout is a plain file, libc fully buffers it; you see almost nothing
   until the buffer fills. Wrap with `stdbuf -oL -eL` for line buffering.
2. **Re-exec discards the buffer.** Every `load_core` re-execs MiSTer (`execve`), which throws away
   any buffered stdout — so the interesting `mgl_parse` output is lost unless stdout is a **tty**
   (ttys are line-buffered by libc and the property survives `execve`).

Reliable recipe (a persistent pty via `socat`, independent of MiSTer's re-exec):

```bash
# on the MiSTer
setsid socat -u pty,link=/tmp/mtty,raw,echo=0 open:/tmp/mister.log,creat,append &
# (re)start MiSTer with stdout on the pty
kill "$(pidof MiSTer)"; setsid sh -c 'exec /media/fat/MiSTer > /tmp/mtty 2>&1' &
# then watch:
grep -viE 'ttyS1: 19200' /tmp/mister.log | tail -40
```

What to look for after a `load_core <mgl>`:
- `MGL /run/x.mgl` then `action=load  delay=…  type=…  index=…  path=…  valid=F` — `valid=F` (0xF)
  means all four attributes parsed; anything else means a malformed `<file>`.
- No `action=load` at all → the MGL `<file>` was never parsed (bad XML / wrong extension).
- Mount happened but disk not in the menu → almost always the **relative-path doubling** bug.

> The system MiSTer (started from `inittab`) works fine for screenshots and `load_core`; you only
> need the pty/relaunch dance when you specifically want to read MiSTer's stdout. Don't kill the
> system MiSTer otherwise.

---

## Common failure → cause

| What you see | Likely cause |
|--------------|--------------|
| Blue **"Check startup device!"** | Disk never mounted (relative path, wrong `index`/`type`), **or** mounted with no trailing `<reset>` on a one-shot 5.25" boot. |
| Core loads, nothing in OSD slot | `<file>` silently dropped — re-check absolute `path`, `type`, `index` against `CONF_STR`. |
| `load_core` loads core but never mounts | You used `load_core <rbf>` instead of `load_core <mgl>`. |
| Screenshot blank/black mid-boot | Just early in boot — wait longer and re-capture. |

---

## End-to-end example (Lode Runner, 5.25")

```bash
M=192.168.1.196
ssh root@$M 'cat > /run/lr.mgl <<EOF
<mistergamedescription>
 <rbf>Apple-IIgs</rbf>
 <file path="/media/fat/games/Apple-IIgs/Lode Runner.woz" delay="2" type="s" index="3" />
 <reset delay="3" hold="1" />
</mistergamedescription>
EOF
echo "load_core /run/lr.mgl" > /dev/MiSTer_cmd
sleep 28
curl -s -X POST http://localhost:8182/api/screenshots >/dev/null'
shot=$(ssh root@$M 'ls -t /media/fat/screenshots/Apple-IIgs/*.png | head -1')
scp "root@$M:$shot" /tmp/lr_fpga.png   # -> Lode Runner gameplay
```
