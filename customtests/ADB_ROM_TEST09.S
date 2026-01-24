;
; ADB ROM Test 09 Reproduction
; Mimics the exact sequence from ROM selftest test 09
;
; Sequence:
; 1. SYNC (0x07) - Synchronize ADB controller
; 2. VERSION (0x0d) - Read ADB microcontroller version
; 3. READ_MEM (0x09) - Read from ADB controller memory
;
; This test should fail until we fix the READ_MEM response mechanism
;

        ORG   $2000
        TYP   $06
        DSK   ADBROM09.SYSTEM

; ADB Register definitions
KMSTATUS EQU   $C026    ; ADB Command/Data register
ADBSTAT  EQU   $C027    ; ADB Status register

; Screen memory
SCREEN   EQU   $0400

START
        ; Clear screen area (first line)
        LDA #$A0        ; Space character
        LDX #$00
CLEAR   STA SCREEN,X
        INX
        CPX #$28        ; Clear first line (40 chars)
        BNE CLEAR

        ; Display test header
        LDX #$00
HEADER  LDA TESTMSG,X
        BEQ HEADER_DONE
        STA SCREEN,X
        INX
        JMP HEADER

HEADER_DONE

        ; ========================================
        ; TEST 1: Send SYNC command (0x07)
        ; ========================================

        LDA #$07
        STA KMSTATUS    ; Write SYNC command

        ; Short delay
        LDX #$10
WAIT1   DEX
        BNE WAIT1

        ; ========================================
        ; TEST 2: Send VERSION command (0x0d)
        ; ========================================

        LDA #$0D
        STA KMSTATUS    ; Write VERSION command

        ; Wait for command to process
        LDX #$1D
WAIT2   DEX
        BNE WAIT2

        ; Poll status register for completion
        ; Bit 7 of $C027 should be set when data is ready
        LDX #$FF        ; Timeout counter
POLL2   LDA ADBSTAT
        AND #$80        ; Check bit 7 (data ready)
        BNE CMD2_DONE
        DEX
        BNE POLL2
        ; Timeout - show "FAIL V" (VERSION failed)
        LDA #$D6        ; 'V'
        STA $02
        JMP TEST_FAIL

CMD2_DONE
        ; Read response from KMSTATUS
        LDA KMSTATUS
        STA $00         ; Save VERSION response

        ; ========================================
        ; TEST 3: Send READ_MEM command (0x09)
        ; This command requires 2 data bytes (address)
        ; ========================================

        LDA #$09
        STA KMSTATUS    ; Write READ_MEM command

        ; Now write address high byte
        LDA #$00
        STA KMSTATUS    ; Address high = 0x00

        ; Write address low byte
        LDA #$00
        STA KMSTATUS    ; Address low = 0x00

        ; Wait for command to process
        LDX #$1D
WAIT3   DEX
        BNE WAIT3

        ; Poll status register for completion
        ; Bit 7 of $C027 should be set when data is ready
        LDX #$FF        ; Timeout counter
POLL3   LDA ADBSTAT
        AND #$80        ; Check bit 7 (data ready)
        BNE CMD3_DONE
        DEX
        BNE POLL3
        ; Timeout - show "FAIL M" (READ_MEM failed)
        LDA #$CD        ; 'M'
        STA $02
        JMP TEST_FAIL

CMD3_DONE
        ; Read response from KMSTATUS
        LDA KMSTATUS
        STA $01         ; Save READ_MEM response

        ; If we got here, the test passed!
        JMP TEST_PASS

        ; ========================================
        ; TEST PASSED
        ; ========================================

TEST_PASS
        ; Display "PASS"
        LDX #$00
PASS_LOOP
        LDA PASSMSG,X
        BEQ PASS_DONE
        STA SCREEN+$0A,X  ; Display at position 10
        INX
        JMP PASS_LOOP

PASS_DONE
        ; Display VERSION response
        LDA $00
        JSR PRINTHEX
        STA SCREEN+$0F    ; High nibble
        STX SCREEN+$10    ; Low nibble

        ; Display READ_MEM response
        LDA $01
        JSR PRINTHEX
        STA SCREEN+$12    ; High nibble
        STX SCREEN+$13    ; Low nibble

        ; Infinite loop
DONE    JMP DONE

        ; ========================================
        ; TEST FAILED
        ; ========================================

TEST_FAIL
        ; Display "FAIL" plus which command failed
        LDX #$00
FAIL_LOOP
        LDA FAILMSG,X
        BEQ SHOW_WHICH
        STA SCREEN+$0A,X  ; Display at position 10
        INX
        JMP FAIL_LOOP

SHOW_WHICH
        ; Display which command failed (V or M)
        LDA $02
        STA SCREEN+$0F

        ; Display VERSION response (if we got that far)
        LDA $00
        JSR PRINTHEX
        STA SCREEN+$11    ; High nibble
        STX SCREEN+$12    ; Low nibble

        ; Display READ_MEM response (if we got that far)
        LDA $01
        JSR PRINTHEX
        STA SCREEN+$14    ; High nibble
        STX SCREEN+$15    ; Low nibble

        ; Infinite loop
FAILLOOP
        JMP FAILLOOP

; ========================================
; SUBROUTINES
; ========================================

; Print hex value in A
; Returns: A=high nibble char, X=low nibble char
PRINTHEX
        PHA
        ; Convert high nibble
        LSR
        LSR
        LSR
        LSR
        JSR HEXCHAR
        STA $10         ; Save high nibble char

        ; Convert low nibble
        PLA
        AND #$0F
        JSR HEXCHAR
        TAX             ; Low nibble to X
        LDA $10         ; High nibble to A
        RTS

; Convert nibble (0-15) to hex character
HEXCHAR
        CMP #$0A
        BCC HEXDIGIT
        ; A-F
        SEC
        SBC #$09
        ORA #$C0        ; Make it 'A'-'F'
        RTS
HEXDIGIT
        ORA #$B0        ; Make it '0'-'9'
        RTS

; ========================================
; DATA
; ========================================

TESTMSG
        ASC "ROM T09:"
        HEX 00

PASSMSG
        ASC "PASS "
        HEX 00

FAILMSG
        ASC "FAIL "
        HEX 00
