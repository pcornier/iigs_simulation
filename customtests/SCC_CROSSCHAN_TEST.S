; SCC Cross-Channel Loopback Test
; Tests the actual UART TX/RX path via cross-channel wiring in iigs.sv:
;   Channel A TX (txd_a) -> Channel B RX (rxd_b)
;   Channel B TX (txd_b) -> Channel A RX (rxd_a)
;
; This test: TX on Channel A, verify RX on Channel B
; Then: TX on Channel B, verify RX on Channel A
;
; Address map:
;   C038 = SCC B Control (command/status)
;   C039 = SCC A Control (command/status)
;   C03A = SCC B Data
;   C03B = SCC A Data

       ORG   $2000
       TYP   $06
       DSK   SCCCROSS.SYSTEM
; Baud rate: 9600 (WR12=$0A, WR13=$00 with x16 clock mode)

SCCA_CTRL  EQU $C039
SCCA_DATA  EQU $C03B
SCCB_CTRL  EQU $C038
SCCB_DATA  EQU $C03A

; Test result display locations (text page 1)
ROW0   EQU $0400       ; Line 0 of text screen
ROW1   EQU $0480       ; Line 1
ROW2   EQU $0500       ; Line 2
ROW3   EQU $0580       ; Line 3

START
       ; ===== Hardware reset both channels via WR9 =====
       LDA   #$09
       STA   SCCA_CTRL       ; Select WR9 (via channel A)
       LDA   #$C0            ; Hardware reset (bits 7:6 = 11)
       STA   SCCA_CTRL

       ; Small delay for reset to take effect
       LDX   #$20
:RSTDLY
       DEX
       BNE   :RSTDLY

       ; ===== Configure Channel A for TX =====
       ; WR4 = $44 (x16 clock, 1 stop bit, no parity)
       LDA   #$04
       STA   SCCA_CTRL
       LDA   #$44
       STA   SCCA_CTRL

       ; WR11 = $50 (RxC = BRG, TxC = BRG)
       LDA   #$0B
       STA   SCCA_CTRL
       LDA   #$50
       STA   SCCA_CTRL

       ; WR12 = $0A (baud rate lower - 9600 baud)
       LDA   #$0C
       STA   SCCA_CTRL
       LDA   #$0A
       STA   SCCA_CTRL

       ; WR13 = $00 (baud rate upper)
       LDA   #$0D
       STA   SCCA_CTRL
       LDA   #$00
       STA   SCCA_CTRL

       ; WR14 = $01 (BRG enable, NO loopback)
       LDA   #$0E
       STA   SCCA_CTRL
       LDA   #$01
       STA   SCCA_CTRL

       ; WR5 = $6A (TX 8 bits, TX enable, RTS)
       LDA   #$05
       STA   SCCA_CTRL
       LDA   #$6A
       STA   SCCA_CTRL

       ; WR3 = $C0 (RX 8 bits, RX NOT enabled on TX channel)
       LDA   #$03
       STA   SCCA_CTRL
       LDA   #$C0
       STA   SCCA_CTRL

       ; ===== Configure Channel B for RX =====
       ; WR4 = $44 (x16 clock, 1 stop bit, no parity - must match A)
       LDA   #$04
       STA   SCCB_CTRL
       LDA   #$44
       STA   SCCB_CTRL

       ; WR11 = $50 (RxC = BRG, TxC = BRG)
       LDA   #$0B
       STA   SCCB_CTRL
       LDA   #$50
       STA   SCCB_CTRL

       ; WR12 = $0A (baud rate lower - 9600 baud, must match A)
       LDA   #$0C
       STA   SCCB_CTRL
       LDA   #$0A
       STA   SCCB_CTRL

       ; WR13 = $00 (baud rate upper - must match A)
       LDA   #$0D
       STA   SCCB_CTRL
       LDA   #$00
       STA   SCCB_CTRL

       ; WR14 = $01 (BRG enable, NO loopback)
       LDA   #$0E
       STA   SCCB_CTRL
       LDA   #$01
       STA   SCCB_CTRL

       ; WR3 = $C1 (RX 8 bits, RX enable)
       LDA   #$03
       STA   SCCB_CTRL
       LDA   #$C1
       STA   SCCB_CTRL

       ; WR5 = $60 (TX 8 bits, TX NOT enabled on RX channel)
       LDA   #$05
       STA   SCCB_CTRL
       LDA   #$60
       STA   SCCB_CTRL

       ; ===== TEST 1: Send $55 on Channel A, receive on Channel B =====
       ; Display test header
       LDA   #$D4            ; 'T'
       STA   ROW0
       LDA   #$B1            ; '1'
       STA   ROW0+1
       LDA   #$BA            ; ':'
       STA   ROW0+2

       ; Transmit test byte $55 on Channel A
       LDA   #$55
       STA   SCCA_DATA

       ; Wait for TX to complete by polling Channel A RR0
