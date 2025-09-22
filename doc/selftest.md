# Vegas ROM Diagnostics

  * [cite\_start]**Date**: 05 May 1986 [cite: 1, 3]
  * [cite\_start]**Author**: Karl Grabe [cite: 2, 4, 5]
  * [cite\_start]**Subject**: Vegas ROM Diagnostics [cite: 6]
  * [cite\_start]**Document Version Number**: 00:40 [cite: 7]
  * [cite\_start]**Test Document Number**: TSKA 0047 [cite: 8]

-----

### [cite\_start]Revision History [cite: 9]

| Version | Notes |
| :--- | :--- |
| **00:00** | Initial Release (KRG) |
| **00:10** | Error codes changed for Alpha 2.0 (KRG)\<br\>Test pointer table described\<br\>Self Test System Beep' shortened\<br\>Clock. Interrupt, FPI Speed tests added for Alpha 2.0 |
| **00:20**\<br\>**00:30** | Staggered screen error code for ram failures (16 Mar86 KRG)\<br\>Rom Checksum "RN" error code added\<br\>"BR" Error message removed\<br\>Burn In Non Volatile Ram usage (16 Apr86 KRG)\<br\>Burn In connector pin usage\<br\>Error Codes changed\<br\>FDB. Shadow tests added\<br\>Fail err code to port\!\<br\>Use of border colors for error detection\<br\>FDB UP fatal error code added\<br\>ROM checksum DD=01 error code added\<br\>Clock/NVR DD-01 error code added |
| **00:40** | Open and Closed apple keys to restart self test (KRG 4May86) |

-----

## [cite\_start]GENERAL [cite: 13]

[cite\_start]The Vegas ROM Diagnostics are used in the following environments: [cite: 14]

1.  [cite\_start]User Self Test [cite: 15]
2.  [cite\_start]Board level Burn-IN [cite: 16]
3.  [cite\_start]Board Level test [cite: 17]
4.  [cite\_start]Final System test [cite: 18]

[cite\_start]**Brief Description of above:** [cite: 19]

1.  [cite\_start]**User Self Test** [cite: 20]
    [cite\_start]This is the equivalent of the //e Kernal Test. [cite: 21] [cite\_start]The tests run here are a subset of those run in Burn-In. [cite: 21] [cite\_start]When the test completes a "System Good" or System Bad: Error code" message is displayed in 40 column text. [cite: 22] [cite\_start]Non Volatile Ram (NVR) is not used for test status storage. [cite: 22]

2.  [cite\_start]**Board Level Burn In** [cite: 23]
    [cite\_start]Vegas boards will have a burn in period of approx 48 hours for initial production. [cite: 24] [cite\_start]During this time the boards are power and temperature cycled. [cite: 25] [cite\_start]During each power on cycle a group of tests are run several times. [cite: 26] [cite\_start]At the end of the cycles the test status is stored in Non Volatile Ram (NVR) and the board awaits power down. [cite: 27] [cite\_start]On each power up test status is read back from NVR. [cite: 28] [cite\_start]After burn in the post Bl tester reads back NVR test results. [cite: 29]

3.  [cite\_start]& 4) **Board and Final System Test** [cite: 30]
    [cite\_start]In these environments, or anytime disk-based diagnostics are running, any or all of the built in ROM tests can be run. [cite: 31] [cite\_start]This is achieved using a table of pointers starting at the 2nd byte of the diagnostics. [cite: 32]

[cite\_start]The ROM Diagnostics are broken into two parts: [cite: 33]

1.  [cite\_start]The Test Sequencer [cite: 34]
2.  [cite\_start]The tests [cite: 35]

[cite\_start]The Test Sequencer is described next in detail. [cite: 36] [cite\_start]For a description of the individual tests see page 8. [cite: 36]

-----

## [cite\_start]Overview [cite: 39]

### [cite\_start]1 The Test Sequencer [cite: 40]

[cite\_start]This piece of code is responsible for determining what the test environment is, running the appropriate tests and storing/displaying the test results. [cite: 41] [cite\_start]The sequencer supervises both Burn-in and User Selt test. [cite: 42] [cite\_start]The sequencer is not used with disk based diagnostics (eg board functional test) but the tests themselves can be called if required. [cite: 42]

