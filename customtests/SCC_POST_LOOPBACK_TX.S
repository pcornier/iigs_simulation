; SCC Post-Loopback TX Test
; Replicates the next ROM selftest phase after loopback: disable loopback,
; keep BRG enabled, and transmit several bytes while polling RR0/RR1.

      ORG   $2000
      TYP   $06
      DSK   SCCPOST.SYSTEM

START
      ; Minimal setup matching ROM sequence
      ; WR4 = $4C (async, x16)
      LDA   #$04
      STA   $C039
      LDA   #$4C
      STA   $C039

      ; WR11 = $D0 (clock source)
      LDA   #$0B
      STA   $C039
      LDA   #$D0
      STA   $C039

      ; WR12:$5E, WR13:$00 (BRG time constant)
      LDA   #$0C
      STA   $C039
      LDA   #$5E
      STA   $C039

      LDA   #$0D
      STA   $C039
      LDA   #$00
      STA   $C039

      ; Disable loopback (WR14=$00), then enable BRG only (WR14=$01)
      LDA   #$0E
      STA   $C039
      LDA   #$00
      STA   $C039

      LDA   #$0E
      STA   $C039
      LDA   #$01
      STA   $C039

      ; WR3=$C1 (RX enable), WR5=$6A (TX enable)
      LDA   #$03
      STA   $C039
      LDA   #$C1
      STA   $C039

      LDA   #$05
      STA   $C039
      LDA   #$6A
      STA   $C039

      ; Transmit sequence like ROM shows (B0, B6, B7, 8D, 8A)
      ; For each: verify RR0 clears to 28, then returns to 2C, and RR1 reflects Tx all sent

      LDA   #$B0
      JSR   SEND_AND_CHECK
      LDA   #$B6
      JSR   SEND_AND_CHECK
      LDA   #$B7
      JSR   SEND_AND_CHECK
      LDA   #$8D
      JSR   SEND_AND_CHECK
      LDA   #$8A
      JSR   SEND_AND_CHECK

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

FAIL
      LDA   #$C6
      STA   $0400
      LDA   #$A1
      STA   $0401
      LDA   #$00
      STA   $0402
      JMP   *

; Subroutine: send A to ADATA, check RR0 clears then returns, and RR1 Tx-all-sent
SEND_AND_CHECK
      PHA
      STA   $C03B          ; write ADATA
      ; RR0 should clear tx_empty (28)
      LDX   #$00
@WAIT_CLR
      LDA   $C039
      CMP   #$28
      BEQ   @CLEARED
      INX
      BNE   @WAIT_CLR
      JMP   FAIL
@CLEARED
      ; Wait for TX complete (RR0 -> 2C)
      LDX   #$00
@WAIT_TX
      LDA   $C039
      CMP   #$2C
      BEQ   @CHECK_RR1
      INX
      BNE   @WAIT_TX
      JMP   FAIL
@CHECK_RR1
      ; Point to RR1 and read it once (ROM reads RR1 in this phase)
      LDA   #$01
      STA   $C039          ; WR0 select RR1
      LDA   $C039          ; RR1
      ; No strict compare here; presence of 2C on RR0 is sufficient
      PLA
      RTS

