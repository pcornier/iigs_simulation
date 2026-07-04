# FLOATBUS vaporlock test — HBL floating-bus fix spec

**Status: diagnosed, fix specified, not yet implemented.** Test:
`vsim/FloatBus_260213/` (arekkusu). Run at **native speed only** — the
accelerator's $C036 override breaks the cycle-exact 1 MHz timing the test
depends on (this is correct: the test is a good regression that turbo stays
invisible to timing-sensitive code).

## What works
Our floating bus is already good — better than the reference emulators
(Clemens returns 0 for blanking and lists vaporlock as broken). The vaporlock
locks, the capture is aligned and recognizable ("APPLE", the logo, "VAPOR 60
HZ"), and active video is accurate. `video_addr` tracks the beam correctly:
the test's beacon bytes appear on the floating bus at the addresses the test
wrote them ($3FF8, $2BF8, $4000).

## What fails and why
All modes fail **spot #1** ($4050+63*262+11 = capture column 63, the
right-edge **HBL region**). We return active HGR bytes ($2a/$a0/$55) where the
Mega II fetches its off-screen HBL scan bytes ($3E/$00/$DF...). Root cause:
during HBL our `chram_x` keeps advancing through `lineaddr(y)+chram_x` into
columns 40-64, instead of following the Apple II HBL scan addressing. The
naive add misses the `& 0x78` wraparound the real scanner applies.

Spots #3-8 likewise need VBL ($C05A=0 in vblank), and the SHR corner/palette/
SCB floating bus.

## The correct address (Sather; verified in gssquared
`src/devices/displaypp/VideoScannerII.cpp`):

```
hcount : Sather H counter, sequence 0x00, 0x40..0x7F (65 values/line).
         Active = 0x58..0x7F (40); HBL = 0x00, 0x40..0x57 (25).
         Our $C02F counter (video_timing hchar) already IS this sequence.
vcount : internal V, first active scanline = 0x100.

A2toA0   = hcount & 7
V3V4V3V4 = ((vcount & 0xC0) >> 1) | ((vcount & 0xC0) >> 3)
A6toA3   = (0x68 + (hcount & 0x38) + V3V4V3V4) & 0x78     // <-- HBL wraparound
A9toA7   = (vcount & 0x38) << 4
HBL      = (hcount < 0x58)
LoresA15toA10 = 0x400  | (HBL << 12)                      // text/lores
HiresA15toA10 = 0x2000 | ((vcount & 7) << 10)             // hires
addr = A2toA0 | A6toA3 | A9toA7 | (page bits, +0x400/+0x2000 for PAGE2)
```

Our `lineaddr(y)` already encodes the V-based part and matches this for active
columns (that's why active video is correct). The HBL divergence is entirely
in the horizontal term (`A2toA0`/`A6toA3` with the `& 0x78` mask).

## Implementation approach (display- and textfunk-safe)
Compute the full Sather address from a Sather `hcount` derived from **H**
(rendering phase — active starts at HACTIVE_PIX=84, so char index
`(H-84+912)%912/14`, hcount = idx<40 ? 0x58+idx : idx==40 ? 0x00 : 0x40+idx-41)
and **V** (vcount = display line + 0x100). Use it for `video_addr_ii` **only
during HBL and only in non-SHR Apple II modes** — the display blanks there so
it can't change the picture, SHR prefetch is a separate branch
(`video_addr_shrg`), and textfunk beam-races off the active display + $C02E/
$C02F counters, none of which HBL fetches touch.

CRITICAL: derive `hcount` from the **rendering** H (HACTIVE_PIX), NOT from the
$C02F counter — the textfunk fix (`8f5394d`) moved the CPU-visible counter to
25-char HBL but left rendering; mixing them reintroduces that skew.

## Guards (both must hold at every step)
- textfunk: `--disk textfunk.po --screenshot 438 --stop-at-frame 439`,
  md5 must stay `7abff109f80d62083437e1c379389fb5`.
- FLOATBUS: build with `DEBUG_FBSPOT`, `--disk floatbus.po`; spot #1 actual
  must move toward the expct1 table (3E 00 3E 00 DF 00 DF A0 A0 FF FF).
- Full regression.sh byte-identical (native path unchanged).

Expected values per spot are embedded in FLOATBUS.S (`expct1`, `expct2`, and
the commented #3-#8 tables).
