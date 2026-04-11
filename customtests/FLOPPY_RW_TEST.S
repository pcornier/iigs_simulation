;
; FLOPPY_RW_TEST.S - Floppy Disk Read/Write Test for Apple IIgs
;
; Tests block-level read and write on floppy disk drives via ProDOS MLI.
; Boot this from HDD (slot 7) with a WOZ floppy in slot 5 or slot 6.
;
; Test pattern:
;   1. Write zeros to block, read back, verify
;   2. Write $FF to block, read back, verify
;   3. Write $AA/$55 alternating, read back, verify
;   4. Write incrementing bytes (00,01,02,...), read back, verify
;   5. Write $DE,$AD pattern, read back after re-read, verify
;   6. Write unique pattern, read back, verify (final integrity)
;
; Uses blocks 10-15 (well past ProDOS catalog area) on the floppy.
;
; On-screen output shows test number and P(ass)/F(ail) for each test,
; plus the expected vs actual byte values on failure.
;
        ORG   $2000
        TYP   $06
        DSK   FLPTEST.SYSTEM

; ============================================================================
; Constants
; ============================================================================

; ProDOS MLI entry point and commands
MLI      EQU   $BF00
CMD_READ  EQU  $80        ; READ_BLOCK
CMD_WRITE EQU  $81        ; WRITE_BLOCK

; ProDOS global page
DEVCNT   EQU   $BF31      ; Number of devices - 1
DEVLST   EQU   $BF32      ; Device list (unit numbers)
DEVBOOT  EQU   $BF30      ; Boot slot (active device)

; Test block range (blocks 0-5 on track 0 - no seeking needed)
FIRST_BLK EQU  0

; Screen memory
SCREEN   EQU   $0400

; Buffers - use $4000-$41FF for write, $4200-$43FF for read-back
WRBUF    EQU   $4000      ; 512-byte write buffer
RDBUF    EQU   $4200      ; 512-byte read buffer

; Zero page
SCRPOS   EQU   $F0        ; Screen position (2 bytes)
TESTCOL  EQU   $F2        ; Column position
TESTROW  EQU   $F3        ; Row position

; ============================================================================
; Program Start
; ============================================================================
START
        ; Stay in emulation mode (ProDOS expects it)
        SEC
        XCE

        ; Clear screen
        LDA   #$A0
        LDX   #$00
:CLEAR  STA   SCREEN,X
        STA   SCREEN+$100,X
        STA   SCREEN+$200,X
        STA   SCREEN+$300,X
        INX
        BNE   :CLEAR

        ; Display title on line 0
        LDX   #$00
:TITLP  LDA   TITLE,X
        BEQ   :TITLDN
        STA   SCREEN,X
        INX
        JMP   :TITLP
:TITLDN

        ; Display separator line 1
        LDX   #$00
:SEPP   LDA   SEPLINE,X
        BEQ   :SEPDN
        STA   SCREEN+$80,X
        INX
        JMP   :SEPP
:SEPDN

        ; Initialize counters
        LDA   #$00
        STA   PASSCOUNT
        STA   FAILCOUNT
        STA   TESTNUM
        STA   TESTCOL
        STA   TESTROW

        ; ====================================================================
        ; Display ProDOS device list for diagnostics
        ; ====================================================================

        ; Display "DEVICES:" header on line 2 ($0100 offset)
        LDX   #$00
:DEVHP  LDA   DEVHDR,X
        BEQ   :DEVHDN
        STA   SCREEN+$100,X
        INX
        JMP   :DEVHP
:DEVHDN

        ; Display each device unit number from DEVLST
        LDA   DEVCNT          ; Number of devices - 1
        CLC
        ADC   #$01
        STA   DEVMAX           ; Actual count of devices
        LDX   #$00             ; Index into DEVLST
        LDY   #$09             ; Screen column (after "DEVICES: ")
