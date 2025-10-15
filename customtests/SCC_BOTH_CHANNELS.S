; SCC Both Channels Test
; Tests both channel A and channel B to see if they respond properly

        ORG   $2000
        TYP   $06
        DSK   SCCBOTH.SYSTEM

START
        ; === Test Channel A First ===

        ; Hardware reset via WR9 on channel A control
        LDA   #$09       ; Select WR9
        STA   $C039      ; Channel A control (C039, not C03B!)
        LDA   #$C0       ; Hardware reset command
        STA   $C039

        ; Small delay
        NOP
        NOP
        NOP
        NOP

        ; Read RR0 from channel A
        LDA   $C039      ; Channel A control
        STA   $0800      ; Store channel A RR0

        ; Expected: 0x2C (CTS + DCD + TX_EMPTY)
        CMP   #$2C
        BNE   FAIL_A_RR0

        ; === Now Test Channel B ===

        ; Read RR0 from channel B control
        LDA   $C038      ; Channel B control (C038, not C03A!)
        STA   $0801      ; Store channel B RR0

        ; Expected: 0x2C (same as channel A)
        CMP   #$2C
        BNE   FAIL_B_RR0

        ; === Test Channel B Register Write/Read ===

        ; Write to WR0 to select register 2
        LDA   #$02
        STA   $C038      ; Channel B control (C038!)

        ; Write to WR2
        LDA   #$55
        STA   $C038

        ; Read back from channel A's view of WR2
        LDA   #$02
        STA   $C039      ; Channel A control - select RR2
        LDA   $C039      ; Read RR2 (should be WR2 value)
        STA   $0802

        ; Expected: 0x55
        CMP   #$55
        BNE   FAIL_WR2

        ; === Test Channel B Data Register ===

        ; Write to channel B data
        LDA   #$AA
        STA   $C03A      ; Channel B data (C03A!)

        ; Read back channel B data
        LDA   $C03A
        STA   $0803

        ; Expected: 0xAA (should echo back)
        CMP   #$AA
        BNE   FAIL_B_DATA

PASS
        ; Show "PASS" at top of screen
        LDA   #$D0       ; 'P'
        STA   $0400
        LDA   #$C1       ; 'A'
        STA   $0401
        STA   $0403
        LDA   #$D3       ; 'S'
        STA   $0402
        STA   $0404
        JMP   *          ; Loop forever

FAIL_A_RR0
        ; Show "FA" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$C1       ; 'A'
        STA   $0401
        LDA   $0800      ; Actual channel A RR0
        STA   $0402
        JMP   *

FAIL_B_RR0
        ; Show "FB" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$C2       ; 'B'
        STA   $0401
        LDA   $0801      ; Actual channel B RR0
        STA   $0402
        JMP   *

FAIL_WR2
        ; Show "F2" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B2       ; '2'
        STA   $0401
        LDA   $0802      ; Actual WR2/RR2 value
        STA   $0402
        JMP   *

FAIL_B_DATA
        ; Show "FD" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$C4       ; 'D'
        STA   $0401
        LDA   $0803      ; Actual channel B data
        STA   $0402
        JMP   *
