#!/bin/sh
# Build the standalone SDRAM controller + behavioral-chip testbench.
# Exercises the REAL rtl/sdram.sv against doc/sdram_accel/sdram_sim_chip.sv.
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 0 -Wno-fatal \
  -Wno-WIDTH -Wno-UNUSED -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-BLKANDNBLK \
  -Wno-DECLFILENAME -Wno-CASEX -Wno-VARHIDDEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  --top-module tb_sdram \
  tb_sdram.sv altddio_out.v ../../rtl/sdram.sv ../../doc/sdram_accel/sdram_sim_chip.sv
echo "built: ./obj_dir/Vtb_sdram"
