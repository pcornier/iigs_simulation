;****************************************************************
;* TIMING_RACE_TEST.S
;*
;* A targeted test to reproduce and verify the fix for the timing race
;* condition that was causing Y register corruption (001C -> C034).
;*
;* This test specifically triggers the conditions that cause the race:
;* 1. Recent write operations to trigger we signal transitions
;* 2. Shadow memory writes to activate slowMem logic
;* 3. Y register loads immediately after address bus activity
;* 4. STA [dp],Y operations that would expose corruption
;*
;* Expected behavior:
;* - BROKEN: Y gets corrupted with address values, writes to wrong locations
;* - FIXED: Y contains correct data values, writes to intended locations
;****************************************************************

            ORG     $2000               ; ProDOS 8 programs start at $2000
            DSK     TIMING.RACE.TEST    ; Set the output filename
            TYP     'SYS'               ; Set ProDOS file type to SYS ($F1)
            MX      %11                 ; Default to 8-bit Accumulator and Index

;--- Monitor Routines
HOME        EQU     $FC58               ; Clear screen and home cursor
COUT        EQU     $FDED               ; Character output

;--- Test addresses that trigger timing races
SHADOW_ADDR EQU     $0400               ; Text page 1 (shadow write triggers slowMem)
RTC_CTRL    EQU     $C034               ; RTC control register (the corruption target)
RTC_DATA    EQU     $C033               ; RTC data register

;****************************************************************
;* MAIN PROGRAM - Timing Race Reproduction Test
;****************************************************************
START
            JSR     HOME                ; Clear screen

            ; Print test header
            LDX     #0
PRINT_HDR   LDA     HEADER_MSG,X
            BEQ     RUN_RACE_TEST
            JSR     COUT
            INX
            BNE     PRINT_HDR

RUN_RACE_TEST
            ; Setup test data structure in Direct Page
            ; Store pointer to our test buffer at DP location $04
            LDA     #<TEST_BUFFER       ; Low byte of buffer address
            STA     $04
            LDA     #>TEST_BUFFER       ; High byte of buffer address
            STA     $05
            LDA     #$00                ; Bank byte (always 0 for our test)
            STA     $06

            ; Initialize test buffer with known pattern
            LDY     #$00
INIT_LOOP   LDA     #$AA                ; Test pattern
            STA     TEST_BUFFER,Y
            INY
            CPY     #$40                ; Initialize 64 bytes
            BNE     INIT_LOOP

            ; **CRITICAL: Create the exact timing race conditions**

            ; Phase 1: Trigger shadow write to activate slowMem logic
            ; This primes the we signal for the race condition
            LDA     #$FF
            STA     SHADOW_ADDR         ; Write to shadow memory (triggers slowMem=1)

            ; Phase 2: Access RTC registers to put addresses on bus
            ; This sets up the address bus with C034 values
            LDA     RTC_CTRL            ; Read from C034 (puts C034 on address bus)
            LDA     RTC_DATA            ; Read from C033 (more address bus activity)

            ; Phase 3: **THE CRITICAL RACE CONDITION**
            ; Load Y register immediately after address bus activity
            ; In broken version: Y gets corrupted with address bus value (C034)
            ; In fixed version: Y gets correct data value (001C)
            LDY     #$1C                ; Should load 001C, but race may load C034!

            ; Phase 4: Test the Y register value with STA [dp],Y
            ; This will expose whether Y was corrupted
            LDA     #$55                ; Test value to store
            STA     [04],Y              ; Store via indirect indexed

            ; Phase 5: Verify where the data actually went
            ; Check if it went to the intended location or was corrupted

            ; Check intended location (TEST_BUFFER + $1C)
            LDA     TEST_BUFFER+$1C     ; Should contain $55 if working correctly
            CMP     #$55
            BEQ     CHECK_CORRUPTION

            ; If we get here, the intended write failed
            JMP     TEST_FAILED

