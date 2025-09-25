;****************************************************************
;* SCCAUTO.SYSTEM.S
;*
;* A simple ProDOS 8 SYSTEM file that automatically launches SCCTEST.P8
;* This bypasses ProDOS file loading and jumps directly to our test.
;*
;* Assembled with Merlin32.
;****************************************************************

            ORG     $2000               ; ProDOS 8 programs start at $2000
            DSK     SCCAUTO.SYSTEM      ; Set the output filename
            TYP     'SYS'               ; Set ProDOS file type to SYS ($F1)
            MX      %11                 ; Default to 8-bit Accumulator and Index

;--- Monitor Routines
HOME        EQU     $FC58               ; Clear screen and home cursor
COUT        EQU     $FDED               ; Character output

;--- SCC Register Addresses for direct testing
SCC_B_CMD   EQU     $C038               ; SCC Channel B Command
SCC_A_CMD   EQU     $C039               ; SCC Channel A Command
SCC_B_DATA  EQU     $C03A               ; SCC Channel B Data
SCC_A_DATA  EQU     $C03B               ; SCC Channel A Data

;****************************************************************
;* MAIN PROGRAM - Direct SCC Test
;****************************************************************
START
            JSR     HOME                ; Clear screen

            ; Print test message
            LDX     #0
PRINT_LOOP  LDA     TEST_MSG,X
            BEQ     DO_SCC_TEST
            JSR     COUT
            INX
            BNE     PRINT_LOOP

DO_SCC_TEST
            ; **NEW: Memory Bank Context Test**
            ; Test SCC access from different memory banks to reproduce the issue
            ; Clemens works with bank E0, FPGA fails with bank 00

            ; Print bank test header
            LDX     #0
BANK_MSG_LOOP LDA   BANK_MSG,X
            BEQ     BANK_TESTS
            JSR     COUT
            INX
            BNE     BANK_MSG_LOOP

BANK_TESTS
            ; Save current Data Bank Register
            PHB                         ; Push current DBR to stack

            ; Test 1: Force Bank 00 context (like failing FPGA trace)
            PEA     $0000               ; Push bank 00 to stack
            PLB                         ; Pull into Data Bank Register
            JSR     TEST_SCC_BANK       ; Test SCC in this context

            ; Test 2: Force Bank E0 context (like working Clemens trace)
            PEA     $E000               ; Push bank E0 to stack
            PLB                         ; Pull into Data Bank Register
            JSR     TEST_SCC_BANK       ; Test SCC in this context

            ; Test 3: Force Bank FF context (ROM bank)
            PEA     $FF00               ; Push bank FF to stack
            PLB                         ; Pull into Data Bank Register
            JSR     TEST_SCC_BANK       ; Test SCC in this context

            ; Restore original Data Bank Register
            PLB                         ; Restore original DBR

            ; Continue with original test pattern
            ; Phase 1: Extended Address Range Reset (like Clemens selftest)
            ; Write FF to extended range C038-C040 as seen in trace
            LDX     #$00
RESET_LOOP  LDA     #$FF
            STA     $C038,X             ; Write FF to C038+X
            INX
            CPX     #$08                ; Test C038-C03F range
            BNE     RESET_LOOP

            ; Phase 2: Initialize specific registers (like Clemens selftest)
            LDA     #$00
            STA     SCC_B_CMD           ; Write 00 to C038
            STA     SCC_A_DATA          ; Write 00 to C03B

            ; Phase 3: Extended Address Range Read Test
            ; Verify reset worked and test read timing across all addresses
            LDX     #$00
ADDR_LOOP   LDA     $C038,X             ; Read from C038+X
            JSR     PRINT_HEX_BYTE      ; Display each result
            INX
            CPX     #$04                ; Test C038-C03B (main SCC registers)
            BNE     ADDR_LOOP

            ; Phase 4: Comprehensive Register Index Test (01-1F as seen in trace)
            ; This tests the register selection mechanism extensively
            LDX     #$01                ; Start with register 1
REG_INDEX_LOOP
            TXA                         ; Use X as register selector
            STA     SCC_A_CMD           ; Write register index to C039
            LDA     SCC_A_CMD           ; Read back from C039
            JSR     PRINT_HEX_BYTE      ; Display result
            INX
            CPX     #$10                ; Test registers 01-0F
            BNE     REG_INDEX_LOOP

            ; Phase 5: Write-Read-Verify Pattern for Key Registers
            ; Test register data storage and retrieval
            LDX     #$01
