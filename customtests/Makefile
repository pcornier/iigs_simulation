# Makefile for assembling with Merlin32

# ============================================================================
# Variables
# ============================================================================
ASM = ./Merlin32_v1.2_b2/MacOS/Merlin32
CP2 = ./cp2_1.1.1_osx-x64_sc/cp2
SCC_DISK = scc_test.2mg
TIMING_DISK = timing_race_test.2mg

# ============================================================================
# Phony Targets
# ============================================================================
.PHONY: all all_tests clean scc_test timing_test plb_test scc_phantom_test \
        dbr_corruption_test serial_selftest c034_test scc_regtest \
        scc_regptr_test scc_selftest sccauto_test io_autorun_test \
        io_debug_test dbr_plb_stage_test dbr_e0_scan_test scc_loopback scc_romseq \
        scc_rxenable scc_exact scc_repro scc_postloop scc_fifo_test

# ============================================================================
# Default Target
# ============================================================================
all: scc_test scc_regtest scc_selftest scc_regptr_test sccauto_test \
     scc_phantom_test serial_selftest plb_test dbr_corruption_test \
     dbr_plb_stage_test dbr_e0_scan_test c034_test timing_test \
io_debug_test io_autorun_test

# ============================================================================
# SCC Tests
# ============================================================================

# SCC Serial Test - builds a bootable disk with the SCC slowMem test
scc_test: SCC.SYSTEM scc_test.2mg

SCC.SYSTEM: SCC_SLOWMEM_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_test.2mg: SCC.SYSTEM
	@echo "Creating SCC test disk..."
	@cp blank.2mg scc_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing scc_test.2mg"
	$(CP2) rm scc_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_test.2mg "SCC.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_test.2mg "SCC.SYSTEM"
	$(CP2) sa scc_test.2mg type=SYS "SCC.SYSTEM"
	@echo "SCC test disk ready: scc_test.2mg"

# SCC Register Test - simple read/write test for debugging I/O access
scc_regtest: SCCREG.SYSTEM scc_regtest.2mg

SCCREG.SYSTEM: SCC_REGTEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_regtest.2mg: SCCREG.SYSTEM
	@echo "Creating SCC register test disk..."
	@cp blank.2mg scc_regtest.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing scc_regtest.2mg"
	$(CP2) rm scc_regtest.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_regtest.2mg "SCCREG.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_regtest.2mg "SCCREG.SYSTEM"
	$(CP2) sa scc_regtest.2mg type=SYS "SCCREG.SYSTEM"
	@echo "SCC register test disk ready: scc_regtest.2mg"

# SCC Register Pointer Test - tests two-step register access protocol
scc_regptr_test: SCCRPTR.SYSTEM scc_regptr_test.2mg

SCCRPTR.SYSTEM: SCC_REGPTR_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_regptr_test.2mg: SCCRPTR.SYSTEM
	@echo "Creating SCC register pointer test disk..."
	@cp blank.2mg scc_regptr_test.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_regptr_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_regptr_test.2mg "SCCRPTR.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_regptr_test.2mg "SCCRPTR.SYSTEM"
	$(CP2) sa scc_regptr_test.2mg type=SYS "SCCRPTR.SYSTEM"
	@echo "SCC register pointer test disk ready: scc_regptr_test.2mg"

# SCC Selftest Replica - replicates ROM selftest Test 06 sequence
scc_selftest: SCCSLF.SYSTEM scc_selftest.2mg

SCCSLF.SYSTEM: SELFTEST_SCC.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_selftest.2mg: SCCSLF.SYSTEM
	@echo "Creating SCC selftest replica disk..."
	@cp blank.2mg scc_selftest.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_selftest.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_selftest.2mg "SCCSLF.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_selftest.2mg "SCCSLF.SYSTEM"
	$(CP2) sa scc_selftest.2mg type=SYS "SCCSLF.SYSTEM"
	@echo "SCC selftest replica disk ready: scc_selftest.2mg"

# SCC Transmit Buffer Test - tests Tx Buffer Empty bit behavior
scc_txbuf: SCCTXBF.SYSTEM scc_txbuf.2mg

