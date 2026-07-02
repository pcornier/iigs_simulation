#!/bin/sh
# Build the burst-controller prototype testbench.
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 0 -Wno-fatal \
  -Wno-WIDTH -Wno-UNUSED -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-BLKANDNBLK \
  -Wno-DECLFILENAME -Wno-CASEX -Wno-VARHIDDEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  --top-module tb_burst \
  tb_burst.sv ../../doc/sdram_accel/sdram_burst.sv ../../doc/sdram_accel/sdram_sim_chip.sv
echo "built: ./obj_dir/Vtb_burst"