WRV_LOOP    TXA                         ; Register selector
            STA     SCC_A_CMD           ; Select register
            LDA     #$AA                ; Test pattern
            STA     SCC_A_CMD           ; Write test data
            TXA                         ; Re-select register
            STA     SCC_A_CMD           ; Write register index again
            LDA     SCC_A_CMD           ; Read back data
            JSR     PRINT_HEX_BYTE      ; Display result
            INX
            CPX     #$08                ; Test registers 01-07
            BNE     WRV_LOOP

            ; Phase 6: Basic Register R/W Test (Error BB=01)
            ; Test basic register readback (original test)
            LDA     #$00                ; WR0 register select
            STA     SCC_A_CMD           ; Write to C039
            LDA     SCC_A_CMD           ; Read back from C039
            JSR     PRINT_HEX_BYTE

            ; Phase 4: Transmit Buffer Setup Test (Error BB=04, BB=05)
            ; Set up transmitter
            LDA     #$05                ; WR5 register select
            STA     SCC_A_CMD           ; Write to C039
            LDA     #$EA                ; Tx enable + RTS + DTR
            STA     SCC_A_CMD           ; Configure WR5

            ; Check transmit buffer empty status
            LDA     #$00                ; RR0 register select (status)
            STA     SCC_A_CMD           ; Select status register
            LDA     SCC_A_CMD           ; Read status
            JSR     PRINT_HEX_BYTE      ; Display status

            ; Phase 7: Intensive Status Polling (like ROM selftest)
            ; This stresses the SCC timing with rapid consecutive reads
            LDX     #$32                ; Poll 50 times (reduced from ROM's 100 for speed)
POLL_INTENSIVE
            LDA     #$00                ; RR0 status register
            STA     SCC_A_CMD           ; Select status register
            LDA     SCC_A_CMD           ; Read status (1st read)
            LDA     SCC_A_CMD           ; Read again immediately (2nd read)
            LDA     SCC_A_CMD           ; Read third time (3rd read)
            CMP     #$80                ; Check for timing bug (0x80 return)
            BEQ     BUG_FOUND           ; Exit immediately if timing issue found
            DEX
            BNE     POLL_INTENSIVE      ; Continue polling

            ; Phase 8: Multi-Register Status Verification
            ; Test different status register combinations
            LDA     #$01                ; RR1 register select
            STA     SCC_A_CMD           ; Select RR1
            LDA     SCC_A_CMD           ; Read RR1 status
            JSR     PRINT_HEX_BYTE      ; Display RR1 result

            LDA     #$02                ; RR2 register select
            STA     SCC_A_CMD           ; Select RR2
            LDA     SCC_A_CMD           ; Read RR2 status
            JSR     PRINT_HEX_BYTE      ; Display RR2 result

            ; Phase 9: Loopback Configuration Test (Error BB=07, BB=08)
            ; Set up internal loopback
            LDA     #$0E                ; WR14 register select
            STA     SCC_A_CMD           ; Write to command register
            LDA     #$03                ; Enable loopback mode
            STA     SCC_A_CMD           ; Set WR14 for loopback

            ; Set up receiver
            LDA     #$03                ; WR3 register select
            STA     SCC_A_CMD           ; Write to command register
            LDA     #$C1                ; Rx enable + 8 bits
            STA     SCC_A_CMD           ; Configure receiver

            ; Send test pattern
            LDA     #$AA                ; Test pattern
            STA     SCC_A_DATA          ; Transmit via Channel A data

            ; Check receiver status
            LDA     #$00                ; RR0 register select
            STA     SCC_A_CMD           ; Select status register
            LDA     SCC_A_CMD           ; Read status
            JSR     PRINT_HEX_BYTE      ; Display receive status

            ; Try to read received data
            LDA     SCC_A_DATA          ; Read from Channel A data
            JSR     PRINT_HEX_BYTE      ; Display received data

            ; Reproduce the problematic polling pattern from ROM selftest
            ; This should trigger the same 0x80 failure we see in the trace