SCCTXBF.SYSTEM: SCC_TXBUF_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_txbuf.2mg: SCCTXBF.SYSTEM
	@echo "Creating SCC transmit buffer test disk..."
	@cp blank.2mg scc_txbuf.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_txbuf.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_txbuf.2mg "SCCTXBF.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_txbuf.2mg "SCCTXBF.SYSTEM"
	$(CP2) sa scc_txbuf.2mg type=SYS "SCCTXBF.SYSTEM"
	@echo "SCC transmit buffer test disk ready: scc_txbuf.2mg"

# SCC Loopback Test - tests internal loopback mode (WR14 bit 4)
scc_loopback: SCCLOOP.SYSTEM scc_loopback.2mg

SCCLOOP.SYSTEM: SCC_LOOPBACK_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_loopback.2mg: SCCLOOP.SYSTEM
	@echo "Creating SCC loopback test disk..."
	@cp blank.2mg scc_loopback.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_loopback.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_loopback.2mg "SCCLOOP.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_loopback.2mg "SCCLOOP.SYSTEM"
	$(CP2) sa scc_loopback.2mg type=SYS "SCCLOOP.SYSTEM"
	@echo "SCC loopback test disk ready: scc_loopback.2mg"

# SCC ROM Sequence Test - replicates exact ROM selftest sequence
scc_romseq: SCCROM.SYSTEM scc_romseq.2mg

SCCROM.SYSTEM: SCC_ROM_SEQUENCE_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_romseq.2mg: SCCROM.SYSTEM
	@echo "Creating SCC ROM sequence test disk..."
	@cp blank.2mg scc_romseq.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_romseq.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_romseq.2mg "SCCROM.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_romseq.2mg "SCCROM.SYSTEM"
	$(CP2) sa scc_romseq.2mg type=SYS "SCCROM.SYSTEM"
	@echo "SCC ROM sequence test disk ready: scc_romseq.2mg"

# SCC RX Enable Test - tests that WR3[0] gates reception
scc_rxenable: SCCRXEN.SYSTEM scc_rxenable.2mg

SCCRXEN.SYSTEM: SCC_RX_ENABLE_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_rxenable.2mg: SCCRXEN.SYSTEM
	@echo "Creating SCC RX enable test disk..."
	@cp blank.2mg scc_rxenable.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_rxenable.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_rxenable.2mg "SCCRXEN.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_rxenable.2mg "SCCRXEN.SYSTEM"
	$(CP2) sa scc_rxenable.2mg type=SYS "SCCRXEN.SYSTEM"
	@echo "SCC RX enable test disk ready: scc_rxenable.2mg"

# SCC Exact ROM Test - EXACT ROM selftest sequence
scc_exact: SCCEXACT.SYSTEM scc_exact.2mg

SCCEXACT.SYSTEM: SCC_EXACT_ROM_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_exact.2mg: SCCEXACT.SYSTEM
	@echo "Creating SCC exact ROM test disk..."
	@cp blank.2mg scc_exact.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_exact.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_exact.2mg "SCCEXACT.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_exact.2mg "SCCEXACT.SYSTEM"
	$(CP2) sa scc_exact.2mg type=SYS "SCCEXACT.SYSTEM"
	@echo "SCC exact ROM test disk ready: scc_exact.2mg"

# SCC ROM Fail Reproducer - preconditions WR14 then runs ROM sequence
scc_repro: SCCREPRO.SYSTEM scc_repro.2mg

SCCREPRO.SYSTEM: SCC_ROM_FAIL_REPRO.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_repro.2mg: SCCREPRO.SYSTEM
	@echo "Creating SCC reproducer disk..."
	@cp blank.2mg scc_repro.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_repro.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_repro.2mg "SCCREPRO.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_repro.2mg "SCCREPRO.SYSTEM"
	$(CP2) sa scc_repro.2mg type=SYS "SCCREPRO.SYSTEM"
	@echo "SCC reproducer disk ready: scc_repro.2mg"

# SCC Post-Loopback TX Test - disable loopback and send bytes B0,B6,B7,8D,8A
scc_postloop: SCCPOST.SYSTEM scc_postloop.2mg

SCCPOST.SYSTEM: SCC_POST_LOOPBACK_TX.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_postloop.2mg: SCCPOST.SYSTEM
	@echo "Creating SCC post-loopback TX test disk..."
	@cp blank.2mg scc_postloop.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_postloop.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_postloop.2mg "SCCPOST.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_postloop.2mg "SCCPOST.SYSTEM"
	$(CP2) sa scc_postloop.2mg type=SYS "SCCPOST.SYSTEM"
	@echo "SCC post-loopback TX test disk ready: scc_postloop.2mg"

