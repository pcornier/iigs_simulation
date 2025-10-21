; SCC Local Loopback Test
; Tests the internal loopback functionality (WR14 bit 4)
; Transmits a byte and verifies it's received via internal loopback

       ORG   $2000
       TYP   $06
       DSK   SCCLOOP.SYSTEM

START
       ; Initialize SCC for loopback test
       ; Setup similar to ROM selftest but simpler

       ; WR4 = 0x44 (x16 clock mode, 1 stop bit, no parity)
       LDA   #$04
       STA   $C039      ; SCCAREG (register pointer)
       LDA   #$44
       STA   $C039      ; SCCAREG (data)

       ; WR3 = 0xC1 (RX 8 bits, RX enable)
       LDA   #$03
       STA   $C039
       LDA   #$C1
       STA   $C039

       ; WR5 = 0x6A (TX 8 bits, TX enable, RTS)
       LDA   #$05
       STA   $C039
       LDA   #$6A
       STA   $C039

       ; WR12 = 0x5E (baud rate lower byte)
       LDA   #$0C
       STA   $C039
       LDA   #$5E
       STA   $C039

       ; WR13 = 0x00 (baud rate upper byte)
       LDA   #$0D
       STA   $C039
       LDA   #$00
       STA   $C039

       ; WR14 = 0x13 (Enable BRG + LOCAL LOOPBACK)
       ; Bit 0 = BRG enable
       ; Bit 4 = Local loopback
       LDA   #$0E
       STA   $C039
       LDA   #$13       ; 0x13 = 0001_0011 = BRG + LOOPBACK
       STA   $C039

       ; Transmit test byte 0xAA
       LDA   #$AA
       STA   $C03B      ; SCCADATA (data port)

       ; Wait for TX to complete by polling RR0
WAIT_TX
       LDA   $C039      ; Read RR0
       AND   #$04       ; Check TX empty bit (bit 2)
       BEQ   WAIT_TX    ; Wait until TX buffer empty

       ; Now wait for RX character available
       LDX   #$00       ; Timeout counter
WAIT_RX
       LDA   $C039      ; Read RR0
       AND   #$01       ; Check RX char available (bit 0)
       BNE   RX_READY   ; Got character!

       INX
       BNE   WAIT_RX    ; Keep waiting (256 iterations max)

       ; Timeout - RX char not available
       JMP   FAIL

RX_READY
       ; Read received character
       LDA   $C03B      ; SCCADATA
       CMP   #$AA       ; Should match transmitted byte
       BNE   FAIL

PASS
       LDA   #$D0       ; 'P'
       STA   $0400
       LDA   #$C1       ; 'A'
       STA   $0401
       LDA   #$D3       ; 'S'
       STA   $0402
       LDA   #$D3       ; 'S'
       STA   $0403
       JMP   *

FAIL
       LDA   #$C6       ; 'F'
       STA   $0400
       LDA   #$C1       ; 'A'
       STA   $0401
       LDA   #$C9       ; 'I'
       STA   $0402
       LDA   #$CC       ; 'L'
       STA   $0403
       JMP   *
