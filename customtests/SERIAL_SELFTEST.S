; Serial I/O Selftest Replica
; Extracted from clemens selftest execution at PC 6641-6649

        ORG $2000
        DSK SERIAL.SYSTEM
        TYP 'SYS'

START
        ; Clear screen and show test name
        LDA #$20        ; Space character
        LDX #$00
CLEAR_LOOP
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $0700,X
        INX
        BNE CLEAR_LOOP

        ; Display "SERIAL TEST"
        LDA #'S'
        STA $0400
        LDA #'E'
        STA $0401
        LDA #'R'
        STA $0402
        LDA #'I'
        STA $0403
        LDA #'A'
        STA $0404
        LDA #'L'
        STA $0405
        LDA #' '
        STA $0406
        LDA #'T'
        STA $0407
        LDA #'E'
        STA $0408
        LDA #'S'
        STA $0409
        LDA #'T'
        STA $040A

        ; DO NOT set DBR=E0 - we need to test the ROM execution case
        ; The real bug occurs when executing from ROM (PBR=FF) with DBR=00
        ; accessing SCC at Bank 00 + C039 (not E0 + C039)

        ; Replicate the actual selftest I/O register scan
        ; This is the sequence that causes DBR corruption

IO_SCAN_TEST
        ; Display test progress
        LDA #'1'
        STA $0428

        ; Start I/O register scan from C000 to C0FF like in trace
        LDX #$00        ; Start at C000

SCAN_LOOP
        ; The actual selftest instruction sequence:
        ASL $C046       ; 6641: 0E 46 C0 - Test shift register
        LDA $C061       ; 6644: AD 61 C0 - Read I/O location
        BCS CARRY_SET   ; 6647: B0 03    - Branch on carry
        AND $C062       ; 6649: 2D 62 C0 - AND operation
        JMP NEXT_REG

CARRY_SET
        ; Handle carry set case
        NOP

NEXT_REG
        ; Now read the current I/O register being tested
        ; This uses DBR which should be E0
        TXA
        CLC
        ADC #$C0        ; Convert X to C0xx address high byte
        STA TEST_ADDR+2
        STX TEST_ADDR+1

TEST_ADDR
        LDA $C000       ; This gets modified above - reads C000+X

        ; Store result somewhere for verification
        STA $0500,X

        ; Move to next register
        INX
        CPX #$100       ; Test C000-C0FF
        BNE SCAN_LOOP

        ; Test specific SCC registers like in the trace
        LDA #'2'
        STA $0429

SCC_TEST
        ; Test SCC registers C038-C03B (should use DBR=E0)
        LDA $C038       ; SCC Channel B Control
        STA $0520

        LDA $C039       ; SCC Channel A Control
        STA $0521

        LDA $C03A       ; SCC Channel B Data
        STA $0522

        LDA $C03B       ; SCC Channel A Data
        STA $0523

        ; Show completion
        LDA #'D'
        STA $0450
        LDA #'O'
        STA $0451
        LDA #'N'
        STA $0452
        LDA #'E'
        STA $0453

DONE
        JMP DONE        ; Infinite loop