[cite\_start]The sequencer determines the test environment using signals brought out on the Burn-In connector on the front LHS of the logic board. [cite: 43] [cite\_start]The input signals are SW0, SW1, and DIAGSW. [cite: 44] [cite\_start]SWO & 1 are the open and closed apple keys resp. and also button 0 & 2 resp. on the game 1/0 connector. [cite: 45] [cite\_start]DIAGSW is an unused Mega // input (originally intended as a mouse button down input). [cite: 46] [cite\_start]The following table shows the different possibilities following a processor reset (including power up), note the User Self test is invoked exactly the same way as on the //e. [cite: 47]

### [cite\_start]Soft Switches for Burn In/Self test [cite: 48]

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
[cite\_start]a) `wr NVR` write test STATUS registers to Non Volatile Ram. [cite: 50, 51]
[cite\_start]b) `DIAGSTYPE (MSB #C046)` is active lo es MSB is a hi on the Burn in connector ($1 = \\text{DIAGSW}$ on connector) [cite: 52, 53]
[cite\_start]c) with no keyboard plugged in `SW0` & `1` are `=0` as opposed to 1 on a //e. [cite: 54, 55] [cite\_start]A Vegas will not run Self Diagnostics on power up when the keyboard is not attached. [cite: 56]
[cite\_start]d) `DIAGSW` is only available on the BI connector. [cite: 57] [cite\_start]The user can't get into burn in diagnostics. [cite: 57]

[cite\_start]The sequencer determines what tests to run from a 16 bit test mask. [cite: 60] [cite\_start]This test mask is fixed (in rom) for User Selt test and programmable (using NVR set up by the Pre-Burn-In functional tester) in Burn-In. [cite: 61] [cite\_start]This allows the board manufacturing site to experiment with turning different tests, particularly ram tests, on and off to see which tests catch the most failures. [cite: 62]

-----

## [cite\_start]Test Sequencer User Self Test [cite: 65]

[cite\_start]The tests run here are a subset of those run in Burn-In. [cite: 66] [cite\_start]User Self Test may be invoked in several ways: [cite: 67]

1.  [cite\_start]Press Control-Open Apple-Closed Apple-Reset (retro only) [cite: 68]
2.  [cite\_start]Press Control-Funct-Open Apple-Reset (Cortland only) [cite: 69]
3.  [cite\_start]Press Open Apple-Closed Apple on power up (retro only) [cite: 70]
4.  [cite\_start]Press Funct-Open Apple on power up (Cortland only) [cite: 70]
5.  [cite\_start]Press Game I/O buttons BTN0, BTN1 on power up [cite: 71]

[cite\_start]The test takes approx 35 seconds to complete. [cite: 72] [cite\_start]During most of this time the test number being executed is visible on the bottom center of the screen followed by 6 zeros. [cite: 72]

[cite\_start]After all tests have been successfully completed a continuous 1 KHz ½-second beep is emitted and a `System Good` message is displayed on the screen. [cite: 73] [cite\_start]The beep is used in manufacturing to test the speaker at final system test. [cite: 74] [cite\_start]The system can now be rebooted by pressing Control-Reset or Self test can be re-activated by pressing both the Open- and Closed-Apple Keys. [cite: 75]

[cite\_start]If any tests fail then a 6 KHz ½-second beep is emitted. [cite: 76] [cite\_start]A `System Bad: AABBCCDD` message is displayed on the lower LHS of the screen and a staggered 'AABBCCDD' is also displayed on the upper LHS to help reading the error code in the event of a ram failure. [cite: 77] [cite\_start]'AA' is the test number that failed and BB-DD is the fail code. [cite: 78] [cite\_start]See individual tests for complete fail codes. [cite: 78]

[cite\_start]NVR is never read or written to by the sequencer. [cite: 80] [cite\_start]Some of the tests may use NVR but if so they will restore its contents after the test is complete. [cite: 81]

[cite\_start]Cork's final system test is performed with the housing cover on so it is not possible to monitor Self Test on the burn-in connector. [cite: 82] [cite\_start]Instead the disk phase lines are used. [cite: 83] [cite\_start]The phase lines were carefully chosen so that it would not affect any peripheral disk devices including UniDisk 3.5 that the user may have connected during User Self test. [cite: 83]

