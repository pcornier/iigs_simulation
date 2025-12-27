;
; MMU_TEST.S - Memory Management Unit Tests for Apple IIgs
;
; Tests memory mapping, shadowing, bank switching, and language card behavior.
; Based on gsquared MMU test suite.
;
; Each test shows its number and PASS/FAIL result on screen.
;
        ORG   $2000
        TYP   $06
        DSK   MMUTEST.SYSTEM

; Screen memory
SCREEN   EQU   $0400

; Softswitch addresses
RAMRD    EQU   $C003       ; Read aux memory
RAMWRT   EQU   $C005       ; Write aux memory
RAMRDOFF EQU   $C002       ; Read main memory
RAMWRTOFF EQU  $C004       ; Write main memory
NEWVIDEO EQU   $C029       ; New video register
SHADOW   EQU   $C035       ; Shadow register
CYAREG   EQU   $C036       ; CYA register (speed/shadow control)

; Language card switches
LCBANK2  EQU   $C082       ; Read ROM, write-protect LC bank 2
LCRAM2W  EQU   $C083       ; Read/write LC bank 2
LCBANK1  EQU   $C08A       ; Read ROM, write-protect LC bank 1
LCRAM1W  EQU   $C08B       ; Read/write LC bank 1

START
        ; Clear screen
        LDA   #$A0
        LDX   #$00
CLEAR   STA   SCREEN,X
        STA   SCREEN+$100,X
        STA   SCREEN+$200,X
        STA   SCREEN+$300,X
        INX
        BNE   CLEAR

        ; Display title
        LDX   #$00
TITLP   LDA   TITLE,X
        BEQ   SETUP
        STA   SCREEN,X
        INX
        JMP   TITLP

SETUP
        ; Switch to native mode with 8-bit registers
        CLC
        XCE
        SEP   #$30          ; 8-bit A, X, Y

        ; Initialize counters
        LDA   #$00
        STA   PASSCOUNT
        STA   FAILCOUNT
        STA   TESTNUM

        ; Initialize display position
        STA   $F2           ; TESTCOL = 0
        STA   $F3           ; TESTROW = 0

        ; Set Data Bank to $00
        LDA   #$00
        PHA
        PLB

        ; Start tests
        JMP   TEST01

;=============================================================================
; TEST 01: Normal text page video shadowing
; Write to 00/0400, should appear at E0/0400
;=============================================================================
TEST01
        INC   TESTNUM
        JSR   SHOWTEST

        ; Setup: NEWVIDEO=$01, SHADOW=$08, CYAREG=$84
        LDA   #$01
        STA   >$E0C029
        LDA   #$08
        STA   >$E0C035
        LDA   #$84
        STA   >$E0C036

        ; Write test pattern to bank 00
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401

        ; Verify it appears in bank E0
        LDA   >$E00400
        CMP   #$12
        BNE   TEST01_FAIL
        LDA   >$E00401
        CMP   #$34
        BNE   TEST01_FAIL

        JSR   SHOWPASS
        JMP   TEST02
TEST01_FAIL
        JSR   SHOWFAIL
        JMP   TEST02

;=============================================================================
; TEST 02: Text page 1 shadowing inhibited (SHADOW bit 0 set)
; With SHADOW=$09, text page shadowing should be disabled
;=============================================================================
TEST02
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear E0/0400 first
        LDA   #$00
        STA   >$E00400
        STA   >$E00401

        ; Setup: SHADOW=$09 (inhibit text page 1)
        LDA   #$01
        STA   >$E0C029
        LDA   #$09
        STA   >$E0C035
        LDA   #$84
        STA   >$E0C036

        ; Write to bank 00
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401

        ; E0 should still be $00 (not shadowed)
        LDA   >$E00400
        CMP   #$00
        BNE   TEST02_FAIL
        LDA   >$E00401
        CMP   #$00
        BNE   TEST02_FAIL

        ; Restore normal shadow
        LDA   #$08
        STA   >$E0C035

        JSR   SHOWPASS
        JMP   TEST03
TEST02_FAIL
        LDA   #$08
        STA   >$E0C035
        JSR   SHOWFAIL
        JMP   TEST03

