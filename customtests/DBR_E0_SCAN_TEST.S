;****************************************************************
;* DBR_E0_SCAN_TEST.S
;* Compare SCC reads with DBR=FF vs DBR=E0 (PLB staging)
;* Prints a banner to the text screen and stores read bytes in RAM.
;* Usage: build via customtests/Makefile target dbr_e0_scan_test
;*        Run for <=150 frames with a final screenshot.
;****************************************************************

            ORG     $2000
            DSK     DBRE0.SYSTEM
            TYP     'SYS'
            MX      %11               ; 8-bit A and X/Y by default

HOME        EQU     $FC58             ; ROM monitor: clear screen/home cursor
COUT        EQU     $FDED             ; ROM monitor: output one char in A

START       JSR     HOME

            ; Print banner
            LDX     #0
PMSG        LDA     MSG,X
            BEQ     PHASE_FF
            JSR     COUT
            INX
            BNE     PMSG

; ------------------------------------------------------------
; Phase A: DBR = FF (expected: IO=0, memory/ROM values at C0xx)
; ------------------------------------------------------------
PHASE_FF    ; Enter native mode for PLB
            CLC
            XCE                     ; native
            SEP     #$20            ; 8-bit A for bank ops
            LDA     #$FF
            PHA
            PLB                     ; DBR <= FF

            ; Read SCC registers with DBR=FF
            LDA     $C038
            STA     $0300
            LDA     $C039
            STA     $0301
            LDA     $C03A
            STA     $0302
            LDA     $C03B
            STA     $0303

            ; Print indicator and the four bytes from $0300-$0303 as hex
            LDX     #0
PFF         LDA     MSG_FF,X
            BEQ     PFF_HEX
            JSR     COUT
            INX
            BNE     PFF

PFF_HEX     LDA     #$0D            ; newline
            JSR     COUT
            LDA     #'F'
            JSR     COUT
            LDA     #'F'
            JSR     COUT
            LDA     #':'
            JSR     COUT
            LDA     #' '
            JSR     COUT
            ; bytes $0300-$0303
            LDA     $0300
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0301
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0302
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0303
            JSR     PRINT_HEX

; ------------------------------------------------------------
; Phase B: DBR = E0 (expected: IO=1, SCC values at C0xx)
; ------------------------------------------------------------
PHASE_E0    LDA     #$E0
            PHA
            PLB                     ; DBR <= E0

            ; Read SCC registers with DBR=E0
            LDA     $C038
            STA     $0304
            LDA     $C039
            STA     $0305
            LDA     $C03A
            STA     $0306
            LDA     $C03B
            STA     $0307

            ; Print indicator and the four bytes from $0304-$0307 as hex
            LDX     #0
PE0         LDA     MSG_E0,X
            BEQ     PE0_HEX
            JSR     COUT
            INX
            BNE     PE0

PE0_HEX     LDA     #$0D            ; newline
            JSR     COUT
            LDA     #'E'
            JSR     COUT
            LDA     #'0'
            JSR     COUT
            LDA     #':'
            JSR     COUT
            LDA     #' '
            JSR     COUT
            ; bytes $0304-$0307
            LDA     $0304
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0305
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0306
            JSR     PRINT_HEX
            LDA     #' '
            JSR     COUT
            LDA     $0307
            JSR     PRINT_HEX

DONE        BRA     DONE            ; Sit here; limit frames externally

; Data
MSG         ASC     'DBR E0 SCAN TEST',0D,00
MSG_FF      ASC     'PHASE FF (DBR=FF)  ',0D,00
MSG_E0      ASC     'PHASE E0 (DBR=E0)  ',0D,00

; ------------------------------------------------------------
; PRINT_HEX: print A as two hex digits (uppercase)
; Trashes: A, X; preserves nothing (callers arrange)
; ------------------------------------------------------------
PRINT_HEX   PHA                     ; save original A
            LSR A                   ; move high nibble down
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            JSR     COUT
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            JSR     COUT
            RTS

HEXTAB      ASC     '0123456789ABCDEF'

            END     START