CHECK_CORRUPTION
            ; Check if data was written to corruption address
            ; The race condition could cause writes to various system addresses
            ; We'll check a few likely corruption targets

            ; In the actual bug, Y contained C034, so STA [04],Y would write to:
            ; base_pointer (000000) + Y (C034) = C034
            ; But our test uses a different base pointer, so let's check the math

            ; With our setup: [04] contains pointer to TEST_BUFFER
            ; If Y is corrupted to C034, STA [04],Y writes to TEST_BUFFER + C034
            ; This would be way outside our buffer - likely a segfault in real hardware

            ; For this test, let's verify Y contains the expected value directly
            ; by using Y in a known operation

            LDA     #$00
            STA     RESULT_Y_LOW        ; Clear result storage
            STY     RESULT_Y_LOW        ; Store Y register value for inspection

            ; Check if Y contains the expected value ($1C)
            LDA     RESULT_Y_LOW
            CMP     #$1C
            BEQ     TEST_PASSED         ; Y contains correct value

            ; If Y contains corruption value (like $34 from C034)
            CMP     #$34
            BEQ     Y_CORRUPTED

            ; Some other unexpected value
            JMP     TEST_UNKNOWN

Y_CORRUPTED
            ; Y register was corrupted with address bus value
            LDX     #0
PRINT_CORRUPT LDA   CORRUPT_MSG,X
            BEQ     SHOW_Y_VALUE
            JSR     COUT
            INX
            BNE     PRINT_CORRUPT
            JMP     SHOW_Y_VALUE

TEST_PASSED
            ; Test passed - Y register contains correct value
            LDX     #0
PRINT_PASS  LDA     PASS_MSG,X
            BEQ     SHOW_Y_VALUE
            JSR     COUT
            INX
            BNE     PRINT_PASS
            JMP     SHOW_Y_VALUE

TEST_FAILED
            ; Test failed - intended write didn't work
            LDX     #0
PRINT_FAIL  LDA     FAIL_MSG,X
            BEQ     SHOW_Y_VALUE
            JSR     COUT
            INX
            BNE     PRINT_FAIL
            JMP     SHOW_Y_VALUE

TEST_UNKNOWN
            ; Unexpected Y value
            LDX     #0
PRINT_UNK   LDA     UNKNOWN_MSG,X
            BEQ     SHOW_Y_VALUE
            JSR     COUT
            INX
            BNE     PRINT_UNK

SHOW_Y_VALUE
            ; Display the actual Y register value for debugging
            LDA     #$20                ; Space
            JSR     COUT
            LDA     #$59                ; 'Y'
            JSR     COUT
            LDA     #$3D                ; '='
            JSR     COUT

            LDA     RESULT_Y_LOW
            JSR     PRINT_HEX_BYTE

            ; Also test the write operation result
            LDA     #$20                ; Space
            JSR     COUT
            LDA     #$57                ; 'W'
            JSR     COUT
            LDA     #$3D                ; '='
            JSR     COUT

            LDA     TEST_BUFFER+$1C
            JSR     PRINT_HEX_BYTE

HANG        JMP     HANG                ; Hang here so we can see results

;****************************************************************
;* SUBROUTINES
;****************************************************************

;--- Print a byte in hex format
PRINT_HEX_BYTE
            PHA                         ; Save the byte
            LSR                         ; Get high nibble
            LSR
            LSR
            LSR
            JSR     PRINT_HEX_NIBBLE    ; Print high nibble
            PLA                         ; Restore byte
            AND     #$0F                ; Get low nibble
            JMP     PRINT_HEX_NIBBLE    ; Print low nibble and return

;--- Print a hex nibble (0-F)
PRINT_HEX_NIBBLE
            CMP     #10                 ; Is it A-F?
            BCC     PRINT_DIGIT         ; No, it's 0-9
            ADC     #6                  ; Yes, convert to A-F (carry is set)
PRINT_DIGIT
            ADC     #'0'                ; Convert to ASCII
            JMP     COUT                ; Print and return

;****************************************************************
;* DATA SECTION
;****************************************************************

HEADER_MSG      ASC     'TIMING RACE TEST - Y REGISTER CORRUPTION',0D,0A,00
PASS_MSG        ASC     'PASS: Y register correct',00
CORRUPT_MSG     ASC     'FAIL: Y register corrupted',00
FAIL_MSG        ASC     'FAIL: Write operation failed',00
UNKNOWN_MSG     ASC     'UNKNOWN: Unexpected Y value',00

; Storage for test results
RESULT_Y_LOW    DFB     $00

; Test buffer for our operations
TEST_BUFFER     DS      $80                 ; 128 bytes of test buffer