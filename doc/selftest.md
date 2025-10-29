# Vegas ROM Diagnostics

  * **Date**: 05 May 1986 
  * **Author**: Karl Grabe 
  * **Subject**: Vegas ROM Diagnostics 
  * **Document Version Number**: 00:40 
  * **Test Document Number**: TSKA 0047 

-----

### Revision History 

| Version | Notes |
| :--- | :--- |
| **00:00** | Initial Release (KRG) |
| **00:10** | Error codes changed for Alpha 2.0 (KRG)\<br\>Test pointer table described\<br\>Self Test System Beep' shortened\<br\>Clock. Interrupt, FPI Speed tests added for Alpha 2.0 |
| **00:20**\<br\>**00:30** | Staggered screen error code for ram failures (16 Mar86 KRG)\<br\>Rom Checksum "RN" error code added\<br\>"BR" Error message removed\<br\>Burn In Non Volatile Ram usage (16 Apr86 KRG)\<br\>Burn In connector pin usage\<br\>Error Codes changed\<br\>FDB. Shadow tests added\<br\>Fail err code to port\!\<br\>Use of border colors for error detection\<br\>FDB UP fatal error code added\<br\>ROM checksum DD=01 error code added\<br\>Clock/NVR DD-01 error code added |
| **00:40** | Open and Closed apple keys to restart self test (KRG 4May86) |

-----

## GENERAL 

The Vegas ROM Diagnostics are used in the following environments: 

1.  User Self Test 
2.  Board level Burn-IN 
3.  Board Level test 
4.  Final System test 

**Brief Description of above:** 

1.  **User Self Test** 
    This is the equivalent of the //e Kernal Test. 

2.  **Board Level Burn In** 
    Vegas boards will have a burn in period of approx 48 hours for initial production. 

3.  & 4) **Board and Final System Test** 
    In these environments, or anytime disk-based diagnostics are running, any or all of the built in ROM tests can be run. 

The ROM Diagnostics are broken into two parts: 

1.  The Test Sequencer 
2.  The tests 

The Test Sequencer is described next in detail. 

-----

## Overview 

### 1 The Test Sequencer 

This piece of code is responsible for determining what the test environment is, running the appropriate tests and storing/displaying the test results. 

The sequencer determines the test environment using signals brought out on the Burn-In connector on the front LHS of the logic board. 

### Soft Switches for Burn In/Self test 

| DIAGTYPE | SW0 | SW1 | MODE |
| :--- | :--- | :--- | :--- |
| 0 | 0 | 0 | Normal Power UP |
| 0 | 1 | 0 | Control Panel |
| 1 | 0 | X | Cold Restart |
| 1 | 1 | 0 or 1 | Self Diagnostic, no wr NVR |
| X | 0 | 1 | BI Diagnostic, wr NVR |
| X | X | 1 | Self Diagnostic, no wr NVR |
| BI.FLAG | BI\_ALT | SELF | Test s/w Equate Names |
| N/A | OA Key | CA Key | From Keyboard |
| 9/10 | 5/6 | 11 | \<- BI Connector pins |

**Note:**
a) `wr NVR` write test STATUS registers to Non Volatile Ram. 
b) `DIAGSTYPE (MSB #C046)` is active lo es MSB is a hi on the Burn in connector ($1 = \\text{DIAGSW}$ on connector) 
c) with no keyboard plugged in `SW0` & `1` are `=0` as opposed to 1 on a //e. 
d) `DIAGSW` is only available on the BI connector. 

The sequencer determines what tests to run from a 16 bit test mask. 

-----

## Test Sequencer User Self Test 

The tests run here are a subset of those run in Burn-In. 

1.  Press Control-Open Apple-Closed Apple-Reset (retro only) 
2.  Press Control-Funct-Open Apple-Reset (Cortland only) 
3.  Press Open Apple-Closed Apple on power up (retro only) 
4.  Press Funct-Open Apple on power up (Cortland only) 
5.  Press Game I/O buttons BTN0, BTN1 on power up 

The test takes approx 35 seconds to complete. 

After all tests have been successfully completed a continuous 1 KHz ½-second beep is emitted and a `System Good` message is displayed on the screen. 

If any tests fail then a 6 KHz ½-second beep is emitted. 

NVR is never read or written to by the sequencer. 

Cork's final system test is performed with the housing cover on so it is not possible to monitor Self Test on the burn-in connector. 

