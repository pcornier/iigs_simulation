; SCC ROM Fail Reproducer
; Attempt to reproduce ROM selftest TX-stuck by pre-conditioning SCC state
; with prior WR14 writes observed in the ROM trace, then running the exact
; loopback transmit sequence without a hardware reset.

      ORG   $2000
      TYP   $06
      DSK   SCCREPRO.SYSTEM

; Channel A base: $C039 (ACTRL), $C03B (ADATA)

START
      ; IMPORTANT: No hardware reset here (to mimic ROM context)

      ; ------------------------------------------------------------
      ; Pre-condition SCC state similar to earlier ROM activity
      ; From vsim_selftest_trace.csv we see earlier WR14 sequences:
      ;   - WR14 <= $02, then WR14 <= $0C, then WR14 <= $0D
      ;   - In other windows: WR14 <= $00, then WR14 <= $01
      ; These may leave BRG/loopback in a state that later causes TX to stick.
      ; ------------------------------------------------------------

      ; Select WR14, then write $02
      LDA   #$0E
      STA   $C039
      LDA   #$02
      STA   $C039

      ; Select WR14, then write $0C
      LDA   #$0E
      STA   $C039
      LDA   #$0C
      STA   $C039

      ; Select WR14, then write $0D
      LDA   #$0E
      STA   $C039
      LDA   #$0D
      STA   $C039

      ; Select WR14, then write $00
      LDA   #$0E
      STA   $C039
      LDA   #$00
      STA   $C039

      ; Select WR14, then write $01
      LDA   #$0E
      STA   $C039
      LDA   #$01
      STA   $C039

      ; ------------------------------------------------------------
      ; Now run the exact ROM loopback TX sequence as seen to fail:
      ; WR4=$4C, WR11=$D0, WR12=$5E, WR13=$00, WR14=$13,
      ; WR3=$C1, WR5=$6A, TX 00, then poll RR0 for RX available.
      ; ------------------------------------------------------------

      ; WR4 = $4C
      LDA   #$04
      STA   $C039
      LDA   #$4C
      STA   $C039

      ; WR11 = $D0 (clock source)
      LDA   #$0B
      STA   $C039
      LDA   #$D0
      STA   $C039

      ; WR12 = $5E (baud low)
      LDA   #$0C
      STA   $C039
      LDA   #$5E
      STA   $C039

      ; WR13 = $00 (baud high)
      LDA   #$0D
      STA   $C039
      LDA   #$00
      STA   $C039

      ; WR14 = $13 (enable BRG + local loopback)
      LDA   #$0E
      STA   $C039
      LDA   #$13
      STA   $C039

      ; WR3 = $C1 (RX enable, 8-bit)
      LDA   #$03
      STA   $C039
      LDA   #$C1
      STA   $C039

      ; WR5 = $6A (TX enable, 8-bit)
      LDA   #$05
      STA   $C039
      LDA   #$6A
      STA   $C039

      ; ROM writes $00 to C039 (interpreted as WR0 command) before ADATA
      ; Mirror that exact step from the trace
      LDA   #$00
      STA   $C039

      ; Optional: mimic a couple of RR0 reads seen in the trace
      LDA   $C039
      LDA   $C039

      ; Now transmit byte $00 (as in ROM)
      LDA   #$00
      STA   $C03B

      ; Mirror the ROM writing $01 to C039 shortly after ADATA
      LDA   #$01
      STA   $C039

      ; Wait for TX complete (RR0 bit 2)
:WAIT_TX
      LDA   $C039
      AND   #$04
      BEQ   :WAIT_TX

      ; Now wait for RX char available (RR0 bit 0) with timeout
      LDX   #$00
:WAIT_RX
      LDA   $C039
      AND   #$01
      BNE   RX_READY
      INX
      BNE   :WAIT_RX
      JMP   FAIL

RX_READY
      LDA   $C03B       ; read echoed byte
      BEQ   PASS        ; expect $00

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
