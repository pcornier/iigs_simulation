;***************************************************************
; IODEBUG.S - Minimal ProDOS 8 SYSTEM file
; - Prints a startup banner
; - Sets DBR to E0 and performs immediate reads from $C000..$C003
;   to exercise IO decode logging in the memory controller
; Assembled with Merlin32
;***************************************************************

            ORG     $2000               ; ProDOS 8 programs start at $2000
            DSK     IODEBUG.SYSTEM      ; Output filename
            TYP     'SYS'               ; ProDOS file type SYS ($F1)
            MX      %11                 ; 8-bit A and X/Y

; Monitor routines
HOME        EQU     $FC58               ; Clear screen/home
COUT        EQU     $FDED               ; Output one char in A

; Entry
START       JSR     HOME

            LDX     #0
PMSG        LDA     MSG,X
            BEQ     SETBANK
            JSR     COUT
            INX
            BNE     PMSG

SETBANK     PHB                         ; Save current DBR
            CLC
            XCE                         ; Enter native mode
            LDA     #$E0
            PHA
            PLB                         ; DBR = E0
            PLA

            ; Perform a handful of IO reads to trigger logs
            LDA     $C000               ; Keyboard strobe
            LDA     $C001
            LDA     $C002
            LDA     $C003

            PLB                         ; Restore DBR

            LDX     #0
PMSG2       LDA     MSG2,X
            BEQ     DONE
            JSR     COUT
            INX
            BNE     PMSG2

DONE        BRA     DONE                ; Sit here

; Data
MSG         ASC     'IODEBUG START',0D,00
MSG2        ASC     'DONE',0D,00

            END     START