### [cite\_start]Error codes for Beta 2.0 and later rom releases: [cite: 84]

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

[cite\_start]For detailed error BBCCDD codes see individual test descriptions below. [cite: 86]

[cite\_start]The test number followed by 6 zeros is displayed just prior to calling each test and during execution of the test. [cite: 89] [cite\_start]This is done so that if the test hangs it is still possible to determine the most likely cause of the fault by reading the test number AA. [cite: 90] [cite\_start]If a test number followed by zeros is displayed on the screen for more than 35 seconds it is likely that that test has hung. [cite: 91] [cite\_start]Note that the test number is not displayed during the Moving Inversions Ram test; instead you see the hires or super res screen 1. [cite: 92]

[cite\_start]Also for `System Bad`: If the system fails self test the fail code bytes (6) preceded by a `@` are transmitted to the printer port. [cite: 93, 94] [cite\_start]This allows automatic error logging in Cork's Final System test. [cite: 95]

[cite\_start]Note: A `System Bad: FFxxxx` message means the system went into Burn In diagnostics. [cite: 97] [cite\_start]This should not occur in Self Test but if it does then there is probably a hardware problem with the Mega //. [cite: 98] [cite\_start]This error message is given because the sequencer expects Battery Ram to be set up in a specific way by the pre burn in tester before commencing the diagnostics. [cite: 99]

### [cite\_start]Interrupting Self Test [cite: 100]

[cite\_start]It is safe to interrupt the self test (by pressing Control Reset) only during the start of the Moving inversions ram test (while screen displays Hires/Super Hires patterns). [cite: 101] [cite\_start]An interruption after this may cause the contents of Battery Ram or the Clock Time to be corrupted. [cite: 102]

### [cite\_start]Board Level Rework: [cite: 103]

[cite\_start]Because the diagnostics require some of the system to be functional before they will run properly it is likely that they may crash/hang on boards that have serious hardware problems. [cite: 104] [cite\_start]The rom diagnostics sequencer has several features built in to help in these situations: [cite: 105]

  * [cite\_start]a) The test number is printed on the screen BEFORE the test is executed. [cite: 106] [cite\_start]If the test hangs then it is most likely that the last test number printed on the screen is causing the problem. [cite: 107]
  * [cite\_start]b) The sequencer changes the border colour each time a new test is run. [cite: 108] [cite\_start]By noting how the colours change on a good system it is possible to determine where a problem is occurring on a bad system in cases where screen text is not working. [cite: 109] [cite\_start]The colours start at 0 and increment once for each test with the exception of the moving inversions ram test which increments a further 4 times by itself. [cite: 110]
  * [cite\_start]c) The fail error code is sent to port 1. [cite: 112] [cite\_start]Again this is useful if video is non functional. [cite: 112, 113]
  * [cite\_start]d) The error code is printed on the top LHS of the screen 3 time and staggered. [cite: 113] [cite\_start]This helps reading the error code in the event of partial ram failures. [cite: 114]
  * [cite\_start]e) The first part of the rom checksum test (which is the very first test) does a register based ram test for `$0000` to `$0400` in bank zero. [cite: 117] [cite\_start]This prevents a rom error code being presented when there is really a ram problem (the rom checksum routine uses some ram). [cite: 118]

### [cite\_start]Self Test Annunciator/Disk Port Truth Table [cite: 119]

[cite\_start]Note: Use an LEDs connected via a buffer to game 1/0 connector or disk port to verify UUT without VDU. [cite: 121, 122]

| AN0 | AN1 | MODE |
| :--- | :--- | :--- |
| 1 | 0 | Test running |
| 0 | 0 | Testing complete, all tests pass |
| 1 | 1 | Testing complete, a test failed |
| | | **Phase 1 | Phase 2** | - Final System Test with cover on |
| | | 13/14 | 17/18 | \<- B1 Connector Pins |

[cite\_start]Note: Cork uses disk port phase lines P1 & P2 to match AN0 & AN1 [cite: 124]

-----

