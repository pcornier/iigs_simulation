;
; GSQMMU.S - GSQuared MMU Test Suite
;
; Tests from the gsquared emulator's MMU test suite
; Assembled to run as a ProDOS SYSTEM file
;
        ORG   $2000
        TYP   $06
        DSK   GSQMMU.SYSTEM

; Switch to native mode
        CLC
        XCE
        SEP   #$30          ; 8-bit A, X, Y

        LDY   #$00
        LDA   #$00

; Running: 1 - Normal text page video shadowing
test1
        LDX   #$01
;  Write to E0/C029:
        LDA   #$01
        STA   >$E0C029
;  Write to E0/C035:
        LDA   #$08
        STA   >$E0C035
;  Write to E0/C036:
        LDA   #$84
        STA   >$E0C036
;  Write to 00/0400:
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401
;  Assert E0/0400
        LDA   >$E00400
        CMP   #$12
        BEQ   test1a1b0ok
        LDA   #$01
        JSR   recordfail
test1a1b0ok
        LDA   >$E00401
        CMP   #$34
        BEQ   test1a1b1ok
        LDA   #$01
        JSR   recordfail
test1a1b1ok
test1a1good
        INX
;  Write to E0/C029:
        LDA   #$01
        STA   >$E0C029

; Running: 201 - text page 1 shadowing inhibited
test201
        LDX   #$01
;  Write to E0/0400:
        LDA   #$00
        STA   >$E00400
        LDA   #$00
        STA   >$E00401
;  Write to E0/C029:
        LDA   #$01
        STA   >$E0C029
;  Write to E0/C035:
        LDA   #$09
        STA   >$E0C035
;  Write to E0/C036:
        LDA   #$84
        STA   >$E0C036
;  Write to 00/0400:
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401
;  Assert E0/0400
        LDA   >$E00400
        CMP   #$00
        BEQ   test201a1b0ok
        LDA   #$C9
        JSR   recordfail
test201a1b0ok
        LDA   >$E00401
        CMP   #$00
        BEQ   test201a1b1ok
        LDA   #$C9
        JSR   recordfail
test201a1b1ok
test201a1good
        INX
;  Write to E0/C029:
        LDA   #$01
        STA   >$E0C029
;  Write to E0/C035:
        LDA   #$08
        STA   >$E0C035

; Running: 2 - shadow all banks copies data from any even bank to bank E0
test2
        LDX   #$01
;  Write to E0/C036:
        LDA   #$94
        STA   >$E0C036
;  Write to 00/0400:
        LDA   #$12
        STA   >$000400
        LDA   #$34
        STA   >$000401
;  Write to 02/0402:
        LDA   #$56
        STA   >$020402
        LDA   #$78
        STA   >$020403
;  Write to E0/C036:
        LDA   #$84
        STA   >$E0C036
;  Assert E0/0402
        LDA   >$E00402
        CMP   #$56
        BEQ   test2a1b0ok
        LDA   #$02
        JSR   recordfail
test2a1b0ok
        LDA   >$E00403
        CMP   #$78
        BEQ   test2a1b1ok
        LDA   #$02
        JSR   recordfail
test2a1b1ok
test2a1good
        INX

; Running: 3 - shadow only copies data written to video pages
test3
        LDX   #$01
;  Write to E0/6000:
        LDA   #$FF
        STA   >$E06000
        LDA   #$FF
        STA   >$E06001
;  Write to 00/6000:
        LDA   #$12
        STA   >$006000
        LDA   #$34
        STA   >$006001
;  Assert E0/6000
        LDA   >$E06000
        CMP   #$FF
        BEQ   test3a1b0ok
        LDA   #$03
        JSR   recordfail
test3a1b0ok
        LDA   >$E06001
        CMP   #$FF
        BEQ   test3a1b1ok
        LDA   #$03
        JSR   recordfail
test3a1b1ok
test3a1good
        INX

; Running: 4 - write to text 1 with ramwrt=1 shadowed to e1
test4
        LDX   #$01
;  Write to E0/0400:
        LDA   #$00
        STA   >$E00400
        LDA   #$00
        STA   >$E00401
