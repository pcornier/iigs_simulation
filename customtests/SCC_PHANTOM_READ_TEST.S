;****************************************************************
;* SCC_PHANTOM_READ_TEST.S - Test for phantom reads during STA to SCC
;* This test reproduces the phantom read bug where STA instructions
;* to SCC registers cause unwanted reads from ROM space
;****************************************************************

            ORG     $2000
            DSK     SCCTEST.SYSTEM
            TYP     'SYS'
            MX      %11

start:
         ; Visual indicator that test is running
         lda #'S'
         sta $0400       ; Write 'S' to screen
         lda #'C'
         sta $0401       ; Write 'C'
         lda #'C'
         sta $0402       ; Write 'C'
         lda #' '
         sta $0403       ; Space
         lda #'T'
         sta $0404       ; Write 'T'

         ; Test 1: Simple STA to C039 - should only write, no phantom read
         lda #$AA        ; Test pattern 1
         sta $C039       ; Write to SCC register - check trace for phantom reads

         ; Test 2: Another STA with different pattern
         lda #$55        ; Test pattern 2
         sta $C038       ; Write to different SCC register

         ; Test 3: STA to C03A
         lda #$FF        ; Test pattern 3
         sta $C03A       ; Write to SCC register A

         ; Test 4: STA to C03B
         lda #$00        ; Test pattern 4
         sta $C03B       ; Write to SCC register B

         ; Visual completion indicator
         lda #'D'
         sta $0428       ; Write 'D' to second line (test Done)
         lda #'O'
         sta $0429       ; Write 'O'
         lda #'N'
         sta $042A       ; Write 'N'
         lda #'E'
         sta $042B       ; Write 'E'

         ; Loop forever for easy trace analysis
:loop    nop
         nop
         jmp :loop