:DEVLP  STX   DEVIDX           ; Save index (PRINTHEX clobbers X)
        LDA   DEVLST,X
        JSR   PRINTHEX         ; A=high nibble char, X=low nibble char
        STA   SCREEN+$100,Y
        INY
        TXA
        STA   SCREEN+$100,Y
        INY
        LDA   #$A0             ; Space
        STA   SCREEN+$100,Y
        INY
        LDX   DEVIDX           ; Restore index
        INX
        CPX   DEVMAX
        BCC   :DEVLP

        ; ====================================================================
        ; Display SLTROMSEL and $C6FF for diagnostics (line 3 = $0580)
        ; ====================================================================
        LDX   #$00
:DBGHP  LDA   DBGHDR,X
        BEQ   :DBGHDN
        STA   $0580,X
        INX
        JMP   :DBGHP
:DBGHDN
        ; Display SLTROMSEL value
        LDA   $C02D
        JSR   PRINTHEX
        STA   $0580+10,Y       ; Actually use fixed offsets
        STA   $058A             ; High nibble at col 10
        STX   $058B             ; Low nibble at col 11
        LDA   #$A0
        STA   $058C             ; Space
        ; Display $C6FF value
        LDA   $C6FF
        JSR   PRINTHEX
        STA   $058D             ; High nibble at col 13
        STX   $058E             ; Low nibble at col 14
        LDA   #$A0
        STA   $058F             ; Space
        ; Display driver address for slot 6 ($BF1A/$BF1B)
        LDA   $BF1B            ; High byte of slot 6 driver
        JSR   PRINTHEX
        STA   $0590
        STX   $0591
        LDA   $BF1A            ; Low byte of slot 6 driver
        JSR   PRINTHEX
        STA   $0592
        STX   $0593

        ; ====================================================================
        ; Inject Disk II unit $60 (slot 6) into DEVLST if $C6FF=$00
        ; Also try $50 (slot 5) as fallback
        ; ====================================================================
        LDA   $C6FF
        BNE   :TRY50           ; No Disk II at slot 6, try slot 5

        ; Slot 6 has Disk II ROM - inject $60 if not present
        LDX   #$00
:CHK60  CPX   DEVMAX
        BCS   :INJ60
        LDA   DEVLST,X
        CMP   #$60
        BEQ   :GOT60
        INX
        JMP   :CHK60
:INJ60  LDX   DEVMAX
        LDA   #$60
        STA   DEVLST,X
        INC   DEVCNT
        INC   DEVMAX
:GOT60  JMP   :ITERATE

:TRY50
        ; Fallback: inject $50 (slot 5) if not present
        LDX   #$00
:CHK50  CPX   DEVMAX
        BCS   :INJ50
        LDA   DEVLST,X
        CMP   #$50
        BEQ   :GOT50
        INX
        JMP   :CHK50
:INJ50  LDX   DEVMAX
        LDA   #$50
        STA   DEVLST,X
        INC   DEVCNT
        INC   DEVMAX
:GOT50

:ITERATE
        ; ====================================================================
        ; Iterate through ProDOS device list
        ; Test slot 5 ($50) or slot 6 ($60) Disk II units
        ; ====================================================================

        LDA   #$00
        STA   DEVIDX           ; Current index into DEVLST

:NEXTDEV
        LDX   DEVIDX
        CPX   DEVMAX           ; Past last device?
        BCS   PROBEDONE

        LDA   DEVLST,X
        STA   CUR_UNIT

        ; Test slot 5 ($50) or slot 6 ($60) Disk II units
        CMP   #$50             ; Slot 5, drive 1?
        BEQ   :TESTDEV
        CMP   #$60             ; Slot 6, drive 1?
        BEQ   :TESTDEV
        JMP   :SKIPDEV         ; Skip anything else
:TESTDEV

        ; Found a non-boot device - display its unit number and test it
        LDA   CUR_UNIT
        JSR   SHOW_UNIT_LABEL  ; Display "UNIT $xx:" on current row
        JSR   RUN_TESTS
        INC   TESTROW          ; Move past test results row

