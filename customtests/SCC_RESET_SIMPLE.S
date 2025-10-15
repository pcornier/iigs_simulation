; Minimal SCC Reset Test
; Just does hardware reset and checks RR0

        ORG   $2000
        TYP   $06
        DSK   SCCRST.SYSTEM

START
        ; Hardware reset via WR9
        LDA   #$09
        STA   $C039
        LDA   #$C0
        STA   $C039

        ; Wait a very short time
        NOP
        NOP
        NOP
        NOP

        ; Read RR0 multiple times to see if it changes
        LDA   $C039
        STA   $0800
        LDA   $C039
        STA   $0801
        LDA   $C039
        STA   $0802

        ; Use first read for comparison
        LDA   $0800

        ; Check if it's 0x6C (TX_UNDERRUN + CTS + DCD + TX_EMPTY)
        CMP   #$6C
        BEQ   PASS

        ; Failed - show error
        STA   $0400          ; Show actual value at top of screen
        JMP   $2000          ; Loop forever

PASS
        ; Show PASS at top of screen
        LDA   #$D0           ; 'P'
        STA   $0400
        LDA   #$C1           ; 'A'
        STA   $0401
        STA   $0403
        LDA   #$D3           ; 'S'
        STA   $0402
        STA   $0404
        JMP   *              ; Loop forever
