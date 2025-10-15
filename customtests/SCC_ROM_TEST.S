; SCC ROM Test 06-01 Replica
; This closely matches what the Apple IIgs ROM selftest does

        ORG   $2000
        TYP   $06
        DSK   SCCROM.SYSTEM

START
        ; First set up WR11 and WR9 like ROM does
        LDA   #$0B       ; Select WR11
        STA   $C039
        LDA   #$D2       ; Write to WR11 (crystal select, etc)
        STA   $C039

        ; Hardware reset via WR9
        LDA   #$09       ; Select WR9
        STA   $C039
        LDA   #$C0       ; Hardware reset command
        STA   $C039

        ; Now test sequence like ROM does
        ; Write 0x02 to select RR2
        LDA   #$02
        STA   $C039
        
        ; Write 0x00 to WR2 (interrupt vector)
        LDA   #$00
        STA   $C039
        
        ; Write 0x02 again to select RR2
        LDA   #$02
        STA   $C039
        
        ; Read RR2 - should be 0x00
        LDA   $C039
        STA   $0800      ; Store result
        CMP   #$00
        BNE   FAIL1

        ; Test the 0xFF command like ROM does
        LDA   #$FF      ; WR0 command 7, select register 7
        STA   $C039

        ; After write, pointer auto-resets to 0
        ; Write 0x02 to WR0 to select register 2
        LDA   #$02
        STA   $C039

        ; But reads after write selection don't work!
        ; After write, rindex auto-resets to 0, so this reads RR0
        LDA   $C039
        STA   $0801     ; This is RR0, not RR2!

        ; Check RR0 should be 0x2C
        CMP   #$2C
        BNE   FAIL2
        
        ; Continue with more register tests...
        ; Write to WR9 with 0x0A (software interrupt)
        LDA   #$09
        STA   $C039
        LDA   #$0A
        STA   $C039
        
        ; Read RR0 again
        LDA   $C039
        STA   $0802
        CMP   #$2C
        BNE   FAIL3

PASS
        LDA   #$D0       ; 'P'
        STA   $0400
        LDA   #$C1       ; 'A'
        STA   $0401
        LDA   #$D3       ; 'S'
        STA   $0402
        STA   $0404
        LDA   #$C1       ; 'A'
        STA   $0403
        JMP   *

FAIL1
        ; Show "F1xx" with error code
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B1       ; '1'
        STA   $0401
        LDA   $0800      ; Show actual RR2 value
        STA   $0402
        JMP   *

FAIL2
        ; Show "F2xx" with error code
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B2       ; '2'
        STA   $0401
        LDA   $0801      ; Show actual RR0 value
        STA   $0402
        JMP   *

FAIL3
        ; Show "F3xx" with error code
        LDA   #$C6       ; 'F'
        STA   $0400
        LDA   #$B3       ; '3'
        STA   $0401
        LDA   $0802      ; Show actual RR0 value
        STA   $0402
        JMP   *