### Error codes for Beta 2.0 and later rom releases: 

| Error code (AA) | Test |
| :--- | :--- |
| 01 | Checksum |
| 02 | Ram Moving Inversions |
| 03 | Softswitch |
| 04 | Ram Address |
| 05 | FPI Speed |
| 06 | Serial I/O |
| 07 | Real Time Clock |
| 08 | Battery Ram |
| 09 | Front Desk Bus |
| 0A | Shadowing |
| 0B | Interrupts |

For detailed error BBCCDD codes see individual test descriptions below. 

The test number followed by 6 zeros is displayed just prior to calling each test and during execution of the test. 

Also for `System Bad`: If the system fails self test the fail code bytes (6) preceded by a `@` are transmitted to the printer port. 

Note: A `System Bad: FFxxxx` message means the system went into Burn In diagnostics. 

### Interrupting Self Test 

It is safe to interrupt the self test (by pressing Control Reset) only during the start of the Moving inversions ram test (while screen displays Hires/Super Hires patterns). 

### Board Level Rework: 

Because the diagnostics require some of the system to be functional before they will run properly it is likely that they may crash/hang on boards that have serious hardware problems. 

  * a) The test number is printed on the screen BEFORE the test is executed. 
  * b) The sequencer changes the border colour each time a new test is run. 
  * c) The fail error code is sent to port 1. 
  * d) The error code is printed on the top LHS of the screen 3 time and staggered. 
  * e) The first part of the rom checksum test (which is the very first test) does a register based ram test for `$0000` to `$0400` in bank zero. 

### Self Test Annunciator/Disk Port Truth Table 

Note: Use an LEDs connected via a buffer to game 1/0 connector or disk port to verify UUT without VDU. 

| AN0 | AN1 | MODE |
| :--- | :--- | :--- |
| 1 | 0 | Test running |
| 0 | 0 | Testing complete, all tests pass |
| 1 | 1 | Testing complete, a test failed |
| | | **Phase 1 | Phase 2** | - Final System Test with cover on |
| | | 13/14 | 17/18 | \<- B1 Connector Pins |

Note: Cork uses disk port phase lines P1 & P2 to match AN0 & AN1 

-----

## Test Sequencer: Burn In 

In Burn In the number of test cycles the board performs before awaiting power down is programmable (by the Pre-Burn-In Functional tester). 

  * `BI.STATUS`: Test Results Stored by ROM diagnostics 
  * `BI.COUNTER`: Counts the number of test cycles done ROM Diag 
  * `BI.PASSES`: Number of cycles passed- ROM diagnostic 
  * `BI.FAILS`: Number of cycles failed - ROM diagnostic 
  * `BI.LASTF`: The cycle the last fail occurred on -\> ROM diagnostic 
  * `CYCLES.MAX`: Test cycles per power cycle-\> Pre BI Tester 
  * `VALID.CHK`: 3 byte check signature Pre BI Tester 
  * `BI.ALT.MASK`: What tests to run Pre BI tester. 

These registers work in the manufacturing process in the following manner: 
a) The Pre-BI board tester tests the board and if it passed sets up the following NVR registers: `CYCLES.MAX`, `VALID.CHECK`, `BI.ALT.MASK`. 
b) When the board is in Burn In the sequencer looks for a certain sequence in the `VALID.CHECK` bytes. 
c) The Post Bl tester reads all NVR registers from which it can determine the following: 

1.  If the board executed correct \# of test cycles (`BI.COUNTER`) 
2.  Whether the board failed at any time during BI 
3.  How often it failed (`BI.FAILS`) 
4.  When the fail(s) occurred (`BI.LASTF`) 
5.  What test last failed and its error code (`BI.STATUS`) 

### Burn In Annunciator/Disk Port Truth Table: 

| AN0 | AN1 | MODE |
| :--- | :--- | :--- |
| 0 | 1 | Passed last cycle, continue |
| 1 | 0 | Failed last cycle, continue |
| 1 | 1 | Pass, ready to power down |
| 1 | 0 | Fail, ready to power down |
| PASS.LED | POWER.ON | \<-- Equate Names to turn on (1) |
| FAIL.LED | POWER.OFF | \<-- Equate Names to turn off (0) |
| **Phase 1** | **Phase 2** | - Final System Test with cover on |
| 13/14 | 17/18 | \<-- BI Connector Pins |

Note: Cork uses disk port phase lines P1 & P2 to match AN0 & AN1 