;=============================================================================
; TEST 03: Shadow all banks copies data from any even bank to bank E0
;=============================================================================
TEST03
        INC   TESTNUM
        JSR   SHOWTEST

        ; Enable all-bank shadowing (CYAREG=$94)
        LDA   #$94
        STA   >$E0C036

        ; Write to banks 00 and 02
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401
        LDA   #$56
        STA   >$020402
        LDA   #$78
        STA   >$020403

        ; Disable all-bank shadowing
        LDA   #$84
        STA   >$E0C036

        ; Verify bank 02 data appears at E0
        LDA   >$E00402
        CMP   #$56
        BNE   TEST03_FAIL
        LDA   >$E00403
        CMP   #$78
        BNE   TEST03_FAIL

        JSR   SHOWPASS
        JMP   TEST04
TEST03_FAIL
        JSR   SHOWFAIL
        JMP   TEST04

;=============================================================================
; TEST 04: Shadow only copies data to video pages, not arbitrary addresses
;=============================================================================
TEST04
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear E0/6000 with known value
        LDA   #$FF
        STA   >$E06000
        STA   >$E06001

        ; Write to 00/6000 (not a video page)
        LDA   #$12
        STA   >$006000
        LDA   #$34
        STA   >$006001

        ; E0/6000 should still be $FF (not shadowed)
        LDA   >$E06000
        CMP   #$FF
        BNE   TEST04_FAIL
        LDA   >$E06001
        CMP   #$FF
        BNE   TEST04_FAIL

        JSR   SHOWPASS
        JMP   TEST05
TEST04_FAIL
        JSR   SHOWFAIL
        JMP   TEST05

;=============================================================================
; TEST 05: Write to text 1 with RAMWRT=1 shadowed to E1
;=============================================================================
TEST05
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear both E0 and E1 text page
        LDA   #$00
        STA   >$E00400
        STA   >$E00401
        STA   >$E10400
        STA   >$E10401

        ; Enable RAMWRT (write to aux)
        LDA   #$01
        STA   >$E0C005

        ; Write test pattern via bank 00 (goes to aux)
        LDA   #$56
        STA   >$000400
        LDA   #$78
        STA   >$000401

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; Verify E1 got the data
        LDA   >$E10400
        CMP   #$56
        BNE   TEST05_FAIL
        LDA   >$E10401
        CMP   #$78
        BNE   TEST05_FAIL

        ; Verify E0 is still 00
        LDA   >$E00400
        CMP   #$00
        BNE   TEST05_FAIL
        LDA   >$E00401
        CMP   #$00
        BNE   TEST05_FAIL

        JSR   SHOWPASS
        JMP   TEST06
TEST05_FAIL
        LDA   #$01
        STA   >$E0C004        ; Make sure RAMWRT is off
        JSR   SHOWFAIL
        JMP   TEST06

;=============================================================================
; TEST 06: Aux write (non-video) put in aux but not shadowed to E1
;=============================================================================
TEST06
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$016000
        STA   >$016001
        STA   >$E16000
        STA   >$E16001

        ; Enable RAMWRT
        LDA   #$01
        STA   >$E0C005

        ; Write to 00/6000 (non-video page, should go to bank 01)
        LDA   #$56
        STA   >$006000
        LDA   #$78
        STA   >$006001

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; E1/6000 should NOT be shadowed
        LDA   >$E16000
        CMP   #$00
        BNE   TEST06_FAIL
        LDA   >$E16001
        CMP   #$00
        BNE   TEST06_FAIL

        ; Bank 01/6000 should have the data
        LDA   >$016000
        CMP   #$56
        BNE   TEST06_FAIL
        LDA   >$016001
        CMP   #$78
        BNE   TEST06_FAIL

        JSR   SHOWPASS
        JMP   TEST07
TEST06_FAIL
        LDA   #$01
        STA   >$E0C004
        JSR   SHOWFAIL
        JMP   TEST07