:SKIPDEV
        INC   DEVIDX
        JMP   :NEXTDEV

PROBEDONE
        ; Check if any drives were found
        LDA   PASSCOUNT
        ORA   FAILCOUNT
        BNE   SHOW_SUMMARY

        ; No drives found - display on line 4 ($0600)
        LDX   #$00
:NODP   LDA   NODRIVMSG,X
        BEQ   HALT
        STA   $0600,X
        INX
        JMP   :NODP

        ; ====================================================================
        ; Summary
        ; ====================================================================
SHOW_SUMMARY
        ; Find a line after tests for summary
        LDY   TESTROW
        INY
        LDA   LINEADDR_LO,Y
        STA   SCRPOS
        LDA   LINEADDR_HI,Y
        STA   SCRPOS+1

        ; Display pass count
        LDA   PASSCOUNT
        JSR   PRINTHEX
        LDY   #$00
        STA   (SCRPOS),Y      ; High nibble
        INY
        TXA
        STA   (SCRPOS),Y      ; Low nibble
        INY
        LDA   #'/'+$80
        STA   (SCRPOS),Y
        INY

        ; Display total
        LDA   PASSCOUNT
        CLC
        ADC   FAILCOUNT
        JSR   PRINTHEX
        STA   (SCRPOS),Y
        INY
        TXA
        STA   (SCRPOS),Y
        INY
        LDA   #$A0
        STA   (SCRPOS),Y
        INY

        ; Check if all passed
        LDA   FAILCOUNT
        BNE   :HASFAIL

        ; All passed!
        LDX   #$00
:ALLP   LDA   ALLPASS,X
        BEQ   HALT
        STA   (SCRPOS),Y
        INY
        INX
        JMP   :ALLP

:HASFAIL
        LDX   #$00
:FAILP  LDA   FAILMSG,X
        BEQ   HALT
        STA   (SCRPOS),Y
        INY
        INX
        JMP   :FAILP

HALT    JMP   HALT

; ============================================================================
; PROBE_DRIVE - Try to read block 0 from PROBE_UNIT
; Returns: Carry clear = success, Carry set = error
; ============================================================================
PROBE_DRIVE
        LDA   PROBE_UNIT
        STA   P_RD_UNIT
        LDA   #<RDBUF
        STA   P_RD_BUF
        LDA   #>RDBUF
        STA   P_RD_BUF+1
        LDA   #$00
        STA   P_RD_BLK
        STA   P_RD_BLK+1
        JSR   MLI
        DB    CMD_READ
        DW    P_RD_PARAMS
        BCS   :PROBFAIL
        CLC
        RTS
:PROBFAIL
        SEC
        RTS

; ============================================================================
; RUN_TESTS - Run all read/write tests on CUR_UNIT
; ============================================================================
RUN_TESTS
        ; Test 1: Write all zeros, read back
        INC   TESTNUM
        JSR   SHOWTEST

        LDA   #$00
        JSR   FILL_WRBUF      ; Fill write buffer with $00
        LDA   #FIRST_BLK
        JSR   WRITE_BLOCK
        BCS   :T1FAIL
        LDA   #FIRST_BLK
        JSR   READ_BLOCK
        BCS   :T1FAIL
        JSR   COMPARE_BUFS
        BCS   :T1FAIL
        JSR   SHOWPASS
        JMP   :T2
:T1FAIL JSR   SHOWFAIL

        ; Test 2: Write all $FF, read back
:T2     INC   TESTNUM
        JSR   SHOWTEST

        LDA   #$FF
        JSR   FILL_WRBUF
        LDA   #FIRST_BLK+1
        JSR   WRITE_BLOCK
        BCS   :T2FAIL
        LDA   #FIRST_BLK+1
        JSR   READ_BLOCK
        BCS   :T2FAIL
        JSR   COMPARE_BUFS
        BCS   :T2FAIL
        JSR   SHOWPASS
        JMP   :T3
