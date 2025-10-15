; SCC Self-Test 06 - Reproduces ROM self-test failure
; Tests TX with minimal BRG setup (WR13=00, WR14=01)

        TYP   $06             ; ProDOS binary file
        DSK   SCC06.SYSTEM
        ORG   $2000

START
        SEI
        CLC
        XCE                   ; Native mode

; Initialize SCC exactly like ROM self-test
        ; Set WR4 first
        LDA   #$04
        STA   $C039          ; Select WR4
        LDA   #$44
        STA   $C039          ; WR4 = 44 (x16 clock, like ROM)

        ; Set WR11
        LDA   #$0B
        STA   $C039          ; Select WR11
        LDA   #$D2
        STA   $C039          ; WR11 = D2 (like ROM)

        ; Set WR12
        LDA   #$0C
        STA   $C039          ; Select WR12
        LDA   #$5E
        STA   $C039          ; WR12 = 5E (like ROM test)

        LDA   #$0D
        STA   $C039          ; Select WR13
        LDA   #$00
        STA   $C039          ; WR13 = 00

        LDA   #$0E
        STA   $C039          ; Select WR14
        LDA   #$00
        STA   $C039          ; WR14 = 00 (BRG off)

        LDA   #$0E
        STA   $C039          ; Select WR14
        LDA   #$01
        STA   $C039          ; WR14 = 01 (BRG enable only)

        LDA   #$05
        STA   $C039          ; Select WR5
        LDA   #$6A
        STA   $C039          ; WR5 = 6A (TX enable, 8 bits)

        LDA   #$03
        STA   $C039          ; Select WR3
        LDA   #$C1
        STA   $C039          ; WR3 = C1 (RX enable, 8 bits)

        LDA   #$0F
        STA   $C039          ; Select WR15
        LDA   #$00
        STA   $C039          ; WR15 = 00

; Check initial RR0 status (should be 2C with TX empty)
        LDA   $C039          ; Read RR0
        CMP   #$2C
        BEQ   INIT_OK

; Initial RR0 wrong
        LDA   #$C6           ; 'F'
        STA   $0400
        LDA   #$B1           ; '1'
        STA   $0401
        LDA   #$00
        STA   $0402
        JMP   *

INIT_OK
; Write test byte to ADATA
        LDA   #$AA
        STA   $C03B          ; Write to ADATA

; Check that TX empty cleared immediately (RR0 should be 28)
        LDA   $C039          ; Read RR0
        CMP   #$28
        BEQ   CLEARED_OK

; RR0 didn't clear on write
        LDA   #$C6           ; 'F'
        STA   $0400
        LDA   #$B2           ; '2'
        STA   $0401
        LDA   #$00
        STA   $0402
        JMP   *

CLEARED_OK
; Poll for TX complete (RR0 should return to 2C)
        LDX   #$00
POLL_LOOP
        LDA   $C039          ; Read RR0
        CMP   #$2C
        BEQ   PASS           ; TX complete!
        INX
        BNE   POLL_LOOP      ; Continue until X wraps

; If we get here, TX never completed
        LDA   #$C6           ; 'F'
        STA   $0400
        LDA   #$B3           ; '3'
        STA   $0401
        LDA   #$00
        STA   $0402
        JMP   *

PASS
        LDA   #$D0           ; 'P'
        STA   $0400
        LDA   #$C1           ; 'A'
        STA   $0401
        STA   $0403
        LDA   #$D3           ; 'S'
        STA   $0402
        STA   $0404
        JMP   *