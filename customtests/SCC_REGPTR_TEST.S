; SCC Register Pointer Test
; This test reproduces the selftest failure by testing the register pointer mechanism
;
; The SCC uses a two-step protocol:
; 1. Write register number to WR0 (control register)
; 2. Next read/write accesses that register
;
; This test writes countdown values to WR12 (baud rate low byte)
; and reads them back via the register pointer to verify it works

        ORG     $2000
        TYP     $06           ; System file
        DSK     SCCRPTR.SYSTEM

START
        ; Initialize - reset SCC
        LDA     #$09          ; WR0: select register 9
        STA     $C039         ; Channel A control

        LDA     #$C0          ; WR9: hardware reset
        STA     $C039         ; Channel A control

        ; Write countdown pattern to WR12 (baud rate low)
        ; and read it back to verify register pointer works

        LDX     #$FF          ; Start countdown
        LDY     #$00          ; Success counter

LOOP
        ; Write to WR12 (baud rate low byte)
        LDA     #$0C          ; WR0: select register 12
        STA     $C039         ; Channel A control

        TXA                   ; Get countdown value
        STA     $C039         ; Write to WR12

        ; Read back from WR12
        LDA     #$0C          ; WR0: select register 12
        STA     $C039         ; Channel A control

        LDA     $C039         ; Read from RR12 (should read back WR12)

        ; Compare with expected value
        CMP     $0900         ; Store read value for debug
        STA     $0900

        TXA                   ; Get expected value
        CMP     $0900         ; Compare
        BNE     FAIL          ; Branch if not equal

        INY                   ; Count success
        DEX                   ; Next countdown
        CPX     #$CE          ; Stop at $CF
        BCS     LOOP

        ; Success!
        LDA     #$00          ; Success code
        STA     $0800

        LDA     #'G'          ; Display 'G'
        STA     $0400

        BRK

FAIL
        ; Failed - store diagnostic info
        STX     $0800         ; Expected value

        LDA     $0900         ; Actual value read
        STA     $0801

        TYA                   ; Number of successes
        STA     $0802

        LDA     #'F'          ; Display 'F'
        STA     $0400

        BRK
