;****************************************************************
;* DBR_PLB_STAGE_SCAN_TEST.S (ROM-free version)
;* Goal: Exercise PLB -> DBR update cleanly without any ROM calls.
;* - Phase 1: Ensure DBR=FF, read SCC regs to $0300-$0303 and screen.
;* - Phase 2: Stage $E0 at $01E2, immediately PLB, read SCC regs to $0304-$0307 and screen.
;* - No JSR to ROM (HOME/COUT), no IRQs in the critical window.
;****************************************************************

            ORG     $2000
            DSK     DBRPLB.SYSTEM
            TYP     'SYS'
            MX      %11               ; 8-bit A/X/Y

START       SEI                      ; keep interrupts from disturbing stack
            CLC
            XCE                      ; native mode
            SEP     #$20             ; 8-bit A

            ; Clear a small banner area on text screen (no ROM calls)
            LDX     #$00
CLR         LDA     #$A0             ; space in Apple text
            STA     $0400,X
            STA     $0420,X
            STA     $0440,X
            INX
            CPX     #$28
            BNE     CLR

            ; Print banner directly to screen
            LDX     #0
BNR         LDA     MSG,X
            BEQ     SETUP
            STA     $0400,X
            INX
            BNE     BNR

; ------------------------------------------------------------
; Enter native mode; ensure DBR=FF initially
; ------------------------------------------------------------
SETUP       LDA     #$FF
            PHA
            PLB                     ; DBR<=FF

; ------------------------------------------------------------
; Phase 1: Stage E0 at stack address $01E2 but DO NOT PLB
; ------------------------------------------------------------
            ; Set SP=$01E3 so next PHA stores at $01E2
            REP     #$10            ; 16-bit X/Y
            LDX     #$01E3
            TXS
            SEP     #$10            ; back to 8-bit X/Y
            LDA     #$E0
            PHA                     ; [$01E2] <= E0

            ; Read SCC with DBR still FF (Phase 1)
            LDA     $C038
            STA     $0300
            LDA     $C039
            STA     $0301
            LDA     $C03A
            STA     $0302
            LDA     $C03B
            STA     $0303

            ; Write "FF:" and hex bytes to screen (no ROM)
            LDA     #'F'
            STA     $0420
            STA     $0421
            LDA     #$3A             ; ':'
            STA     $0422
            LDA     #$A0             ; space
            STA     $0423
            ; bytes $0300-$0303 → $0424-$042B
            LDA     $0300
            JSR     PRINT_HEX_0424
            LDA     $0301
            JSR     PRINT_HEX_0426
            LDA     $0302
            JSR     PRINT_HEX_0428
            LDA     $0303
            JSR     PRINT_HEX_042A

; ------------------------------------------------------------
; Phase 2: Execute PLB to pull E0 from $01E2, rescan SCC
; ------------------------------------------------------------
            PLB                     ; DBR<=[$01E3+1]=$01E2=E0 (immediate, no ROM in between)

            LDA     $C038
            STA     $0304
            LDA     $C039
            STA     $0305
            LDA     $C03A
            STA     $0306
            LDA     $C03B
            STA     $0307

            ; Write "E0:" and hex bytes to screen (no ROM)
            LDA     #'E'
            STA     $0440
            LDA     #'0'
            STA     $0441
            LDA     #$3A             ; ':'
            STA     $0442
            LDA     #$A0             ; space
            STA     $0443
            ; bytes $0304-$0307 → $0444-$044B
            LDA     $0304
            JSR     PRINT_HEX_0444
            LDA     $0305
            JSR     PRINT_HEX_0446
            LDA     $0306
            JSR     PRINT_HEX_0448
            LDA     $0307
            JSR     PRINT_HEX_044A

DONE        BRA     DONE

; Messages
MSG         ASC     'DBR PLB STAGE/SCAN TEST',00

; Print helpers: write A as 2 hex digits to fixed screen addrs
PRINT_HEX_0424
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0424
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0425
            RTS

PRINT_HEX_0426
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0426
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0427
            RTS

PRINT_HEX_0428
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0428
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0429
            RTS

PRINT_HEX_042A
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $042A
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $042B
            RTS

PRINT_HEX_0444
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0444
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0445
            RTS

PRINT_HEX_0446
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0446
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0447
            RTS

PRINT_HEX_0448
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0448
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $0449
            RTS

PRINT_HEX_044A
            PHA
            LSR A
            LSR A
            LSR A
            LSR A
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $044A
            PLA
            AND     #$0F
            TAX
            LDA     HEXTAB,X
            STA     $044B
            RTS

HEXTAB      ASC     '0123456789ABCDEF'

            END     START
