; Comprehensive SCC Test Suite
; Based on ROM selftest requirements

        TYP   $06
        DSK   SCCFULL.SYSTEM
        ORG   $2000

; Test result codes
TEST_01_PASS    = $01
TEST_02_PASS    = $02
TEST_03_PASS    = $03
TEST_04_PASS    = $04
TEST_05_PASS    = $05
TEST_06_PASS    = $06
TEST_07_PASS    = $07
TEST_08_PASS    = $08

; Display location
SCREEN  = $0400

START
        SEI
        CLC
        XCE                   ; Native mode

        ; Clear screen
        LDX   #0
        LDA   #$A0            ; Space character
:CLEAR  STA   SCREEN,X
        STA   SCREEN+256,X
        INX
        BNE   :CLEAR

; ========================================
; TEST 01: Basic Register Access
; ========================================
TEST_01
        ; Write to WR0 to select WR4
        LDA   #$04
        STA   $C039
        ; Write to WR4
        LDA   #$44            ; x16 clock, 1 stop bit, no parity
        STA   $C039

        ; Read back via RR12 (mirrors WR12) - first select it
        LDA   #$0C
        STA   $C039
        LDA   $C039           ; Should read WR12 value (uninitialized)

        ; Mark test 01 passed
        LDA   #TEST_01_PASS
        STA   SCREEN

; ========================================
; TEST 02: Reset Commands
; ========================================
TEST_02
        ; Test channel reset
        LDA   #$09
        STA   $C039           ; Select WR9
        LDA   #$80            ; Channel A reset
        STA   $C039

        ; Check RR0 after reset (should be 2C with TX empty)
        LDA   $C039
        CMP   #$2C
        BNE   TEST_02_FAIL

        LDA   #TEST_02_PASS
        STA   SCREEN+1
        BRA   TEST_03

TEST_02_FAIL
        LDA   #$F2            ; 'F2'
        STA   SCREEN+1
        JMP   HALT

; ========================================
; TEST 03: BRG Setup
; ========================================
TEST_03
        ; Setup BRG like ROM test
        LDA   #$0C
        STA   $C039           ; Select WR12
        LDA   #$5E
        STA   $C039           ; WR12 = 5E

        LDA   #$0D
        STA   $C039           ; Select WR13
        LDA   #$00
        STA   $C039           ; WR13 = 00

        LDA   #$0E
        STA   $C039           ; Select WR14
        LDA   #$01
        STA   $C039           ; WR14 = 01 (BRG enable)

        LDA   #TEST_03_PASS
        STA   SCREEN+2

; ========================================
; TEST 04: TX/RX Enable
; ========================================
TEST_04
        ; Enable TX
        LDA   #$05
        STA   $C039           ; Select WR5
        LDA   #$6A            ; TX enable, 8 bits
        STA   $C039

        ; Enable RX
        LDA   #$03
        STA   $C039           ; Select WR3
        LDA   #$C1            ; RX enable, 8 bits
        STA   $C039

        LDA   #TEST_04_PASS
        STA   SCREEN+3

; ========================================
; TEST 05: Vector Setup
; ========================================
TEST_05
        ; Set interrupt vector
        LDA   #$02
        STA   $C039           ; Select WR2
        LDA   #$00            ; Vector base = 00
        STA   $C039

        ; Enable status affects vector
        LDA   #$09
        STA   $C039           ; Select WR9
        LDA   #$10            ; VIS=1 (Vector Includes Status)
        STA   $C039

        LDA   #TEST_05_PASS
        STA   SCREEN+4

; ========================================
; TEST 06: TX Empty Behavior (Critical)
; ========================================
TEST_06
        ; Setup exactly like ROM test
        LDA   #$04
        STA   $C039
        LDA   #$44            ; WR4 = 44
        STA   $C039

        LDA   #$0B
        STA   $C039
        LDA   #$D2            ; WR11 = D2
        STA   $C039

        LDA   #$0C
        STA   $C039
        LDA   #$5E            ; WR12 = 5E
        STA   $C039

        LDA   #$0D
        STA   $C039
        LDA   #$00            ; WR13 = 00
        STA   $C039

        LDA   #$0E
        STA   $C039
        LDA   #$01            ; WR14 = 01
        STA   $C039

        LDA   #$05
        STA   $C039
        LDA   #$6A            ; WR5 = 6A
        STA   $C039

        LDA   #$03
        STA   $C039
        LDA   #$C1            ; WR3 = C1
        STA   $C039

        ; Check initial RR0 (should be 2C)
        LDA   $C039
        CMP   #$2C
        BNE   TEST_06_FAIL_1

        ; Write test byte
        LDA   #$AA
        STA   $C03B           ; Write to ADATA

        ; Check that TX empty cleared (should be 28)
        LDA   $C039
        CMP   #$28
        BNE   TEST_06_FAIL_2

        ; Poll for TX complete - should take some time
        LDX   #$00
        LDY   #$00
:POLL   LDA   $C039
        CMP   #$2C            ; TX complete?
        BEQ   :TX_DONE
        INX
        BNE   :POLL
        INY
        BNE   :POLL
        ; Timeout
        BRA   TEST_06_FAIL_3

:TX_DONE
        ; Check that it took some time (X or Y should be non-zero)
        CPX   #$02
        BCC   TEST_06_FAIL_4  ; Too fast!

        LDA   #TEST_06_PASS
        STA   SCREEN+5
        BRA   TEST_07

TEST_06_FAIL_1
        LDA   #$61            ; '61'
        STA   SCREEN+5
        JMP   HALT

TEST_06_FAIL_2
        LDA   #$62            ; '62'
        STA   SCREEN+5
        JMP   HALT

TEST_06_FAIL_3
        LDA   #$63            ; '63'
        STA   SCREEN+5
        JMP   HALT

TEST_06_FAIL_4
        LDA   #$64            ; '64' - TX too fast!
        STA   SCREEN+5
        JMP   HALT

; ========================================
; TEST 07: Interrupt Status
; ========================================
TEST_07
        ; Enable TX interrupts
        LDA   #$01
        STA   $C039           ; Select WR1
        LDA   #$02            ; Enable TX interrupts
        STA   $C039

        ; Read RR3 (interrupt pending)
        LDA   #$03
        STA   $C039           ; Select RR3
        LDA   $C039
        ; Don't check value, just verify readable

        LDA   #TEST_07_PASS
        STA   SCREEN+6

; ========================================
; TEST 08: Channel B Basic
; ========================================
TEST_08
        ; Write to channel B control
        LDA   #$04
        STA   $C038           ; Channel B, select WR4
        LDA   #$44
        STA   $C038           ; Write data

        ; Read channel B RR0
        LDA   $C038
        ; Should have TX empty set
        AND   #$04
        BEQ   TEST_08_FAIL

        LDA   #TEST_08_PASS
        STA   SCREEN+7
        BRA   DONE

TEST_08_FAIL
        LDA   #$F8
        STA   SCREEN+7
        JMP   HALT

; ========================================
; All tests passed
; ========================================
DONE
        ; Display "PASS" message
        LDA   #$D0            ; 'P'
        STA   SCREEN+20
        LDA   #$C1            ; 'A'
        STA   SCREEN+21
        LDA   #$D3            ; 'S'
        STA   SCREEN+22
        STA   SCREEN+23

HALT
        JMP   *               ; Stop here