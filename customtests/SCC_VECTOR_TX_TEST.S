; SCC Vector + TX Pending Test (ROM-like)
; - Sets VIS+MIE (WR9), WR2 vector, WR1 TX interrupt enable, WR5 TX enable
; - Writes one byte to ADATA
; - Polls RR2 (via B control) for 0x10 (TX interrupt pending in our mapping)
; - Also verifies RR0 TXEMPTY transitions 0->1

        ORG   $2000
        TYP   $06
        DSK   SCCVTX.SYSTEM

START
        SEI
        ; Hardware reset
        LDA   #$09
        STA   $C039
        LDA   #$C0
        STA   $C039

        ; VIS+MIE
        LDA   #$09
        STA   $C039
        LDA   #$18
        STA   $C039

        ; Vector base 00
        LDA   #$02
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR1: TX interrupt enable (bit1)
        LDA   #$01
        STA   $C039
        LDA   #$02
        STA   $C039

        ; WR5: TX enable (and RTS/DTR typical)
        LDA   #$05
        STA   $C039
        LDA   #$6A
        STA   $C039

        ; Baud: WR12=$5E WR13=$00 (common ROM setting)
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

        ; Write a byte to ADATA
        LDA   #'V'
        STA   $C03B

        ; Check RR0: should be TXEMPTY=0 immediately
        LDA   #$00
        STA   $C039
        LDA   $C039
        AND   #$04
        BEQ   OK0
        JMP   FAIL0
OK0

        ; Poll RR2 on B control for 0x10 (TX pending)
        LDX   #$02 ; Outer loop counter
POLL_OUTER
        LDY   #$FF
POLLV
        LDA   #$02
        STA   $C038
        LDA   $C038
        AND   #$70
        CMP   #$40
        BEQ   V_OK
        DEY
        BNE   POLLV
        DEX
        BNE   POLL_OUTER
        JMP   FAILV

V_OK
        ; Wait for TXEMPTY to return to 1
        LDY   #$A0
POLLX
        LDA   #$00
        STA   $C039
        LDA   $C039
        AND   #$04
        BNE   PASS
        DEY
        BNE   POLLX
        JMP   FAIL1

FAIL0
        LDA   #$C6 ; F
        STA   $0400
        LDA   #$B0 ; 0
        STA   $0401
        JMP   *

FAILV
        LDA   #$C6 ; F
        STA   $0400
        LDA   #$B7 ; 7
        STA   $0401
        JMP   *

FAIL1
        LDA   #$C6 ; F
        STA   $0400
        LDA   #$B1 ; 1
        STA   $0401
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

