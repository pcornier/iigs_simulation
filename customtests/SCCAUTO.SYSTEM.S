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
            ; Phase 1: Reset/Clear all SCC registers (like Clemens selftest)
            ; Write FF to all SCC registers to reset them
            LDA     #$FF
            STA     SCC_B_CMD           ; Write FF to C038
            STA     SCC_A_CMD           ; Write FF to C039
            STA     SCC_B_DATA          ; Write FF to C03A
            STA     SCC_A_DATA          ; Write FF to C03B

            ; Phase 2: Initialize registers (like Clemens selftest)
            ; Write 00 to setup registers
            LDA     #$00
            STA     SCC_B_CMD           ; Write 00 to C038
            STA     SCC_A_DATA          ; Write 00 to C03B

            ; Phase 3: Register R/W Test (Error BB=01)
            ; Test basic register readback
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

            ; Phase 5: Loopback Configuration Test (Error BB=07, BB=08)
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
DONE_MSG    ASC     ' - RESULTS: ',00