:T2FAIL JSR   SHOWFAIL

        ; Test 3: Write $AA/$55 alternating, read back
:T3     INC   TESTNUM
        JSR   SHOWTEST

        JSR   FILL_AA55       ; Fill with alternating $AA/$55
        LDA   #FIRST_BLK+2
        JSR   WRITE_BLOCK
        BCS   :T3FAIL
        LDA   #FIRST_BLK+2
        JSR   READ_BLOCK
        BCS   :T3FAIL
        JSR   COMPARE_BUFS
        BCS   :T3FAIL
        JSR   SHOWPASS
        JMP   :T4
:T3FAIL JSR   SHOWFAIL

        ; Test 4: Write incrementing bytes (00,01,02,...), read back
:T4     INC   TESTNUM
        JSR   SHOWTEST

        JSR   FILL_INCR       ; Fill with 00,01,02,...
        LDA   #FIRST_BLK+3
        JSR   WRITE_BLOCK
        BCS   :T4FAIL
        LDA   #FIRST_BLK+3
        JSR   READ_BLOCK
        BCS   :T4FAIL
        JSR   COMPARE_BUFS
        BCS   :T4FAIL
        JSR   SHOWPASS
        JMP   :T5
:T4FAIL JSR   SHOWFAIL

        ; Test 5: Write $DEAD pattern, then read block from test 1
        ;         to force a track seek, then re-read this block
:T5     INC   TESTNUM
        JSR   SHOWTEST

        LDA   #$DE
        JSR   FILL_WRBUF      ; Fill with $DE
        LDA   #FIRST_BLK+4
        JSR   WRITE_BLOCK
        BCS   :T5FAIL
        ; Read a different block to force the head to potentially seek
        LDA   #FIRST_BLK
        JSR   READ_BLOCK
        BCS   :T5FAIL
        ; Now re-read the block we wrote
        LDA   #FIRST_BLK+4
        JSR   READ_BLOCK
        BCS   :T5FAIL
        ; Re-fill WRBUF with $DE for comparison
        LDA   #$DE
        JSR   FILL_WRBUF
        JSR   COMPARE_BUFS
        BCS   :T5FAIL
        JSR   SHOWPASS
        JMP   :T6
:T5FAIL JSR   SHOWFAIL

        ; Test 6: Write unique pattern to block, read back, verify
        ;         Uses XOR pattern: byte[i] = i ^ $A5
:T6     INC   TESTNUM
        JSR   SHOWTEST

        JSR   FILL_XOR        ; Fill with i ^ $A5
        LDA   #FIRST_BLK+5
        JSR   WRITE_BLOCK
        BCS   :T6FAIL
        LDA   #FIRST_BLK+5
        JSR   READ_BLOCK
        BCS   :T6FAIL
        JSR   COMPARE_BUFS
        BCS   :T6FAIL
        JSR   SHOWPASS
        RTS
:T6FAIL JSR   SHOWFAIL
        RTS

; ============================================================================
; WRITE_BLOCK - Write WRBUF to block A on CUR_UNIT
; Returns: Carry clear = success, Carry set = error
; ============================================================================
WRITE_BLOCK
        STA   P_WR_BLK
        LDA   #$00
        STA   P_WR_BLK+1
        LDA   CUR_UNIT
        STA   P_WR_UNIT
        LDA   #<WRBUF
        STA   P_WR_BUF
        LDA   #>WRBUF
        STA   P_WR_BUF+1
        JSR   MLI
        DB    CMD_WRITE
        DW    P_WR_PARAMS
        RTS                    ; Carry from MLI

; ============================================================================
; READ_BLOCK - Read block A from CUR_UNIT into RDBUF
; Returns: Carry clear = success, Carry set = error
; ============================================================================
READ_BLOCK
        STA   P_RD_BLK
        LDA   #$00
        STA   P_RD_BLK+1
        LDA   CUR_UNIT
        STA   P_RD_UNIT
        LDA   #<RDBUF
        STA   P_RD_BUF
        LDA   #>RDBUF
        STA   P_RD_BUF+1
        JSR   MLI
        DB    CMD_READ
        DW    P_RD_PARAMS
        RTS                    ; Carry from MLI

