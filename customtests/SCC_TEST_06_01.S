; SCC Test 06-01: Local Loopback Test

        ORG   $2000
        TYP   $06
        DSK   SCC0601.SYSTEM

START
        SEI

        ; Reset SCC Channel A
        LDA   #$09
        STA   $C039
        LDA   #$80
        STA   $C039

        ; WR4: x1 clock, 1 stop bit
        LDA   #$04
        STA   $C039
        LDA   #$44
        STA   $C039

        ; WR3: 8 bits/char, Rx Enable
        LDA   #$03
        STA   $C039
        LDA   #$C1
        STA   $C039

        ; WR5: 8 bits/char, Tx Enable
        LDA   #$05
        STA   $C039
        LDA   #$E2
        STA   $C039

        ; WR14: Enable Local Loopback
        LDA   #$0E
        STA   $C039
        LDA   #$02
        STA   $C039

        ; Write a byte to ADATA
        LDA   #'A'
        STA   $C03B

        ; Wait for Rx Char Available (RR0 bit 0)
        LDY   #$FF
POLL_RX
        LDA   $C039  ; Read RR0
        AND   #$01
        BNE   RX_OK
        DEY
        BNE   POLL_RX
        JMP   FAIL_RX_TIMEOUT

RX_OK
        ; Read the character from RDATA
        LDA   $C03B
        CMP   #'A'
        BEQ   PASS
        JMP   FAIL_DATA_MISMATCH

FAIL_RX_TIMEOUT
        LDA   #$C0
        STA   $0400
        LDA   #$C6
        STA   $0401
        LDA   #$B0
        STA   $0402
        LDA   #$B1
        STA   $0403
        JMP   *

FAIL_DATA_MISMATCH
        LDA   #$C0
        STA   $0400
        LDA   #$C6
        STA   $0401
        LDA   #$B0
        STA   $0402
        LDA   #$B2
        STA   $0403
        JMP   *

PASS
        LDA   #$D0
        STA   $0400
        LDA   #$C1
        STA   $0401
        LDA   #$D3
        STA   $0402
        LDA   #$D3
        STA   $0403
        JMP   *
