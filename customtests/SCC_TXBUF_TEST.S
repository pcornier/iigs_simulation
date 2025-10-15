; SCC Transmit Buffer Test - Replicates ROM Test 06-01 behavior
; Tests that writing to transmit buffer causes Tx Buffer Empty bit to clear
;
; This test replicates what the ROM selftest actually does:
; 1. Initialize SCC for transmission
; 2. Write data to transmit buffer
; 3. Poll RR0 expecting bit 2 (Tx Buffer Empty) to clear
;
; Error codes match ROM format: AABBCCDD
;   AA = 06 (Test number)
;   BB = 01 (Subtest - Register R/W)
;   CCDD = Error details

        ORG   $2000
        TYP   $06            ; System file
        DSK   SCCTXBF.SYSTEM

START
        ; === Initialize SCC matching ROM test sequence ===

        ; Reset SCC - write to WR9 (register 9)
        LDA   #$09           ; Select WR9
        STA   $C039          ; Channel A control
        LDA   #$C0           ; Hardware reset command
        STA   $C039

        ; === CRITICAL TEST: Check RR0 immediately after reset ===
        ; The ROM expects RR0 to return 0x2C after hardware reset
        ; This tests that DCD and CTS latches are properly initialized

        ; Small delay to let hardware reset settle
        NOP
        NOP
        NOP
        NOP

        ; Read RR0 immediately after reset (before any other config)
        LDA   $C039          ; Read RR0 (register index is already 0)
        STA   $0808          ; Save post-reset RR0 value

        ; Expected value: 0x2C (bits 5,3,2 = DCD + CTS + Tx Empty)
        ; If latches aren't initialized, we might see 0x04 or 0x08
        CMP   #$2C
        BEQ   POST_RESET_OK  ; If 0x2C, continue
        JMP   FAIL_POST_RESET  ; If not 0x2C, test fails!

POST_RESET_OK

        ; Configure WR2 - interrupt vector
        LDA   #$02
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR10 - sync/encoding
        LDA   #$0A
        STA   $C039
        LDA   #$04
        STA   $C039

        ; Configure WR4 - clock/parity
        LDA   #$04
        STA   $C039
        LDA   #$44
        STA   $C039

        ; Configure WR1 - interrupts/DMA
        LDA   #$01
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR3 - receiver control
        LDA   #$03
        STA   $C039
        LDA   #$C0           ; Rx 8 bits
        STA   $C039

        ; Configure WR5 - transmitter control
        LDA   #$05
        STA   $C039
        LDA   #$6A           ; Tx enabled, 8 bits (matching ROM)
        STA   $C039

        ; Configure WR11 - clock mode
        LDA   #$0B
        STA   $C039
        LDA   #$D2
        STA   $C039

        ; Configure WR12 - baud rate low
        LDA   #$0C
        STA   $C039
        LDA   #$5E           ; Baud rate value from ROM
        STA   $C039

        ; Configure WR13 - baud rate high
        LDA   #$0D
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR14 - misc control
        LDA   #$0E
        STA   $C039
        LDA   #$00           ; No loopback
        STA   $C039

        ; Configure WR14 - enable BRG
        LDA   #$0E
        STA   $C039
        LDA   #$01           ; Enable BRG
        STA   $C039

        ; Configure WR15 - interrupt enables
        LDA   #$0F
        STA   $C039
        LDA   #$00
        STA   $C039

        ; === Now replicate the actual test sequence ===
        ; The ROM test writes data then polls RR0

        ; First check initial RR0 status
        LDA   $C039          ; Read RR0 (register index is already 0)
        STA   $0810          ; Save initial RR0 value

        ; Check if Tx Buffer Empty is set initially (bit 2)
        AND   #$04           ; Isolate bit 2
        BEQ   FAIL_INIT      ; Should be set initially

        ; Write test data to transmit buffer (like ROM does)
        LDA   #$AA           ; Test pattern
        STA   $C03B          ; Write to channel A data register

        ; Small delay to let hardware respond
        NOP
        NOP
        NOP
        NOP

        ; Now poll RR0 expecting Tx Buffer Empty (bit 2) to clear
        LDX   #$00           ; Poll counter
