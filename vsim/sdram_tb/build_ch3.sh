#!/bin/sh
# Build the ch3 (single-word read) testbench against the PRODUCTION controller.
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 0 -Wno-fatal \
  -Wno-WIDTH -Wno-UNUSED -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-BLKANDNBLK \
  -Wno-DECLFILENAME -Wno-CASEX -Wno-VARHIDDEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  --top-module tb_ch3 \
  tb_ch3.sv ../../rtl/sdram_burst.sv ../../doc/sdram_accel/sdram_sim_chip.sv altddio_out.v
echo "built: ./obj_dir/Vtb_ch3"
