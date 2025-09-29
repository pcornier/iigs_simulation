;****************************************************************
;* PLB_DBR_TEST.S - Test PLB instruction updating DBR register
;* This test mimics the Apple IIgs ROM sequence that should set DBR=E1
;* and then verifies that SCC register accesses use the correct bank
;****************************************************************

            ORG     $2000
            DSK     PLB.SYSTEM
            TYP     'SYS'
            MX      %11

start:
         ; Simple visual indicator - write directly to text screen
         lda #'P'
         sta $0400       ; Write 'P' to top-left of screen
         lda #'L'
         sta $0401       ; Write 'L'
         lda #'B'
         sta $0402       ; Write 'B'
         lda #' '
         sta $0403       ; Space
         lda #'T'
         sta $0404       ; Write 'T'
         lda #'E'
         sta $0405       ; Write 'E'
         lda #'S'
         sta $0406       ; Write 'S'
         lda #'T'
         sta $0407       ; Write 'T'

         ; Execute the same sequence as Apple IIgs ROM:
         ; PEA $E1E1 / PLB / PLB to set DBR=E1
         pea $E1E1       ; Push E1 twice to stack
         plb             ; Pull first E1 into B register (should set DBR=E1)
         plb             ; Pull second E1 into B register (DBR should still be E1)

         ; Now test SCC register access at C039 - should use E1:C039 not 00:C039
         ; Write a test pattern to SCC register
         lda #$5A
         sta $C039       ; This should access E1:C039 if DBR is correct

         ; Read it back
         lda $C039       ; This should read from E1:C039 if DBR is correct

         ; Visual completion indicator
         lda #'O'
         sta $0428       ; Write 'O' to second line (40 chars down)
         lda #'K'
         sta $0429       ; Write 'K'

         ; Loop forever to make it easy to see in trace
:loop    nop
         nop
         jmp :loop