# SCC FIFO Test - tests 3-byte RX FIFO with rapid loopback transmission
scc_fifo_test: SCCFIFO.SYSTEM scc_fifo_test.2mg

SCCFIFO.SYSTEM: SCC_FIFO_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_fifo_test.2mg: SCCFIFO.SYSTEM
	@echo "Creating SCC FIFO test disk..."
	@cp blank.2mg scc_fifo_test.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_fifo_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_fifo_test.2mg "SCCFIFO.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_fifo_test.2mg "SCCFIFO.SYSTEM"
	$(CP2) sa scc_fifo_test.2mg type=SYS "SCCFIFO.SYSTEM"
	@echo "SCC FIFO test disk ready: scc_fifo_test.2mg"

# SCC Simple Reset Test - minimal test of RR0 after hardware reset
scc_reset: SCCRST.SYSTEM scc_reset.2mg

SCCRST.SYSTEM: SCC_RESET_SIMPLE.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_reset.2mg: SCCRST.SYSTEM
	@echo "Creating SCC reset test disk..."
	@cp blank.2mg scc_reset.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_reset.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_reset.2mg "SCCRST.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_reset.2mg "SCCRST.SYSTEM"
	$(CP2) sa scc_reset.2mg type=SYS "SCCRST.SYSTEM"
	@echo "SCC reset test disk ready: scc_reset.2mg"

# SCC Both Channels Test - tests both channel A and B
scc_wr2: SCCWR2.SYSTEM scc_wr2.2mg

scc_both: SCCBOTH.SYSTEM scc_both.2mg

SCCBOTH.SYSTEM: SCC_BOTH_CHANNELS.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_both.2mg: SCCBOTH.SYSTEM
	@echo "Creating SCC both channels test disk..."
	@cp blank.2mg scc_both.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_both.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_both.2mg "SCCBOTH.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_both.2mg "SCCBOTH.SYSTEM"
	$(CP2) sa scc_both.2mg type=SYS "SCCBOTH.SYSTEM"
	@echo "SCC both channels test disk ready: scc_both.2mg"

# SCC Auto Test - builds a bootable disk with the auto SCC test
sccauto_test: SCCAUTO.SYSTEM sccauto_test.2mg

SCCAUTO.SYSTEM: SCCAUTO.SYSTEM.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

sccauto_test.2mg: SCCAUTO.SYSTEM
	@echo "Creating SCC auto test disk..."
	@cp blank.2mg sccauto_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing sccauto_test.2mg"
	$(CP2) rm sccauto_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm sccauto_test.2mg "SCCAUTO.SYSTEM" 2>/dev/null || true
	$(CP2) add sccauto_test.2mg "SCCAUTO.SYSTEM"
	$(CP2) sa sccauto_test.2mg type=SYS "SCCAUTO.SYSTEM"
	@echo "SCC auto test disk ready: sccauto_test.2mg"

# SCC Phantom Read Test - tests for phantom reads during STA to SCC registers
scc_phantom_test: SCCTEST.SYSTEM scc_phantom_test.2mg

SCCTEST.SYSTEM: SCC_PHANTOM_READ_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_phantom_test.2mg: SCCTEST.SYSTEM
	@echo "Creating SCC phantom read test disk..."
	@cp blank.2mg scc_phantom_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing scc_phantom_test.2mg"
	$(CP2) rm scc_phantom_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_phantom_test.2mg "SCCTEST.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_phantom_test.2mg "SCCTEST.SYSTEM"
	$(CP2) sa scc_phantom_test.2mg type=SYS "SCCTEST.SYSTEM"
	@echo "SCC phantom read test disk ready: scc_phantom_test.2mg"

# ============================================================================
# Serial Tests
# ============================================================================

# Serial Selftest Replica - replicates the actual ROM selftest I/O scan
serial_selftest: SERIAL.SYSTEM serial_selftest.2mg

SERIAL.SYSTEM: SERIAL_SELFTEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

serial_selftest.2mg: SERIAL.SYSTEM
	@echo "Creating serial selftest disk..."
	@cp blank.2mg serial_selftest.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing serial_selftest.2mg"
	$(CP2) rm serial_selftest.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm serial_selftest.2mg "SERIAL.SYSTEM" 2>/dev/null || true
	$(CP2) add serial_selftest.2mg "SERIAL.SYSTEM"
	$(CP2) sa serial_selftest.2mg type=SYS "SERIAL.SYSTEM"
	@echo "Serial selftest disk ready: serial_selftest.2mg"

