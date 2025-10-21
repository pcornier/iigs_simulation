;
; SCC RX FIFO Test
; Tests that the SCC can buffer multiple received bytes in its 3-byte FIFO
;
; This test sends 3 bytes rapidly via loopback, then reads them back.
; If the FIFO is not implemented, bytes will be lost.
;

        ORG   $2000
        TYP   $06
        DSK   SCCFIFO.SYSTEM

START
        ; Initialize SCC for local loopback mode
        ; Similar to ROM selftest sequence

        ; Reset SCC channel A
        LDA #$09        ; Point to WR9
        STA $C039       ; ACTRL
        LDA #$80        ; Channel A reset
        STA $C039       ; ACTRL

        ; Configure WR4: x1 clock mode, 1 stop bit, no parity
        LDA #$04
        STA $C039       ; ACTRL
        LDA #$44        ; x1 clock, async, 1 stop bit
        STA $C039       ; ACTRL

        ; Configure WR3: RX 8 bits/char, RX enable
        LDA #$03
        STA $C039       ; ACTRL
        LDA #$C1        ; RX enable, 8 bits
        STA $C039       ; ACTRL

        ; Configure WR5: TX 8 bits/char, TX enable
        LDA #$05
        STA $C039       ; ACTRL
        LDA #$68        ; TX enable, 8 bits, DTR, RTS
        STA $C039       ; ACTRL

        ; Configure baud rate (fast for test)
        LDA #$0C        ; Point to WR12
        STA $C039       ; ACTRL
        LDA #$5E        ; Baud rate time constant low
        STA $C039       ; ACTRL

        LDA #$0D        ; Point to WR13
        STA $C039       ; ACTRL
        LDA #$00        ; Baud rate time constant high
        STA $C039       ; ACTRL

        ; Configure WR14: Enable BRG, local loopback
        LDA #$0E        ; Point to WR14
        STA $C039       ; ACTRL
        LDA #$11        ; BRG enable + local loopback
        STA $C039       ; ACTRL

        ; Small delay to let config settle
        LDX #$10
DELAY1  DEX
        BNE DELAY1

        ; ========================================
        ; RAPID SEND: Send 3 bytes without waiting
        ; This will test if FIFO can buffer them
        ; ========================================

        LDA #$AA        ; Test pattern 1
        STA $C03B       ; ADATA (transmit)

        LDA #$55        ; Test pattern 2
        STA $C03B       ; ADATA (transmit)

        LDA #$F0        ; Test pattern 3
        STA $C03B       ; ADATA (transmit)

        ; Wait for transmission to complete
        ; Poll RR0 until all bytes received (RX_AVAIL set)
        LDX #$00        ; Timeout counter
WAIT_RX
        LDA $C039       ; Read RR0
        AND #$01        ; Check RX_AVAIL bit
        BNE RX_READY    ; Byte available!
        INX
        BNE WAIT_RX     ; Keep waiting (256 iterations max)
        JMP TEST_FAIL   ; Timeout - no RX

RX_READY
        ; Now read back the 3 bytes
        ; They should be AA, 55, F0 in that order

        ; Read byte 1
        LDA $C03B       ; ADATA (receive)
        CMP #$AA        ; Should be AA
        BNE TEST_FAIL

        ; Small delay before next read
        NOP
        NOP
        NOP
        NOP

        ; Read byte 2
        LDA $C03B       ; ADATA (receive)
        CMP #$55        ; Should be 55
        BNE TEST_FAIL

        ; Small delay before next read
        NOP
        NOP
        NOP
        NOP

        ; Read byte 3
        LDA $C03B       ; ADATA (receive)
        CMP #$F0        ; Should be F0
        BNE TEST_FAIL

        ; SUCCESS!
TEST_PASS
        LDA #'P'
        STA $0400       ; Display P at screen location
        LDA #'A'
        STA $0401
        LDA #'S'
        STA $0402
        STA $0403
        JMP DONE

TEST_FAIL
        LDA #'F'
        STA $0400       ; Display F at screen location
        LDA #'A'
        STA $0401
        LDA #'I'
        STA $0402
        LDA #'L'
        STA $0403

DONE
        ; Infinite loop
        JMP DONE
