; SCC Selftest Replica - Test 06 Subtest 01
; Replicates the ROM selftest Register R/W test
;
; According to the ROM selftest documentation:
; Test 06: Serial I/O (Internal Loopback)
;   BB=01: Register R/W - tests WR12/WR13 (baud rate registers)
;          These are the only write registers readable on the 8530
;
; Error code format: AABBCCDD where:
;   AA = 06 (Test number)
;   BB = 01 (Subtest - Register R/W)
;   CCDD = Error details

        ORG   $2000
        TYP   $06            ; System file
        DSK   SCCSLF.SYSTEM

START
        ; === SCC Initialization sequence from selftest ===
        ; This matches the ROM selftest initialization

        ; Reset SCC - write to WR9 (register 9)
        LDA   #$09           ; Select WR9
        STA   $C039          ; Channel A control
        LDA   #$C0           ; Hardware reset command
        STA   $C039

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
        LDA   #$C0           ; Rx disabled initially
        STA   $C039

        ; Configure WR5 - transmitter control
        LDA   #$05
        STA   $C039
        LDA   #$62           ; Tx disabled initially
        STA   $C039

        ; Configure WR11 - clock mode
        LDA   #$0B
        STA   $C039
        LDA   #$D2
        STA   $C039

        ; Configure WR12 - baud rate low (set to known value)
        LDA   #$0C
        STA   $C039
        LDA   #$5E           ; Initial baud rate
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

        ; === Test 06-01: Register R/W Test ===
        ; Test WR12/RR12 (baud rate low byte)
        ; ROM test pattern: write value, read back, write pointer to 0, repeat
        ; Note: Reading a register does NOT reset pointer, only writing does

        ; Test pattern 1: Write $55 to WR12
        LDA   #$0C           ; Select WR12
        STA   $C039
        LDA   #$55           ; Test pattern $55
        STA   $C039          ; Write to WR12 (this resets pointer to 0)

        ; Read back RR12
        LDA   #$0C           ; Select RR12 (pointer is 0, so this selects reg 12)
        STA   $C039
        LDA   $C039          ; Read RR12 (pointer stays at 12 after read)
        CMP   #$55
        BEQ   T55_OK
        JMP   FAIL_55        ; Jump if doesn't match
T55_OK

        ; Test pattern 2: Write $AA to WR12
        ; Pointer is still at 12 from previous read, so just write the value
        LDA   #$AA           ; Test pattern $AA
        STA   $C039          ; Write to WR12 (pointer was still 12, now resets to 0)

        ; Read back RR12
        LDA   #$0C           ; Select RR12
        STA   $C039
        LDA   $C039          ; Read RR12
        CMP   #$AA
        BEQ   TAA_OK
        JMP   FAIL_AA
TAA_OK

        ; Test pattern 3: Write $FF to WR12
        LDA   #$FF           ; Pointer still at 12
        STA   $C039

        ; Read back RR12
        LDA   #$0C
        STA   $C039
        LDA   $C039
        CMP   #$FF
        BEQ   TFF_OK
        JMP   FAIL_FF
TFF_OK

        ; Test pattern 4: Write $00 to WR12
        LDA   #$00           ; Pointer still at 12
        STA   $C039

        ; Read back RR12
        LDA   #$0C
        STA   $C039
        LDA   $C039
        CMP   #$00
        BEQ   T00_OK
        JMP   FAIL_00
T00_OK

        ; Test WR13/RR13 (baud rate high byte)
        ; Reset pointer first since it's still at 12
        LDA   #$00           ; Write 0 to WR12 to reset pointer
        STA   $C039

        ; Test pattern 1: $33
        LDA   #$0D           ; Select WR13
        STA   $C039
        LDA   #$33
        STA   $C039          ; Write to WR13 (resets pointer)

        LDA   #$0D           ; Select RR13
        STA   $C039
        LDA   $C039          ; Read RR13 (pointer stays at 13)
        CMP   #$33
        BEQ   T33_OK
        JMP   FAIL_WR13
T33_OK

        ; Test pattern 2: $CC
        LDA   #$CC           ; Pointer still at 13
        STA   $C039

        LDA   #$0D           ; Select RR13
        STA   $C039
        LDA   $C039
        CMP   #$CC
        BEQ   TCC_OK
        JMP   FAIL_WR13
TCC_OK