;  Write to E1/0400:
        LDA   #$00
        STA   >$E10400
        LDA   #$00
        STA   >$E10401
;  Write to E0/C005: (enable RAMWRT)
        LDA   #$01
        STA   >$E0C005
;  Write to 00/0400: (should go to bank 01 and shadow to E1)
        LDA   #$56
        STA   >$000400
        LDA   #$78
        STA   >$000401
;  Write to E0/C004: (disable RAMWRT)
        LDA   #$01
        STA   >$E0C004
;  Assert E1/0400
        LDA   >$E10400
        CMP   #$56
        BEQ   test4a1b0ok
        LDA   #$04
        JSR   recordfail
test4a1b0ok
        LDA   >$E10401
        CMP   #$78
        BEQ   test4a1b1ok
        LDA   #$04
        JSR   recordfail
test4a1b1ok
test4a1good
        INX
;  Assert E0/0400
        LDA   >$E00400
        CMP   #$00
        BEQ   test4a2b0ok
        LDA   #$04
        JSR   recordfail
test4a2b0ok
        LDA   >$E00401
        CMP   #$00
        BEQ   test4a2b1ok
        LDA   #$04
        JSR   recordfail
test4a2b1ok
test4a2good
        INX

; Running: 5 - aux write (non-video) put in aux but not shadowed to e1
test5
        LDX   #$01
;  Write to 01/6000:
        LDA   #$00
        STA   >$016000
        LDA   #$00
        STA   >$016001
;  Write to E1/6000:
        LDA   #$00
        STA   >$E16000
        LDA   #$00
        STA   >$E16001
;  Write to E0/C005:
        LDA   #$01
        STA   >$E0C005
;  Write to 00/6000:
        LDA   #$56
        STA   >$006000
        LDA   #$78
        STA   >$006001
;  Write to E0/C004:
        LDA   #$01
        STA   >$E0C004
;  Assert E1/6000
        LDA   >$E16000
        CMP   #$00
        BEQ   test5a1b0ok
        LDA   #$05
        JSR   recordfail
test5a1b0ok
        LDA   >$E16001
        CMP   #$00
        BEQ   test5a1b1ok
        LDA   #$05
        JSR   recordfail
test5a1b1ok
test5a1good
        INX
;  Assert 01/6000
        LDA   >$016000
        CMP   #$56
        BEQ   test5a2b0ok
        LDA   #$05
        JSR   recordfail
test5a2b0ok
        LDA   >$016001
        CMP   #$78
        BEQ   test5a2b1ok
        LDA   #$05
        JSR   recordfail
test5a2b1ok
test5a2good
        INX

; Running: 7 - aux write shadowed to e1 - direct access to aux bank
; (This is the TEST 08 equivalent - direct bank 01 write)
test7
        LDX   #$01
;  Write to E1/0400:
        LDA   #$00
        STA   >$E10400
        LDA   #$00
        STA   >$E10401
;  Write to 01/0400: (direct bank 01 write should shadow to E1)
        LDA   #$56
        STA   >$010400
        LDA   #$78
        STA   >$010401
;  Assert E1/0400
        LDA   >$E10400
        CMP   #$56
        BEQ   test7a1b0ok
        LDA   #$07
        JSR   recordfail
test7a1b0ok
        LDA   >$E10401
        CMP   #$78
        BEQ   test7a1b1ok
        LDA   #$07
        JSR   recordfail
test7a1b1ok
test7a1good
        INX

; ============================================================================
; Test complete - display results
; ============================================================================
testpassed
        LDA   #$00
testfailed
        CPY   #$00
        BEQ   exittest
        JSR   displayfail
exittest
        ; Return to emulation mode
        SEC
        XCE
        RTS

recordfail
        STA   failtable,Y
        INY
        TXA
        STA   failtable,Y
        INY
        RTS

displayfail
        TYX
        LDY   #$00
dfloop
        LDA   failtable,Y
        JSR   $FDDA         ; Print hex byte
        INY
        LDA   failtable,Y
        JSR   $FDDA
        INY
        LDA   #$A0
        JSR   $FDED         ; Print character
        DEX
        DEX
        BNE   dfloop
        LDA   #$8D
        JSR   $FDED
        RTS

failtable
        DS    256
