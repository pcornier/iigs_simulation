; Test WR15/RR15 register access
; This tests the exact failure found in ROM selftest

        TYP   $06
        DSK   SCCWR15.SYSTEM
        ORG   $2000

; Display location
SCREEN  = $0400

START
        SEI
        CLC
        XCE                   ; Native mode

        ; Clear screen
        LDX   #0
        LDA   #$A0            ; Space character
:CLEAR  STA   SCREEN,X
        STA   SCREEN+256,X
        INX
        BNE   :CLEAR

; ========================================
; Test WR15/RR15 on both channels
; ========================================

        ; Test Channel A first
        LDA   #$0F            ; Select WR15
        STA   $C039
        LDA   #$00            ; Write 00 to WR15
        STA   $C039

        ; Now read it back
        LDA   #$0F            ; Point high + select RR15
        ORA   #$08            ; Set bit 3 for point high
        STA   $C039           ; Select RR15 for reading

        LDA   $C039           ; Read RR15
        CMP   #$F8            ; Should be F8 (bits 2,0 masked)
        BNE   FAIL_A

        ; Mark Channel A pass
        LDA   #$C1            ; 'A'
        STA   SCREEN

        ; Test Channel B (the one that failed in ROM)
        LDA   #$0F            ; Select WR15
        STA   $C038
        LDA   #$00            ; Write 00 to WR15
        STA   $C038

        ; Now read it back
        LDA   #$0F            ; Point high + select RR15
        ORA   #$08            ; Set bit 3 for point high
        STA   $C038           ; Select RR15 for reading

        LDA   $C038           ; Read RR15
        ; RR15 has read-only bits: bit 2 and 0 are always 0
        ; So writing 00 should read back as F8 (11111000)
        CMP   #$F8
        BNE   FAIL_B

        ; Mark Channel B pass
        LDA   #$C2            ; 'B'
        STA   SCREEN+1

        ; Now test writing different values
        LDA   #$0F
        STA   $C038
        LDA   #$FF            ; Write FF to WR15
        STA   $C038

        LDA   #$0F
        ORA   #$08
        STA   $C038
        LDA   $C038           ; Should read FA (bits 2,0 masked)
        CMP   #$FA
        BNE   FAIL_B2

        ; All tests passed
        LDA   #$D0            ; 'P'
        STA   SCREEN+10
        LDA   #$C1            ; 'A'
        STA   SCREEN+11
        LDA   #$D3            ; 'S'
        STA   SCREEN+12
        STA   SCREEN+13
        JMP   HALT

FAIL_A
        LDA   #$C6            ; 'F'
        STA   SCREEN
        LDA   #$C1            ; 'A'
        STA   SCREEN+1
        JMP   HALT

FAIL_B
        LDA   #$C6            ; 'F'
        STA   SCREEN+1
        LDA   #$C2            ; 'B'
        STA   SCREEN+2
        ; Also show what we got
        LDA   $C038           ; Re-read the value
        STA   SCREEN+4        ; Display raw value
        JMP   HALT

FAIL_B2
        LDA   #$C6            ; 'F'
        STA   SCREEN+1
        LDA   #$B2            ; '2'
        STA   SCREEN+2
        JMP   HALT

HALT
        JMP   *               ; Stop here