;=============================================================================
; TEST 07: Bank 02 + RAMWRT + all-bank shadow - data goes to bank 03
;=============================================================================
TEST07
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$E16000
        STA   >$E16001
        STA   >$026000
        STA   >$026001
        STA   >$036000
        STA   >$036001

        ; Enable all-bank shadow
        LDA   #$94
        STA   >$E0C036

        ; Enable RAMWRT
        LDA   #$01
        STA   >$E0C005

        ; Write to 02/6000 (should go to 03 with RAMWRT)
        LDA   #$56
        STA   >$026000
        LDA   #$78
        STA   >$026001

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; Disable all-bank shadow
        LDA   #$84
        STA   >$E0C036

        ; E1 should NOT be shadowed (non-video page)
        LDA   >$E16000
        CMP   #$00
        BNE   TEST07_FAIL

        ; Bank 02 should still be 00
        LDA   >$026000
        CMP   #$00
        BNE   TEST07_FAIL

        ; Bank 03 should have data
        LDA   >$036000
        CMP   #$56
        BNE   TEST07_FAIL
        LDA   >$036001
        CMP   #$78
        BNE   TEST07_FAIL

        JSR   SHOWPASS
        JMP   TEST08
TEST07_FAIL
        LDA   #$01
        STA   >$E0C004
        LDA   #$84
        STA   >$E0C036
        JSR   SHOWFAIL
        JMP   TEST08

;=============================================================================
; TEST 08: Direct write to bank 01 text page shadowed to E1
;=============================================================================
TEST08
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear E1 text page
        LDA   #$00
        STA   >$E10400
        STA   >$E10401

        ; Write directly to bank 01 text page
        LDA   #$56
        STA   >$010400
        LDA   #$78
        STA   >$010401

        ; Verify E1 has the data
        LDA   >$E10400
        CMP   #$56
        BNE   TEST08_FAIL
        LDA   >$E10401
        CMP   #$78
        BNE   TEST08_FAIL

        JSR   SHOWPASS
        JMP   TEST09
TEST08_FAIL
        JSR   SHOWFAIL
        JMP   TEST09

;=============================================================================
; TEST 09: Write to bank 03 text page with all-bank shadow -> shadowed to E1
;=============================================================================
TEST09
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear E1 text page
        LDA   #$00
        STA   >$E10400
        STA   >$E10401

        ; Enable all-bank shadow
        LDA   #$94
        STA   >$E0C036

        ; Write to bank 03 text page
        LDA   #$56
        STA   >$030400
        LDA   #$78
        STA   >$030401

        ; Touch speaker to sync (original test did this)
        LDA   #$00
        STA   >$03C030

        ; Disable all-bank shadow
        LDA   #$84
        STA   >$E0C036

        ; Verify E1 has the data
        LDA   >$E10400
        CMP   #$56
        BNE   TEST09_FAIL
        LDA   >$E10401
        CMP   #$78
        BNE   TEST09_FAIL

        JSR   SHOWPASS
        JMP   TEST10
TEST09_FAIL
        LDA   #$84
        STA   >$E0C036
        JSR   SHOWFAIL
        JMP   TEST10

;=============================================================================
; TEST 10: IOLC inhibit disables access to CXXX in bank 0
;=============================================================================
TEST10
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test location
        LDA   #$00
        STA   >$E00500       ; Use $0500 to store result

        ; Enable IOLC inhibit (SHADOW=$68)
        LDA   #$68
        STA   >$E0C035

        ; Write to bank 00 CXXX area (should go to RAM, not I/O)
        LDA   #$12
        STA   >$00C010

        ; Read it back (should be RAM)
        LDA   >$00C010
        STA   >$E00500

        ; Restore normal shadow
        LDA   #$28
        STA   >$E0C035

        ; Verify we read back what we wrote
        LDA   >$E00500
        CMP   #$12
        BNE   TEST10_FAIL

        JSR   SHOWPASS
        JMP   TEST11
TEST10_FAIL
        LDA   #$28
        STA   >$E0C035
        JSR   SHOWFAIL
        JMP   TEST11

;=============================================================================
; TEST 11: There is normally no IOLC in bank 02
;=============================================================================
TEST11
        INC   TESTNUM
        JSR   SHOWTEST

        ; Write to bank 02 CXXX area (should be RAM)
        LDA   #$12
        STA   >$02C010

        ; Read it back
        LDA   >$02C010
        CMP   #$12
        BNE   TEST11_FAIL

        JSR   SHOWPASS
        JMP   TEST12
TEST11_FAIL
        JSR   SHOWFAIL
        JMP   TEST12

