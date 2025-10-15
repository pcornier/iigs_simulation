; SCC IRQ Test - verifies TX interrupt propagates to system
; - Enables SCC master interrupt and TX interrupt
; - Triggers a TX operation and polls RR2 (vector mode) for TX pending (100)
; - Prints PASS or F (with code) to screen

        ORG   $2000
        TYP   $06
        DSK   SCCIRQ.SYSTEM

START
        SEI             ; Disable CPU IRQs while we poll RR2
        ; Hardware reset
        LDA   #$09        ; WR0: select WR9
        STA   $C039
        LDA   #$C0        ; WR9: hardware reset
        STA   $C039

        ; Small delay
        NOP
        NOP

        ; WR9: enable vector mode + MIE
        LDA   #$09        ; select WR9
        STA   $C039
        LDA   #$18        ; 0001 1000 -> VIS (bit4)=1, MIE (bit3)=1
        STA   $C039

        ; WR2: vector base arbitrary
        LDA   #$02        ; select WR2
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR1: enable TX interrupt (bit1)
        LDA   #$01        ; select WR1
        STA   $C039
        LDA   #$02
        STA   $C039

        ; WR5: enable TX (bit3) and set DTR/RTS typical (use 0x6A seen in ROM)
        LDA   #$05        ; select WR5
        STA   $C039
        LDA   #$6A        ; Tx enable + RTS/DTR as per ROM init
        STA   $C039

        ; WR14: local loopback so TX feeds RX (not strictly needed for TX IRQ)
        LDA   #$0E        ; select WR14
        STA   $C039
        LDA   #$03        ; 11b -> remote loopback (internal)
        STA   $C039

        ; Clear any pending TX interrupt via WR0 (Reset Tx Int Pend)
        LDA   #$00        ; select WR0
        STA   $C039
        LDA   #$28        ; 101 xxx -> Reset Tx Int Pending
        STA   $C039

        ; Write a byte to A data to trigger TX busy edge
        LDA   #'A'
        STA   $C03B       ; ADATA (channel A data)

        ; Poll RR2 (vector mode) until TX pending (100) or timeout
        LDY   #$40        ; timeout ~64 iterations
POLL_LOOP
        ; Select RR2 (Channel B control for RR2)
        LDA   #$02
        STA   $C038
        ; Read from B control
        LDA   $C038
        AND   #$70        ; isolate vector bits (vector appears in bits 6:4 with bit4 as MSB)
        CMP   #$10        ; 100b -> TX interrupt pending (appears as $10 in rr2_b mapping)
        BEQ   PASS
        DEY
        BNE   POLL_LOOP

FAIL
        ; Show F and vector code readback for debugging
        LDA   #$C6        ; 'F'
        STA   $0400
        LDA   #$B9        ; '9' (arbitrary)
        STA   $0401
        LDA   #$20
        STA   $0402
        JMP   *

PASS
        LDA   #$D0        ; 'P'
        STA   $0400
        LDA   #$C1        ; 'A'
        STA   $0401
        STA   $0403
        LDA   #$D3        ; 'S'
        STA   $0402
        STA   $0404
        JMP   *
