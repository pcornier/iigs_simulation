# Makefile for assembling with Merlin32

# --- Variables ---
ASM = ./Merlin32_v1.2_b2/Linux/Merlin32
CP2 = ./cp2_1.1.0_linux-x64_sc/cp2
SCC_DISK = scc_test.2mg
TIMING_DISK = timing_race_test.2mg

# --- Rules ---

# Default rule: typing 'make' will build all tests and add them to disk
all: scc_test

# All tests: build both SCC and timing race tests
all_tests: scc_test timing_test

# SCC Serial Test - builds a bootable disk with just the SCC test
scc_test: SCCAUTO.SYSTEM
	@echo "Creating SCC test disk..."
	@cp blank.2mg $(SCC_DISK) 2>/dev/null || echo "Note: blank.2mg not found, using existing $(SCC_DISK)"
	$(CP2) rm $(SCC_DISK) "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm $(SCC_DISK) "SCCAUTO.SYSTEM" 2>/dev/null || true
	$(CP2) add $(SCC_DISK) "SCCAUTO.SYSTEM"
	$(CP2) sa $(SCC_DISK) type=SYS "SCCAUTO.SYSTEM"
	@echo "SCC test disk ready: $(SCC_DISK)"

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

# Timing Race Test - builds a bootable disk with the Y register corruption test
timing_test: YRACE.SYSTEM
	@echo "Creating timing race test disk..."
	@cp blank.2mg $(TIMING_DISK) 2>/dev/null || echo "Note: blank.2mg not found, using existing $(TIMING_DISK)"
	$(CP2) rm $(TIMING_DISK) "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm $(TIMING_DISK) "YRACE.SYSTEM" 2>/dev/null || true
	$(CP2) add $(TIMING_DISK) "YRACE.SYSTEM"
	$(CP2) sa $(TIMING_DISK) type=SYS "YRACE.SYSTEM"
	@echo "Timing race test disk ready: $(TIMING_DISK)"

# Rule to build SCCAUTO.SYSTEM
SCCAUTO.SYSTEM: SCCAUTO.SYSTEM.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

# Rule to build YRACE.SYSTEM
YRACE.SYSTEM: Y_CORRUPTION_DEMO.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

# Rule to clean up the build output
clean:
	rm -f $(SCC_DISK) $(TIMING_DISK)
	rm -f SCCAUTO.SYSTEM YRACE.SYSTEM
	rm -f *_S01_Segment1_Output.txt
	rm -f *_Symbols.txt
	rm -f _FileInformation.txt

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

# Phony targets are not actual files
.PHONY: all all_tests clean scc_test timing_test plb_test scc_phantom_test dbr_corruption_test serial_selftest c034_test



scc_test: scc_test.2mg

scc_test.2mg:
	@echo "Building SCC slowMem test..."
	./Merlin32_v1.2_b2/Linux/Merlin32 -V Merlin32_v1.2_b2/Library/ SCC_SLOWMEM_TEST.S
	@echo "Creating SCC test disk..."
	./cp2_1.1.0_linux-x64_sc/cp2 rm scc_test.2mg "BASIC.SYSTEM" 2>/dev/null || true
	./cp2_1.1.0_linux-x64_sc/cp2 rm scc_test.2mg "SCC.SYSTEM" 2>/dev/null || true
	./cp2_1.1.0_linux-x64_sc/cp2 add scc_test.2mg "SCC.SYSTEM"
	./cp2_1.1.0_linux-x64_sc/cp2 sa scc_test.2mg type=SYS "SCC.SYSTEM"
	@echo "SCC test disk ready: scc_test.2mg"

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