;=============================================================================
; TEST 12: There IS an IOLC in bank 02 with ALL BANK SHADOW enabled
;=============================================================================
TEST12
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear bank 02 CXXX
        LDA   #$00
        STA   >$02C010

        ; Enable all-bank shadow
        LDA   #$94
        STA   >$E0C036

        ; Write to bank 02 CXXX (should NOT be readable - goes to I/O)
        LDA   #$12
        STA   >$02C010

        ; Disable all-bank shadow
        LDA   #$84
        STA   >$E0C036

        ; Bank 02 CXXX should still be $00
        LDA   >$02C010
        CMP   #$00
        BNE   TEST12_FAIL

        JSR   SHOWPASS
        JMP   TEST13
TEST12_FAIL
        LDA   #$84
        STA   >$E0C036
        JSR   SHOWFAIL
        JMP   TEST13

;=============================================================================
; TEST 13: Bank latch disabled - write to E1 goes to E0 instead
;=============================================================================
TEST13
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear both locations
        LDA   #$00
        STA   >$E06000
        STA   >$E06001
        STA   >$E16000
        STA   >$E16001

        ; Disable bank latch (NEWVIDEO=$00)
        LDA   #$00
        STA   >$E0C029

        ; Write to E1/6000 - should actually go to E0
        LDA   #$12
        STA   >$E16000
        LDA   #$34
        STA   >$E16001

        ; Re-enable bank latch
        LDA   #$01
        STA   >$E0C029

        ; Verify E0 got the data
        LDA   >$E06000
        CMP   #$12
        BNE   TEST13_FAIL
        LDA   >$E06001
        CMP   #$34
        BNE   TEST13_FAIL

        ; Verify E1 is still 00
        LDA   >$E16000
        CMP   #$00
        BNE   TEST13_FAIL
        LDA   >$E16001
        CMP   #$00
        BNE   TEST13_FAIL

        JSR   SHOWPASS
        JMP   TEST14
TEST13_FAIL
        LDA   #$01
        STA   >$E0C029
        JSR   SHOWFAIL
        JMP   TEST14

;=============================================================================
; TEST 14: Bank latch disabled + RAMWRT - E0 write goes to E1
;=============================================================================
TEST14
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$E06100
        STA   >$E06101
        STA   >$E16100
        STA   >$E16101

        ; Disable bank latch
        LDA   #$00
        STA   >$E0C029

        ; Enable RAMWRT
        LDA   #$01
        STA   >$E0C005

        ; Write to E0/6100 - should go to E1 with RAMWRT
        LDA   #$12
        STA   >$E06100
        LDA   #$34
        STA   >$E06101

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; Re-enable bank latch
        LDA   #$01
        STA   >$E0C029

        ; Verify E0 is still 00
        LDA   >$E06100
        CMP   #$00
        BNE   TEST14_FAIL
        LDA   >$E06101
        CMP   #$00
        BNE   TEST14_FAIL

        ; Verify E1 got the data
        LDA   >$E16100
        CMP   #$12
        BNE   TEST14_FAIL
        LDA   >$E16101
        CMP   #$34
        BNE   TEST14_FAIL

        JSR   SHOWPASS
        JMP   TEST15
TEST14_FAIL
        LDA   #$01
        STA   >$E0C004
        LDA   #$01
        STA   >$E0C029
        JSR   SHOWFAIL
        JMP   TEST15

;=============================================================================
; TEST 15: Bank latch disabled + all-bank shadow - write 03 goes to 03
;=============================================================================
TEST15
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$026200
        STA   >$026201
        STA   >$036200
        STA   >$036201

        ; Enable all-bank shadow
        LDA   #$94
        STA   >$E0C036

        ; Disable bank latch
        LDA   #$00
        STA   >$E0C029

        ; Write to bank 03
        LDA   #$12
        STA   >$036200
        LDA   #$34
        STA   >$036201

        ; Re-enable bank latch
        LDA   #$01
        STA   >$E0C029

        ; Disable all-bank shadow
        LDA   #$84
        STA   >$E0C036

        ; Verify bank 02 is still 00
        LDA   >$026200
        CMP   #$00
        BNE   TEST15_FAIL
        LDA   >$026201
        CMP   #$00
        BNE   TEST15_FAIL

        ; Verify bank 03 got the data
        LDA   >$036200
        CMP   #$12
        BNE   TEST15_FAIL
        LDA   >$036201
        CMP   #$34
        BNE   TEST15_FAIL

        JSR   SHOWPASS
        JMP   TEST16