# ============================================================================
# DBR Tests
# ============================================================================

# PLB DBR Test - tests PLB instruction updating DBR register
plb_test: PLB.SYSTEM plb_test.2mg

PLB.SYSTEM: PLB_DBR_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

plb_test.2mg: PLB.SYSTEM
	@echo "Creating PLB test disk..."
	@cp blank.2mg plb_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing plb_test.2mg"
	$(CP2) rm plb_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm plb_test.2mg "PLB.SYSTEM" 2>/dev/null || true
	$(CP2) add plb_test.2mg "PLB.SYSTEM"
	$(CP2) sa plb_test.2mg type=SYS "PLB.SYSTEM"
	@echo "PLB test disk ready: plb_test.2mg"

# DBR Corruption Test - identifies which instruction corrupts DBR after PLB
dbr_corruption_test: DBRTEST.SYSTEM dbr_corruption_test.2mg

DBRTEST.SYSTEM: DBR_CORRUPTION_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

dbr_corruption_test.2mg: DBRTEST.SYSTEM
	@echo "Creating DBR corruption test disk..."
	@cp blank.2mg dbr_corruption_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing dbr_corruption_test.2mg"
	$(CP2) rm dbr_corruption_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm dbr_corruption_test.2mg "DBRTEST.SYSTEM" 2>/dev/null || true
	$(CP2) add dbr_corruption_test.2mg "DBRTEST.SYSTEM"
	$(CP2) sa dbr_corruption_test.2mg type=SYS "DBRTEST.SYSTEM"
	@echo "DBR corruption test disk ready: dbr_corruption_test.2mg"

# DBR PLB Stage/Scan Test — stage E0 at $01E2, scan before/after PLB
dbr_plb_stage_test: DBRPLB.SYSTEM dbr_plb_stage_test.2mg

DBRPLB.SYSTEM: DBR_PLB_STAGE_SCAN_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

dbr_plb_stage_test.2mg: DBRPLB.SYSTEM
	@echo "Creating DBR PLB stage/scan test disk..."
	@cp blank.2mg dbr_plb_stage_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing dbr_plb_stage_test.2mg"
	$(CP2) rm dbr_plb_stage_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm dbr_plb_stage_test.2mg "DBRPLB.SYSTEM" 2>/dev/null || true
	$(CP2) add dbr_plb_stage_test.2mg "DBRPLB.SYSTEM"
	$(CP2) sa dbr_plb_stage_test.2mg type=SYS "DBRPLB.SYSTEM"
	@echo "DBR PLB stage/scan test disk ready: dbr_plb_stage_test.2mg"

# DBR E0 Scan Test — compares DBR=FF vs DBR=E0 SCC reads
dbr_e0_scan_test: DBRE0.SYSTEM dbr_e0_scan_test.2mg

DBRE0.SYSTEM: DBR_E0_SCAN_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

dbr_e0_scan_test.2mg: DBRE0.SYSTEM
	@echo "Creating DBR E0 scan test disk..."
	@cp blank.2mg dbr_e0_scan_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing dbr_e0_scan_test.2mg"
	$(CP2) rm dbr_e0_scan_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm dbr_e0_scan_test.2mg "DBRE0.SYSTEM" 2>/dev/null || true
	$(CP2) add dbr_e0_scan_test.2mg "DBRE0.SYSTEM"
	$(CP2) sa dbr_e0_scan_test.2mg type=SYS "DBRE0.SYSTEM"
	@echo "DBR E0 scan test disk ready: dbr_e0_scan_test.2mg"

# ============================================================================
# Other Tests
# ============================================================================

# C034 Bank Register Test - tests C034 register bank switching behavior
c034_test: C034TEST.SYSTEM c034_test.2mg

C034TEST.SYSTEM: C034_TIMING_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

c034_test.2mg: C034TEST.SYSTEM
	@echo "Creating C034 bank register test disk..."
	@cp blank.2mg c034_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing c034_test.2mg"
	$(CP2) rm c034_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm c034_test.2mg "C034TEST.SYSTEM" 2>/dev/null || true
	$(CP2) add c034_test.2mg "C034TEST.SYSTEM"
	$(CP2) sa c034_test.2mg type=SYS "C034TEST.SYSTEM"
	@echo "C034 test disk ready: c034_test.2mg"

