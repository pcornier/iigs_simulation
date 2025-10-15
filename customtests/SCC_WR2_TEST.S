; SCC WR2 Register Write/Read Test
; Reproduces the exact sequence that fails in ROM selftest Test 06-01

        ORG   $2000
        TYP   $06
        DSK   SCCWR2.SYSTEM

START
        ; === Hardware reset first ===
        LDA   #$09       ; Select WR9
        STA   $C039      ; Channel A control
        LDA   #$C0       ; Hardware reset command
        STA   $C039

        ; Small delay
        NOP
        NOP
        NOP
        NOP

        ; === Test 1: Write 0x00 to WR2, read it back ===

        ; Select WR2
        LDA   #$02
        STA   $C039

        ; Write 0x00 to WR2
        LDA   #$00
        STA   $C039

        ; Select RR2 for read
        LDA   #$02
        STA   $C039

        ; Read RR2
        LDA   $C039
        STA   $0800      ; Store result

        ; Expected: 0x00
        CMP   #$00
        BNE   FAIL_TEST1

        ; === Test 2: Write 0xFF to WR2, read it back ===

        ; Select WR2
        LDA   #$02
        STA   $C039

        ; Write 0xFF to WR2
        LDA   #$FF
        STA   $C039

        ; Select RR2 for read
        LDA   #$02
        STA   $C039

        ; Read RR2
        LDA   $C039
        STA   $0801      ; Store result

        ; Expected: 0xFF
        CMP   #$FF
        BNE   FAIL_TEST2

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

FAIL_TEST1
        ; Show "F1" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B1       ; '1'
        STA   $0401
        LDA   $0800      ; Actual RR2 value from test 1
        STA   $0402
        JMP   *

FAIL_TEST2
        ; Show "F2" and actual value
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B2       ; '2'
        STA   $0401
        LDA   $0801      ; Actual RR2 value from test 2
        STA   $0402
        JMP   *
