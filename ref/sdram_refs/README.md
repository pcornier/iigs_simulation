# SDRAM controller references

Third-party MiSTer SDRAM controllers, pulled for comparison while designing the IIgs CPU
accelerator / SDRAM upgrade. See `../../HANDOFF_sdram_accelerator.md` for the analysis and
`../../doc/sdram_accel/` for the resulting design.

These are unmodified copies of upstream files, retained as reference only (not built here).
All are GPL (same license family as this project's own `rtl/sdram.sv`, itself a Sorgelig /
Genesis_MiSTer derivative). Pulled 2026-06-27 from MiSTer-devel default branches.

| File | Source repo | Path upstream |
|------|-------------|---------------|
| `neogeo/sdram.sv`, `neogeo/sdram_mux.sv` | MiSTer-devel/NeoGeo_MiSTer | `rtl/mem/` |
| `saturn/sdram1.sv`, `saturn/sdram2.sv`   | MiSTer-devel/Saturn_MiSTer | `rtl/` |
| `psx/sdram.sv`                            | MiSTer-devel/PSX_MiSTer    | `rtl/` |
| `psx/sdram_model.vhd`, `psx/sdram_model3x.vhd` | MiSTer-devel/PSX_MiSTer | `sim/system/src/tb/` (sim-only) |
| `n64/sdram.sv`, `n64/SDRamMux.vhd`        | MiSTer-devel/N64_MiSTer    | `rtl/` |

Key takeaway (full detail in the handoff): none of these use open-row/page-mode or bank
interleaving — they are the same single-access-per-row state machine this core already uses;
their only bandwidth edge is **burst**. The PSX VHDL "model" files are simulation behavioral
models (not synthesizable, and they don't even model tRCD/tRP) — reference only.
