; SCC Exact ROM Selftest Sequence
; This test EXACTLY replicates what the ROM selftest does,
; including the register order and values

      ORG   $2000
      TYP   $06
      DSK   SCCEXACT.SYSTEM

START
      ; NO hardware reset (ROM doesn't do one before the loop test)
      ; BUT - try with explicit clock setup first

      ; WR4 = 0x4C (ROM uses 0x4C, not 0x44)
      LDA   #$04
      STA   $C039
      LDA   #$4C
      STA   $C039

      ; WR11 = 0xD0 (clock source - ROM sets this - CRITICAL!)
      LDA   #$0B
      STA   $C039
      LDA   #$D0
      STA   $C039

      ; WR12 = 0x5E (baud rate low)
      LDA   #$0C
      STA   $C039
      LDA   #$5E
      STA   $C039

      ; WR13 = 0x00 (baud rate high)
      LDA   #$0D
      STA   $C039
      LDA   #$00
      STA   $C039

      ; WR14 = 0x13 (Enable BRG + loopback)
      ; NOTE: WR3 and WR5 NOT set yet!
      LDA   #$0E
      STA   $C039
      LDA   #$13
      STA   $C039

      ; NOW set WR3 = 0xC1 (RX enable) AFTER loopback
      LDA   #$03
      STA   $C039
      LDA   #$C1
      STA   $C039

      ; NOW set WR5 = 0x6A (TX enable) AFTER loopback and RX enable
      LDA   #$05
      STA   $C039
      LDA   #$6A
      STA   $C039

      ; Transmit byte 0x00 (like ROM does)
      LDA   #$00
      STA   $C03B      ; SCCADATA

      ; Wait for TX to complete
:WAIT_TX
      LDA   $C039      ; Read RR0
      AND   #$04       ; Check TX empty
      BEQ   :WAIT_TX

      ; Now wait for RX char available (bit 0)
      LDX   #$00       ; Timeout counter
:WAIT_RX
      LDA   $C039      ; Read RR0
      AND   #$01       ; Check RX char available
      BNE   RX_READY

      INX
      BNE   :WAIT_RX

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