TEST15_FAIL
        LDA   #$01
        STA   >$E0C029
        LDA   #$84
        STA   >$E0C036
        JSR   SHOWFAIL
        JMP   TEST16

;=============================================================================
; TEST 16: IOLC inhibit does not disable IIe memory management (aux write)
;=============================================================================
TEST16
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$006400
        STA   >$006401
        STA   >$016400
        STA   >$016401
        STA   >$E06400
        STA   >$E06401
        STA   >$E16400
        STA   >$E16401

        ; Enable IOLC inhibit
        LDA   #$68
        STA   >$E0C035

        ; Enable RAMWRT
        LDA   #$01
        STA   >$E0C005

        ; Write via bank 00 (should go to bank 01)
        LDA   #$56
        STA   >$006400
        LDA   #$78
        STA   >$006401

        ; Also write via E0 (should go to E1)
        LDA   #$89
        STA   >$E06401

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; Disable IOLC inhibit
        LDA   #$28
        STA   >$E0C035

        ; Verify bank 00 is still 00
        LDA   >$006400
        CMP   #$00
        BNE   TEST16_FAIL
        LDA   >$006401
        CMP   #$00
        BNE   TEST16_FAIL

        ; Verify bank 01 got the data
        LDA   >$016400
        CMP   #$56
        BNE   TEST16_FAIL
        LDA   >$016401
        CMP   #$78
        BNE   TEST16_FAIL

        ; Verify E0 is still 00
        LDA   >$E06400
        CMP   #$00
        BNE   TEST16_FAIL
        LDA   >$E06401
        CMP   #$00
        BNE   TEST16_FAIL

        ; Verify E1 got the $89
        LDA   >$E16400
        CMP   #$00
        BNE   TEST16_FAIL
        LDA   >$E16401
        CMP   #$89
        BNE   TEST16_FAIL

        JSR   SHOWPASS
        JMP   TEST17
TEST16_FAIL
        LDA   #$01
        STA   >$E0C004
        LDA   #$28
        STA   >$E0C035
        JSR   SHOWFAIL
        JMP   TEST17

;=============================================================================
; TEST 17: RAMWRT has no effect in banks 02/03 without all-bank shadow
;=============================================================================
TEST17
        INC   TESTNUM
        JSR   SHOWTEST

        ; Clear test locations
        LDA   #$00
        STA   >$E16500
        STA   >$E16501
        STA   >$026500
        STA   >$026501
        STA   >$036500
        STA   >$036501

        ; Enable RAMWRT
        LDA   #$01
        STA   >$E0C005

        ; Write to bank 02 (should stay in 02, not go to 03)
        LDA   #$56
        STA   >$026500
        LDA   #$78
        STA   >$026501

        ; Disable RAMWRT
        LDA   #$01
        STA   >$E0C004

        ; Verify E1 is still 00
        LDA   >$E16500
        CMP   #$00
        BNE   TEST17_FAIL

        ; Verify bank 02 has the data
        LDA   >$026500
        CMP   #$56
        BNE   TEST17_FAIL
        LDA   >$026501
        CMP   #$78
        BNE   TEST17_FAIL

        ; Verify bank 03 is still 00
        LDA   >$036500
        CMP   #$00
        BNE   TEST17_FAIL

        JSR   SHOWPASS
        JMP   TEST18
TEST17_FAIL
        LDA   #$01
        STA   >$E0C004
        JSR   SHOWFAIL
        JMP   TEST18

;=============================================================================
; TEST 18: Language Card Bank 2 in bank $00
;=============================================================================
TEST18
        INC   TESTNUM
        JSR   SHOWTEST

        ; Enable LC read/write bank 2
        LDA   >$E0C082        ; Reset
        LDA   >$E0C083        ; Read RAM
        LDA   >$E0C083        ; Write RAM

        ; Write test pattern
        LDA   #$12
        STA   >$00D000
        LDA   #$34
        STA   >$00E000

        ; Read back and verify
        LDA   >$00D000
        CMP   #$12
        BNE   TEST18_FAIL
        LDA   >$00E000
        CMP   #$34
        BNE   TEST18_FAIL

        ; Restore ROM
        LDA   >$E0C082

        JSR   SHOWPASS
        JMP   TEST19
