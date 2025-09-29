;****************************************************************
;* C034_TIMING_TEST.S - Test C034 bank switching register
;* Tests if writing E0 to C034 immediately enables Bank E0 for SCC access
;*
;* Expected behavior:
;* 1. Write E0 to C034 register (bank control)
;* 2. Immediately try to read SCC register C038
;* 3. Should read from Bank E0 (I/O space), not ROM
;*
;* This isolates whether C034 register works properly in vsim
;****************************************************************

            ORG     $2000
            DSK     C034TEST.SYSTEM
            TYP     'SYS'
            MX      %11

start:
        sei           ; Disable interrupts

        ; Set up 16-bit mode
        clc
        xce           ; Clear emulation mode
        rep #$30      ; 16-bit A and X/Y

        ; Test sequence 1: Write E0 to C034 and immediately test
        lda #$E000    ; Load E0 into A (16-bit)
        sep #$20      ; Switch to 8-bit A for I/O

        ; Write E0 to C034 (bank control register)
        sta $C034     ; This should enable Bank E0 access

        ; Immediate test - read SCC register C038
        ; If C034 works properly, this should read from Bank E0 (I/O)
        ; If C034 fails, this will read from ROM bank
        lda $C038     ; Read SCC register
        sta $0300     ; Store result at $0300 for inspection

        ; Test sequence 2: Multiple C034 writes
        lda #$E0
        sta $C034     ; Write 1
        sta $C034     ; Write 2
        sta $C034     ; Write 3

        ; Test SCC access after multiple writes
        lda $C038
        sta $0301     ; Store result at $0301

        ; Test sequence 3: Delay test
        lda #$E0
        sta $C034     ; Write to C034

        ; Add some delay
        ldx #$1000
:delay  dex
        bne :delay

        ; Test SCC access after delay
        lda $C038
        sta $0302     ; Store result at $0302

        ; Test sequence 4: Read back C034 register
        lda $C034     ; Read current C034 value
        sta $0303     ; Store for verification

        ; Test sequence 5: Test other SCC registers
        lda #$E0
        sta $C034     ; Ensure E0 is set

        lda $C038     ; Read SCC register C038
        sta $0304
        lda $C039     ; Read SCC register C039
        sta $0305
        lda $C03A     ; Read SCC register C03A
        sta $0306
        lda $C03B     ; Read SCC register C03B
        sta $0307

        ; Test complete - infinite loop
:done   jmp :done

            END