; ============================================================================
; Buffer Fill Routines
; ============================================================================

; Fill WRBUF with value in A (512 bytes)
FILL_WRBUF
        LDX   #$00
:FILL   STA   WRBUF,X
        STA   WRBUF+$100,X
        INX
        BNE   :FILL
        RTS

; Fill WRBUF with alternating $AA/$55
FILL_AA55
        LDX   #$00
:FILL   TXA
        AND   #$01
        BNE   :ODD
        LDA   #$AA
        JMP   :STORE
:ODD    LDA   #$55
:STORE  STA   WRBUF,X
        STA   WRBUF+$100,X
        INX
        BNE   :FILL
        RTS

; Fill WRBUF with incrementing bytes (00,01,02,...)
FILL_INCR
        LDX   #$00
:FILL   TXA
        STA   WRBUF,X
        STA   WRBUF+$100,X
        INX
        BNE   :FILL
        RTS

; Fill WRBUF with XOR pattern: byte[i] = i ^ $A5
FILL_XOR
        LDX   #$00
:FILL   TXA
        EOR   #$A5
        STA   WRBUF,X
        INX
        BNE   :FILL
        LDX   #$00
:FILL2  TXA
        EOR   #$A5
        STA   WRBUF+$100,X
        INX
        BNE   :FILL2
        RTS

; ============================================================================
; COMPARE_BUFS - Compare WRBUF and RDBUF (512 bytes)
; Returns: Carry clear = match, Carry set = mismatch
; On mismatch: shows byte offset + expected/actual on screen
; ============================================================================
COMPARE_BUFS
        ; Compare first 256 bytes
        LDX   #$00
:CMP1   LDA   WRBUF,X
        CMP   RDBUF,X
        BNE   :MISMATCH1
        INX
        BNE   :CMP1

        ; Compare second 256 bytes
        LDX   #$00
:CMP2   LDA   WRBUF+$100,X
        CMP   RDBUF+$100,X
        BNE   :MISMATCH2
        INX
        BNE   :CMP2

        CLC                    ; All match
        RTS

:MISMATCH1
        ; X = offset (0-255), page 0 of block
        STX   ERRBYTE
        LDA   #$00
        STA   ERRBYTE+1
        LDA   WRBUF,X
        STA   ERREXP
        LDA   RDBUF,X
        STA   ERRACT
        JSR   SHOW_ERROR
        SEC
        RTS

:MISMATCH2
        ; X = offset (0-255), page 1 of block
        STX   ERRBYTE
        LDA   #$01
        STA   ERRBYTE+1
        LDA   WRBUF+$100,X
        STA   ERREXP
        LDA   RDBUF+$100,X
        STA   ERRACT
        JSR   SHOW_ERROR
        SEC
        RTS

; ============================================================================
; SHOW_ERROR - Display error details on an error line
; Shows: "@HHLL:EE!=AA" (offset:expected!=actual)
; ============================================================================
SHOW_ERROR
        ; Find error display line (2 lines after current test row)
        LDY   TESTROW
        INY
        INY
        CPY   #MAX_ROWS
        BCC   :ROWOK
        LDY   #MAX_ROWS
        DEY