POLL_LOOP
        LDA   $C039          ; Read RR0
        STA   $0811,X        ; Save each read value for debug
        AND   #$04           ; Check bit 2 (Tx Buffer Empty)
        BEQ   TX_BUSY        ; If clear, transmitter is busy - good!

        INX
        CPX   #$A0           ; Poll up to 160 times like ROM
        BNE   POLL_LOOP

        ; If we get here, Tx Buffer Empty never cleared - test fails
        JMP   FAIL_TX_EMPTY

TX_BUSY
        ; Success! Tx Buffer Empty cleared as expected
        ; Now wait for it to set again (transmission complete)

        LDX   #$00
POLL_DONE
        LDA   $C039          ; Read RR0
        AND   #$04           ; Check bit 2
        BNE   TX_DONE        ; If set, transmission complete

        INX
        CPX   #$FF           ; Safety timeout
        BNE   POLL_DONE

        ; Timeout waiting for completion
        JMP   FAIL_TX_COMPLETE

TX_DONE
        ; Test passed - display success
        LDA   #$00
        STA   $0800          ; Clear error code
        LDA   #'P'
        STA   $0400
        LDA   #'A'
        STA   $0401
        LDA   #'S'
        STA   $0402
        LDA   #'S'
        STA   $0403

        ; Show how many polls before busy
        STX   $0820          ; Save poll count

DONE_LOOP
        JMP   DONE_LOOP      ; Stay here

FAIL_POST_RESET
        ; RR0 value wrong immediately after hardware reset
        ; This is the actual bug the ROM selftest detects!
        PHA                  ; Save actual RR0 value
        LDA   #$06
        STA   $0800          ; Test number
        LDA   #$01
        STA   $0801          ; Subtest
        LDA   #$FE           ; Error: Post-reset RR0 wrong
        STA   $0802
        PLA
        STA   $0803          ; Actual RR0 value (expected 0x2C)
        JMP   SHOW_FAIL

FAIL_INIT
        ; Initial state wrong - Tx Buffer should be empty
        LDA   #$06
        STA   $0800          ; Test number
        LDA   #$01
        STA   $0801          ; Subtest
        LDA   #$FF           ; Error: Initial state
        STA   $0802
        LDA   $0810          ; Initial RR0 value
        STA   $0803
        JMP   SHOW_FAIL

FAIL_TX_EMPTY
        ; Tx Buffer Empty never cleared after write
        LDA   #$06
        STA   $0800          ; Test number
        LDA   #$01
        STA   $0801          ; Subtest
        LDA   #$00           ; Error: Tx never busy (matches ROM)
        STA   $0802
        LDA   #$00
        STA   $0803
        JMP   SHOW_FAIL

FAIL_TX_COMPLETE
        ; Tx never completed
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$01           ; Error: Tx never complete
        STA   $0802
        STX   $0803          ; Timeout count
        JMP   SHOW_FAIL

SHOW_FAIL
        ; Display FAIL on screen
        LDA   #'F'
        STA   $0400
        LDA   #'A'
        STA   $0401
        LDA   #'I'
        STA   $0402
        LDA   #'L'
        STA   $0403

        ; Also show error code
        LDA   $0800
        JSR   PRHEX
        LDA   $0801
        JSR   PRHEX
        LDA   $0802
        JSR   PRHEX
        LDA   $0803
        JSR   PRHEX

FAIL_LOOP
        JMP   FAIL_LOOP      ; Stay here

; Print hex digit in A to screen at current position
PRHEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR   PRDIG
        PLA
        AND   #$0F
PRDIG
        ORA   #$B0           ; Convert to ASCII
        CMP   #$BA
        BCC   :1
        ADC   #$06           ; A-F adjustment
:1      STA   $0405,Y
        INY
        RTS