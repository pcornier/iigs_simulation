;-------------------------------------------------------------------------------
; TIME.S - ProDOS 8 Compatible Time Display (Robust with Halt)
;-------------------------------------------------------------------------------

        ORG   $2000
        TYP   $06       ; File type $06 (BIN/SYS)
        DSK   TIME.SYSTEM

; Entry Point
START
        ; Force Emulation Mode (just in case)
        SEC             ; Set Carry
        XCE             ; Exchange Carry/Emulation (Switch to Emulation if in Native)
        
        JMP   MAIN

; Constants and Data
MLI_ENTRY EQU $BF00     ; ProDOS 8 MLI entry point
MLI_GET_TIME EQU $82    ; MLI call number for GET_TIME
COUT    EQU   $FDF0     ; Monitor COUT routine

; Zero Page Pointers
PTR     EQU   $06       ; Zero Page pointer for string printing (2 bytes)

MSG_START ASC "Program Start", $8D, $00
MSG_NO_CLOCK_DRIVER ASC "No clock driver found", $8D, $00
MSG_TIME  ASC "ProDOS 8 Time (Hex): ",00
MSG_DATE  ASC " Date (Hex): ",00
HEX_DIGITS ASC "0123456789ABCDEF"

;-------------------------------------------------------------------------------
; MLI Parameter Blocks
;-------------------------------------------------------------------------------
GT_PARAMS
        DB    0         ; Parameter count for GET_TIME is usually 0

;-------------------------------------------------------------------------------
; Main Program
;-------------------------------------------------------------------------------
MAIN
        ; Print start message
        LDX   #<MSG_START
        LDA   #>MSG_START
        JSR   PUTS

        ; 1. Call GET_TIME
        ;    MLI call number in A, address of parameter list in X
        LDA   #MLI_GET_TIME
        LDX   #<GT_PARAMS
        JSR   MLI_ENTRY
        BCS   NO_CLOCK_DRIVER ; Branch if error (Carry Set) - no clock driver

        ; 2. Display Label
        LDX   #<MSG_TIME
        LDA   #>MSG_TIME
        JSR   PUTS

        ; 3. Display Time (Hours:Minutes) from $BF90-$BF93
        LDA   $BF93     ; Hours
        JSR   PRBYTE
        LDA   #':'
        JSR   COUT
        LDA   $BF92     ; Minutes
        JSR   PRBYTE
        
        ; 4. Display Date Label
        LDX   #<MSG_DATE
        LDA   #>MSG_DATE
        JSR   PUTS

        ; 5. Display Date (Month/Day/Year)
        LDA   $BF91     ; Month(hi)/Year
        JSR   PRBYTE
        LDA   $BF90     ; Day/Month(lo)
        JSR   PRBYTE

        JMP   FINISH_DISPLAY

NO_CLOCK_DRIVER
        LDX   #<MSG_NO_CLOCK_DRIVER
        LDA   #>MSG_NO_CLOCK_DRIVER
        JSR   PUTS

FINISH_DISPLAY
        ; 6. Newline
        LDA   #$8D
        JSR   COUT
        
        ; Halt program (instead of MLI Quit, which crashes emulator)
HALT
        JMP   HALT

;-------------------------------------------------------------------------------
; Subroutines
;-------------------------------------------------------------------------------

; PUTS: Print null-terminated string at A(hi), X(lo)
PUTS
        PHA
        PHX
        STA   PTR+1     ; Store high byte of address
        STX   PTR       ; Store low byte of address (PTR in Zero Page)
        LDY   #0        ; Initialize index
PUTS_LOOP
        LDA   (PTR),Y   ; Load character indirectly from Zero Page pointer
        BEQ   PUTS_DONE
        JSR   COUT
        INY
        BNE   PUTS_LOOP
PUTS_DONE
        PLX
        PLA
        RTS

; PRBYTE: Print byte in A as two hex digits
PRBYTE
        PHA             ; Save original byte
        LSR             ; Shift top nibble down
        LSR
        LSR
        LSR
        TAX
        LDA   HEX_DIGITS,X
        JSR   COUT
        PLA             ; Restore byte
        AND   #$0F      ; Mask bottom nibble
        TAX
        LDA   HEX_DIGITS,X
        JSR   COUT
        RTS