## [cite\_start]Test Sequencer: Burn In [cite: 127]

[cite\_start]In Burn In the number of test cycles the board performs before awaiting power down is programmable (by the Pre-Burn-In Functional tester). [cite: 128] [cite\_start]The following is a list or NVR registers used by the Pre-Burn In tester, BI rom diagnostics, and the Post Bl tester: [cite: 128]

  * [cite\_start]`BI.STATUS`: Test Results Stored by ROM diagnostics [cite: 129, 140]
  * [cite\_start]`BI.COUNTER`: Counts the number of test cycles done ROM Diag [cite: 130, 141]
  * [cite\_start]`BI.PASSES`: Number of cycles passed- ROM diagnostic [cite: 131, 142]
  * [cite\_start]`BI.FAILS`: Number of cycles failed - ROM diagnostic [cite: 133, 143]
  * [cite\_start]`BI.LASTF`: The cycle the last fail occurred on -\> ROM diagnostic [cite: 135, 144]
  * [cite\_start]`CYCLES.MAX`: Test cycles per power cycle-\> Pre BI Tester [cite: 137, 145]
  * [cite\_start]`VALID.CHK`: 3 byte check signature Pre BI Tester [cite: 138, 146]
  * [cite\_start]`BI.ALT.MASK`: What tests to run Pre BI tester. [cite: 139, 147]

[cite\_start]These registers work in the manufacturing process in the following manner: [cite: 148]
[cite\_start]a) The Pre-BI board tester tests the board and if it passed sets up the following NVR registers: `CYCLES.MAX`, `VALID.CHECK`, `BI.ALT.MASK`. [cite: 149] [cite\_start]Each bit in the 16 bit `BI.ALT.MASK` represents a test in rom and may be turned on or off. [cite: 150]
[cite\_start]b) When the board is in Burn In the sequencer looks for a certain sequence in the `VALID.CHECK` bytes. [cite: 151] [cite\_start]If this sequence is not found then the Pre-BI tester failed to set up NVR or the UUT/NVR is bad so the test waits setting the FAIL.LED(AN0). [cite: 152] [cite\_start]If this sequence is correct then the tests mask `BI.ALT.MASK` is used instead of the default mask. [cite: 153] [cite\_start]The entire test sequence is repeated for a number of cycles `CYCLES.MAX`. [cite: 154] [cite\_start]When the cycles are complete the power off annunciator is activated to tell the BI controller that the UUT is inactive and ready to power down. [cite: 155] [cite\_start]Test fail status (if any) is stored in NVR to be read by the Post-BI tester. [cite: 156]
[cite\_start]c) The Post Bl tester reads all NVR registers from which it can determine the following: [cite: 158]

1.  [cite\_start]If the board executed correct \# of test cycles (`BI.COUNTER`) [cite: 159]
2.  [cite\_start]Whether the board failed at any time during BI [cite: 160]
3.  [cite\_start]How often it failed (`BI.FAILS`) [cite: 162]
4.  [cite\_start]When the fail(s) occurred (`BI.LASTF`) [cite: 163]
5.  [cite\_start]What test last failed and its error code (`BI.STATUS`) [cite: 164]

### [cite\_start]Burn In Annunciator/Disk Port Truth Table: [cite: 172]

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

[cite\_start]Note: Cork uses disk port phase lines P1 & P2 to match AN0 & AN1 [cite: 176]

-----

## [cite\_start]ROM Tests available: [cite: 180, 183]

[cite\_start]This is a list of tests in ROM: [cite: 181]

[cite\_start]Note: Each TEST NO corresponds to a bit in the 16 bit C register on calling `EXT.SED`. [cite: 184] [cite\_start]If the bit is true then the test is run, else it is skipped. [cite: 185] [cite\_start]The test subroutine must clear the carry if the test passed, else set the carry. [cite: 186]