-----

## ROM Tests available: 

This is a list of tests in ROM: 

Note: Each TEST NO corresponds to a bit in the 16 bit C register on calling `EXT.SED`. 

| TST NO | Test(s) performed |
| :--- | :--- |
| **LSB: 0** | Bank FE/ FF Roms Checksum  |
| **1** | Ram: Moving Inversions  |
| **2** | Softswitch/STATEREG test  |
| **3** | Ram: Addressing  |
| **4** | FPI/Video Counters Speed verification  |
| **5** | Serial: Internal Loopback  |
| **6** | Real Time Clock  |
| **7** | Battery Ram  |
| **8** | Front Desk Bus Processor & Rom  |
| **9** | Shadow register  |
| **10** | Interrupts  |
| **11** | - |
| **12** | - |
| **13** | - |
| **14** | - |
| **15** | - |

Each test is now given a brief description on the next page 

-----

## ROM Tests: 

System Self Test errors are in the format: `System Bad: AABBCCDD` 

**Serial Tests (J. Reynolds)** 
The serial chip registers are tested for Read/Write. 
Error code `AA=06`. 

  * `BB=01`: Register R/W 
  * `BB=04`: Tx Buffer empty status 
  * `BB=05`: Tx Buffer empty failure 
  * `BB=06`: All sent status fail 
  * `BB=07`: Rx char available 
  * `BB=08`: Bad data 

**Ram 1 (R. Carr) Moving Inversions** 
This checks bank 0 ram pages 0 thru 4 non-destructively and then tests the remaining ram in bank 0. 
Error code `AA=02`. 

**ROM Checksum (KRG)** 
This computes the checksum of Banks `$FE` & `$FF` and compares it against a known good value. 
Error code `AA=01`, `BB=1`=Failed checksum. 

**Speed (KRG)** 
Here the relative speed of the video counters is compared to the system speed in fast and slow modes. 
Error code `AA=05`, `BB=1` speed stuck slow, `BB=2` speed stuck fast. 

**Battery Ram or NVR (KRG)** 
This tests the 255 byte Non Volatile Ram non destructively. 
Error code `AA=08`. 
`BB=01` is address test and `CC`=bad address value 
`BB=02` is memory fail and `CC`=pattern, `DD`=address 

**Soft Switches/STATEREG (KRG)** 
This tests all soft switches by setting/testing and clearing/testing. 
Error code `AA=02`, `BB`=STATEREG bit, `CC`=Read softswitch address. 

**Front Desk Bus (KRG)** 
Reads the entire FDB processor rom into Vegas memory and computes a checksum. 
Error code `AA=09`, `BBCC`=Bad checksum found. 

**Ram Address (RCarr)** 
This is a ram test testing unique addressing capability of Vegas ram. 
Error code `AA=04`, `BB=F` Failed Bank No. `CC`=Failed bit. 

**Clock Test (KRG)** 
Performs a R/W test on the 32 bit clock register. 
Error code `AA=07`, `BBCCDD` not used. 

**Shadow Register (J. Reynolds)** 
Tests the functionality of the shadow register. 
Error code `AA=0A`. 

**Interrupts (J. Reynolds)** 
Tests Mega// and VGC capability of generating interrupts. 

  * `BB=01`: VBL interrupt timeout 
  * `BB=02`: VBL IRQ status fail 
  * `BB=03`: 1/4 SEC INTERRUPT 
  * `BB=04`: 1/4 SEC INTERRUPT 
  * `BB=05`: [not defined] 
  * `BB=06`: VGC IRQ 
  * `BB=07`: SCAN LINE 

**Burn In error** 
Error code `AA=FF`, `BBCCDD` not defined 
This error code should only occur when running burn in diagnostics (ie when pins 9 or 10 on the burn in connector are grounded). 

-----

## Calling rom tests using Test Pointer Table: 

The test pointer table resides at DIAGNOSTICS+2. Currently the diagnostics begin at
$FF7400 (this is not expected to change) so the table begins at $FF7402. The fist byte is
the size of the table followed by the 2 byte pointers themselves. All tests pointed to are
in bank $FF. For Alpha 2.0 the pointer table starts at $FF7430. For Beta 1.0 and later it's
at $FF7402.
To call a diagnostic routine simply JSL to the address pointed to by the table. On return
the carry flag is clear if the test passes or set if it fails. For a fail, the error status
stored in the 5 TST.STATUS registers - see source code for location ( currently at $000315
and is not expected to change ). The error codes are the same as those in self test. You
should clear these registers before calling the test routine. Enter with Data Bank = $00,
Native mode and 8 bit data and index. Return will be in Native mode with the M, X and data
bank in unknown states. Note that the main ram tests are destructive above $0400 in all
banks! Outside of the ram tests all other tests use memory in bank $00 from $0000
$1FFF.

