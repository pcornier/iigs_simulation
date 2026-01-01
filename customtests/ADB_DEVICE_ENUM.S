;
; ADB Device Enumeration Test
; Tests ADB response to commands sent to device 5 (reserved/non-existent)
;
; This test verifies that:
; 1. Sending TALK command (0x5B) to device 5 returns response with bit 7 set
; 2. The response indicates 0 data bytes available
; 3. Expected response: 0x80 (response received, no data)
;
; Based on ROM selftest sequence at $FF:6F9F
;

        ORG   $2000
        TYP   $06
        DSK   ADBENUM.SYSTEM

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
        ; TEST 1: Send FLUSH command to device 5
        ; ========================================

        ; Send FLUSH command (0x59) to device 5
        ; Format: 0101 10 01 = Device 5, Register 2, FLUSH
        LDA #$59
        STA KMSTATUS    ; Write command to ADB

        ; Wait for command to process (same delay as ROM selftest)
        ; ROM uses: ldx #$1d4c / dex / beq (7500 iterations)
        LDX #$1D
WAIT1   DEX
        BNE WAIT1

        ; Poll status register for completion
        LDX #$FF        ; Timeout counter
POLL1   LDA ADBSTAT
        AND #$80        ; Check command complete bit
        BNE CMD1_DONE
        DEX
        BNE POLL1
        JMP TEST_FAIL   ; Timeout waiting for command

CMD1_DONE
        ; Read response from KMSTATUS
        LDA KMSTATUS
        STA $00         ; Save response for debugging

        ; Check bit 7 (response received)
        AND #$80
        BEQ TEST_FAIL   ; If bit 7 not set, FAIL

        ; Check data count (bits 2-0 should be 0)
        LDA $00
        AND #$07
        BNE TEST_FAIL   ; If data count != 0, FAIL

        ; ========================================
        ; TEST 2: Send TALK command to device 5
        ; ========================================

        ; Send TALK command (0x5B) to device 5
        ; Format: 0101 10 11 = Device 5, Register 2, TALK
        LDA #$5B
        STA KMSTATUS    ; Write command to ADB

        ; Wait for command to process
        LDX #$1D
WAIT2   DEX
        BNE WAIT2

        ; Poll status register for completion
        LDX #$FF        ; Timeout counter
POLL2   LDA ADBSTAT
        AND #$80        ; Check command complete bit
        BNE CMD2_DONE
        DEX
        BNE POLL2
        JMP TEST_FAIL   ; Timeout waiting for command

CMD2_DONE
        ; Read response from KMSTATUS
        LDA KMSTATUS
        STA $01         ; Save response for debugging

        ; Check bit 7 (response received)
        AND #$80
        BEQ TEST_FAIL   ; If bit 7 not set, FAIL

        ; Check data count (bits 2-0 should be 0)
        LDA $01
        AND #$07
        BNE TEST_FAIL   ; If data count != 0, FAIL

        ; ========================================
        ; TEST PASSED
        ; ========================================

TEST_PASS
        ; Display "PASS"
        LDX #$00
PASS_LOOP
        LDA PASSMSG,X
        BEQ DONE
        STA SCREEN+$0B,X  ; Display at position 11
        INX
        JMP PASS_LOOP

DONE
        ; Infinite loop
        JMP DONE

        ; ========================================
        ; TEST FAILED
        ; ========================================

TEST_FAIL
        ; Display "FAIL" plus response bytes
        LDX #$00
FAIL_LOOP
        LDA FAILMSG,X
        BEQ SHOW_RESP
        STA SCREEN+$0B,X  ; Display at position 11
        INX
        JMP FAIL_LOOP

SHOW_RESP
        ; Display first response byte (from FLUSH)
        LDA $00
        JSR PRINTHEX
        STA SCREEN+$10    ; High nibble
        STX SCREEN+$11    ; Low nibble

        ; Display second response byte (from TALK)
        LDA $01
        JSR PRINTHEX
        STA SCREEN+$13    ; High nibble
        STX SCREEN+$14    ; Low nibble

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
        ASC "ADB TEST:"
        HEX 00

PASSMSG
        ASC "PASS"
        HEX 00

FAILMSG
        ASC "FAIL "
        HEX 00