WAIT_TX1
       LDA   SCCA_CTRL       ; Read RR0 channel A
       AND   #$04            ; TX buffer empty (bit 2)
       BEQ   WAIT_TX1

       ; Now wait for RX character on Channel B
       LDY   #$00            ; Timeout counter (outer)
       LDX   #$00            ; Timeout counter (inner)
WAIT_RX1
       LDA   SCCB_CTRL       ; Read RR0 channel B
       AND   #$01            ; RX char available (bit 0)
       BNE   RX1_READY

       INX
       BNE   WAIT_RX1
       INY
       CPY   #$10            ; ~4K iterations
       BNE   WAIT_RX1
       JMP   FAIL1           ; Timeout

RX1_READY
       ; Read received byte from Channel B
       LDA   SCCB_DATA       ; Read RX data
       CMP   #$55            ; Should match what we sent
       BEQ   :T1OK
       JMP   FAIL1
:T1OK

       ; TEST 1 PASS - show "P1" on screen
       LDA   #$D0            ; 'P'
       STA   ROW0+3
       LDA   #$B1            ; '1'
       STA   ROW0+4

       ; ===== TEST 2: Send $AA on Channel A, receive on Channel B =====
       LDA   #$D4            ; 'T'
       STA   ROW1
       LDA   #$B2            ; '2'
       STA   ROW1+1
       LDA   #$BA            ; ':'
       STA   ROW1+2

       ; Transmit $AA
       LDA   #$AA
       STA   SCCA_DATA

WAIT_TX2
       LDA   SCCA_CTRL
       AND   #$04
       BEQ   WAIT_TX2

       LDY   #$00
       LDX   #$00
WAIT_RX2
       LDA   SCCB_CTRL
       AND   #$01
       BNE   RX2_READY
       INX
       BNE   WAIT_RX2
       INY
       CPY   #$10
       BNE   WAIT_RX2
       JMP   FAIL2

RX2_READY
       LDA   SCCB_DATA
       CMP   #$AA
       BEQ   :T2OK
       JMP   FAIL2
:T2OK

       ; TEST 2 PASS
       LDA   #$D0            ; 'P'
       STA   ROW1+3
       LDA   #$B2            ; '2'
       STA   ROW1+4

       ; ===== TEST 3: Reverse direction - TX on B, RX on A =====
       ; Reconfigure: Enable TX on B, RX on A
       ; Channel B: enable TX
       LDA   #$05
       STA   SCCB_CTRL
       LDA   #$6A            ; TX 8 bits, TX enable, RTS
       STA   SCCB_CTRL

       ; Channel A: enable RX
       LDA   #$03
       STA   SCCA_CTRL
       LDA   #$C1            ; RX 8 bits, RX enable
       STA   SCCA_CTRL

       LDA   #$D4            ; 'T'
       STA   ROW2
       LDA   #$B3            ; '3'
       STA   ROW2+1
       LDA   #$BA            ; ':'
       STA   ROW2+2

       ; Transmit $42 ('B') on Channel B
       LDA   #$42
       STA   SCCB_DATA

WAIT_TX3
       LDA   SCCB_CTRL
       AND   #$04
       BEQ   WAIT_TX3

       LDY   #$00
       LDX   #$00
WAIT_RX3
       LDA   SCCA_CTRL
       AND   #$01
       BNE   RX3_READY
       INX
       BNE   WAIT_RX3
       INY
       CPY   #$10
       BNE   WAIT_RX3
       JMP   FAIL3

RX3_READY
       LDA   SCCA_DATA
       CMP   #$42
       BEQ   :T3OK
       JMP   FAIL3
:T3OK

       ; TEST 3 PASS
       LDA   #$D0            ; 'P'
       STA   ROW2+3
       LDA   #$B3            ; '3'
       STA   ROW2+4

       ; ===== ALL PASS =====
       LDA   #$D0            ; 'P'
       STA   ROW3
       LDA   #$C1            ; 'A'
       STA   ROW3+1
       LDA   #$D3            ; 'S'
       STA   ROW3+2
       LDA   #$D3            ; 'S'
       STA   ROW3+3
       JMP   *               ; Halt

       ; ===== FAIL handlers =====
FAIL1
       LDA   #$C6            ; 'F'
       STA   ROW0+3
       LDA   #$B1            ; '1'
       STA   ROW0+4
       JMP   DONE_FAIL

FAIL2
       LDA   #$C6            ; 'F'
       STA   ROW1+3
       LDA   #$B2            ; '2'
       STA   ROW1+4
       JMP   DONE_FAIL

FAIL3
       LDA   #$C6            ; 'F'
       STA   ROW2+3
       LDA   #$B3            ; '3'
       STA   ROW2+4

DONE_FAIL
       LDA   #$C6            ; 'F'
       STA   ROW3
       LDA   #$C1            ; 'A'
       STA   ROW3+1
       LDA   #$C9            ; 'I'
       STA   ROW3+2
       LDA   #$CC            ; 'L'
       STA   ROW3+3
       JMP   *               ; Halt