TEST18_FAIL
        LDA   >$E0C082
        JSR   SHOWFAIL
        JMP   TEST19

;=============================================================================
; TEST 19: Language Card Bank 2 in bank $E0
;=============================================================================
TEST19
        INC   TESTNUM
        JSR   SHOWTEST

        ; Enable LC read/write bank 2
        LDA   >$E0C082
        LDA   >$E0C083
        LDA   >$E0C083

        ; Write test pattern
        LDA   #$12
        STA   >$E0D000
        LDA   #$34
        STA   >$E0E000

        ; Read back and verify
        LDA   >$E0D000
        CMP   #$12
        BNE   TEST19_FAIL
        LDA   >$E0E000
        CMP   #$34
        BNE   TEST19_FAIL

        ; Restore ROM
        LDA   >$E0C082

        JSR   SHOWPASS
        JMP   TEST20
TEST19_FAIL
        LDA   >$E0C082
        JSR   SHOWFAIL
        JMP   TEST20

;=============================================================================
; TEST 20: LC Bank $00 does NOT shadow to $E0
;=============================================================================
TEST20
        INC   TESTNUM
        JSR   SHOWTEST

        ; Enable LC read/write bank 2
        LDA   >$E0C082
        LDA   >$E0C083
        LDA   >$E0C083

        ; Clear E0 first
        LDA   #$00
        STA   >$E0E000

        ; Write to 00
        LDA   #$34
        STA   >$00E000

        ; E0 should still be $00
        LDA   >$E0E000
        CMP   #$00
        BNE   TEST20_FAIL

        ; Restore ROM
        LDA   >$E0C082

        JSR   SHOWPASS
        JMP   TEST21
TEST20_FAIL
        LDA   >$E0C082
        JSR   SHOWFAIL
        JMP   TEST21

;=============================================================================
; TEST 21: LC Bank 1 write $D000, disable IOLC shadow, readable at $C000
;=============================================================================
TEST21
        INC   TESTNUM
        JSR   SHOWTEST

        ; Enable LC bank 1 read/write
        LDA   >$E0C08B
        LDA   >$E0C08B

        ; Write test pattern to LC bank 1
        LDA   #$12
        STA   >$00D000

        ; Switch to read ROM
        LDA   >$E0C08A

        ; Enable IOLC inhibit (exposes LC at C000-CFFF)
        LDA   #$68
        STA   >$E0C035

        ; Read from $C000 - should be LC bank 1
        LDA   >$00C000
        STA   >$E00502       ; Store result

        ; Disable IOLC inhibit
        LDA   #$28
        STA   >$E0C035

        ; Verify we read the test pattern
        LDA   >$E00502
        CMP   #$12
        BNE   TEST21_FAIL

        JSR   SHOWPASS
        JMP   TEST22
TEST21_FAIL
        LDA   #$28
        STA   >$E0C035
        JSR   SHOWFAIL
        JMP   TEST22

;=============================================================================
; TEST 22: ROM appears in bank FF
;=============================================================================
TEST22
        INC   TESTNUM
        JSR   SHOWTEST

        ; Check ROM signature at FF:D000
        LDA   >$FFD000
        CMP   #$6F          ; Expected ROM byte
        BNE   TEST22_FAIL

        ; Check another location
        LDA   >$FFE000
        CMP   #$4C          ; Expected ROM byte (JMP opcode)
        BNE   TEST22_FAIL

        JSR   SHOWPASS
        JMP   TEST23
TEST22_FAIL
        JSR   SHOWFAIL
        JMP   TEST23

;=============================================================================
; TEST 23: ROM appears in bank 00 (shadowed)
;=============================================================================
TEST23
        INC   TESTNUM
        JSR   SHOWTEST

        ; Make sure ROM is enabled (not LC)
        LDA   >$E0C082

        ; Check ROM at 00:D000
        LDA   >$00D000
        CMP   #$6F
        BNE   TEST23_FAIL

        ; Check ROM at 00:E000
        LDA   >$00E000
        CMP   #$4C
        BNE   TEST23_FAIL

        JSR   SHOWPASS
        JMP   TEST24