| TST NO | Test(s) performed |
| :--- | :--- |
| **LSB: 0** | [cite\_start]Bank FE/ FF Roms Checksum [cite: 190] |
| **1** | [cite\_start]Ram: Moving Inversions [cite: 192] |
| **2** | [cite\_start]Softswitch/STATEREG test [cite: 193] |
| **3** | [cite\_start]Ram: Addressing [cite: 194] |
| **4** | [cite\_start]FPI/Video Counters Speed verification [cite: 196] |
| **5** | [cite\_start]Serial: Internal Loopback [cite: 198] |
| **6** | [cite\_start]Real Time Clock [cite: 200] |
| **7** | [cite\_start]Battery Ram [cite: 201] |
| **8** | [cite\_start]Front Desk Bus Processor & Rom [cite: 202] |
| **9** | [cite\_start]Shadow register [cite: 203] |
| **10** | [cite\_start]Interrupts [cite: 204] |
| **11** | - |
| **12** | - |
| **13** | - |
| **14** | - |
| **15** | - |

[cite\_start]Each test is now given a brief description on the next page [cite: 212]

-----

## [cite\_start]ROM Tests: [cite: 215]

[cite\_start]System Self Test errors are in the format: `System Bad: AABBCCDD` [cite: 216]

[cite\_start]**Serial Tests (J. Reynolds)** [cite: 217]
[cite\_start]The serial chip registers are tested for Read/Write. [cite: 218] [cite\_start]Then an internal loop back test is performed. [cite: 218]
[cite\_start]Error code `AA=06`. [cite: 219] [cite\_start]BB is as follows: [cite: 219]

  * [cite\_start]`BB=01`: Register R/W [cite: 220]
  * [cite\_start]`BB=04`: Tx Buffer empty status [cite: 221]
  * [cite\_start]`BB=05`: Tx Buffer empty failure [cite: 222]
  * [cite\_start]`BB=06`: All sent status fail [cite: 223]
  * [cite\_start]`BB=07`: Rx char available [cite: 224]
  * [cite\_start]`BB=08`: Bad data [cite: 225]

[cite\_start]**Ram 1 (R. Carr) Moving Inversions** [cite: 226]
[cite\_start]This checks bank 0 ram pages 0 thru 4 non-destructively and then tests the remaining ram in bank 0. [cite: 227] [cite\_start]This is repeated for banks `$01`, `$E0`, `$E1`. [cite: 227]
[cite\_start]Error code `AA=02`. [cite: 228] [cite\_start]`BBCC`=Address [cite: 228]

[cite\_start]**ROM Checksum (KRG)** [cite: 229]
[cite\_start]This computes the checksum of Banks `$FE` & `$FF` and compares it against a known good value. [cite: 230] [cite\_start]For a fail "RN" appears on top LHS of screen. [cite: 231] [cite\_start]This is done as there is a reasonable chance that the system will crash before printing the error code. [cite: 232]
[cite\_start]Error code `AA=01`, `BB=1`=Failed checksum. [cite: 233] [cite\_start]If `DD=1` then the test encountered bad ram and the error code is a ram error code similar to the `MOVIRAM` errorcodes. [cite: 233]

[cite\_start]**Speed (KRG)** [cite: 234]
[cite\_start]Here the relative speed of the video counters is compared to the system speed in fast and slow modes. [cite: 235] [cite\_start]It checks that the system is capable of switching speed, that the FPI slows down when accessing the Mega // and that the video counters are working. [cite: 236]
[cite\_start]Error code `AA=05`, `BB=1` speed stuck slow, `BB=2` speed stuck fast. [cite: 237]

[cite\_start]**Battery Ram or NVR (KRG)** [cite: 238]
[cite\_start]This tests the 255 byte Non Volatile Ram non destructively. [cite: 239] [cite\_start]An address uniqueness tests is followed by a pattern test. [cite: 239, 240]
[cite\_start]Error code `AA=08`. [cite: 241]
[cite\_start]`BB=01` is address test and `CC`=bad address value [cite: 242]
[cite\_start]`BB=02` is memory fail and `CC`=pattern, `DD`=address [cite: 243, 244]

[cite\_start]**Soft Switches/STATEREG (KRG)** [cite: 247]
[cite\_start]This tests all soft switches by setting/testing and clearing/testing. [cite: 248] [cite\_start]Eight of the softswitches have an equivalent bit in the STATEREG and these are also tested. [cite: 248] [cite\_start]All combinations of setting/clearing a softswitch directly and with the STATEREG are tested. [cite: 249]
[cite\_start]Error code `AA=02`, `BB`=STATEREG bit, `CC`=Read softswitch address. [cite: 250]

