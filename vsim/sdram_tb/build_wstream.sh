#!/bin/sh
# Build + run the 1-tick write-stream stress TB (iverilog; local verilator is 4.204).
# Runs BOTH configurations:
#   BACKPRESSURE=0  pre-fix fire-and-forget bridge -> expect dropped writes (FAILURES)
#   BACKPRESSURE=1  production fix                 -> expect OK
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o tb_wstream_bp0.vvp -Ptb_wstream.BACKPRESSURE=0 \
  tb_wstream.sv ../../rtl/sdram_cache.sv ../../rtl/sdram_burst.sv \
  ../../doc/sdram_accel/sdram_sim_chip.sv altddio_out.v
iverilog -g2012 -o tb_wstream_bp1.vvp -Ptb_wstream.BACKPRESSURE=1 \
  tb_wstream.sv ../../rtl/sdram_cache.sv ../../rtl/sdram_burst.sv \
  ../../doc/sdram_accel/sdram_sim_chip.sv altddio_out.v
echo "--- BACKPRESSURE=0 (pre-fix, failures expected) ---"
vvp tb_wstream_bp0.vvp | tail -15
echo "--- BACKPRESSURE=1 (fix, must be OK) ---"
vvp tb_wstream_bp1.vvp | tail -15