SUCCESS
        ; Success - show 'G' on screen
        LDA   #$00
        STA   $0800          ; Success code
        LDA   #'G'
        STA   $0400          ; Display 'G'
        LDA   #'O'
        STA   $0401
        LDA   #'O'
        STA   $0402
        LDA   #'D'
        STA   $0403

        ; ===== Additional SCC sanity checks (to mirror ROM serial selftest) =====
        ; 1) RR0 value immediately after hardware reset should be $2C
        ; 2) Writing ADATA (WR8) should clear TX EMPTY (RR0 bit2) then set it again

        ; Re-issue hardware reset so RR0 is observed from a known state
        LDA   #$09           ; Select WR9
        STA   $C039
        LDA   #$C0           ; Hardware reset
        STA   $C039

        ; Small delay
        NOP
        NOP
        NOP
        NOP

        ; Read RR0 right after reset
        LDA   $C039
        STA   $0808          ; Save for debug
        CMP   #$2C
        BEQ   :post_reset_ok
        JMP   FAIL_POST_RESET
:post_reset_ok

        ; Minimal enable like ROM: WR5 (TX enable, 8 bits), WR1 off, clocks already set
        LDA   #$05
        STA   $C039
        LDA   #$6A           ; Tx enable, DTR=1, 8 bits
        STA   $C039

        ; Confirm TX EMPTY initially set
        LDA   $C039
        AND   #$04
        BNE   :tx_empty_initial_ok
        JMP   FAIL_INIT
:tx_empty_initial_ok

        ; Write a byte to ADATA (WR8) and expect TX EMPTY to clear
        LDA   #$AA
        STA   $C03B

        ; Poll RR0 for TX EMPTY clear (bit2 = 0)
        LDX   #$00
:poll_busy
        LDA   $C039
        AND   #$04
        BEQ   :tx_busy
        INX
        CPX   #$A0
        BNE   :poll_busy
        JMP   FAIL_TX_EMPTY
:tx_busy

        ; Now poll for TX EMPTY set again (transmission complete)
        LDX   #$00
:poll_done
        LDA   $C039
        AND   #$04
        BNE   :tx_done
        INX
        CPX   #$FF
        BNE   :poll_done
        JMP   FAIL_TX_COMPLETE
:tx_done

        BRK

FAIL_55
        ; Failed on $55 pattern
        LDA   #$06
        STA   $0800          ; Test number
        LDA   #$01
        STA   $0801          ; Subtest
        LDA   #$55
        STA   $0802          ; Expected value
        ; Actual value is in A
        STA   $0803
        BRA   SHOW_FAIL

FAIL_AA
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$AA
        STA   $0802
        LDA   $C039          ; Re-read to get actual
        STA   $0803
        BRA   SHOW_FAIL

FAIL_FF
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$FF
        STA   $0802
        LDA   $C039
        STA   $0803
        BRA   SHOW_FAIL

FAIL_00
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$00
        STA   $0802
        LDA   $C039
        STA   $0803
        BRA   SHOW_FAIL

FAIL_WR13
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$13           ; Indicate WR13 failure
        STA   $0802
        ; A still has the read value
        STA   $0803
        BRA   SHOW_FAIL

SHOW_FAIL
        ; Display 'F' on screen
        LDA   #'F'
        STA   $0400
        LDA   #'A'
        STA   $0401
        LDA   #'I'
        STA   $0402
        LDA   #'L'
        STA   $0403
        BRK

; Additional failure codes for extended checks
FAIL_POST_RESET
        ; RR0 value wrong immediately after hardware reset
        ; Use the same AA/BB as 06/01 and two data bytes FE,<RR0>
        PHA
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$FE
        STA   $0802
        PLA
        STA   $0803
        JMP   SHOW_FAIL

FAIL_INIT
        ; Initial RR0 did not have TX EMPTY set
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$FF
        STA   $0802
        LDA   $C039
        STA   $0803
        JMP   SHOW_FAIL

FAIL_TX_EMPTY
        ; TX EMPTY never cleared after ADATA write
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$00
        STA   $0802
        LDA   #$00
        STA   $0803
        JMP   SHOW_FAIL

FAIL_TX_COMPLETE
        ; TX never completed (EMPTY never set again)
        LDA   #$06
        STA   $0800
        LDA   #$01
        STA   $0801
        LDA   #$01
        STA   $0802
        STX   $0803
        JMP   SHOW_FAIL