POLL_TEST
            LDA     #$09                ; Write register 9 select (like ROM selftest)
            STA     SCC_A_CMD           ; Write to C039
            LDA     SCC_A_CMD           ; Read back from C039 (should get status, might get 0x80)
            JSR     PRINT_HEX_BYTE      ; Display what we got

            ; Do multiple rapid reads like selftest does
            LDA     SCC_A_CMD           ; Read again immediately
            JSR     PRINT_HEX_BYTE      ; Display second read

            LDA     SCC_A_CMD           ; Read third time
            JSR     PRINT_HEX_BYTE      ; Display third read

            ; If we get 0x80, we've reproduced the bug
            CMP     #$80                ; Check if we got the problematic 0x80
            BEQ     BUG_FOUND           ; If so, show we found the bug

            ; Add intensive polling loop like ROM selftest to stress timing
            LDX     #100                ; Poll 100 times
POLL_LOOP
            LDA     #$00                ; RR0 register select
            STA     SCC_A_CMD           ; Write to C039
            LDA     SCC_A_CMD           ; Read back immediately
            CMP     #$80                ; Check for the bug value
            BEQ     BUG_FOUND           ; Exit if we find the bug
            DEX
            BNE     POLL_LOOP           ; Continue polling

            ; If we reach here, test passed - no 0x80 values found
            JMP     TEST_PASSED

BUG_FOUND
            ; Print bug indicator
            LDA     #$42                ; 'B' for Bug found
            JSR     COUT
            LDA     #$55                ; 'U'
            JSR     COUT
            LDA     #$47                ; 'G'
            JSR     COUT
            JMP     PRINT_RESULTS       ; Skip to results printing

TEST_PASSED
            ; Print success indicator
            LDA     #$4F                ; 'O' for OK
            JSR     COUT
            LDA     #$4B                ; 'K'
            JSR     COUT

PRINT_RESULTS
            ; Print success message
            LDX     #0
PRINT_DONE  LDA     DONE_MSG,X
            BEQ     HANG
            JSR     COUT
            INX
            BNE     PRINT_DONE

HANG        JMP     HANG                ; Hang here so we can see results

;****************************************************************
;* BANK CONTEXT TEST SUBROUTINE
;****************************************************************

;--- Test SCC access from current Data Bank context
TEST_SCC_BANK
            ; Print current bank identifier
            LDA     #$5B                ; '['
            JSR     COUT

            ; Print a simple bank indicator (we'll see different results)
            LDA     #$30                ; '0' base
            JSR     COUT

            LDA     #$5D                ; ']'
            JSR     COUT

            ; Test basic SCC register access in current bank context
            LDA     #$00                ; WR0 register select
            STA     SCC_A_CMD           ; Write to C039
            LDA     SCC_A_CMD           ; Read back from C039
            JSR     PRINT_HEX_BYTE      ; Show what we got

            ; Test if we get the problematic 0x80 or proper register values
            CMP     #$80                ; Check for bus default (timing issue)
            BEQ     BANK_BUG_FOUND

            ; Print "OK" for this bank
            LDA     #$4F                ; 'O'
            JSR     COUT
            LDA     #$4B                ; 'K'
            JSR     COUT
            JMP     BANK_TEST_DONE

BANK_BUG_FOUND
            ; Print "BG" for this bank
            LDA     #$42                ; 'B'
            JSR     COUT
            LDA     #$47                ; 'G'
            JSR     COUT

BANK_TEST_DONE
            LDA     #$20                ; Space
            JSR     COUT
            RTS                         ; Return to caller

;****************************************************************
;* SUBROUTINES
;****************************************************************

;--- Print a byte in hex format
PRINT_HEX_BYTE
            PHA                         ; Save the byte
            LSR                         ; Get high nibble
            LSR
            LSR
            LSR
            JSR     PRINT_HEX_NIBBLE    ; Print high nibble
            PLA                         ; Restore byte
            AND     #$0F                ; Get low nibble
            JMP     PRINT_HEX_NIBBLE    ; Print low nibble and return

;--- Print a hex nibble (0-F)
PRINT_HEX_NIBBLE
            CMP     #10                 ; Is it A-F?
            BCC     PRINT_DIGIT         ; No, it's 0-9
            ADC     #6                  ; Yes, convert to A-F (carry is set)
PRINT_DIGIT
            ADC     #'0'                ; Convert to ASCII
            JMP     COUT                ; Print and return

;****************************************************************
;* DATA SECTION
;****************************************************************

TEST_MSG    ASC     'SCC COMPLETE TEST',0D,0A,00
BANK_MSG    ASC     'BANK CONTEXT TESTS: ',00
DONE_MSG    ASC     ' - RESULTS: ',00