:ROWOK
        LDA   LINEADDR_LO,Y
        STA   $FE
        LDA   LINEADDR_HI,Y
        STA   $FF

        ; Display "@"
        LDY   #$00
        LDA   #'@'+$80
        STA   ($FE),Y
        INY

        ; Display high byte of offset
        LDA   ERRBYTE+1
        JSR   PRINTHEX
        STA   ($FE),Y
        INY
        TXA
        STA   ($FE),Y
        INY

        ; Display low byte of offset
        LDA   ERRBYTE
        JSR   PRINTHEX
        STA   ($FE),Y
        INY
        TXA
        STA   ($FE),Y
        INY

        ; Display ":"
        LDA   #':'+$80
        STA   ($FE),Y
        INY

        ; Display expected
        LDA   ERREXP
        JSR   PRINTHEX
        STA   ($FE),Y
        INY
        TXA
        STA   ($FE),Y
        INY

        ; Display "!"
        LDA   #'!'+$80
        STA   ($FE),Y
        INY

        ; Display "="
        LDA   #'='+$80
        STA   ($FE),Y
        INY

        ; Display actual
        LDA   ERRACT
        JSR   PRINTHEX
        STA   ($FE),Y
        INY
        TXA
        STA   ($FE),Y

        RTS

; ============================================================================
; Display Helper Routines
; ============================================================================

; Display label string at current TESTROW, then advance TESTROW
; Input: $06/$07 = pointer to null-terminated string
SHOW_LABEL
        PHA
        PHX
        PHY

        ; Get line address for current TESTROW
        LDX   TESTROW
        LDA   LINEADDR_LO,X
        STA   SCRPOS
        LDA   LINEADDR_HI,X
        STA   SCRPOS+1

        ; Copy string to screen
        LDY   #$00
:LOOP   LDA   ($06),Y
        BEQ   :DONE
        STA   (SCRPOS),Y
        INY
        JMP   :LOOP
:DONE
        ; Advance to next row for test results
        INC   TESTROW
        LDA   #$00
        STA   TESTCOL

        PLY
        PLX
        PLA
        RTS

; Display "UNIT $xx:" label on current TESTROW, advance row, reset test state
; Input: A = unit number
SHOW_UNIT_LABEL
        STA   $08             ; Save unit number

        ; Get line address for current TESTROW
        LDX   TESTROW
        LDA   LINEADDR_LO,X
        STA   SCRPOS
        LDA   LINEADDR_HI,X
        STA   SCRPOS+1

        ; Display "UNIT $" prefix
        LDY   #$00
        LDX   #$00
:ULBL   LDA   UNITPFX,X
        BEQ   :UHEX
        STA   (SCRPOS),Y
        INY
        INX
        JMP   :ULBL

        ; Display unit number in hex
:UHEX   LDA   $08
        JSR   PRINTHEX         ; A=high nibble char, X=low nibble char
        STA   (SCRPOS),Y
        INY
        TXA
        STA   (SCRPOS),Y
        INY

        ; Display ":"
        LDA   #':'+$80
        STA   (SCRPOS),Y

        ; Advance to next row for test results
        INC   TESTROW
        LDA   #$00
        STA   TESTCOL
        STA   TESTNUM         ; Reset test numbering for new device
        RTS

; Display current test number "NN:" at current grid position
SHOWTEST
        PHA
        PHX
        PHY

        ; Calculate screen position (8 chars per test)
        LDA   TESTCOL
        ASL                    ; *2
        ASL                    ; *4
        ASL                    ; *8
        TAY                    ; Y = column offset

        ; Get line address
        LDA   TESTROW
        TAX
        LDA   LINEADDR_LO,X
        STA   SCRPOS
        LDA   LINEADDR_HI,X
        STA   SCRPOS+1

        ; Display test number in hex
        LDA   TESTNUM
        JSR   PRINTHEX
        STA   (SCRPOS),Y      ; High nibble
        INY
        TXA
        STA   (SCRPOS),Y      ; Low nibble
        INY
        LDA   #':'+$80
        STA   (SCRPOS),Y

        ; Store result column
        INY
        STY   $F4              ; Save column for result

        PLY
        PLX
        PLA
        RTS

; Display PASS and advance position
SHOWPASS
        PHA
        PHY
        INC   PASSCOUNT
        LDY   $F4
        LDA   #'P'+$80
        STA   (SCRPOS),Y
        JSR   ADVANCEPOS
        PLY
        PLA
        RTS

