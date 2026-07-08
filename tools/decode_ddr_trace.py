#!/usr/bin/env python3
"""Decode a ddr_trace capture from the Apple IIgs core (DEBUG_DDR_TRACE build).

Record format (64-bit LE, CYCLE_BITS=8):
  [63:56] cycle counter at change (wraps every 256 clk_sys)
  [55:0]  data:
     [30] use_cache_path  [29] wr_pending  [28] cache_hit_now
     [27] mem_stall       [26] accel_r     [25] we
     [24] phi2            [23:0] addr_bus (physical)

Capture on the MiSTer (after the wedge):
  sshpass -p 1 ssh root@<ip> 'dd if=/dev/mem of=/tmp/trace.bin bs=1M \
      iflag=skip_bytes skip=805306368 count=16'
  sshpass -p 1 scp root@<ip>:/tmp/trace.bin .

Usage: decode_ddr_trace.py trace.bin [--tail N] [--loops]
"""
import struct, sys, argparse
from collections import Counter

FLAGS = ["phi2", "we", "accel_r", "mem_stall", "hit_now", "wr_pend", "use_cache"]

def parse(fn):
    recs = []
    t = 0
    prev_cyc = None
    with open(fn, "rb") as f:
        raw = f.read()
    for off in range(0, len(raw) - 7, 8):
        (v,) = struct.unpack_from("<Q", raw, off)
        if v == 0 and off > 0:
            # zero record after start = end of capture (region was pre-zeroed)
            # (a genuine all-zero data record still has a nonzero cycle usually)
            break
        cyc = v >> 56
        data = v & ((1 << 56) - 1)
        if prev_cyc is None:
            dt = 0
        else:
            dt = (cyc - prev_cyc) & 0xFF
            if dt == 0:
                dt = 256  # cycle-wrap keepalive
        t += dt
        prev_cyc = cyc
        recs.append((t, data))
    return recs

def fmt(data):
    addr = data & 0xFFFFFF
    bits = [(data >> (24 + i)) & 1 for i in range(7)]
    fl = " ".join(f"{n}={b}" for n, b in zip(FLAGS, bits))
    return f"addr={addr:06X} {fl}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bin")
    ap.add_argument("--tail", type=int, default=100, help="print last N records")
    ap.add_argument("--head", type=int, default=30, help="print first N records")
    ap.add_argument("--loops", action="store_true", help="summarize repeating address patterns")
    a = ap.parse_args()

    recs = parse(a.bin)
    print(f"records: {len(recs)}  span: {recs[-1][0] - recs[0][0]} clk_sys ticks"
          f" ({(recs[-1][0]-recs[0][0])/14318.0:.2f} ms)" if recs else "empty")

    print("\n--- first records (trigger = first IWM access) ---")
    for t, d in recs[: a.head]:
        print(f"t={t:>10} {fmt(d)}")

    print("\n--- last records (wedge steady state) ---")
    for t, d in recs[-a.tail:]:
        print(f"t={t:>10} {fmt(d)}")

    if a.loops:
        # committed cycles = records where phi2 bit is set; count address frequency
        commits = [d & 0xFFFFFF for t, d in recs if (d >> 24) & 1]
        print(f"\ncommitted-cycle records: {len(commits)}")
        print("top addresses in the final 20k committed cycles:")
        for addr, n in Counter(commits[-20000:]).most_common(20):
            print(f"  {addr:06X}: {n}")

if __name__ == "__main__":
    main()
