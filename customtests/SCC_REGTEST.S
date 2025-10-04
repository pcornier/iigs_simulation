; SCC Register Read/Write Test
; Simple test to debug SCC I/O access issue
; Tests if we can read/write SCC registers at $C038-$C03B from bank 00

        ORG $2000
        DSK SCCREG.SYSTEM
        TYP 'SYS'

START
        ; Clear screen
        LDA #$20        ; Space character
        LDX #$00
CLEAR_LOOP
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $0700,X
        INX
        BNE CLEAR_LOOP

        ; Display "SCC REG TEST"
        LDX #$00
TITLE_LOOP
        LDA TITLE_TEXT,X
        BEQ TITLE_DONE
        STA $0400,X
        INX
        JMP TITLE_LOOP
TITLE_DONE

        ; Test 1: Read SCC registers from bank 00
        ; This should trigger IO=1 since we're in bank 00, addr C038-C03B
        LDA #'1'
        STA $0428       ; Show test 1

        LDA $C038       ; Read SCC Channel B Control
        STA $0500       ; Store result at $0500

        LDA $C039       ; Read SCC Channel A Control
        STA $0501       ; Store result at $0501

        LDA $C03A       ; Read SCC Channel B Data
        STA $0502       ; Store result at $0502

        LDA $C03B       ; Read SCC Channel A Data
        STA $0503       ; Store result at $0503

        ; Test 2: Write to SCC registers
        LDA #'2'
        STA $0429       ; Show test 2

        LDA #$0B        ; Reset command
        STA $C039       ; Write to Channel A Control

        LDA #$D2        ; Some test value
        STA $C039       ; Write again

        ; Test 3: Read back and verify
        LDA #'3'
        STA $042A       ; Show test 3

        LDA $C039       ; Read Channel A Control
        STA $0504       ; Store at $0504

        ; Test 4: Try reading from different addresses to see pattern
        LDA #'4'
        STA $042B

        LDA $C038
        STA $0520
        LDA $C039
        STA $0521
        LDA $C03A
        STA $0522
        LDA $C03B
        STA $0523

        ; Display "DONE"
        LDA #'D'
        STA $0450
        LDA #'O'
        STA $0451
        LDA #'N'
        STA $0452
        LDA #'E'
        STA $0453

        ; Show what we read at positions that are easy to see
        ; Row 2 will show the values
        LDA $0500
        JSR PRINTHEX
        LDA $0501
        JSR PRINTHEX
        LDA $0502
        JSR PRINTHEX
        LDA $0503
        JSR PRINTHEX

DONE
        JMP DONE        ; Infinite loop

; Print hex value in A to screen
PRINTHEX
        PHA
        LSR A
        LSR A
        LSR A
        LSR A
        JSR PRINTNYB
        PLA
        AND #$0F
PRINTNYB
        CMP #$0A
        BCC IS_NUM
        ADC #$06
IS_NUM
        ADC #$30
        STA $0480,X
        INX
        RTS

TITLE_TEXT
        ASC "SCC REG TEST"
        HEX 00
