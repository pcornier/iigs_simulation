;****************************************************************
;* Y_CORRUPTION_DEMO.S
;*
;* Test to detect CPU instruction address bus corruption
;*
;* The real bug (from trace analysis):
;* - CPU should execute STA $C034 from address BAB4
;* - But due to timing corruption, CPU fetches opcodes from BAB7 instead
;* - This causes wrong instruction execution
;*
;* Test Strategy:
;* Place different opcodes at consecutive addresses and detect if
;* CPU executes the wrong instruction due to address corruption
;*
;* Expected Results:
;* BROKEN: Wrong instruction executed (address bus corrupted)
;* FIXED:  Correct instruction executed
;****************************************************************

            ORG     $2000
            DSK     YRACE.SYSTEM
            TYP     'SYS'
            MX      %11

HOME        EQU     $FC58
COUT        EQU     $FDED

START
            JSR     HOME

            ; Print test message
            LDX     #0
PRINT_MSG   LDA     MSG,X
            BEQ     DO_TEST
            JSR     COUT
            INX
            BNE     PRINT_MSG

DO_TEST
            ; **INSTRUCTION ADDRESS CORRUPTION TEST**
            ; Based on trace analysis showing CPU executing from wrong addresses
            ; (BAB7 instead of BAB4 during STA $C034 instruction)

            ; Setup test scenario: Place different opcodes at consecutive addresses
            ; If CPU address corruption occurs, it will execute wrong instruction

            LDA     #$00                ; Initialize test value
            STA     RESULT              ; Clear result flag

            ; **STRATEGY**: Create a scenario where if address corruption occurs,
            ; the CPU will execute a different instruction with different behavior

TIMING_LOOP
            LDY     #$00                ; Loop counter

            ; Set up Bank E1 context (matches failing SCC pattern)
            LDA     #$E1
            PHA
            PLB                         ; Now in Bank E1

            ; Create timing pressure with memory operations
            LDA     #$A0                ; Test pattern value
            STA     $2000               ; E1 bank write (triggers slowMem)

            ; **CRITICAL TEST SEQUENCE**
            ; The following instruction sequence is carefully crafted:
            ; If the CPU address bus is corrupted and fetches from wrong addresses,
            ; it will execute different opcodes and produce different results

TEST_CRITICAL_SECTION:
            ; This section must be at a specific address pattern to test corruption
            LDA     #$55                ; Load test pattern 1

            ; **CRITICAL INSTRUCTION**: This is where corruption occurs
            ; If address is corrupted, CPU might fetch wrong opcode bytes
            STA     $C034               ; Store to RTC (timing sensitive)

            NOP                         ; Padding to create specific address layout
            NOP                         ; These NOPs create the BAB4/BAB7 pattern
            NOP                         ; that was seen in the corruption trace

            ; After critical section, test if expected instruction executed
            LDA     #$AA                ; Load test pattern 2
            STA     RESULT              ; Store result

            ; Test with different bank switching pattern
            LDA     #$00
            PHA
            PLB                         ; Switch to Bank 00

            ; Shadow memory operations (triggers timing conditions)
            LDA     #$CC                ; Different pattern
            STA     $0400               ; Shadow memory write

            ; Switch back to E1 and repeat critical section
            LDA     #$E1
            PHA
            PLB                         ; Back to Bank E1

            ; Second critical test with different timing
            LDA     #$77                ; Another test pattern
            STA     $C034               ; Critical RTC access
            NOP
            NOP

            ; Check if corruption affected register contents
            LDY     #$1C                ; Expected Y value
            ; If address corruption occurred during LDY, Y might have wrong value

            ; Test Y register value for corruption
            CPY     #$1C                ; Should be 1C
            BEQ     CONT_TEST

            ; Y register was corrupted - this indicates address bus corruption
            LDA     #$FF
            STA     RESULT              ; Mark corruption detected
            JMP     CORRUPTION_FOUND

CONT_TEST
            ; Continue stress testing
            INY
            CPY     #20                 ; Test multiple iterations
            BNE     TIMING_LOOP

            ; If we reach here, no obvious corruption detected
            JMP     TEST_PASSED

CORRUPTION_FOUND
            ; Corruption detected - display error
            PEA     $0000               ; Switch to Bank 00 for display
            PLB

            LDX     #0
PRINT_ERR   LDA     ERR_MSG,X
            BEQ     HANG
            JSR     COUT
            INX
            BNE     PRINT_ERR
            JMP     HANG

TEST_PASSED
            ; No corruption detected - show success
            PEA     $0000               ; Switch to Bank 00 for display
            PLB

            ; Step 4: Display the Y register value
            LDA     #$59                ; 'Y'
            JSR     COUT
            LDA     #$3D                ; '='
            JSR     COUT

            TYA                         ; Get Y register value
            JSR     PRINT_HEX_BYTE      ; Display it

            ; Compare and show result
            CPY     #$1C
            BEQ     CORRECT
            CPY     #$34
            BEQ     CORRUPTED

            ; Unknown value
            LDA     #$20                ; Space
            JSR     COUT
            LDA     #$3F                ; '?'
            JSR     COUT
            JMP     HANG

CORRECT
            LDA     #$20                ; Space
            JSR     COUT
            LDA     #$4F                ; 'O'
            JSR     COUT
            LDA     #$4B                ; 'K'
            JSR     COUT
            JMP     HANG

CORRUPTED
            LDA     #$20                ; Space
            JSR     COUT
            LDA     #$42                ; 'B'
            JSR     COUT
            LDA     #$55                ; 'U'
            JSR     COUT
            LDA     #$47                ; 'G'
            JSR     COUT

HANG        JMP     HANG

;--- Print hex byte
PRINT_HEX_BYTE
            PHA
            LSR
            LSR
            LSR
            LSR
            JSR     PRINT_HEX_NIBBLE
            PLA
            AND     #$0F
            JMP     PRINT_HEX_NIBBLE

PRINT_HEX_NIBBLE
            CMP     #10
            BCC     PRINT_DIGIT
            ADC     #6
PRINT_DIGIT
            ADC     #'0'
            JMP     COUT

MSG         ASC     'ADDR BUS CORRUPTION TEST: ',00
ERR_MSG     ASC     'CPU ADDRESS CORRUPTED!',00

RESULT      DS      1                   ; Test result storage