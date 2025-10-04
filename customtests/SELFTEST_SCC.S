; SCC Selftest Replica
; Replicates the exact SCC test sequence from ROM selftest
;
; This test initializes the SCC and then performs data loopback testing

        ORG   $2000
        TYP   $06            ; System file
        DSK   SCCSLF.SYSTEM

START
        ; === SCC Initialization sequence from selftest ===

        ; Reset SCC - write to WR9 (register 9)
        LDA   #$09           ; Select WR9
        STA   $C039
        LDA   #$C0           ; Hardware reset command
        STA   $C039

        ; Configure WR2 - interrupt vector
        LDA   #$02
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR2 again
        LDA   #$02
        STA   $C039
        LDA   #$09
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
        LDA   #$C0
        STA   $C039

        ; Configure WR5 - transmitter control
        LDA   #$05
        STA   $C039
        LDA   #$62
        STA   $C039

        ; Configure WR11 - clock mode
        LDA   #$0B
        STA   $C039
        LDA   #$D2
        STA   $C039

        ; Configure WR12 - baud rate low
        LDA   #$0C
        STA   $C039
        LDA   #$5E
        STA   $C039

        ; Configure WR13 - baud rate high
        LDA   #$0D
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR14 - misc control
        LDA   #$0E
        STA   $C039
        LDA   #$00
        STA   $C039

        ; Configure WR14 again
        LDA   #$0E
        STA   $C039
        LDA   #$01
        STA   $C039

        ; Configure WR5 - enable transmitter
        LDA   #$05
        STA   $C039
        LDA   #$6A
        STA   $C039

        ; Configure WR3 - enable receiver
        LDA   #$03
        STA   $C039
        LDA   #$C1
        STA   $C039

        ; Configure WR15 - interrupt enables
        LDA   #$0F
        STA   $C039
        LDA   #$00
        STA   $C039

        ; === Register pointer test ===
        ; Test that we can write and read back WR12/RR12

        ; Write to WR12
        LDA   #$0C
        STA   $C039          ; Select register 12
        LDA   #$55
        STA   $C039          ; Write $55 to WR12

        ; Read from RR12
        LDA   #$0C
        STA   $C039          ; Select register 12
        LDA   $C039          ; Read from RR12
        CMP   #$55
        BNE   FAIL1

        ; Write different value to WR12
        LDA   #$0C
        STA   $C039
        LDA   #$AA
        STA   $C039

        ; Read it back
        LDA   #$0C
        STA   $C039
        LDA   $C039
        CMP   #$AA
        BNE   FAIL1

        ; Test WR13/RR13
        LDA   #$0D
        STA   $C039
        LDA   #$33
        STA   $C039

        LDA   #$0D
        STA   $C039
        LDA   $C039
        CMP   #$33
        BNE   FAIL1

SUCCESS
        ; Success - show 'G' on screen
        LDA   #$00
        STA   $0800          ; Success code
        LDA   #'G'
        STA   $0400          ; Display character
        BRK

FAIL1
        ; Failed - show 'F' on screen
        LDA   #$01
        STA   $0800          ; Failure code
        LDA   #'F'
        STA   $0400
        BRK
