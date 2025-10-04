# Makefile for assembling with Merlin32

# ============================================================================
# Variables
# ============================================================================
ASM = ./Merlin32_v1.2_b2/Linux/Merlin32
CP2 = ./cp2_1.1.0_linux-x64_sc/cp2
SCC_DISK = scc_test.2mg
TIMING_DISK = timing_race_test.2mg

# ============================================================================
# Phony Targets
# ============================================================================
.PHONY: all all_tests clean scc_test timing_test plb_test scc_phantom_test \
        dbr_corruption_test serial_selftest c034_test scc_regtest \
        scc_regptr_test scc_selftest sccauto_test io_autorun_test \
        io_debug_test dbr_plb_stage_test dbr_e0_scan_test

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
