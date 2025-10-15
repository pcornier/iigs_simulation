; SCC TXEMPTY status test (RR0 bit2)
; 1) Init SCC (WR11, WR4, WR1=0, WR3=0, WR5=0x6A, WR14=01)
; 2) Write one byte to ADATA
; 3) Immediately read RR0 and expect TXEMPTY=0
; 4) Poll RR0 until TXEMPTY returns to 1

        ORG   $2000
        TYP   $06
        DSK   SCCTXE.SYSTEM

START
        SEI
        ; Reset SCC (WR9=C0)
        LDA   #$09
        STA   $C039
        LDA   #$C0
        STA   $C039

        ; WR11: clock mode (like ROM)
        LDA   #$0B
        STA   $C039
        LDA   #$D2
        STA   $C039

        ; WR4: parity/clock default
        LDA   #$04
        STA   $C039
        LDA   #$44
        STA   $C039

        ; WR1: disable RX/TX IRQ for this test
        LDA   #$01
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR3: RX disabled
        LDA   #$03
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR5: TX enable + RTS/DTR
        LDA   #$05
        STA   $C039
        LDA   #$6A
        STA   $C039

        ; Set baud rate like ROM uses here: WR12=$5E, WR13=$00 (1200 bps)
        LDA   #$0C
        STA   $C039
        LDA   #$5E
        STA   $C039
        LDA   #$0D
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR14: enable BRG
        LDA   #$0E
        STA   $C039
        LDA   #$01
        STA   $C039

        ; Write a byte to ADATA to start TX
        LDA   #'X'
        STA   $C03B

        ; Select RR0
        LDA   #$00
        STA   $C039
        ; Immediate read
        LDA   $C039
        AND   #$04        ; TXEMPTY
        BEQ   EXPECT_OK   ; want 0 immediately

FAIL_IMM
        ; Show F0 + RR0
        LDA   #$C6
        STA   $0400
        LDA   #$B0
        STA   $0401
        LDA   #$00
        STA   $0402
        JMP   *

EXPECT_OK
        ; Poll until TXEMPTY=1 or timeout
        LDY   #$C0
POLL
        LDA   #$00
        STA   $C039
        LDA   $C039
        AND   #$04
        BNE   PASS
        DEY
        BNE   POLL

FAIL_LATE
        ; F1
        LDA   #$C6
        STA   $0400
        LDA   #$B1
        STA   $0401
        LDA   #$00
        STA   $0402
        JMP   *

PASS
        LDA   #$D0
        STA   $0400
        LDA   #$C1
        STA   $0401
        STA   $0403
        LDA   #$D3
        STA   $0402
        STA   $0404
        JMP   *
