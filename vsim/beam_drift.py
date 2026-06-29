#!/usr/bin/env python3
"""
beam_drift.py -- Stage 0 drift metric for CPU<->video beam phase.

Reads beam_trace.csv (produced by `Vemu --beam-trace <start>[,<end>]`), which logs
one row per enabled CPU cycle with the video beam position (V, H_CHAR) at that cycle.

A correctly-locked machine running a deterministic beam-racing demo (e.g. textfunk)
re-synchronizes to vsync every frame, so the beam position at the SAME
instruction-index-after-the-frame-anchor is identical every frame. Drift shows up as
that beam position wandering frame-to-frame, and the wander grows the further into the
frame you get. This script quantifies that.

Anchor: textfunk reads $C02F exactly once per frame (the sub-char fine-align). We use
that read as each frame's index origin, then walk opcode-fetch cycles (phase 'F') and,
for each local index j, measure how much the beam position varies across frames.

Usage:  ./beam_drift.py [beam_trace.csv]
Output: per-frame anchor beam position + a drift curve (spread vs instruction index).
"""
import sys, csv
from collections import defaultdict

PATH = sys.argv[1] if len(sys.argv) > 1 else "beam_trace.csv"

def char_index(hchar):
    # Mega II H_CHAR encoding (TN.IIGS.039): 0x00 == char 0; 0x40..0x7F == chars 1..64
    return 0 if hchar == 0 else (hchar - 0x3F)

def beam_chars(V, hchar):
    # Linear beam coordinate in "char" units (65 chars per line).
    return V * 65 + char_index(hchar)

# ---- load ----
rows = []
with open(PATH) as f:
    for r in csv.DictReader(f):
        rows.append((
            int(r["gidx"]), int(r["frame"]), r["phase"], r["type"],
            int(r["addr"], 16), int(r["data"], 16),
            int(r["V"]), int(r["HCHAR"]),
            int(r["pbr"], 16), int(r["pc"], 16),     # [8]=pbr [9]=pc
        ))
if not rows:
    print("empty trace"); sys.exit(1)

frames = sorted(set(r[1] for r in rows))
print(f"loaded {len(rows)} cycles over frames {frames[0]}..{frames[-1]}")

# ---- per-frame: find $C02F-read anchor, then index opcode fetches after it ----
# beam_at[j] = list of (V, char) tuples, one per frame that reached index j
beam_at = defaultdict(list)
pc_at   = defaultdict(list)   # (pbr,pc) per j, to detect variable-delay divergence
anchors = {}                  # frame -> (V, HCHAR) at the $C02F read

per_frame_rows = defaultdict(list)
for r in rows:
    per_frame_rows[r[1]].append(r)

for fr in frames:
    fr_rows = per_frame_rows[fr]
    # anchor = first $C02F read this frame
    anchor_i = None
    for i, r in enumerate(fr_rows):
        addr, typ = r[4], r[3]
        if (addr & 0xFFFF) == 0xC02F and typ == 'R':
            anchor_i = i
            anchors[fr] = (r[6], r[7])
            break
    if anchor_i is None:
        continue
    j = 0
    for r in fr_rows[anchor_i:]:
        if r[2] == 'F':                      # opcode fetch
            beam_at[j].append((r[6], char_index(r[7])))   # (V, char)
            pc_at[j].append((r[8], r[9]))                 # (pbr, pc)
            j += 1

# ---- report frame-start anchor stability ----
print("\n=== per-frame $C02F fine-align anchor (V, H_CHAR) ===")
print("  (rock-stable across frames == frame-start alignment is good)")
for fr in frames:
    if fr in anchors:
        v, h = anchors[fr]
        print(f"  frame {fr}: V={v:3d}  H_CHAR=${h:02X}  (char {char_index(h)})")

# ---- drift curve: spread of beam position at matched instruction index ----
# We report line-spread (V) and char-spread separately, plus a combined
# beam-coordinate spread, so a 1-line + 1-char excursion reads honestly instead
# of as a misleading ~66-char number. We also flag indices where the executed
# instruction (pbr:pc) diverges across frames -- textfunk's fine-align does a
# data-dependent variable delay, so post-anchor the streams can legitimately
# differ; those indices are not a fair beam comparison and are excluded.
nframes_with_anchor = len(anchors)
print(f"\n=== drift curve ({nframes_with_anchor} frames anchored) ===")
print("  j = opcode-fetch index after the $C02F anchor (only PC-aligned indices counted)")
worst_line = (0, 0); worst_char = (0, 0)
samples = []          # (j, line_spread, char_spread)
diverge_j = None
for j in sorted(beam_at):
    vals = beam_at[j]
    if len(vals) < nframes_with_anchor:            # only fully-covered indices
        continue
    if len(set(pc_at[j])) != 1:                    # instruction stream diverged here
        if diverge_j is None:
            diverge_j = j
        continue
    Vs   = [v for (v, c) in vals]
    Cs   = [c for (v, c) in vals]
    lsp  = max(Vs) - min(Vs)
    csp  = max(Cs) - min(Cs)
    samples.append((j, lsp, csp))
    if lsp > worst_line[1]: worst_line = (j, lsp)
    if csp > worst_char[1]: worst_char = (j, csp)

if diverge_j is not None:
    print(f"  note: instruction stream first diverges across frames at j={diverge_j}")
    print(f"        (textfunk's data-dependent fine-align delay; PC-aligned indices still compared)")

if not samples:
    print("  (no PC-aligned overlapping indices -- widen window or check anchor)")
else:
    step = max(1, len(samples) // 30)
    print("\n    j       line-spread   char-spread")
    for k in range(0, len(samples), step):
        j, lsp, csp = samples[k]
        print(f"  {j:6d}        {lsp:6d}        {csp:6d}")
    j, lsp, csp = samples[-1]
    print(f"  {j:6d}        {lsp:6d}        {csp:6d}   <- last")
    nstable = sum(1 for (_, l, c) in samples if l == 0 and c <= 1)
    print(f"\n  PC-aligned indices compared : {len(samples)}")
    print(f"  perfectly stable (<=1 char, 0 line) : {nstable}  ({100.0*nstable/len(samples):.1f}%)")
    print(f"  WORST line drift : {worst_line[1]} lines at j={worst_line[0]}")
    print(f"  WORST char drift : {worst_char[1]} chars ({worst_char[1]*14}px) at j={worst_char[0]}")
    anchor_chars = sorted(set(char_index(h) for (_, h) in anchors.values()))
    print(f"  anchor ($C02F) char values seen : {anchor_chars}  "
          f"-> {max(anchor_chars)-min(anchor_chars)}-char frame-start jitter")
