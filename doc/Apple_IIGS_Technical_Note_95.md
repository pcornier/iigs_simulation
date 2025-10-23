# Apple IIGS Technical Note #95: ROM Diagnostic Errors

**Written by:** Dan Strnad  
**Date:** September 1990  
**Developer Technical Support**

This Technical Note describes errors returned by the ROM Diagnostics on Apple IIGS systems.

## The Built-In Diagnostics Revealed

The IIGS has a self-test capability in ROM. The self-test is activated by pressing Open-Apple and Option on power up, or Open-Apple, Option, and Reset. During the test, the test number is visible on the bottom of the screen followed by six zeros. After all tests are complete, a continuous 6 KHz one-second beep sounds and the screen displays a System Good message.

If any test fails, the screen displays a message of the form `System Bad: AABBCCDD` on the lower left hand side and a staggered `AABBCCDD` on the upper left hand side to help read the error code in the event of a RAM failure. In the event of video failure, the failure code is also sent to the printer port. In the number contained in the error message, `AA` is the test number that failed and the failure code is embedded in the `BB`, `CC`, and `DD` fields. The complete failure codes for each of the 12 tests are as follows:

## Self Test 1: ROM Test

- **AA** = 01
- **BB** = Failed checksum
- **DD** = 01 if the test encountered bad RAM and the error code is a RAM error code similar to the RAM Test error codes

For a failure in ROM, the ROM diagnostics also display `RM` on the top left hand corner of the screen.

## Self Test 2: RAM Test

- **AA** = 02
- **BB** = Bank Number (or $FF for ADB Tool call error)
- **CC** = Bit(s) failed

## Self Test 3: Soft Switches and State Register Test

- **AA** = 03
- **BB** = State Register bit (if any)
- **CC** = Low byte of soft switch address

## Self Test 4: RAM Address Test

- **AA** = 04
- **BB** = Failed bank number (or $FF for ADB Tool call error)
- **CCDD** = Failed address

## Self Test 5: Speed Test

- **AA** = 05
- **BB** = 
  - 01: Speed stuck slow
  - 02: Speed stuck fast

## Self Test 6: Serial Test

- **AA** = 06
- **BB** = 
  - 01: Register R/W
  - 04: Tx Buffer empty status
  - 05: Tx Buffer empty failure
  - 06: All Sent Status fail
  - 07: Rx Char available
  - 08: Bad data

## Self Test 7: Clock Test

- **AA** = 07
- **DD** = 01: Fatal error occurred and the test is aborted

## Self Test 8: Battery RAM Test

- **AA** = 08
- **BB** = 
  - 01: Address test and CC = bad address
  - 02: Non-volatile RAM failed and CC = pattern, DD = address

## Self Test 9: Apple Desktop Bus Test

- **AA** = 09
- **BBCC** = Bad checksum
- **DD** = 01: Apple Desktop Bus tools call encountered a fatal error, no checksum computed.

## Self Test 10: Shadow Register Test

- **AA** = 0A
- **BB** = 
  - 01: Text page 1 fail
  - 02: Text page 2 fail
  - 03: Apple Desktop Bus Tool call error
  - 04: Power On Clear bit error

## Self Test 11: Interrupts Test

- **AA** = 0B
- **BB** = 
  - 01: VBL interrupt time-out
  - 02: VBL IRQ status fail
  - 03: 1/4 sec interrupt
  - 04: 1/4 sec interrupt
  - 05:
  - 06: VGC IRQ
  - 07: Scan line

## Self Test 12: Sound Test

- **AA** = 0C
- **DD** = 
  - 01: RAM data error
  - 02: RAM address error
  - 03: Data register failed
  - 04: Control register failed
  - 05: Oscillator interrupt timeout

## Further Reference

- *Apple IIGS Hardware Reference*, Second Edition
