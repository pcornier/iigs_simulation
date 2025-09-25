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

# Phony targets are not actual files
.PHONY: all all_tests clean scc_test timing_test



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