[cite\_start]**Front Desk Bus (KRG)** [cite: 251]
[cite\_start]Reads the entire FDB processor rom into Vegas memory and computes a checksum. [cite: 252] [cite\_start]If this is as expected then the FDB processor is functional and all the language layouts are correct. [cite: 253] [cite\_start]Test works with REV 2 and subsequent revs of FDB processor. [cite: 254]
[cite\_start]Error code `AA=09`, `BBCC`=Bad checksum found. [cite: 255] [cite\_start]If `DD=01` then the FDB toolcode encountered a fatal error and no checksum was computed. [cite: 255]

[cite\_start]**Ram Address (RCarr)** [cite: 256]
[cite\_start]This is a ram test testing unique addressing capability of Vegas ram. [cite: 257] [cite\_start]Address uniqueness between banks is also tested. [cite: 257]
[cite\_start]Error code `AA=04`, `BB=F` Failed Bank No. `CC`=Failed bit. [cite: 258]

[cite\_start]**Clock Test (KRG)** [cite: 259]
[cite\_start]Performs a R/W test on the 32 bit clock register. [cite: 260] [cite\_start]The time is restored after the test (to within a second). [cite: 261]
[cite\_start]Error code `AA=07`, `BBCCDD` not used. [cite: 262] [cite\_start]If `DD=01` then a fatal error occurred and the test was aborted. [cite: 262]

[cite\_start]**Shadow Register (J. Reynolds)** [cite: 263]
[cite\_start]Tests the functionality of the shadow register. [cite: 264]
[cite\_start]Error code `AA=0A`. [cite: 265]

[cite\_start]**Interrupts (J. Reynolds)** [cite: 266]
[cite\_start]Tests Mega// and VGC capability of generating interrupts. [cite: 267] [cite\_start]Error code `AA=0B`: [cite: 267]

  * [cite\_start]`BB=01`: VBL interrupt timeout [cite: 268]
  * [cite\_start]`BB=02`: VBL IRQ status fail [cite: 269]
  * [cite\_start]`BB=03`: 1/4 SEC INTERRUPT [cite: 270]
  * [cite\_start]`BB=04`: 1/4 SEC INTERRUPT [cite: 271]
  * [cite\_start]`BB=05`: [not defined] [cite: 271]
  * [cite\_start]`BB=06`: VGC IRQ [cite: 272]
  * [cite\_start]`BB=07`: SCAN LINE [cite: 273]

[cite\_start]**Burn In error** [cite: 274]
[cite\_start]Error code `AA=FF`, `BBCCDD` not defined [cite: 275]
[cite\_start]This error code should only occur when running burn in diagnostics (ie when pins 9 or 10 on the burn in connector are grounded). [cite: 278] [cite\_start]This code means that NVR was not correctly set up (by the pre BI tester) for Burn In or that the Battery ram is bad. [cite: 279]

-----

## [cite\_start]Calling rom tests using Test Pointer Table: [cite: 282]

[cite\_start]The test pointer table resides at `DIAGNOSTICS+2`. [cite: 283] [cite\_start]Currently the diagnostics begin at `$FF7400` (this is not expected to change) so the table begins at `$FF7402`. [cite: 283] [cite\_start]The first byte is the size of the table followed by the 2 byte pointers themselves. [cite: 283] [cite\_start]For Alpha 2.0 the pointer table starts at `$FF7430`. [cite: 283] [cite\_start]For Beta 1.0 and later it's at `$FF7402`. [cite: 283]

[cite\_start]To call a diagnostic routine simply JSL to the address pointed to by the table. [cite: 284] [cite\_start]On return the carry flag is clear if the test passes or set if it fails. [cite: 285] [cite\_start]For a fail, the error status is stored in the 5 `TST.STATUS` registers (currently at `$000315` and is not expected to change). [cite: 286] [cite\_start]The error codes are the same as those in self test. [cite: 287] [cite\_start]You should clear these registers before calling the test routine. [cite: 288]

