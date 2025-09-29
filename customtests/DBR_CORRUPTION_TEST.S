; DBR Corruption Test
; Tests which instruction corrupts DBR after PLB sets it to E1

        ORG $2000
        DSK DBRTEST.SYSTEM
        TYP 'SYS'

START
        ; Clear screen
        LDA #$20        ; Space character
        LDX #$00
CLEAR_LOOP
        STA $0400,X     ; Clear text page
        STA $0500,X
        STA $0600,X
        STA $0700,X
        INX
        BNE CLEAR_LOOP

        ; Display "DBR TEST"
        LDA #'D'
        STA $0400
        LDA #'B'
        STA $0401
        LDA #'R'
        STA $0402
        LDA #' '
        STA $0403
        LDA #'T'
        STA $0404
        LDA #'E'
        STA $0405
        LDA #'S'
        STA $0406
        LDA #'T'
        STA $0407

        ; Set DBR=E1 using PLB
        PEA $E1E1       ; Push E1 twice to stack
        PLB             ; Pull first E1 into B register
        PLB             ; Pull second E1 into B register

        ; Test 1: Verify DBR=E1 works initially
        LDA #'1'
        STA $0428       ; Display test number
        LDA #$AA        ; Test pattern
        STA $C039       ; Should go to E1:C039 if DBR=E1
        LDA $C039       ; Read it back
        CMP #$AA        ; Should match if DBR correct
        BEQ TEST1_OK
        ; Failed - show 'F'
        LDA #'F'
        STA $0429
        JMP TEST2
TEST1_OK
        LDA #'K'
        STA $0429

TEST2
        ; Test 2: Try NOP (should not affect DBR)
        LDA #'2'
        STA $042A
        NOP             ; <-- Test this instruction
        LDA #$55        ; Different test pattern
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$55        ; Should match if DBR still E1
        BEQ TEST2_OK
        LDA #'F'
        STA $042B
        JMP TEST3
TEST2_OK
        LDA #'K'
        STA $042B

TEST3
        ; Test 3: Try LDX immediate (common instruction)
        LDA #'3'
        STA $042C
        LDX #$10        ; <-- Test this instruction
        LDA #$77        ; Different test pattern
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$77        ; Should match if DBR still E1
        BEQ TEST3_OK
        LDA #'F'
        STA $042D
        JMP TEST4
TEST3_OK
        LDA #'K'
        STA $042D

TEST4
        ; Test 4: Try LDA immediate (very common)
        LDA #'4'
        STA $042E
        LDA #$99        ; <-- Test this instruction (loads A with $99)
        PHA             ; Save A
        LDA #$33        ; Different test pattern for SCC
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$33        ; Should match if DBR still E1
        BEQ TEST4_OK
        PLA             ; Restore stack
        LDA #'F'
        STA $042F
        JMP TEST5
TEST4_OK
        PLA             ; Restore stack
        LDA #'K'
        STA $042F

TEST5
        ; Test 5: Try CMP instruction
        LDA #'5'
        STA $0450       ; Next line
        LDA #$44        ; Test pattern
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$44        ; <-- Test this instruction (compare)
        BEQ TEST5_OK
        LDA #'F'
        STA $0451
        JMP TEST6
TEST5_OK
        LDA #'K'
        STA $0451

TEST6
        ; Test 6: Try branch instruction (BNE)
        LDA #'6'
        STA $0452
        LDA #$66        ; Test pattern
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$67        ; Compare with wrong value to force branch
        BNE TEST6_BRANCH  ; <-- Test this instruction (branch)
        JMP TEST6_FAIL
TEST6_BRANCH
        ; Branch taken, now check if DBR still works
        LDA #$88        ; New test pattern
        STA $C039       ; Should still go to E1:C039
        LDA $C039       ; Read it back
        CMP #$88        ; Should match if DBR still E1
        BEQ TEST6_OK
TEST6_FAIL
        LDA #'F'
        STA $0453
        JMP DONE
TEST6_OK
        LDA #'K'
        STA $0453

DONE
        ; Show "DONE"
        LDA #'D'
        STA $0478       ; Third line
        LDA #'O'
        STA $0479
        LDA #'N'
        STA $047A
        LDA #'E'
        STA $047B

LOOP    NOP
        JMP LOOP