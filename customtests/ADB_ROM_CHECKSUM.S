;
; ADB ROM Checksum Test
; Tests READ_MEM command with ROM addresses (page 0x1F)
;

        ORG   $2000
        TYP   $06
        DSK   ADBROMCK.SYSTEM

; ADB Register definitions
KMSTATUS EQU   $C026    ; ADB Command/Data register
ADBSTAT  EQU   $C027    ; ADB Status register

; Screen memory
SCREEN   EQU   $0400

START
        ; Clear screen area (first two lines)
        LDA #$A0        ; Space character
        LDX #$00
CLEAR   STA SCREEN,X
        INX
        CPX #$50        ; Clear first two lines (80 chars)
        BNE CLEAR

        ; Display test header
        LDX #$00
HEADER  LDA TESTMSG,X
        BEQ TEST_START
        STA SCREEN,X
        INX
        JMP HEADER

TEST_START
        ; ========================================
        ; TEST 1: Read checksum low byte from page 0x1F, address 0x00
        ; ========================================

        ; Send READ_MEM command (0x09)
        LDA #$09
        STA KMSTATUS

        ; Send address byte (0x00)
        LDA #$00
        STA KMSTATUS

        ; Send page byte (0x1F)
        LDA #$1F
        STA KMSTATUS

        ; Wait for response
        LDX #$FF
WAIT1   LDA ADBSTAT
        AND #$80        ; Check bit 7 (data ready)
        BNE READ1
        DEX
        BNE WAIT1
        ; Timeout
        LDA #$D4        ; 'T'
        STA SCREEN+$28  ; Second line
        JMP HANG

READ1   ; Read checksum low byte (should be 0x72)
        LDA KMSTATUS
        STA $00

        ; ========================================
        ; TEST 2: Read checksum high byte from page 0x1F, address 0x01
        ; ========================================

        ; Send READ_MEM command (0x09)
        LDA #$09
        STA KMSTATUS

        ; Send address byte (0x01)
        LDA #$01
        STA KMSTATUS

        ; Send page byte (0x1F)
        LDA #$1F
        STA KMSTATUS

        ; Wait for response
        LDX #$FF
WAIT2   LDA ADBSTAT
        AND #$80        ; Check bit 7 (data ready)
        BNE READ2
        DEX
        BNE WAIT2
        ; Timeout
        LDA #$D4        ; 'T'
        STA SCREEN+$28  ; Second line
        JMP HANG

READ2   ; Read checksum high byte (should be 0x26 for ROM3)
        LDA KMSTATUS
        STA $01

        ; ========================================
        ; TEST 3: Read from page 0 (RAM) address 0x00
        ; ========================================

        ; Send READ_MEM command (0x09)
        LDA #$09
        STA KMSTATUS

        ; Send address byte (0x00)
        LDA #$00
        STA KMSTATUS

        ; Send page byte (0x00 = RAM)
        LDA #$00
        STA KMSTATUS

        ; Wait for response
        LDX #$FF
WAIT3   LDA ADBSTAT
        AND #$80        ; Check bit 7 (data ready)
        BNE READ3
        DEX
        BNE WAIT3
        ; Timeout
        LDA #$D4        ; 'T'
        STA SCREEN+$28  ; Second line
        JMP HANG

READ3   ; Read RAM byte
        LDA KMSTATUS
        STA $02

        ; ========================================
        ; DISPLAY RESULTS
        ; ========================================

        ; Display "LOW:"
        LDX #$00
SHOW_L  LDA LOWMSG,X
        BEQ SHOW_L_DONE
        STA SCREEN+$28,X  ; Second line
        INX
        JMP SHOW_L
SHOW_L_DONE

        ; Display checksum low byte
        LDA $00
        JSR PRINTHEX
        STA SCREEN+$2D    ; High nibble
        STX SCREEN+$2E    ; Low nibble

        ; Display " HI:"
        LDX #$00
SHOW_H  LDA HIMSG,X
        BEQ SHOW_H_DONE
        STA SCREEN+$30,X
        INX
        JMP SHOW_H
SHOW_H_DONE

        ; Display checksum high byte
        LDA $01
        JSR PRINTHEX
        STA SCREEN+$34    ; High nibble
        STX SCREEN+$35    ; Low nibble

        ; Display " RAM:"
        LDX #$00
SHOW_R  LDA RAMMSG,X
        BEQ SHOW_R_DONE
        STA SCREEN+$37,X
        INX
        JMP SHOW_R
SHOW_R_DONE

        ; Display RAM byte
        LDA $02
        JSR PRINTHEX
        STA SCREEN+$3D    ; High nibble
        STX SCREEN+$3E    ; Low nibble

        ; ========================================
        ; VERIFY EXPECTED VALUES
        ; ========================================

        ; Check if low byte = 0x72
        LDA $00
        CMP #$72
        BNE TEST_FAIL

        ; Check if high byte = 0x26
        LDA $01
        CMP #$26
        BNE TEST_FAIL

        ; All tests passed!
        LDX #$00
PASS_LP LDA PASSMSG,X
        BEQ HANG
        STA SCREEN+$0A,X  ; First line at position 10
        INX
        JMP PASS_LP

TEST_FAIL
        ; Display FAIL
        LDX #$00
FAIL_LP LDA FAILMSG,X
        BEQ HANG
        STA SCREEN+$0A,X  ; First line at position 10
        INX
        JMP FAIL_LP

HANG    JMP HANG

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
        ASC "ADB ROM: "
        HEX 00

LOWMSG
        ASC "LOW:"
        HEX 00

HIMSG
        ASC " HI:"
        HEX 00

RAMMSG
        ASC " RAM:"
        HEX 00

PASSMSG
        ASC "PASS"
        HEX 00

FAILMSG
        ASC "FAIL"
        HEX 00
