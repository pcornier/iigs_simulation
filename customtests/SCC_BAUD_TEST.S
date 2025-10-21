; SCC Baud Rate Generator Test
; This test replicates the specific register writes that trigger the
; "SCC_BAUD_SPECIAL" message and cause the selftest to hang.

        ORG   $2000
        TYP   $06
        DSK   SCCBAUD.SYSTEM

START
        ; Replicate the selftest SCC setup
        ; WR4 = 0x44 (x16 clock mode)
        LDA   #$04
        STA   $C039
        LDA   #$44
        STA   $C039

        ; WR12 = 0x5E
        LDA   #$0C
        STA   $C039
        LDA   #$5E
        STA   $C039

        ; WR13 = 0x00
        LDA   #$0D
        STA   $C039
        LDA   #$00
        STA   $C039

        ; WR14 = 0x01 (Enable BRG)
        LDA   #$0E
        STA   $C039
        LDA   #$01
        STA   $C039

        ; Now, the selftest would write to the TX buffer and poll
        ; a status register (in the sound GLU, not the SCC).
        ; We will just loop here to observe the behavior.
        
POLL_LOOP
        LDA   $C03D      ; Poll the sound GLU status register
        NOP
        NOP
        JMP   POLL_LOOP

PASS
        LDA   #$D0       ; 'P'
        STA   $0400
        JMP   *

FAIL
        LDA   #$C6       ; 'F'
        STA   $0400
        JMP   *
