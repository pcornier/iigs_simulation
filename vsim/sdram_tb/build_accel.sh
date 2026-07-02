#!/bin/sh
# Build the production accelerator integration testbench (mirrors the Apple-IIgs.sv bridge).
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 0 -Wno-fatal \
  -Wno-WIDTH -Wno-UNUSED -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-BLKANDNBLK \
  -Wno-DECLFILENAME -Wno-CASEX -Wno-VARHIDDEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  --top-module tb_accel \
  tb_accel.sv altddio_out.v ../../rtl/sdram_burst.sv ../../rtl/sdram_cache.sv \
  ../../doc/sdram_accel/sdram_sim_chip.sv
echo "built: ./obj_dir/Vtb_accel"
