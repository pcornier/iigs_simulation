;***************************************************************
; IODEBUG.AUTO.S - Auto-boot SYSTEM file (SCCAUTO.SYSTEM)
; - Prints banner
; - Sets DBR=E0 and performs immediate reads from $C000..$C003
;***************************************************************

            ORG     $2000
            DSK     SCCAUTO.SYSTEM
            TYP     'SYS'
            MX      %11

HOME        EQU     $FC58
COUT        EQU     $FDED

START       JSR     HOME
            LDX     #0
PMSG        LDA     MSG,X
            BEQ     SETBANK
            JSR     COUT
            INX
            BNE     PMSG

SETBANK     ; Stay in emulation mode for stability
            ; Visual cue: print a second line and then do C0 reads
            ; --- Phase A: Fast SCC FF read (expected 0x80 if DBR=FF) ---
            LDX     #0
P_FF        LDA     MSG_FF,X
            BEQ     DO_FF
            JSR     COUT
            INX
            BNE     P_FF

DO_FF       CLC                     ; enter native
            XCE
            LDA     #$FF            ; DBR <= FF
            PHA
            PLB
            PLA
            LDA     $C038
            LDA     $C039
            LDA     $C03A
            LDA     $C03B

            ; --- Phase B: SCC E0 read (expected SCC values) ---
            LDX     #0
P_E0        LDA     MSG_E0,X
            BEQ     DO_E0
            JSR     COUT
            INX
            BNE     P_E0

DO_E0       LDA     #$E0            ; DBR <= E0
            PHA
            PLB
            PLA
            LDA     $C038
            LDA     $C039
            LDA     $C03A
            LDA     $C03B

            ; Back to emulation and done
            SEC
            XCE
            LDX     #0
P_DONE      LDA     MSG_DONE,X
            BEQ     LOOP
            JSR     COUT
            INX
            BNE     P_DONE

LOOP        LDA     $C000           ; idle poll
            JMP     LOOP

MSG         ASC     'IODEBUG AUTO',0D,00
MSG_FF      ASC     'SCC FF',0D,00
MSG_E0      ASC     'SCC E0',0D,00
MSG_DONE    ASC     'DONE',0D,00

            END     START
