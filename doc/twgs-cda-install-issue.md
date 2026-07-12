# TWGS CDA auto-install — open issue (the last piece of Tier C)

**Status:** phase 2 machinery shipped (commit `26b7cc8`), benign but incomplete.
The "TransWarp GS" entry does not yet appear in the Classic Desk Accessories
menu. Everything up to the final stack detour works; this doc records exactly
where it stops so the investigation can resume cold.

## What works (sim-verified, `rtl/iigs.sv` twgs_nmi_state machine)

1. **Handoff detection.** The firmware's chain-to-IIgs-ROM sequence (`LFB07`,
   twgs.3.s:2054) data-reads `$00FFFC` from bank-`$BC` code. That signature
   (VDA & ~VPA read of 00/FFFC with the last instruction fetch from bank $BC)
   arms a 2.5 s countdown. The countdown **pauses while execution is inside
   bank `$BC`**, so the firmware's own early vector read (via `LF94F`) cannot
   mistime it — it effectively times from the true handoff.
2. **NMI delivery.** One ~9 µs NMI_N pulse; a *tight* overlay serves only the
   native NMI vector (`$00FFEA/B` → `LFB24`) and its 4-byte `JMPL $BCFA2F`
   (`$00FB24-27`) from the card ROM. Runtime bank-0 language-card traffic is
   untouched. If the CPU was in emulation mode it pulls `$FFFA` (real ROM
   handler, benign) and we miss — retried every 0.1 s, up to 15 times.
3. **Trampoline executes.** `LFA2F` (twgs.3.s:1954) runs end-to-end on our
   CPU: `REP #$20 / PHB / PHA / PHA`, the stack-relative shuffle
   (`LDA $6,S → STA $3,S`, `LDA $8,S → STA $5,S`), the injected return
   (`#$BCFA → $8,S`, `#$FA5C → $7,S`), the four hardware-ack reads of
   `LFB24`/`LFFEA`, `PLA`, `RTI`.

## What fails

The `RTI` resumes the **interrupted code** (observed: the ROM wait loop at
`FF:FCE1`) instead of detouring to `LFA5D` (`$BC:FA5D`, the routine that
saves zero page via `MVN`, calls `_InstallCDA` — `LFA88`, twgs.3.s:2001 —
and chains back to the interrupted PC).

## Diagnosis so far / hypothesis

The firmware's rewrite offsets are tuned to the **real 65C816's native
interrupt frame** as it sits after `PHB + PHA + PHA` (5 bytes pushed on top
of the 4-byte native frame P/PCL/PCH/PBR). For the detour to work, the bytes
`RTI` pops (after one `PLA`) must be the *injected* `$FA5C/$BCFA` values, and
`LFA5D` must later find the *copied-down* original return where the shuffle
put it. On our P65C816 core the `RTI` evidently pops the **original** frame
bytes — meaning at least one of:

- the native-NMI frame our core pushes differs in size/order from the real
  chip (check the `GotInterrupt` microcode path — what exactly is pushed, in
  which order, and where S points afterwards);
- 16-bit stack-relative `LDA/STA $n,S` addressing is off by one relative to
  the real chip in this M=0 context;
- `PLA` width vs the `REP #$20` state, shifting where `RTI` reads.

Note the CPU passes 504/512 SingleStepTests — this compound sequence
(native NMI frame + stack-relative rewrite + PLA + RTI) is evidently outside
that coverage.

## How to resume

1. Repro: `vsim/sim.v` → `twgs_present(1'b1)`, `make`, then
   `./obj_dir/Vemu --headless --stop-at-frame 1010 > trace.log` and find
   `BC:FA2F` (the trampoline; appears once, ~frame 1000 after the retries).
   `$time` in sim = **1 ns per CLK_14M tick**, not wall time.
2. Instrument: dump S and the 16 bytes above it at the `BC:FA2F` fetch and at
   the `RTI` (a small `ifndef SYNTHESIS` block watching `cpu_addr`, or
   verilator public_flat access to `SP`/memory from sim_main).
3. Compare against the real chip's frame: native interrupt pushes PBR, PCH,
   PCL, P (P at S+1 after entry). Walk the firmware sequence by hand from
   twgs.3.s:1954 and check byte-for-byte where our core diverges.
4. Fix the core (or, if the core is right and the frame differs for another
   reason, adjust the overlay/NMI timing), rerun the CDA test:
   `--send-keys '1450:\b' --send-keys '1480:\m' --send-keys '1510:\e'
   --send-keys '1570:\M\c' --screenshot 1650` — success = "TransWarp GS"
   listed in the Desk Accessories menu.
5. Then verify: entry opens (Speed/Configure/Self-Test/About menus render),
   changes persist via NVRAM save, and a GS/OS boot still installs cleanly.

## Reference material

- Firmware source: `/home/alans/mister/TransWarpGS-ROM/src/twgs_1.8s/`
  (`twgs.3.s` LFA2F/LFA5D/LFA88/LFB07/LFB24; `twgs.s` CDA_Install_Hdr:237).
- Manual: `doc/TransWarpGS_Manual.pdf` ch.2 (CDA menus).
- Research: `doc/transwarp_gs/README.md` §4.8 (IRQ/reset/NMI/CDA).
- The state machine + WIP notes: `rtl/iigs.sv` (search `twgs_nmi_state`).

## 2026-07-12 update — machinery DISABLED after hardware crash

First hardware exposure (merged build `79306b19`) crashed **ROM1** boots to
the monitor (double BRK at 00/03FB and 00/0000, X=$00BC on the stack frame):
the trampoline's mis-landing RTI is only benign in the ROM3-sim case that was
tested. The NMI fire is now fenced behind `` `ifdef TWGS_CDA_INSTALL `` in
`rtl/iigs.sv` (default off — the state machine arms but never counts).
Define it to resume the investigation, and this time validate on BOTH ROM
versions in sim before any hardware deploy.