[cite\_start]Enter with Data Bank = `$00`, Native mode and 8 bit data and index. [cite: 289] [cite\_start]Return will be in Native mode with the M, X and data bank in unknown states. [cite: 290] [cite\_start]Note that the main ram tests are destructive above `$0400` in all banks\! [cite: 291]

```
TST.TAB      DFB TST.TAB.E--3     ; [cite_start]Number of pointers times 2 [cite: 300]
             [cite_start]DW ROM.CHECKSUM      ;Test 1 128K rom [cite: 302]
             [cite_start]DW MOVIRAM           ;Test 2 Ram: Moving Inversions [cite: 303]
             [cite_start]DW SOFT.SW           ;Test 3 Mega // & Statereg softswitch test [cite: 304]
             [cite_start]DW RAM.ADDR          ;TEST 4 Ram: Addressing [cite: 305]
             [cite_start]DW FPI.SPEED         ;Test 5 Fpi fast/slow mode check [cite: 306]
             [cite_start]DW SER.TST           ;Test 6 Serial Chip [cite: 307]
             [cite_start]DW CLOCK             ;Test 7 Real Time Clock [cite: 308]
             [cite_start]DW BAT.RAM           ;Test 8 Battery ram [cite: 309]
             [cite_start]DW FDB               ;Test 9 Front Desk Bus [cite: 310]
             [cite_start]DW SHADOW.TST        ;Test 0A Shadow [cite: 311]
             [cite_start]DW CUSTOM.IRQ        ;Test 0B Interrupts [cite: 315]
[cite_start]TST.TAB.E    EQU * ;End of test pointer table [cite: 317]
```

```
BI.MASK        EQU %1111111111111111  ; [cite_start]Tests to run if in BI and BTN0 = 1 [cite: 319]
SELF.MASK      EQU %0000011111111111  ; [cite_start]Tests to run in self test [cite: 319]
BI.SELF.MASK   EQU %1111111100111111  ; [cite_start]Tests to run in BI and BTN0 = 0 [cite: 320, 321]
```

-----

## [cite\_start]Using Battery Ram (NVR) for Burn In [cite: 324]

[cite\_start]The pre Burn In tester is required to set up the following NVR registers: [cite: 325]

  * [cite\_start]**BI.STATUS**: Set to zero [cite: 326, 327]
  * [cite\_start]**BI.COUNTER**: Set to zero [cite: 328, 329]
  * [cite\_start]**BI.PASSES**: Set to zero [cite: 330, 331]
  * [cite\_start]**BI.FAILS**: Set to zero [cite: 332, 333]
  * [cite\_start]**BI.LASTF**: Set to zero [cite: 334, 335]
  * [cite\_start]**CYCLES.MAX**: Set to number of BI test cycles. [cite: 336] [cite\_start]Currently this should by 26 for a 20 minute power on cycle time. [cite: 337, 338]
  * [cite\_start]**VALID.CHK**: Set to `$CBD2C7` [cite: 339]
  * [cite\_start]**BI.ALT.MASK**: Set what tests to run. [cite: 340] [cite\_start]Normally `$FFFF` for all tests. [cite: 341]

### [cite\_start]Writing to NVR (Pre Burn-in tester) [cite: 342]

[cite\_start]The registers above start in location `$A1` in NVR. [cite: 343] [cite\_start]The easiest way to write to them is to call the `TOWRITEBR` hook. [cite: 343] [cite\_start]This copies a page of main ram starting at `$E10200` to NVR. [cite: 344] [cite\_start]The first register, `BI.STATUS`, is at location `$E10200` + `$A1` = `$E10341`. [cite: 344]

### [cite\_start]Reading NVR (Post Burn-In tester) [cite: 345]

[cite\_start]Use `TOREADER` to retrieve the contents of these registers after Burn In. [cite: 346] [cite\_start]This routine loads NVR into a page in main ram starting at location `$E10200` so the first register is at `$E10341` as before. [cite: 347]

[cite\_start]The locations of `TOREADER` and `TOWRITEBR` can be found in the file `BANKFF.EQUATES2` used in the bank `$FF` rom source. [cite: 348] [cite\_start]Currently `TOREADER` is at `$E10084` and `TOWRITEBR` at `$E10080`. [cite: 349]