```
SKP 2
******************************************************
* Test pointer table
* Points to tests in Bank $FF
* Tests must return with RTL instruction
* This allows disk s/w to look up the pointer table and
* call the tests from any bank).
******************************************************
SKP 2
TST.TAB DFB TST.TAB.E-*-3;Number of pointers times 2
SKP 1
DW ROM.CHECKSUM ;Test 1 128K гom
DW MOVIRAM ;Test 2 Ram: Moving Inversions
DW SOFT.SW ;Test 2 Mega // & Statereg softswitch test
DW RAM.ADDR ;TEST 4 Ram: Addressing
DW FPI.SPEED ;Test 5 Foi fast/slow mode check
DW SER.TST ;Test 6 Serial Chip
DW CLOCK ;Test 7 Real Time Clock
DW BAT.RAM ;Test 8 Battery ram
DW FDB ; Test 9 Front Desk Bus
DW SHADOW.TST ;Test OA Shadow
DO SEG.DEBUG ;Do following 'test' for debug only
DW TEST1 ;Fails if a key is pressed
FIN
DW CUSTOM.IRQ ;Test 0B Interrupts
SKP 1
TST.TAB.E EQU * ;End of test pointer table
DW EXT.SEQ ;Pointer for Disk s/w
SKP 1
BI.MASK EQU %1111111111111111 ;Tests to run if in BI and BTN0 = 1
SELF.MASK EQU %1111111111111111 ;Tests to run in self test
BI.SELF.MASK EQU %11111111001111111 ;Tests to run in BI and BTNO =0
SKP 1
```

The test pointer table resides at `DIAGNOSTICS+2`. 

To call a diagnostic routine simply JSL to the address pointed to by the table. 

Enter with Data Bank = `$00`, Native mode and 8 bit data and index. 

```
TST.TAB      DFB TST.TAB.E--3     ; Number of pointers times 2 
             DW ROM.CHECKSUM      ;Test 1 128K rom 
             DW MOVIRAM           ;Test 2 Ram: Moving Inversions 
             DW SOFT.SW           ;Test 3 Mega // & Statereg softswitch test 
             DW RAM.ADDR          ;TEST 4 Ram: Addressing 
             DW FPI.SPEED         ;Test 5 Fpi fast/slow mode check 
             DW SER.TST           ;Test 6 Serial Chip 
             DW CLOCK             ;Test 7 Real Time Clock 
             DW BAT.RAM           ;Test 8 Battery ram 
             DW FDB               ;Test 9 Front Desk Bus 
             DW SHADOW.TST        ;Test 0A Shadow 
             DW CUSTOM.IRQ        ;Test 0B Interrupts 
TST.TAB.E    EQU * ;End of test pointer table 
```

```
BI.MASK        EQU %1111111111111111  ; Tests to run if in BI and BTN0 = 1 
SELF.MASK      EQU %0000011111111111  ; Tests to run in self test 
BI.SELF.MASK   EQU %1111111100111111  ; Tests to run in BI and BTN0 = 0 
```

-----

## Using Battery Ram (NVR) for Burn In 

The pre Burn In tester is required to set up the following NVR registers: 

  * **BI.STATUS**: Set to zero 
  * **BI.COUNTER**: Set to zero 
  * **BI.PASSES**: Set to zero 
  * **BI.FAILS**: Set to zero 
  * **BI.LASTF**: Set to zero 
  * **CYCLES.MAX**: Set to number of BI test cycles. 
  * **VALID.CHK**: Set to `$CBD2C7` 
  * **BI.ALT.MASK**: Set what tests to run. 

### Writing to NVR (Pre Burn-in tester) 

The registers above start in location `$A1` in NVR. 

### Reading NVR (Post Burn-In tester) 

Use `TOREADER` to retrieve the contents of these registers after Burn In. 

The locations of `TOREADER` and `TOWRITEBR` can be found in the file `BANKFF.EQUATES2` used in the bank `$FF` rom source. 
