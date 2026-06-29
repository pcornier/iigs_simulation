#!/usr/bin/env bash
# Stage-0 beam-drift baseline for textfunk (see doc/core-timing-plan.md).
#
# Produces TWO things:
#   1. vsim frame-to-frame drift metric  (beam_trace.csv -> beam_drift.py)
#   2. the absolute CPU<->beam phase error vs the GSSquared golden, measured at
#      textfunk's own $C02F fine-align read (LDA $2F at PC 00/207B).
#
# A correctly-timed core makes vsim's $C02F read match GSS's ($48 == char 9),
# rock-stable. Today vsim reads $5A/$5B (char 27/28) == ~18 chars / ~250px off.
#
# Usage:  ./beam_stage0.sh            (runs vsim; GSS leg only if GSS is built)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GSS="$HERE/../software_emulators/gssquared"
DISK="$HERE/textfunk.po"
OUT="${OUT:-/tmp/beam_stage0}"
mkdir -p "$OUT"

echo "=== [1/3] vsim: trace textfunk frames 430-436 ==="
( cd "$HERE" && ./obj_dir/Vemu --disk "$DISK" --beam-trace 430,436 \
      --stop-at-frame 437 --quiet --no-cpu-log >"$OUT/vsim.log" 2>&1 )
cp -f "$HERE/beam_trace.csv" "$OUT/beam_trace.csv" 2>/dev/null

echo "=== [2/3] vsim frame-to-frame drift metric ==="
python3 "$HERE/beam_drift.py" "$OUT/beam_trace.csv"

echo
echo "=== vsim \$C02F fine-align reads (PC 00/207B) ==="
awk -F, 'NR>1 && $9=="C02F" && $4=="R"{print "  frame="$2" data=$"$10" char="($12-63<0?0:$12-63)}' \
    "$OUT/beam_trace.csv"

if [ -x "$GSS/build/bin/GSSquared" ]; then
  echo
  echo "=== [3/3] GSSquared golden: trace textfunk, extract \$C02F ==="
  rm -f "$HOME/Documents/trace.bin"
  ( cd "$GSS" && LD_LIBRARY_PATH="$PWD/build/lib" DISPLAY="${DISPLAY:-:0}" \
      ./build/bin/GSSquared -p 5 --disk "$DISK" --stop-at-frame 321 \
      --trace-entries 3500000 >"$OUT/gss.log" 2>&1 )
  LD_LIBRARY_PATH="$GSS/build/lib" "$GSS/build/gstrace" 65816 "$HOME/Documents/trace.bin" \
      2>/dev/null | grep -E '/C02F' > "$OUT/gss_c02f.txt"
  echo "  GSS \$C02F read-value distribution (data byte):"
  awk '{print "    $"$NF}' "$OUT/gss_c02f.txt" | sort | uniq -c
  echo "  -> GSS golden fine-align == \$48 (char 9). vsim target = same."
else
  echo "(GSSquared not built; skipping golden leg)"
fi
