; SCC ROM Selftest Sequence Replication
; This test replicates the EXACT sequence the ROM selftest uses
; Based on analysis of the ROM code

       ORG   $2000
       TYP   $06
       DSK   SCCROM.SYSTEM

START
       ; ROM sequence from analysis:
       ; 1. WR4 = 0x44
       ; 2. WR3 = 0xC1 (RX enable, 8 bits)
       ; 3. WR5 = 0x6A
       ; 4. WR12 = 0x5E
       ; 5. WR13 = 0x00
       ; 6. WR14 = 0x13 (BRG + LOOPBACK)
       ; 7. WR3 = 0xC1 AGAIN (re-enable RX after loopback?)
       ; 8. TX byte 0x00
       ; 9. Poll RR0 for RX char available

       ; WR4 = 0x44
       LDA   #$04
       STA   $C039
       LDA   #$44
       STA   $C039

       ; WR3 = 0xC1 (RX enable + 8 bits)
       LDA   #$03
       STA   $C039
       LDA   #$C1
       STA   $C039

       ; WR5 = 0x6A
       LDA   #$05
       STA   $C039
       LDA   #$6A
       STA   $C039

       ; WR12 = 0x5E
       LDA   #$0C
       STA   $C039
       LDA   #$5E
       STA   $C039

       ; WR13 = 0x00
       LDA   #$0D
       STA   $C039
       LDA   #$00
       STA   $C039

       ; WR14 = 0x13 (Enable loopback)
       LDA   #$0E
       STA   $C039
       LDA   #$13
       STA   $C039

       ; WR3 = 0xC1 AGAIN (try re-enabling RX)
       LDA   #$03
       STA   $C039
       LDA   #$C1
       STA   $C039

       ; Transmit byte 0x00 (like ROM does)
       LDA   #$00
       STA   $C03B      ; SCCADATA

       ; Wait for TX to complete
WAIT_TX
       LDA   $C039      ; Read RR0
       AND   #$04       ; Check TX empty
       BEQ   WAIT_TX

       ; Now wait for RX char available (bit 0)
       LDX   #$00       ; Timeout counter
WAIT_RX
       LDA   $C039      ; Read RR0
       AND   #$01       ; Check RX char available
       BNE   RX_READY

       INX
       BNE   WAIT_RX

       ; Timeout - no RX char
       JMP   FAIL

RX_READY
       ; Read received byte
       LDA   $C03B
       ; Should be 0x00
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
