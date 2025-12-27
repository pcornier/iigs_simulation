;
; SELFTEST04.S - Direct launcher for ROM selftest 4
;
; This test directly calls ROM selftest 4 via the test pointer table
; at DIAGNOSTICS+2 in ROM bank FF
;
; NOTE: The ROM RAM address test is destructive and overwrites $0400-$BFFF
; and $D000-$FFFF. We copy our return handler to $0300 (safe area) before
; calling the test so we can report results afterward.
;
        ORG   $2000
        TYP   $06
        DSK   TEST04.SYSTEM

; Screen memory
SCREEN   EQU   $0400

; Safe area for return handler (below test range)
SAFE_AREA EQU  $0300

; DIAGNOSTICS pointer table found at FF:6400 in actual ROM
; Table structure: DIAGNOSTICS+2 = size byte, DIAGNOSTICS+3 = first pointer
; Test 4 at DIAGNOSTICS+3 + (3*2) = DIAGNOSTICS+9
DIAGNOSTICS EQU $6400
TEST_OFFSET EQU 9  ; Test 4

START
        ; Switch to native mode first
        CLC
        XCE
        SEP #$30        ; 8-bit A and X/Y

        ; Clear screen
        LDA #$A0
        LDX #$00
CLEAR   STA SCREEN,X
        STA SCREEN+$80,X
        STA SCREEN+$100,X
        STA SCREEN+$180,X
        INX
        BNE CLEAR

        ; Display "Running Test 04..."
        LDX #$00
MSGLP   LDA RUNMSG,X
        BEQ SETUP
        STA SCREEN,X
        INX
        JMP MSGLP

SETUP
        ; Clear TST.STATUS registers at $000315 (5 bytes) BEFORE copying handler
        ; (Handler code spans $0300-$03B3 which overlaps TST.STATUS at $0315!)
        LDA #$00
        STA $0315       ; Clear status byte 1
        STA $0316       ; Clear status byte 2
        STA $0317       ; Clear status byte 3
        STA $0318       ; Clear status byte 4
        STA $0319       ; Clear status byte 5

        ; Copy return handler to safe area ($0300)
        LDX #$00
COPYLP  LDA HANDLER,X
        STA SAFE_AREA,X
        INX
        CPX #HANDLER_END-HANDLER
        BNE COPYLP

        ; Read test pointer from table
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

        ; Patch JSL instruction in the copied handler with test address
        ; CALLTST is at offset 0 in HANDLER, so patch goes to SAFE_AREA+1
        REP #$20
        LDA TEST_ADDR
        STA SAFE_AREA+1     ; JSL operand is at offset 1
        SEP #$20

        ; Jump to our safe handler to call the test
        JMP SAFE_AREA

;=============================================================================
; HANDLER - This code gets copied to $0300 (safe from RAM test)
;=============================================================================
HANDLER
        ; Call test 4 via JSL to ROM
CALLTST JSL $FF0000     ; Address will be patched above

        ; Test returned - save result
        ; Carry clear = pass, carry set = fail
        PHP             ; Save flags
        PHK
        PLB             ; Set data bank to our code bank

        ; Restore emulation mode for screen access
        SEC
        XCE

        ; Clear screen first
        LDA #$A0
        LDX #$00
HCLR    STA SCREEN,X
        STA SCREEN+$80,X
        STA SCREEN+$100,X
        STA SCREEN+$180,X
        INX
        BNE HCLR

        ; Display "TEST 04:" at screen start
        LDA #'T'+$80
        STA SCREEN
        LDA #'E'+$80
        STA SCREEN+1
        LDA #'S'+$80
        STA SCREEN+2
        LDA #'T'+$80
        STA SCREEN+3
        LDA #$A0
        STA SCREEN+4
        LDA #'0'+$80
        STA SCREEN+5
        LDA #'4'+$80
        STA SCREEN+6
        LDA #':'+$80
        STA SCREEN+7

        ; Check carry flag from saved flags
        PLP             ; Restore flags
        BCS HFAIL

        ; PASS
        LDA #'P'+$80
        STA SCREEN+9
        LDA #'A'+$80
        STA SCREEN+10
        LDA #'S'+$80
        STA SCREEN+11
        LDA #'S'+$80
        STA SCREEN+12
        BRA HHANG       ; Use relative branch (position-independent)

HFAIL
        ; FAIL - also display error code from $0315
        LDA #'F'+$80
        STA SCREEN+9
        LDA #'A'+$80
        STA SCREEN+10
        LDA #'I'+$80
        STA SCREEN+11
        LDA #'L'+$80
        STA SCREEN+12

        ; Display error code
        LDA #$A0
        STA SCREEN+13
        LDA $0315       ; Error code AA
        JSR HHEX
        STA SCREEN+14
        STX SCREEN+15
        LDA $0316       ; Error code BB
        JSR HHEX
        STA SCREEN+16
        STX SCREEN+17

HHANG   BRA HHANG       ; Use relative branch for position-independent infinite loop

; Print hex value in A (inline in handler)
; Returns: A=high nibble char, X=low nibble char
HHEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR HHEXC
        STA $10
        PLA
        AND #$0F
        JSR HHEXC
        TAX
        LDA $10
        RTS

HHEXC
        CMP #$0A
        BCC HHEXD
        SEC
        SBC #$09
        ORA #$C0
        RTS
HHEXD
        ORA #$B0
        RTS

HANDLER_END

;=============================================================================
; Data in main code area (will be destroyed, but we've already copied handler)
;=============================================================================

RUNMSG
        ASC "Running Test 04..."
        HEX 00

; Storage for test address read from pointer table
TEST_ADDR
        HEX 0000

