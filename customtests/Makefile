# Makefile for assembling with Merlin32

# --- Variables ---
ASM = ./Merlin32_v1.2_b2/Linux/Merlin32
CP2 = ./cp2_1.1.0_linux-x64_sc/cp2
SCC_DISK = scc_test.2mg

# --- Rules ---

# Default rule: typing 'make' will build all tests and add them to disk
all: scc_test

# SCC Serial Test - builds a bootable disk with just the SCC test
scc_test: SCCAUTO.SYSTEM
	@echo "Creating SCC test disk..."
	@cp blank.2mg $(SCC_DISK) 2>/dev/null || echo "Note: blank.2mg not found, using existing $(SCC_DISK)"
	$(CP2) rm $(SCC_DISK) "BASIC.SYSTEM" 2>/dev/null || true
	$(CP2) rm $(SCC_DISK) "SCCAUTO.SYSTEM" 2>/dev/null || true
	$(CP2) add $(SCC_DISK) "SCCAUTO.SYSTEM"
	$(CP2) sa $(SCC_DISK) type=SYS "SCCAUTO.SYSTEM"
	@echo "SCC test disk ready: $(SCC_DISK)"

# Rule to build SCCAUTO.SYSTEM
SCCAUTO.SYSTEM: SCCAUTO.SYSTEM.S
	$(ASM) -V Merlin32_v1.2_b2/Library/ $<

# Rule to clean up the build output
clean:
	rm -f $(SCC_DISK)
	rm -f SCCAUTO.SYSTEM
	rm -f *_S01_Segment1_Output.txt
	rm -f *_Symbols.txt
	rm -f _FileInformation.txt

# Phony targets are not actual files
.PHONY: all clean scc_test

