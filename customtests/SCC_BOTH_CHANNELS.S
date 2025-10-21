;
; SCC FIFO Test - Both Channels A and B
; Tests that both SCC channels can buffer multiple bytes in their 3-byte FIFOs
;
; This test:
; 1. Tests Channel A: Send 3 bytes via loopback, read them back
; 2. Tests Channel B: Send 3 bytes via loopback, read them back
; 3. Displays results: "A:OK B:OK" or "A:FAIL B:FAIL"
;

        ORG   $2000
        TYP   $06
        DSK   SCCBOTH.SYSTEM

START
        ; Initialize result flags so display reflects test outcome
        LDA #$00
        STA $00         ; A result flag = 0 (assume pass until set)
        STA $01         ; B result flag = 0 (assume pass until set)

        ; Clear screen area
        LDA #$A0        ; Space character
        LDX #$00
CLEAR   STA $0400,X
        INX
        CPX #$28        ; Clear first line (40 chars)
        BNE CLEAR

        ; ========================================
        ; TEST CHANNEL A
        ; ========================================

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

        ; Configure baud rate
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

        ; Small delay
        LDX #$10
DELAY_A DEX
        BNE DELAY_A

        ; RAPID SEND: 3 bytes to channel A
        LDA #$AA        ; Test pattern 1
        STA $C03B       ; ADATA (transmit)
        LDA #$55        ; Test pattern 2
        STA $C03B       ; ADATA (transmit)
        LDA #$F0        ; Test pattern 3
        STA $C03B       ; ADATA (transmit)

        ; Wait for RX available
        LDX #$00
WAIT_A  LDA $C039       ; Read RR0
        AND #$01        ; Check RX_AVAIL bit
        BNE RX_A_READY
        INX
        BNE WAIT_A
        JMP TEST_A_FAIL

RX_A_READY
        ; Read and verify 3 bytes
        LDA $C03B       ; Read byte 1
        CMP #$AA
        BNE TEST_A_FAIL
        NOP
        NOP
        NOP
        NOP

        LDA $C03B       ; Read byte 2
        CMP #$55
        BNE TEST_A_FAIL
        NOP
        NOP
        NOP
        NOP

        LDA $C03B       ; Read byte 3
        CMP #$F0
        BNE TEST_A_FAIL

        ; Channel A passed!
        JMP TEST_B

TEST_A_FAIL
        ; Mark channel A as failed
        LDA #$01
        STA $00         ; Store failure flag
        JMP TEST_B

TEST_B
        ; ========================================
        ; TEST CHANNEL B
        ; ========================================

        ; Reset SCC channel B
        LDA #$09        ; Point to WR9
        STA $C038       ; BCTRL
        LDA #$40        ; Channel B reset
        STA $C038       ; BCTRL

        ; Configure WR4: x1 clock mode, 1 stop bit, no parity
        LDA #$04
        STA $C038       ; BCTRL
        LDA #$44        ; x1 clock, async, 1 stop bit
        STA $C038       ; BCTRL

        ; Configure WR3: RX 8 bits/char, RX enable
        LDA #$03
        STA $C038       ; BCTRL
        LDA #$C1        ; RX enable, 8 bits
        STA $C038       ; BCTRL

        ; Configure WR5: TX 8 bits/char, TX enable
        LDA #$05
        STA $C038       ; BCTRL
        LDA #$68        ; TX enable, 8 bits, DTR, RTS
        STA $C038       ; BCTRL

        ; Configure baud rate
        LDA #$0C        ; Point to WR12
        STA $C038       ; BCTRL
        LDA #$5E        ; Baud rate time constant low
        STA $C038       ; BCTRL

        LDA #$0D        ; Point to WR13
        STA $C038       ; BCTRL
        LDA #$00        ; Baud rate time constant high
        STA $C038       ; BCTRL

        ; Configure WR14: Enable BRG, local loopback
        LDA #$0E        ; Point to WR14
        STA $C038       ; BCTRL
        LDA #$11        ; BRG enable + local loopback
        STA $C038       ; BCTRL

        ; Small delay
        LDX #$10
DELAY_B DEX
        BNE DELAY_B

        ; RAPID SEND: 3 bytes to channel B
        LDA #$CC        ; Test pattern 1 (different from A)
        STA $C03A       ; BDATA (transmit)
        LDA #$33        ; Test pattern 2
        STA $C03A       ; BDATA (transmit)
        LDA #$0F        ; Test pattern 3
        STA $C03A       ; BDATA (transmit)

        ; Wait for RX available
        LDX #$00
WAIT_B  LDA $C038       ; Read RR0
        AND #$01        ; Check RX_AVAIL bit
        BNE RX_B_READY
        INX
        BNE WAIT_B
        JMP TEST_B_FAIL

RX_B_READY
        ; Read and verify 3 bytes
        LDA $C03A       ; Read byte 1
        CMP #$CC
        BNE TEST_B_FAIL
        NOP
        NOP
        NOP
        NOP

        LDA $C03A       ; Read byte 2
        CMP #$33
        BNE TEST_B_FAIL
        NOP
        NOP
        NOP
        NOP

        LDA $C03A       ; Read byte 3
        CMP #$0F
        BNE TEST_B_FAIL

        ; Channel B passed!
        JMP DISPLAY_RESULTS

TEST_B_FAIL
        ; Mark channel B as failed
        LDA #$01
        STA $01         ; Store failure flag

DISPLAY_RESULTS
        ; Display "A:" at position 0
        LDA #'A'
        STA $0400
        LDA #':'
        STA $0401

        ; Check channel A result
        LDA $00         ; Load A failure flag
        BNE SHOW_A_FAIL

        ; Channel A passed
        LDA #'O'
        STA $0402
        LDA #'K'
        STA $0403
        JMP CHECK_B

SHOW_A_FAIL
        LDA #'F'
        STA $0402
        LDA #'A'
        STA $0403
        LDA #'I'
        STA $0404
        LDA #'L'
        STA $0405

CHECK_B
        ; Display " B:" at position 7
        LDA #$A0        ; Space
        STA $0407
        LDA #'B'
        STA $0408
        LDA #':'
        STA $0409

        ; Check channel B result
        LDA $01         ; Load B failure flag
        BNE SHOW_B_FAIL

        ; Channel B passed
        LDA #'O'
        STA $040A
        LDA #'K'
        STA $040B
        JMP DONE

SHOW_B_FAIL
        LDA #'F'
        STA $040A
        LDA #'A'
        STA $040B
        LDA #'I'
        STA $040C
        LDA #'L'
        STA $040D

DONE
        ; Infinite loop
        JMP DONE