# Timing Race Test - builds a bootable disk with the Y register corruption test
timing_test: YRACE.SYSTEM
	@echo "Creating timing race test disk..."
	@cp blank.2mg $(TIMING_DISK) 2>/dev/null || echo "Note: blank.2mg not found, using existing $(TIMING_DISK)"
	$(CP2) rm $(TIMING_DISK) "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm $(TIMING_DISK) "YRACE.SYSTEM" 2>/dev/null || true
	$(CP2) add $(TIMING_DISK) "YRACE.SYSTEM"
	$(CP2) sa $(TIMING_DISK) type=SYS "YRACE.SYSTEM"
	@echo "Timing race test disk ready: $(TIMING_DISK)"

YRACE.SYSTEM: Y_CORRUPTION_DEMO.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

# IO Debug Test - prints banner and does immediate C0xx reads
io_debug_test: IODEBUG.SYSTEM io_debug_test.2mg

IODEBUG.SYSTEM: IODEBUG.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

io_debug_test.2mg: IODEBUG.SYSTEM
	@echo "Creating IO debug test disk..."
	@cp blank.2mg io_debug_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing io_debug_test.2mg"
	$(CP2) rm io_debug_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm io_debug_test.2mg "IODEBUG.SYSTEM" 2>/dev/null || true
	@cp IODEBUG.SYSTEM BASIC.SYSTEM
	$(CP2) add io_debug_test.2mg "BASIC.SYSTEM"
	$(CP2) sa io_debug_test.2mg type=SYS "BASIC.SYSTEM"
	@echo "IO debug test disk ready: io_debug_test.2mg"

# IO Auto-run Test - boots directly into IODEBUG auto program
io_autorun_test: SCCAUTO_AUTO.SYSTEM io_autorun_test.2mg

SCCAUTO_AUTO.SYSTEM: IODEBUG.AUTO.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

io_autorun_test.2mg: SCCAUTO_AUTO.SYSTEM
	@echo "Creating IO auto-run disk..."
	@cp blank.2mg io_autorun_test.2mg 2>/dev/null || echo "Note: blank.2mg not found, using existing io_autorun_test.2mg"
	$(CP2) rm io_autorun_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm io_autorun_test.2mg "SCCAUTO.SYSTEM" 2>/dev/null || true
	$(CP2) add io_autorun_test.2mg "SCCAUTO.SYSTEM"
	$(CP2) sa io_autorun_test.2mg type=SYS "SCCAUTO.SYSTEM"
	@echo "IO auto-run disk ready: io_autorun_test.2mg"

# ============================================================================
# Clean
# ============================================================================
clean:
	rm -f scc_test.2mg timing_race_test.2mg io_autorun_test.2mg io_debug_test.2mg
	rm -f scc_phantom_test.2mg serial_selftest.2mg c034_test.2mg scc_regtest.2mg
	rm -f scc_regptr_test.2mg scc_selftest.2mg plb_test.2mg dbr_corruption_test.2mg
	rm -f dbr_plb_stage_test.2mg dbr_e0_scan_test.2mg sccauto_test.2mg
	rm -f *.SYSTEM
	rm -f *_S01_Segment1_Output*.txt
	rm -f *_Symbols.txt
	rm -f _FileInformation.txt
	@echo "Clean complete - removed all generated files (preserved blank.2mg)"

# SCC WR2 Test - reproduces Test 06-01 failure
SCCWR2.SYSTEM: SCC_WR2_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_wr2.2mg: SCCWR2.SYSTEM
	@cp blank.2mg scc_wr2.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_wr2.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_wr2.2mg "SCCWR2.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_wr2.2mg "SCCWR2.SYSTEM"
	$(CP2) sa scc_wr2.2mg type=SYS "SCCWR2.SYSTEM"
	@echo "SCC WR2 test disk ready: scc_wr2.2mg"

# SCC IRQ test
.PHONY: scc_irq
scc_irq: SCCIRQ.SYSTEM scc_irq.2mg

SCCIRQ.SYSTEM: SCC_IRQ_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ SCC_IRQ_TEST.S
	@echo "Built SCCIRQ.SYSTEM"

