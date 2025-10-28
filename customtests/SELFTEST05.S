;
; SELFTEST05.S - Direct launcher for ROM selftest 5
;
; This test directly calls ROM selftest 5 via the test pointer table
; at DIAGNOSTICS+2 in ROM bank FF
;
        ORG   $2000
        TYP   $06
        DSK   TEST05.SYSTEM

; Screen memory
SCREEN   EQU   $0400

; DIAGNOSTICS pointer table found at FF:6400 in actual ROM
; Table structure: DIAGNOSTICS+2 = size byte, DIAGNOSTICS+3 = first pointer
; Test 5 at DIAGNOSTICS+3 + (4*2) = DIAGNOSTICS+11
DIAGNOSTICS EQU $6400
TEST_OFFSET EQU 11  ; Test 5

START
        ; Clear screen
        LDA #$A0
        LDX #$00
CLEAR   STA SCREEN,X
        STA SCREEN+$80,X
        STA SCREEN+$100,X
        STA SCREEN+$180,X
        INX
        BNE CLEAR

        ; Display "Running Test 05..."
        LDX #$00
MSGLP   LDA RUNMSG,X
        BEQ SETUP
        STA SCREEN,X
        INX
        JMP MSGLP

SETUP
        ; Switch to native mode
        CLC
        XCE

        ; Read test pointer from table
        ; DIAGNOSTICS+2 = size byte, DIAGNOSTICS+3 = first pointer
        REP #$20        ; 16-bit accumulator
        LDA >$FF0000+DIAGNOSTICS+TEST_OFFSET
        STA TEST_ADDR
        SEP #$20        ; Back to 8-bit

        ; Set 8-bit index
        SEP #$10

        ; Set Data Bank to $00
        LDA #$00
        PHA
        PLB

        ; Display test address for debugging
        LDA TEST_ADDR+1
        JSR PRINTHEX
        STA SCREEN+$28
        STX SCREEN+$29
        LDA TEST_ADDR
        JSR PRINTHEX
        STA SCREEN+$2A
        STX SCREEN+$2B

        ; Clear TST.STATUS registers at $000315 (5 bytes) before calling test
        LDA #$00
        STA $0315       ; Clear status byte 1
        STA $0316       ; Clear status byte 2
        STA $0317       ; Clear status byte 3
        STA $0318       ; Clear status byte 4
        STA $0319       ; Clear status byte 5

        ; Patch JSL instruction with test address
        REP #$20
        LDA TEST_ADDR
        STA CALLTST+1
        SEP #$20

        ; Call test 5 via JSL to ROM
CALLTST JSL $FF0000     ; Address will be patched above

RETURN
        ; Test returned - restore data bank (ROM tests leave it in unknown state)
        PHK
        PLB

        ; Check carry flag for pass/fail per Apple IIGS Diagnostics documentation
        ; Carry clear = pass, carry set = fail
        BCS FAIL_BRANCH
        LDA #$00
FAIL_BRANCH
        STA RESULT

        ; Display "RESULT:" message
        LDX #$00
RESLP   LDA RESMSG,X
        BEQ SHOWRES
        STA SCREEN+$50,X
        INX
        JMP RESLP

SHOWRES
        ; Display the result code in hex
        LDA RESULT
        JSR PRINTHEX
        STA SCREEN+$58
        STX SCREEN+$59

        ; Check if zero (pass)
        LDA RESULT
        CMP #$00
        BNE TESTFAIL

TESTPASS
        LDX #$00
PASSLP  LDA PASSMSG,X
        BEQ HANG
        STA SCREEN+$5B,X
        INX
        JMP PASSLP

TESTFAIL
        LDX #$00
FAILLP  LDA FAILMSG,X
        BEQ HANG
        STA SCREEN+$5B,X
        INX
        JMP FAILLP

HANG    JMP HANG

; Print hex value in A
; Returns: A=high nibble char, X=low nibble char
PRINTHEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR HEXCHAR
        STA $10
        PLA
        AND #$0F
        JSR HEXCHAR
        TAX
        LDA $10
        RTS

; Convert nibble to hex character
HEXCHAR
        CMP #$0A
        BCC HEXDIGIT
        SEC
        SBC #$09
        ORA #$C0
        RTS
HEXDIGIT
        ORA #$B0
        RTS

RUNMSG
        ASC "Running Test 05..."
        HEX 00

RESMSG
        ASC "RESULT:"
        HEX 00

PASSMSG
        ASC " PASS"
        HEX 00

FAILMSG
        ASC " FAIL"
        HEX 00

; Storage for result
RESULT
        HEX 00

; Storage for test address read from pointer table
TEST_ADDR
        HEX 0000