TEST23_FAIL
        JSR   SHOWFAIL
        JMP   TEST24

;=============================================================================
; TEST 24: C071-C07F are present when IOLC enabled
;=============================================================================
TEST24
        INC   TESTNUM
        JSR   SHOWTEST

        ; Read IOLC space bytes - these are ROM slot bytes
        ; Expected values are specific to the ROM version
        LDA   >$00C071
        CMP   #$E2
        BNE   TEST24_FAIL
        LDA   >$00C072
        CMP   #$40
        BNE   TEST24_FAIL
        LDA   >$00C073
        CMP   #$50
        BNE   TEST24_FAIL
        LDA   >$00C074
        CMP   #$B8
        BNE   TEST24_FAIL

        JSR   SHOWPASS
        JMP   TEST25
TEST24_FAIL
        JSR   SHOWFAIL
        JMP   TEST25

;=============================================================================
; TEST 25: Floating bus - RAM bank above real RAM reads as bank number
;=============================================================================
TEST25
        INC   TESTNUM
        JSR   SHOWTEST

        ; Read from bank 81 (beyond real RAM)
        LDA   >$810000
        CMP   #$81
        BNE   TEST25_FAIL

        ; Read from bank 82
        LDA   >$820000
        CMP   #$82
        BNE   TEST25_FAIL

        JSR   SHOWPASS
        JMP   TEST26
TEST25_FAIL
        JSR   SHOWFAIL
        JMP   TEST26

;=============================================================================
; TEST 26: LC switches work even with IOLC inhibit (shadow bit 6)
; This is critical for the ROM RAM address test which sets shadow=$7F
;=============================================================================
TEST26
        INC   TESTNUM
        JSR   SHOWTEST

        ; First, make sure ROM is enabled
        LDA   >$E0C082

        ; Enable IOLC inhibit (shadow=$7F - all bits set including bit 6)
        LDA   #$7F
        STA   >$E0C035

        ; Now access LC switch - this should STILL work!
        ; $C08B = Read/Write LC bank 1 (needs two reads)
        LDA   >$00C08B        ; First read
        LDA   >$00C08B        ; Second read enables write

        ; Write test pattern to LC area
        LDA   #$A5
        STA   >$00D000

        ; Read it back
        LDA   >$00D000
        STA   >$E00503        ; Store in known location

        ; Disable IOLC inhibit
        LDA   #$08
        STA   >$E0C035

        ; Restore ROM
        LDA   >$E0C082

        ; Verify we read back what we wrote
        LDA   >$E00503
        CMP   #$A5
        BNE   TEST26_FAIL

        JSR   SHOWPASS
        JMP   SUMMARY
TEST26_FAIL
        LDA   #$08
        STA   >$E0C035
        LDA   >$E0C082
        JSR   SHOWFAIL
        JMP   SUMMARY

;=============================================================================
; SUMMARY: Display pass/fail counts
;=============================================================================
SUMMARY
        ; Display checkboxes on line 2 (offset $80)
        LDA   #'['+$80
        STA   SCREEN+$80
        LDA   #'X'+$80
        STA   SCREEN+$81
        LDA   #']'+$80
        STA   SCREEN+$82
        LDA   #$A0           ; space
        STA   SCREEN+$83
        LDA   #'['+$80
        STA   SCREEN+$84
        LDA   #'X'+$80
        STA   SCREEN+$85
        LDA   #']'+$80
        STA   SCREEN+$86

        ; Display pass count on line 3 (offset $180)
        LDA   PASSCOUNT
        JSR   PRINTHEX
        STA   SCREEN+$180     ; High nibble
        STX   SCREEN+$181     ; Low nibble

        ; Display separator
        LDA   #'/'+$80
        STA   SCREEN+$182

        ; Display total (PASSCOUNT + FAILCOUNT)
        LDA   PASSCOUNT
        CLC
        ADC   FAILCOUNT
        JSR   PRINTHEX
        STA   SCREEN+$183
        STX   SCREEN+$184

        ; Check if all passed
        LDA   FAILCOUNT
        BNE   ALLDONE

        ; Display "*** ALL" on right of line 3
        LDX   #$00