scc_irq.2mg: SCCIRQ.SYSTEM
	@cp blank.2mg scc_irq.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_irq.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_irq.2mg "SCCIRQ.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_irq.2mg "SCCIRQ.SYSTEM"
	$(CP2) sa scc_irq.2mg type=SYS "SCCIRQ.SYSTEM"
	@echo "SCC IRQ test disk ready: scc_irq.2mg"
# SCC TXEMPTY status test
.PHONY: scc_txempty
scc_txempty: SCCTXE.SYSTEM scc_txempty.2mg

SCCTXE.SYSTEM: SCC_TXEMPTY_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_txempty.2mg: SCCTXE.SYSTEM
	@cp blank.2mg scc_txempty.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_txempty.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_txempty.2mg "SCCTXE.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_txempty.2mg "SCCTXE.SYSTEM"
	$(CP2) sa scc_txempty.2mg type=SYS "SCCTXE.SYSTEM"
	@echo "SCC TXEMPTY test disk ready: scc_txempty.2mg"
# SCC Vector + TX pending test
.PHONY: scc_vtx
scc_vtx: SCCVTX.SYSTEM scc_vtx.2mg

SCCVTX.SYSTEM: SCC_VECTOR_TX_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_vtx.2mg: SCCVTX.SYSTEM
	@cp blank.2mg scc_vtx.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_vtx.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_vtx.2mg "SCCVTX.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_vtx.2mg "SCCVTX.SYSTEM"
	$(CP2) sa scc_vtx.2mg type=SYS "SCCVTX.SYSTEM"
	@echo "SCC Vector TX test disk ready: scc_vtx.2mg"

# SCC Self Test 06 - reproduces ROM self-test failure
.PHONY: scc_selftest06
scc_selftest06: SCC06.SYSTEM scc_selftest06.2mg

SCC06.SYSTEM: SCC_SELFTEST_06.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_selftest06.2mg: SCC06.SYSTEM
	@cp blank.2mg scc_selftest06.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_selftest06.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_selftest06.2mg "SCC06.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_selftest06.2mg "SCC06.SYSTEM"
	$(CP2) sa scc_selftest06.2mg type=SYS "SCC06.SYSTEM"
	@echo "SCC Self Test 06 disk ready: scc_selftest06.2mg"

# Comprehensive SCC Test - covers all ROM selftest checks
.PHONY: scc_full
scc_full: SCCFULL.SYSTEM scc_full.2mg

SCCFULL.SYSTEM: SCC_FULL_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_full.2mg: SCCFULL.SYSTEM
	@cp blank.2mg scc_full.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_full.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_full.2mg "SCCFULL.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_full.2mg "SCCFULL.SYSTEM"
	$(CP2) sa scc_full.2mg type=SYS "SCCFULL.SYSTEM"
	@echo "Comprehensive SCC test disk ready: scc_full.2mg"

# SCC WR15 Test - tests WR15/RR15 register access bug
.PHONY: scc_wr15
scc_wr15: SCCWR15.SYSTEM scc_wr15.2mg

SCCWR15.SYSTEM: SCC_WR15_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_wr15.2mg: SCCWR15.SYSTEM
	@cp blank.2mg scc_wr15.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_wr15.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_wr15.2mg "SCCWR15.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_wr15.2mg "SCCWR15.SYSTEM"
	$(CP2) sa scc_wr15.2mg type=SYS "SCCWR15.SYSTEM"
	@echo "SCC WR15 test disk ready: scc_wr15.2mg"

# SCC Baud Rate Generator Test
.PHONY: scc_baud_test
scc_baud_test: SCCBAUD.SYSTEM scc_baud_test.2mg

SCCBAUD.SYSTEM: SCC_BAUD_TEST.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

scc_baud_test.2mg: SCCBAUD.SYSTEM
	@cp blank.2mg scc_baud_test.2mg 2>/dev/null || echo "Note: blank.2mg not found"
	$(CP2) rm scc_baud_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm scc_baud_test.2mg "SCCBAUD.SYSTEM" 2>/dev/null || true
	$(CP2) add scc_baud_test.2mg "SCCBAUD.SYSTEM"
	$(CP2) sa scc_baud_test.2mg type=SYS "SCCBAUD.SYSTEM"
	@echo "SCC Baud Rate test disk ready: scc_baud_test.2mg"