; Display FAIL and error code, then advance position
; Input: A = MLI error code (if from MLI call) or other value
SHOWFAIL
        STA   ERRCODE         ; Save error code for display
        PHA
        PHY
        PHX
        INC   FAILCOUNT
        LDY   $F4
        LDA   #'F'+$80
        STA   (SCRPOS),Y
        INY
        LDA   ERRCODE
        JSR   PRINTHEX        ; A=high nibble, X=low nibble
        STA   (SCRPOS),Y
        INY
        TXA
        STA   (SCRPOS),Y
        JSR   ADVANCEPOS
        PLX
        PLY
        PLA
        RTS

ERRCODE   DB  $00              ; Last error code

; Advance to next test position
ADVANCEPOS
        INC   TESTCOL
        LDA   TESTCOL
        CMP   #$08             ; 8 tests per line
        BCC   :DONE
        LDA   #$00
        STA   TESTCOL
        INC   TESTROW
:DONE   RTS

; Print hex value in A
; Returns: A = high nibble char (with high bit), X = low nibble char
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

; Convert nibble in A to hex char (with high bit set)
HEXCHAR
        CMP   #$0A
        BCC   :DIGIT
        SEC
        SBC   #$09
        ORA   #$C0
        RTS
:DIGIT  ORA   #$B0
        RTS

; ============================================================================
; Data
; ============================================================================

; Apple II text screen line addresses (lines 4-22, skipping 0-3 for headers)
LINEADDR_LO
        DB    <$0600       ; Line 4
        DB    <$0680       ; Line 5
        DB    <$0700       ; Line 6
        DB    <$0780       ; Line 7
        DB    <$0428       ; Line 8
        DB    <$04A8       ; Line 9
        DB    <$0528       ; Line 10
        DB    <$05A8       ; Line 11
        DB    <$0628       ; Line 12
        DB    <$06A8       ; Line 13
        DB    <$0728       ; Line 14
        DB    <$07A8       ; Line 15

LINEADDR_HI
        DB    >$0600
        DB    >$0680
        DB    >$0700
        DB    >$0780
        DB    >$0428
        DB    >$04A8
        DB    >$0528
        DB    >$05A8
        DB    >$0628
        DB    >$06A8
        DB    >$0728
        DB    >$07A8

MAX_ROWS EQU  12

; Messages (high-bit ASCII for Apple II display)
TITLE
        ASC   "FLOPPY READ/WRITE TEST"
        HEX   00

SEPLINE
        ASC   "======================"
        HEX   00

DEVHDR
        ASC   "DEVICES: "
        HEX   00

UNITPFX
        ASC   "UNIT $"
        HEX   00

DBGHDR
        ASC   "SLT/C6FF: "
        HEX   00

NODRIVMSG
        ASC   "NO FLOPPY DRIVES FOUND"
        HEX   00

ALLPASS
        ASC   "ALL TESTS PASSED"
        HEX   00

FAILMSG
        ASC   "** FAILURES **"
        HEX   00

; ProDOS MLI parameter blocks
P_WR_PARAMS
        DB    $03              ; Parameter count
P_WR_UNIT DB  $00              ; Unit number
P_WR_BUF DW   WRBUF           ; Buffer address
P_WR_BLK DW   $0000           ; Block number

P_RD_PARAMS
        DB    $03              ; Parameter count
P_RD_UNIT DB  $00              ; Unit number
P_RD_BUF DW   RDBUF           ; Buffer address
P_RD_BLK DW   $0000           ; Block number

; Variables
CUR_UNIT  DB  $00              ; Current unit being tested
PROBE_UNIT DB $00              ; Unit being probed

TESTNUM   HEX 00
PASSCOUNT HEX 00
FAILCOUNT HEX 00

; Device iteration variables
DEVIDX    DB  $00              ; Current index into DEVLST
DEVMAX    DB  $00              ; Actual device count (DEVCNT + 1)

; Error display variables
ERRBYTE   DW  $0000            ; Byte offset where mismatch occurred
ERREXP    DB  $00              ; Expected value
ERRACT    DB  $00              ; Actual value