ALLPLP  LDA   ALLPASS,X
        BEQ   ALLP2
        STA   SCREEN+$1A0,X
        INX
        JMP   ALLPLP

        ; Display "TESTS PASSED ***" on line 10 ($0528)
ALLP2   LDX   #$00
ALLP2LP LDA   ALLPASS2,X
        BEQ   ALLDONE
        STA   SCREEN+$128,X
        INX
        JMP   ALLP2LP

ALLDONE
        JMP   ALLDONE

;=============================================================================
; HELPER ROUTINES
;=============================================================================

; Zero page variables
SCRPOS   EQU   $F0        ; Current screen position (2 bytes)
TESTCOL  EQU   $F2        ; Current column (0-7)
TESTROW  EQU   $F3        ; Current row index into LINEADDR

; Apple II text screen line addresses
; Using lines 5-10 for test results display
LINEADDR
        DW    $0680       ; Line 5
        DW    $0700       ; Line 6
        DW    $0780       ; Line 7
        DW    $0428       ; Line 8
        DW    $04A8       ; Line 9
        DW    $0528       ; Line 10

; Display current test number
; Format: "NN:R " where NN is hex test number, R is result
SHOWTEST
        PHA
        PHX
        PHY

        ; Calculate screen position
        ; Column = (TESTCOL * 5)
        LDA   TESTCOL
        ASL               ; *2
        ASL               ; *4
        CLC
        ADC   TESTCOL     ; *5
        TAY               ; Y = column offset

        ; Get line address
        LDA   TESTROW
        ASL               ; *2 for word index
        TAX
        LDA   LINEADDR,X
        STA   SCRPOS
        LDA   LINEADDR+1,X
        STA   SCRPOS+1

        ; Display test number in hex
        LDA   TESTNUM
        JSR   PRINTHEX
        STA   (SCRPOS),Y   ; High nibble
        INY
        TXA
        STA   (SCRPOS),Y   ; Low nibble
        INY
        LDA   #':'+$80
        STA   (SCRPOS),Y   ; Colon

        ; Store result column
        INY
        STY   $F4          ; Save column for result

        PLY
        PLX
        PLA
        RTS

; Display PASS (shows 'P') and advance position
SHOWPASS
        PHA
        PHY
        INC   PASSCOUNT

        LDY   $F4          ; Get result column
        LDA   #'P'+$80
        STA   (SCRPOS),Y

        JSR   ADVANCEPOS

        PLY
        PLA
        RTS

; Display FAIL (shows 'F') and advance position
SHOWFAIL
        PHA
        PHY
        INC   FAILCOUNT

        LDY   $F4          ; Get result column
        LDA   #'F'+$80
        STA   (SCRPOS),Y

        JSR   ADVANCEPOS

        PLY
        PLA
        RTS

; Advance to next test position
ADVANCEPOS
        INC   TESTCOL
        LDA   TESTCOL
        CMP   #$08         ; 8 tests per line
        BCC   ADVDONE
        LDA   #$00
        STA   TESTCOL
        INC   TESTROW
ADVDONE
        RTS

; Print hex value in A
; Returns: A=high nibble char, X=low nibble char
PRINTHEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR   HEXCHAR
        STA   $10
        PLA
        AND   #$0F
        JSR   HEXCHAR
        TAX
        LDA   $10
        RTS

; Convert nibble to hex character (with high bit set for display)
HEXCHAR
        CMP   #$0A
        BCC   HEXDIGIT
        SEC
        SBC   #$09
        ORA   #$C0
        RTS
HEXDIGIT
        ORA   #$B0
        RTS

;=============================================================================
; DATA
;=============================================================================

TITLE
        ASC   "GSTEST - MEMORY MANAGEMENT TESTS"
        HEX   00

SUMMSG
        HEX   00

ALLPASS
        ASC   "*** ALL"
        HEX   00

ALLPASS2
        ASC   "TESTS PASSED ***"
        HEX   00

; Variables (in program memory)
TESTNUM  HEX   00
PASSCOUNT HEX  00
FAILCOUNT HEX  00

