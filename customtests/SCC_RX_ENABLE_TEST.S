; SCC RX Enable Test
; This test verifies that WR3[0] (RX enable) actually controls reception
;
; Test sequence:
; 1. Setup SCC with RX DISABLED (WR3 = 0xC0, bit 0 = 0)
; 2. Enable loopback mode
; 3. Enable TX and transmit a byte
; 4. Check RR0 - should show rx_avail = 0 (RX is disabled)
; 5. Enable RX (WR3 = 0xC1, bit 0 = 1)
; 6. Transmit another byte
; 7. Check RR0 - should show rx_avail = 1 (RX is now enabled)
;
; Expected behavior:
; - First transmission should NOT set rx_avail (RX disabled)
; - Second transmission SHOULD set rx_avail (RX enabled)
;
; Current bug:
; - rx_wr_a_latch gets set even when WR3[0]=0
; - This causes rx_avail to be set incorrectly

      ORG   $2000
      TYP   $06
      DSK   SCCRXEN.SYSTEM

START
      ; Hardware reset first (WR9 = 0xC0)
      LDA   #$09
      STA   $C039
      LDA   #$C0       ; Hardware reset
      STA   $C039

      ; Wait a bit for reset
      LDX   #$00
:WAIT1
      INX
      BNE   :WAIT1

      ; WR4 = 0x44 (clock mode, 1 stop bit)
      LDA   #$04
      STA   $C039
      LDA   #$44
      STA   $C039

      ; WR3 = 0xC0 (8 bits, RX DISABLED - bit 0 = 0)
      LDA   #$03
      STA   $C039
      LDA   #$C0       ; Note: 0xC0 not 0xC1, RX disabled!
      STA   $C039

      ; WR5 = 0x6A (TX 8 bits, TX enable)
      LDA   #$05
      STA   $C039
      LDA   #$6A
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
      LDA   #$0E
      STA   $C039
      LDA   #$13
      STA   $C039

      ; Transmit byte 0xAA with RX DISABLED
      LDA   #$AA
      STA   $C03B      ; SCCADATA

      ; Wait for TX to complete
:WAIT_TX1
      LDA   $C039      ; Read RR0
      AND   #$04       ; Check TX empty
      BEQ   :WAIT_TX1

      ; Now check RX - should be 0 because RX is disabled
      ; Give it some time for any incorrect reception
      LDX   #$00
:WAIT_RX1
      INX
      BNE   :WAIT_RX1

      ; Check RR0 for RX char available
      LDA   $C039      ; Read RR0
      AND   #$01       ; Check RX char available
      BNE   FAIL_RX_DISABLED  ; Should be 0!

      ; Good! RX was properly disabled
      ; Now enable RX and try again
      LDA   #$03
      STA   $C039
      LDA   #$C1       ; WR3 = 0xC1 (RX ENABLED now)
      STA   $C039

      ; Transmit another byte
      LDA   #$55
      STA   $C03B      ; SCCADATA

      ; Wait for TX to complete
:WAIT_TX2
      LDA   $C039      ; Read RR0
      AND   #$04       ; Check TX empty
      BEQ   :WAIT_TX2

      ; Now check for RX - should be available
      LDX   #$00
:WAIT_RX2
      LDA   $C039      ; Read RR0
      AND   #$01       ; Check RX char available
      BNE   RX_READY

      INX
      CPX   #$FF       ; Longer timeout
      BNE   :WAIT_RX2

      ; Timeout - no RX even though enabled
      JMP   FAIL_RX_NOT_RECEIVED

RX_READY
      ; Read the received byte
      LDA   $C03B
      CMP   #$55       ; Should match what we sent
      BNE   FAIL_WRONG_DATA

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

FAIL_RX_DISABLED
      ; RX char available even though RX was disabled!
      LDA   #$C6       ; 'F'
      STA   $0400
      LDA   #$C1       ; 'A'
      STA   $0401
      LDA   #$C9       ; 'I'
      STA   $0402
      LDA   #$CC       ; 'L'
      STA   $0403
      LDA   #$A0       ; ' '
      STA   $0404
      LDA   #$D2       ; 'R'
      STA   $0405
      LDA   #$D8       ; 'X'
      STA   $0406
      LDA   #$C4       ; 'D'
      STA   $0407
      LDA   #$C9       ; 'I'
      STA   $0408
      LDA   #$D3       ; 'S'
      STA   $0409
      JMP   *

FAIL_RX_NOT_RECEIVED
      ; RX not received even though enabled
      LDA   #$C6       ; 'F'
      STA   $0400
      LDA   #$C1       ; 'A'
      STA   $0401
      LDA   #$C9       ; 'I'
      STA   $0402
      LDA   #$CC       ; 'L'
      STA   $0403
      LDA   #$A0       ; ' '
      STA   $0404
      LDA   #$CE       ; 'N'
      STA   $0405
      LDA   #$CF       ; 'O'
      STA   $0406
      LDA   #$D2       ; 'R'
      STA   $0407
      LDA   #$D8       ; 'X'
      STA   $0408
      JMP   *

FAIL_WRONG_DATA
      ; Received wrong data
      LDA   #$C6       ; 'F'
      STA   $0400
      LDA   #$C1       ; 'A'
      STA   $0401
      LDA   #$C9       ; 'I'
      STA   $0402
      LDA   #$CC       ; 'L'
      STA   $0403
      LDA   #$A0       ; ' '
      STA   $0404
      LDA   #$C4       ; 'D'
      STA   $0405
      LDA   #$C1       ; 'A'
      STA   $0406
      LDA   #$D4       ; 'T'
      STA   $0407
      LDA   #$C1       ; 'A'
      STA   $0408
      JMP   *
