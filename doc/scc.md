# [cite_start]Z80C30/Z85C30 CMOS SCC Serial Communications Controller Product Specification [cite: 3, 4, 5]

[cite_start]*PS011708-0115* [cite: 6]

---
### [cite_start]**Warning: DO NOT USE THIS PRODUCT IN LIFE SUPPORT SYSTEMS.** [cite: 13]

[cite_start]**LIFE SUPPORT POLICY** [cite: 14]

[cite_start]ZILOG'S PRODUCTS ARE NOT AUTHORIZED FOR USE AS CRITICAL COMPONENTS IN LIFE SUPPORT DEVICES OR SYSTEMS WITHOUT THE EXPRESS PRIOR WRITTEN APPROVAL OF THE PRESIDENT AND GENERAL COUNSEL OF ZILOG CORPORATION. [cite: 15]

[cite_start]As used herein: [cite: 16]

[cite_start]Life support devices or systems are devices which (a) are intended for surgical implant into the body, or (b) support or sustain life and whose failure to perform when properly used in accordance with instructions for use provided in the labeling can be reasonably expected to result in a significant injury to the user. [cite: 17] [cite_start]A critical component is any component in a life support device or system whose failure to perform can be reasonably expected to cause the failure of the life support device or system or to affect its safety or effectiveness. [cite: 18]

[cite_start]**Document Disclaimer** [cite: 19]

[cite_start]©2015 Zilog, Inc. [cite: 20] [cite_start]All rights reserved. [cite: 20] [cite_start]Information in this publication concerning the devices, applications, or technology described is intended to suggest possible uses and may be superseded. [cite: 20] [cite_start]Zilog, INC. DOES NOT ASSUME LIABILITY FOR OR PROVIDE A REPRESENTATION OF ACCURACY OF THE INFORMATION, DEVICES, OR TECHNOLOGY DESCRIBED IN THIS DOCUMENT. [cite: 21] [cite_start]Zilog ALSO DOES NOT ASSUME LIABILITY FOR INTELLECTUAL PROPERTY INFRINGEMENT RELATED IN ANY MANNER TO USE OF INFORMATION, DEVICES, OR TECHNOLOGY DESCRIBED HEREIN OR OTHERWISE. [cite: 22] [cite_start]The information contained within this document has been verified according to the general principles of electrical and mechanical engineering. [cite: 23] [cite_start]Z8 is a registered trademark of Zilog, Inc. [cite: 24] [cite_start]All other product or service names are the property of their respective owners. [cite: 24]

---
### [cite_start]**Revision History** [cite: 31, 36]

[cite_start]Each instance in Revision History reflects a change to this document from its previous revision. [cite: 32]

| Date | Revision Level | Description | Page |
| :--- | :--- | :--- | :--- |
| Jan 2015 | 08 | [cite_start]Updated the Ordering Information chapter to delete Z80C3008PSG and Z80C3010PSG, which are EOL status. [cite: 34] | [cite_start]75 [cite: 34] |
| Oct 2012 | 07 | [cite_start]Corrected state of RTSB pin on Z85C30 DIP package; corrected name of PCLK pin on Z85C30 PLCC package. [cite: 34] | [cite_start]11, 12 [cite: 34] |
| May 2011 | 06 | [cite_start]Corrected Ordering Information chapter to reflect lead-free parts; updated logo and style to conform to current template. [cite: 34] | [cite_start]75, all [cite: 34] |
| Jun 2008 | 05 | [cite_start]Updated Zilog logo, Zilog Text, Disclaimer as per latest template. [cite: 34] | [cite_start]All [cite: 34] |
| Aug 2001 | 01 | [cite_start]Original issue [cite: 34] | [cite_start]All [cite: 34] |

---
## [cite_start]Overview [cite: 80, 106]

[cite_start]The features of Zilog's Z80C30 and Z85C30 devices include: [cite: 85]

* [cite_start]Z85C30: optimized for nonmultiplexed bus microprocessors [cite: 86]
* [cite_start]Z80C30: optimized for multiplexed bus microprocessors [cite: 87]
* [cite_start]Pin-compatible to NMOS versions [cite: 88]
* [cite_start]Two independent 0 to 4.1 Mbps, full-duplex channels, each with separate crystal oscillator, Baud Rate Generator (BRG), and Digital Phase-Locked Loop (DPLL) for clock recovery [cite: 89]
* [cite_start]Multiprotocol operation under program control; programmable for NRZ, NRZI or FM data encoding [cite: 90]
* [cite_start]Asynchronous Mode with 5 to 8 bits and 1, 1/2, or 2 stop bits per character, programmable clock factor, break detection and generation; parity, overrun, and framing error detection [cite: 91, 92]
* [cite_start]Synchronous Mode with internal or external character synchronization on 1 or 2 synchronous characters and CRC generation and checking with CRC-16 or CRC-CCITT preset to either 1s or 0s [cite: 93]
* [cite_start]SDLC/HDLC Mode with comprehensive frame-level control, automatic zero insertion and deletion, I-Field residue handling, abort generation and detection, CRC generation and checking, and SDLC loop [cite: 94]
* [cite_start]Software interrupt acknowledge feature (not available with NMOS) [cite: 95]
* [cite_start]Local Loopback and Auto Echo modes [cite: 96]
* [cite_start]Supports T1 Digital Trunk76 [cite: 97]
* [cite_start]Enhanced DMA support (not available with NMOS), $10 \times 19$-bit status FIFO, 14-bit byte counter [cite: 98]
* [cite_start]Speeds [cite: 99]
    * [cite_start]Z85C3O: 8.5, 10, 16.384MHz [cite: 100]
    * [cite_start]Z80C3O: 8, 10MHz [cite: 101]

### [cite_start]Z85C30-Only Features [cite: 102]
[cite_start]Some of the features listed below are available by default. [cite: 103] [cite_start]Some of them (features with \*) are disabled on default to maintain compatibility with the existing Serial Communications Controller (SCC) design, and program to enable through WR7': [cite: 104]

* [cite_start]New programmable Write Register 7 prime (WR7') to enable new features [cite: 111]
* [cite_start]Improvements to support the SDLC Mode of synchronous communication: [cite: 112]
    * [cite_start]Improve functionality to ease sending back-to-back frames [cite: 113]
    * [cite_start]Automatic SDLC opening Flag transmission [cite: 114]
    * [cite_start]Automatic Tx Underrun/EOM Latch reset in SDLC Mode [cite: 115]
    * [cite_start]Automatic $\overline{RTS}$ deactivation [cite: 116]
    * [cite_start]TxD pin forced High in SDLC NRZI Mode after closing flag [cite: 117]
    * [cite_start]Complete CRC reception [cite: 118]
    * [cite_start]Improved response to Abort sequence in status FIFO [cite: 119]
    * [cite_start]Automatic Tx CRC generator preset/reset [cite: 120]
* [cite_start]Extended read for write registers [cite: 121]
* [cite_start]Write data set-up timing improvement [cite: 122]
* [cite_start]Improved AC timing: [cite: 123]
    * [cite_start]3 to 3.6 PCLK access recovery time [cite: 124]
    * [cite_start]Programmable DTR/REQ timing [cite: 125]
    * [cite_start]Write data to falling edge of $\overline{WR}$ setup time requirement is now eliminated [cite: 126]
    * [cite_start]Reduced INT timing [cite: 126]
* [cite_start]Other features include: [cite: 127]
    * [cite_start]Extended read function to read back the written value to the write registers [cite: 128]
    * [cite_start]Latching RR0 during read [cite: 128]
    * [cite_start]RR0, bit D7 and RR10, bit D6 now has reset default value [cite: 129]

---
## [cite_start]General Description [cite: 136, 150]

[cite_start]The Z80C30/Z85C30 Serial Communications Controller (SCC), is a pin and software compatible CMOS member of the SCC family introduced by Zilog in 1981. [cite: 137] [cite_start]It is a dual-channel, multiprotocol data communications peripheral that easily interfaces with CPU's with either multiplexed or nonmultiplexed address/data buses. [cite: 137] [cite_start]The advanced CMOS process offers lower power consumption, higher performance, and superior noise immunity. [cite: 138] [cite_start]The programming flexibility of the internal registers allow the SCC to be configured to various serial communications applications. [cite: 139] [cite_start]The many on-chip features such as Baud Rate Generators (BRG), Digital Phase Locked Loops (DPLL), and crystal oscillators reduce the need for an external logic. [cite: 140] [cite_start]Additional features include a 10 x 19-bit status FIFO and 14-bit byte counter to support high speed SDLC transfers using DMA controllers. [cite: 141]

[cite_start]The SCC handles asynchronous formats, synchronous byte-oriented protocols such as IBM Bisync, and synchronous bit-oriented protocols such as HDLC and IBM SDLC. [cite: 142] [cite_start]This device supports virtually any serial data transfer application (for example, cassette, diskette, tape drives, etc.). [cite: 143] [cite_start]The device generates and checks CRC codes in any synchronous mode and can be programmed to check data integrity in various modes. [cite: 144] [cite_start]The SCC also contains facilities for modem controls in both channels. [cite: 145] [cite_start]In applications where these controls are not required, the modem controls can be used for general-purpose I/O. [cite: 146] [cite_start]The daisy-chain interrupt hierarchy is also supported. [cite: 147] [cite_start]Figure 1 shows a block diagram of the SCC. [cite: 148]

[cite_start][Image: Figure 1. SCC Block Diagram] [cite: 197]

---
## [cite_start]Pin Descriptions [cite: 204, 230]

### [cite_start]Common Pin Functions [cite: 205]

#### [cite_start]$\overline{CTSA}$, $\overline{CTSB}$ [cite: 206]
[cite_start]Clear To Send (inputs, active Low). [cite: 221] [cite_start]If these pins are programmed for Auto Enable functions, a Low on the inputs enables the respective transmitters. [cite: 221] [cite_start]If not programmed as Auto Enable, these pins can be used as general-purpose inputs. [cite: 222] [cite_start]Both inputs are Schmitt-trigger buffered to accommodate slow rise-time inputs. [cite: 223] [cite_start]The SCC detects pulses on these inputs and can interrupt the CPU on both logic level transitions. [cite: 224]

#### [cite_start]$\overline{DCDA}$, $\overline{DCDB}$ [cite: 207]
[cite_start]Data Carrier Detect (inputs, active Low). [cite: 226] [cite_start]These pins function as receiver enables if programmed for Auto Enable. [cite: 226] [cite_start]Otherwise, these pins are used as general-purpose input pins. [cite: 227] [cite_start]Both pins are Schmitt-trigger buffered to accommodate slow rise-time signals. [cite: 227] [cite_start]The SCC detects pulses on these pins and can interrupt the CPU on both logic level transitions. [cite: 228]

#### [cite_start]$\overline{DTR/REQA}$, $\overline{DTR/REQB}$ [cite: 235]
[cite_start]Data Terminal Ready/Request (outputs, active Low). [cite: 236] [cite_start]These outputs follow the state programmed into the DTR bit. [cite: 236] [cite_start]They can also be used as general-purpose outputs or as Request lines for a DMA controller. [cite: 237]

#### [cite_start]IEI [cite: 238]
[cite_start]Interrupt Enable In (input, active High). [cite: 239] [cite_start]IEI is used with IEO to form an interrupt daisy-chain when there is more than one interrupt driven device. [cite: 239] [cite_start]A high IEI indicates that no other higher priority device has an interrupt under service or is requesting an interrupt. [cite: 240]

#### [cite_start]IEO [cite: 241]
[cite_start]Interrupt Enable Out (output, active High). [cite: 242] [cite_start]IEO is High only if IEI is High and the CPU is not servicing the SCC interrupt or the SCC is not requesting an interrupt (interrupt Acknowledge cycle only). [cite: 242] [cite_start]IEO is connected to the next lower priority device's IEI input and thus inhibits interrupts from lower priority devices. [cite: 243]

#### [cite_start]$\overline{INT}$ [cite: 244]
[cite_start]Interrupt Request (output, open-drain, active Low). [cite: 245] [cite_start]This signal activates when the SCC requests an interrupt. [cite: 245]

#### [cite_start]$\overline{INTACK}$ [cite: 246]
[cite_start]Interrupt Acknowledge (input, active Low). [cite: 247] [cite_start]This signal indicates an active Interrupt Acknowledge cycle. [cite: 247] [cite_start]During this cycle, the SCC interrupt daisy chain settles. [cite: 248] [cite_start]When $\overline{RD}$ is active, the SCC places an interrupt vector on the data bus (if IEI is High). [cite: 248] [cite_start]$\overline{INTACK}$ is latched by the rising edge of PCLK. [cite: 249]

#### [cite_start]PCLK [cite: 250]
[cite_start]Clock (input). [cite: 251] [cite_start]This is the master SCC clock used to synchronize internal signals. [cite: 251] [cite_start]PCLK is a TTL level signal. [cite: 251] [cite_start]PCLK is not required to have any phase relationship with the master system clock. [cite: 252] [cite_start]The maximum transmit rate is $1/4$ PCLK. [cite: 253]

#### [cite_start]RxDA, RxDB [cite: 254]
[cite_start]Receive Data (inputs, active High). [cite: 255] [cite_start]These signals receive serial data at standard TTL levels. [cite: 255]

#### [cite_start]$\overline{RTXCA}$, $\overline{RTxCB}$ [cite: 264]
[cite_start]Receive/Transmit Clocks (inputs, active Low). [cite: 265] [cite_start]These pins can be programmed in several different operating modes. [cite: 265] [cite_start]In each channel, RTxC can supply the receive clock, the transmit clock, clock for the Baud Rate Generator, or the clock for the Digital Phase-Locked Loop. [cite: 266] [cite_start]These pins can also be programmed for use with the respective SYNC pins as a crystal oscillator. [cite: 267] [cite_start]The receive clock can be 1, 16, 32, or 64 times the data rate in Asynchronous modes. [cite: 268]

#### [cite_start]$\overline{RTSA}$, $\overline{RTSB}$ [cite: 269]
[cite_start]Request To Send (outputs, active Low). [cite: 270] [cite_start]When the Request To Send (RTS) bit in Write Register 5 is set (see Figure 9 on page 22), the RTS signal goes Low. [cite: 270] [cite_start]When the RTS bit is reset in Asynchronous Mode and Auto Enable is ON, the signal goes High after the transmitter is empty. [cite: 271] [cite_start]In Synchronous Mode, it strictly follows the state of the RTS bit. [cite: 272] [cite_start]When Auto Enable is OFF, the RTS pins can be used as general-purpose outputs. [cite: 273]

#### [cite_start]$\overline{SYNCA}$, $\overline{SYNCB}$ [cite: 274]
[cite_start]Synchronization (inputs or outputs, active Low). [cite: 275] [cite_start]These pins function as inputs, outputs, or part of the crystal oscillator circuit. [cite: 275] [cite_start]In the Asynchronous Receive Mode (crystal oscillator option not selected), these pins are inputs similar to $\overline{CTS}$ and $\overline{DCD}$. [cite: 276] [cite_start]In this mode, transitions on these lines affect the state of the Synchronous/Hunt status bits in Read Register 0 but have no other function. [cite: 277] [cite_start]In External Synchronization Mode with the crystal oscillator not selected, these lines also act as inputs. [cite: 278] [cite_start]In this mode, $\overline{SYNC}$ must be driven Low for two receive clock cycles after the last bit in the synchronous character is received. [cite: 279] [cite_start]Character assembly begins on the rising edge of the receive clock immediately preceding the activation of $\overline{SYNC}$. [cite: 280] [cite_start]In the Internal Synchronization Mode (Monosync and Bisync) with the crystal oscillator not selected, these pins act as outputs and are active only during the part of the receive clock cycle in which synchronous characters are recognized. [cite: 281] [cite_start]This synchronous condition is not latched. [cite: 282] [cite_start]These outputs are active each time a synchronization pattern is recognized (regardless of character boundaries). [cite: 282] [cite_start]In SDLC Mode, these pins act as outputs and are valid on receipt of a flag. [cite: 283]

#### [cite_start]TxDA, TxDB [cite: 284]
[cite_start]Transmit Data (outputs, active High). [cite: 285] [cite_start]These output signals transmit serial data at standard TTL levels. [cite: 285]

#### [cite_start]$\overline{TRXCA}$, $\overline{TRxCB}$ [cite: 293]
[cite_start]Transmit/Receive Clocks (inputs or outputs, active Low). [cite: 294] [cite_start]These pins can be programmed in several different operating modes. [cite: 294] [cite_start]TRxC may supply the receive clock or the transmit clock in the input mode or supply the output of the Digital Phase-locked loop, the crystal oscillator, the Baud Rate Generator, or the transmit clock in the output mode. [cite: 295]

#### [cite_start]$\overline{W/REQA}$, $\overline{W/REQB}$ [cite: 296]
[cite_start]Wait/Request (outputs, open-drain when programmed for a Wait function, driven High or low when programmed for a Request function). [cite: 297] [cite_start]These dual-purpose outputs can be programmed as Request lines for a DMA controller or as Wait lines to synchronize the CPU to the SCC data rate. [cite: 298] [cite_start]The reset state is Wait. [cite: 299]

### [cite_start]Z85C30 [cite: 300]

#### [cite_start]A/$\overline{B}$ [cite: 308]
[cite_start]Channel A/Channel B (input). [cite: 311] [cite_start]This signal selects the channel in which the read or write operation occurs. [cite: 311]

#### [cite_start]$\overline{CE}$ [cite: 309]
[cite_start]Chip Enable (input, active Low). [cite: 312] [cite_start]This signal selects the SCC for a read or write operation. [cite: 312]

#### [cite_start]D7-D0 [cite: 319]
[cite_start]Data Bus (bidirectional, tri-state). [cite: 321] [cite_start]These lines carry data and command to and from the SCC. [cite: 321]

#### [cite_start]D/$\overline{C}$ [cite: 320]
[cite_start]Data/Control Select (input). [cite: 322] [cite_start]This signal defines the type of information transferred to or from the SCC. [cite: 322] [cite_start]A High indicates a data transfer; a Low indicates a command. [cite: 323]

#### [cite_start]$\overline{RD}$ [cite: 324]
[cite_start]Read (input, active Low). [cite: 327] [cite_start]This signal indicates a read operation and when the SCC is selected, enables the SCC's bus drivers. [cite: 327] [cite_start]During the Interrupt Acknowledge cycle, this signal gates the interrupt vector onto the bus if the SCC is the highest priority device requesting an interrupt. [cite: 328]

#### [cite_start]$\overline{WR}$ [cite: 325]
[cite_start]Write (input, active Low). [cite: 329] [cite_start]When the SCC is selected, this signal indicates a write operation. [cite: 329] [cite_start]The coincidence of $\overline{RD}$ and $\overline{WR}$ is interpreted as a reset. [cite: 330]

### [cite_start]Z80C30 [cite: 326]

#### [cite_start]AD7-AD0 [cite: 338]
[cite_start]Address/Data Bus (bidirectional, active High, Tri-state). [cite: 339] [cite_start]These multiplexed lines carry register addresses to the SCC as well as data or control information. [cite: 339]

#### [cite_start]$\overline{AS}$ [cite: 343]
[cite_start]Address Strobe (input, active Low). [cite: 347] [cite_start]Addresses on AD7-AD0 are latched by the rising edge of this signal. [cite: 347]

#### [cite_start]$\overline{CS0}$ [cite: 348]
[cite_start]Chip Select 0 (input, active Low). [cite: 349] [cite_start]This signal is latched concurrently with the addresses on AD7-AD0 and must be active for the intended bus transaction to occur. [cite: 349]

#### [cite_start]CS1 [cite: 350]
[cite_start]Chip Select 1 (input, active High). [cite: 351] [cite_start]This second select signal must also be active before the intended bus transaction can occur. [cite: 351] [cite_start]CS1 must remain active throughout the transaction. [cite: 352]

#### [cite_start]$\overline{DS}$ [cite: 353]
[cite_start]Data strobe (input, active Low). [cite: 354] [cite_start]This signal provides timing for the transfer of data into and out of the SCC. [cite: 354] [cite_start]If $\overline{AS}$ and $\overline{DS}$ coincide, this confluence is interpreted as a reset. [cite: 355]

#### [cite_start]R/$\overline{W}$ [cite: 356]
[cite_start]Read/Write (input). [cite: 357] [cite_start]This signal specifies whether the operation to be performed is a read or a write. [cite: 357]

---
## [cite_start]Pin Diagrams [cite: 366]

[cite_start]Figure 2 shows the pin assignments for the Z85C30 and Z80C30 DIP packages. [cite: 367]
[cite_start][Image: Figure 2. Z85C30 and Z80C30 DIP Pin Assignments] [cite: 528]

[cite_start]Figure 3 shows the pin assignments for the Z85C30 and Z80C30 PLCC packages. [cite: 535]
[cite_start][Image: Figure 3. Z85C30 and Z80C30 PLCC Pin Assignments] [cite: 631]

[cite_start]Figures 4 and 5 show the pin functions for the Z85C30 and Z80C30 devices, respectively. [cite: 648]
[cite_start][Image: Figure 4. Z85C30 Pin Functions] [cite: 710]
[cite_start][Image: Figure 5. Z80C30 Pin Functions] [cite: 772]

---
## [cite_start]Functional Descriptions [cite: 778]

[cite_start]The architecture of the SCC device functions as: [cite: 779]
* [cite_start]A data communications device which transmits and receives data in various protocols [cite: 780]
* [cite_start]A microprocessor peripheral in which the SCC offers valuable features such as vectored interrupts and DMA support [cite: 781]

[cite_start]The SCC's peripheral and data communication features are described in the following sections. [cite: 782] Figure 1 on page 4 shows a SCC block diagram; [cite_start]Figures 6 and 7 show the details of the communication between the receive and transmit logic to the system bus. [cite: 783, 784] [cite_start]The features and data path for each of the SCC's A and B channels are identical. [cite: 785]

[cite_start][Image: Figure 6. SCC Transmit Data Path] [cite: 809]
[cite_start][Image: Figure 7. SCC Receive Data Path] [cite: 850]

### [cite_start]I/O Interface Capabilities [cite: 851]

[cite_start]System communication to and from the SCC device is performed through the SCC's register set. [cite: 852] [cite_start]There are sixteen write registers and eight read registers. [cite: 853] [cite_start]Throughout this document, write and read registers are referenced with the following notation: [cite: 854]
* [cite_start]WR for write registers [cite: 855]
* [cite_start]RR for read registers [cite: 856]

[cite_start]For example: [cite: 863]
* [cite_start]WR4A: Write Register 4 for channel A [cite: 864]
* [cite_start]RR3: Read Register 3 for either/both channels [cite: 864]

[cite_start]Tables 1 and 2 list the SCC registers and provide a brief description of their functions. [cite: 865]

[cite_start]**Table 1. SCC Read Register Functions** [cite: 866]

| Register | Function |
| :--- | :--- |
| RR0 | [cite_start]Transmit/Receive buffer status and External status [cite: 867] |
| RR1 | [cite_start]Special Receive Condition status [cite: 867] |
| RR2 | [cite_start]Modified interrupt vector (Channel B only) Unmodified interrupt vector (Channel A only) [cite: 867] |
| RR3 | [cite_start]Interrupt Pending bits (Channel A only) [cite: 867] |
| RR8 | [cite_start]Receive Buffer [cite: 867] |
| RR10 | [cite_start]Miscellaneous status [cite: 867] |
| RR12 | [cite_start]Lower byte of Baud Rate Generator time constant [cite: 867] |
| RR13 | [cite_start]Upper byte of Baud Rate Generator time constant [cite: 867] |
| RR15 | [cite_start]External/Status interrupt information [cite: 867] |

[cite_start]**Table 2. SCC Write Register Functions** [cite: 868]

| Register | Function |
| :--- | :--- |
| WR0 | [cite_start]CRC initialize, initialization commands for the various modes, register pointers [cite: 869] |
| WR1 | [cite_start]Transmit/Receive interrupt and data transfer mode definition [cite: 869] |
| WR2 | [cite_start]Interrupt vector (accessed through either channel) [cite: 869] |
| WR3 | [cite_start]Receive parameters and control [cite: 869] |
| WR4 | [cite_start]Transmit/Receive miscellaneous parameters and modes [cite: 869] |
| WR5 | [cite_start]Transmit parameters and controls [cite: 869] |
| WR6 | [cite_start]Sync characters or SDLC address field [cite: 869] |
| WR7 | [cite_start]Sync character or SDLC flag [cite: 869] |
| WR7' | [cite_start]Extended Feature and FIFO Control (WR7 Prime) 85C30 Only [cite: 869] |
| WR8 | [cite_start]Transmit buffer [cite: 869] |
| WR9 | [cite_start]Master interrupt control and reset (accessed through either channel) [cite: 869] |
| WR10 | [cite_start]Miscellaneous transmitter/receiver control bits [cite: 869] |
| WR11 | [cite_start]Clock mode control [cite: 869] |
| WR12 | [cite_start]Lower byte of Baud Rate Generator time constant [cite: 869] |
| WR13 | [cite_start]Upper byte of Baud Rate Generator time constant [cite: 878] |
| WR14 | [cite_start]Miscellaneous control bits [cite: 878] |
| WR15 | [cite_start]External/Status interrupt control [cite: 878] |

### [cite_start]Polling [cite: 879]
[cite_start]The following three methods move data, status and control information in and out of the SCC; each is described in this section. [cite: 880, 881]
* [cite_start]Polling [cite: 882]
* [cite_start]Interrupts (vectored and nonvectored) [cite: 883]
* [cite_start]CPU/DMA Block Transfer, in which BLOCK TRANSFER Mode can be implemented under CPU or DMA control [cite: 884]

[cite_start]When polling, all interrupts are disabled. [cite: 885] [cite_start]Three status registers in the SCC are automatically updated when any function is performed. [cite: 885] [cite_start]For example, End-Of-Frame in SDLC Mode sets a bit in one of these status registers. [cite: 886] [cite_start]The purpose of polling is for the CPU to periodically read a status register until the register contents indicate the need for data to be transferred. [cite: 887] [cite_start]Only one register is read, and depending on its contents, the CPU either writes data, reads data, or continues. [cite: 888] [cite_start]Two bits in the register indicate the need for data transfer. [cite: 889] [cite_start]An alternative is a poll of the Interrupt Pending register to determine the source of an interrupt. [cite: 890] [cite_start]The status for both channels resides in one register. [cite: 891]

### [cite_start]Interrupts [cite: 892]

[cite_start]The SCC's interrupt structure supports vectored and nested interrupts. [cite: 893] [cite_start]Nested interrupts are supported with the interrupt acknowledge feature ($\overline{INTACK}$ pin) of the SCC. [cite: 893] [cite_start]This allows the CPU to recognize the occurrence of an interrupt, and reenable higher priority interrupts. [cite: 894] [cite_start]Because an $\overline{INTACK}$ cycle releases the $\overline{INT}$ pin from the active state, a higher priority SCC interrupt or another higher priority device can interrupt the CPU. [cite: 895]

[cite_start]When an SCC responds to an Interrupt Acknowledge signal ($\overline{INTACK}$) from the CPU, an interrupt vector can be placed on the data bus. [cite: 896] [cite_start]This vector is written in WR2 and can be read in RR2A or RR2B. [cite: 897] [cite_start]To speed interrupt response time, the SCC can modify three bits in this vector to indicate status. [cite: 898] [cite_start]If the vector is read in Channel A, status is never included. [cite: 899] [cite_start]If the vector is read in Channel B, status is always included. [cite: 900]

[cite_start][Image: Figure 8. SCC Interrupt Priority Schedule] [cite: 928]

[cite_start]Each of the six sources of interrupts in the SCC (Transmit, Receive, and External/Status interrupts in both channels) has three bits associated with the interrupt source: Interrupt Pending (IP), Interrupt Under Service (IUS), and Interrupt Enable (IE). [cite: 901, 911] [cite_start]Operation of the IE bit is straight forward. [cite: 911] [cite_start]If the IE bit is set for a given interrupt source, then that source can request interrupts. [cite: 912] [cite_start]The exception is when the MIE (Master Interrupt Enable) bit in WR9 is reset and no interrupts can be requested. [cite: 913] [cite_start]The IE bits are write-only. [cite: 914]

[cite_start]The SCC can also execute an interrupt acknowledge cycle through software. [cite: 929] [cite_start]In some CPU environments, it is difficult to create the $\overline{INTACK}$ signal with the necessary timing to acknowledge interrupts and allow the nesting of interrupts. [cite: 930] [cite_start]In these cases, the $\overline{INTACK}$ signal can be created with a software command to the SCC. [cite: 931]

[cite_start]In the SCC, the Interrupt Pending (IP) bit signals a need for interrupt servicing. [cite: 932] [cite_start]When an IP bit is 1 and the IEI input is High, the $\overline{INT}$ output is pulled Low, requesting an interrupt. [cite: 933] [cite_start]In the SCC, if the IE bit is not set by enabling interrupts, then the IP for that source is never set. [cite: 934] [cite_start]The IP bits are readable in RR3A. [cite: 935]

[cite_start]The IUS bits signal that an interrupt request is being serviced. [cite: 936] [cite_start]If an IUS is set, all interrupt sources of lower priority in the SCC and external to the SCC are prevented from requesting interrupts. [cite: 937] [cite_start]An IUS bit is set during an Interrupt Acknowledge cycle, if there are no higher priority devices requesting interrupts. [cite: 939]

[cite_start]There are three types of interrupts: [cite: 940]
* [cite_start]Transmit [cite: 941]
* [cite_start]Receive [cite: 944]
* [cite_start]External/Status [cite: 946]

[cite_start]Each interrupt type is enabled under program control with Channel A having higher priority than Channel B, and with Receiver, Transmit, and External/Status interrupts prioritized in that order within each channel. [cite: 950]

[cite_start]When enabled, the receiver interrupts the CPU in one of three ways: [cite: 951]
* [cite_start]Interrupt on First Receive Character or Special Receive Condition [cite: 952]
* [cite_start]Interrupt on All Receive Characters or Special Receive Conditions [cite: 952]
* [cite_start]Interrupt on Special Receive Conditions Only [cite: 952]

[cite_start]A special Receive Condition is one of the following: receiver overrun, framing error in Asynchronous Mode, end-of-frame in SDLC Mode and, optionally, a parity error. [cite: 954]

[cite_start]The main function of the External/Status interrupt is to monitor the signal transitions of the $\overline{CTS}$, $\overline{DCD}$, and $\overline{SYNC}$ pins, however, an External/Status interrupt is also caused by a Transmit Underrun condition; a zero count in the Baud Rate Generator; by the detection of a Break (Asynchronous Mode), Abort (SDLC Mode) or EOP (SDLC Loop Mode) sequence in the data stream. [cite: 957, 958]

#### [cite_start]Software Interrupt Acknowledge [cite: 962]
[cite_start]On the CMOS version of the SCC, the SCC interrupt acknowledge cycle can be initiated through software. [cite: 963] [cite_start]If Write Register 9 (WR9) bit D5 is set, Read Register 2 (RR2) results in an interrupt acknowledge cycle to be executed internally. [cite: 964] [cite_start]Like a hardware $\overline{INTACK}$ cycle, a software acknowledge causes the $\overline{INT}$ pin to return High, the IEO pin to go low and set the IUS latch for the highest priority interrupt pending. [cite: 965] [cite_start]Similar to using the hardware $\overline{INTACK}$ signal, a software acknowledge cycle requires that a Reset Highest IUS command be issued in the interrupt service routine. [cite: 966]

[cite_start]If RR2 is read from channel A, the unmodified vector is returned. [cite: 975] [cite_start]If RR2 is read from channel B, then the vector is modified to indicate the source of the interrupt. [cite: 976] [cite_start]When the $\overline{INTACK}$ and IEI pins are not being used, they should be pulled up to $V_{CC}$ through a resistor (10 KΩ typical). [cite: 978]

### [cite_start]CPU/DMA Block Transfer [cite: 979]
[cite_start]The SCC provides a Block Transfer Mode to accommodate CPU block transfer functions and DMA controllers. [cite: 980] [cite_start]The Block Transfer Mode uses the $\overline{WAIT/REQUEST}$ output in conjunction with the Wait/Request bits in WR1. [cite: 981] [cite_start]The $\overline{WAIT/REQUEST}$ output can be defined under software control as a $\overline{WAIT}$ line in the CPU Block Transfer Mode or as a $\overline{REQUEST}$ line in the DMA Block Transfer Mode. [cite: 982] [cite_start]The $\overline{DTR/REQUEST}$ line allows full-duplex operation under DMA control. [cite: 984]

---
## [cite_start]SCC Data Communications Capabilities [cite: 992]

[cite_start]The SCC provides two independent full-duplex programmable channels for use in any common asynchronous or synchronous data communication protocols; see Figure 9. [cite: 993] [cite_start]Each data communication channel has identical feature and capabilities. [cite: 994]

[cite_start][Image: Figure 9. SCC Protocols] [cite: 1031]

### [cite_start]Asynchronous Modes [cite: 1032]
[cite_start]Send and Receive is accomplished independently on each channel with five to eight bits per character, plus optional even or odd parity. [cite: 1033] [cite_start]The transmitters can supply one, one-and-a-half, or two stop bits per character and can provide a break output at any time. [cite: 1034] [cite_start]The receiver break-detection logic interrupts the CPU both at the start and at the end of a received break. [cite: 1035] [cite_start]Framing errors and overrun errors are detected and buffered together with the partial character on which they occur. [cite: 1045] [cite_start]In Asynchronous modes, the $\overline{SYNC}$ pin can be programmed as an input used for functions such as monitoring a ring indicator. [cite: 1051]

### [cite_start]Synchronous Modes [cite: 1052]
[cite_start]The SCC supports both byte and bit-oriented synchronous communication. [cite: 1053] [cite_start]Synchronous byte-oriented protocols are handled in several modes. [cite: 1053] [cite_start]They allow character synchronization with a 6-bit or 8-bit sync character (Monosync), and a 12-bit or 16-bit synchronization pattern (Bisync), or with an external sync signal. [cite: 1054] [cite_start]Leading sync characters are removed without interrupting the CPU. [cite: 1055] [cite_start]5- or 7-bit synchronous characters are detected with 8- or 16-bit patterns in the SCC by overlapping the larger pattern across multiple incoming synchronous characters, as shown in Figure 10. [cite: 1056]

[cite_start][Image: Figure 10. Detecting 5- or 7-Bit Synchronous Characters] [cite: 1068]

[cite_start]CRC checking for Synchronous byte-oriented modes is delayed by one character time so that the CPU can disable CRC checking on specific characters. [cite: 1069] [cite_start]Both CRC-16 ($X^{16}+X^{15}+X^{12}+1$) and CCITT ($X^{16}+X^{12}+X^{5}+1$) error-checking polynomials are supported. [cite: 1071] [cite_start]Either polynomial can be selected in all Synchronous modes. [cite: 1071] [cite_start]You can preset the CRC generator and checker to all 1s or all 0s. [cite: 1078]

#### [cite_start]SDLC Mode [cite: 1083]
[cite_start]The SCC supports Synchronous bit-oriented protocols, such as SDLC and HDLC, by performing automatic flag sending, zero insertion, and CRC generation. [cite: 1084] [cite_start]At the end of a message, the SCC automatically transmits the CRC and trailing flag when the transmitter underruns. [cite: 1086] [cite_start]The receiver automatically acquires synchronization on the leading flag of a frame in SDLC or HDLC and provides a synchronization signal on the $\overline{SYNC}$ pin (an interrupt can also be programmed). [cite: 1091] [cite_start]The receiver automatically deletes all 0s inserted by the transmitter during character assembly CRC is also calculated and is automatically checked to validate frame transmission. [cite: 1096] [cite_start]NRZ, NRZI or FM coding can be used in any 1x mode. [cite: 1100]

#### [cite_start]SDLC Loop Mode [cite: 1102]
[cite_start]The SCC supports SDLC Loop Mode in addition to normal SDLC. [cite: 1103] [cite_start]In an SDLC Loop, a primary controller station manages the message traffic flow on the loop and any number of secondary stations. [cite: 1104] [cite_start]In SDLC Loop Mode, the SCC performs the functions of a secondary station while an SCC operating in regular SDLC Mode acts as a controller; see Figure 11. [cite: 1112, 1113] [cite_start]The SDLC Loop Mode can be selected by setting WR10 bit D1. [cite: 1113]

[cite_start][Image: Figure 11. An SDLC Loop] [cite: 1119]

[cite_start]A secondary station in an SDLC Loop is always listening to the messages sent around the loop and passes these messages to the rest of the loop by retransmitting them with a one-bit-time delay. [cite: 1120] [cite_start]When a secondary station contains a message to transmit and recognizes an EOP on the line, it changes the last binary 1 of the EOP to a 0 before transmission. [cite: 1124] [cite_start]This change has the effect of turning the EOP into a flag sequence. [cite: 1125] [cite_start]The secondary station now places its message on the loop and terminates the message with an EOP. [cite: 1126] [cite_start]In SDLC Loop Mode, NRZ, NRZI, and FM coding can be used. [cite: 1129]

### [cite_start]Baud Rate Generator [cite: 1141]
[cite_start]Each channel in the SCC contains a programmable Baud Rate Generator (BRG). [cite: 1142] [cite_start]Each generator consists of two 8-bit time constant registers that form a 16-bit time constant, a 16-bit down counter, and a flip-flop on the output producing a square wave. [cite: 1143] [cite_start]The output of the BRG can be used as either the transmit clock, the receive clock, or both. [cite: 1147] [cite_start]It can also drive the Digital Phase-locked loop. [cite: 1148]

[cite_start]The following formula relates the time constant to the baud rate where PCLK or RTxC is the BRG input frequency in Hertz. [cite: 1150]
[cite_start]$$\text{Time Constant} = \frac{\text{PCLK or RTXC Frequency}}{2(\text{Baud Rate}) (\text{Clock Mode})} - 2$$ [cite: 1153, 1154, 1156]
[cite_start]The clock mode is 1, 16, 32, or 64, as selected in Write Register 4, bits D6 and D7. [cite: 1151] [cite_start]Synchronous operation modes select 1 and Asynchronous modes select 16, 32 or 64. [cite: 1152]

### [cite_start]Digital Phase-Locked Loop [cite: 1155]
[cite_start]The SCC contains a Digital Phase-Locked Loop (DPLL) to recover clock information from a data stream with NRZI or FM encoding. [cite: 1157] [cite_start]The DPLL is driven by a clock that is nominally 32 (NRZI) or 16 (FM) times the data rate. [cite: 1158] [cite_start]The DPLL uses this clock, along with the data stream, to construct a clock for the data. [cite: 1159] [cite_start]This clock is used as the SCC receive clock, the transmit clock, or both. [cite: 1160] [cite_start]The 32x clock for the DPLL can be programmed to come from either the $\overline{RTxC}$ input or the output of the BRG. [cite: 1174]

### [cite_start]Data Encoding [cite: 1176]
[cite_start]The SCC can be programmed to encode and decode the serial data in four different methods; see Figure 12. [cite: 1177, 1178]
* [cite_start]**NRZ encoding**: a 1 is represented by a High level and a 0 is represented by a Low level. [cite: 1178]
* [cite_start]**NRZI encoding**: a 1 is represented by no change in level and a 0 is represented by a change in level. [cite: 1179]
* [cite_start]**FM1 (bi-phase mark)**: a transition occurs at the beginning of every bit cell. [cite: 1180] [cite_start]A 1 is represented by an additional transition at the center of the bit cell and a 0 is represented by no additional transition at the center of the bit cell. [cite: 1181]
* [cite_start]**FM0 (bi-phase space)**: a transition occurs at the beginning of every bit cell. [cite: 1182] [cite_start]A 0 is represented by an additional transition at the center of the bit cell, and a 1 is represented by no additional transition at the center of the bit cell. [cite: 1183]

[cite_start]In addition to these four methods, the SCC can be used to decode Manchester (bi-phase level) data by using the DPLL in FM Mode and programming the receiver for NRZ data. [cite: 1184]

[cite_start][Image: Figure 12. Data Encoding Methods] [cite: 1204]

### [cite_start]Auto Echo and Local Loopback [cite: 1205]
[cite_start]The SCC is capable of automatically echoing everything it receives. [cite: 1206] [cite_start]This feature is useful mainly in Asynchronous modes, but works in Synchronous and SDLC modes as well. [cite: 1207] [cite_start]The SCC is also capable of local loopback. [cite: 1211] [cite_start]In this mode, TxD or RxD is similar to Auto Echo Mode. [cite: 1211] [cite_start]However, in Local Loopback Mode the internal transmit data is tied to the internal receive data and RxD is ignored (except to be echoed out through TxD). [cite: 1212]

### [cite_start]SDLC FIFO Frame Status FIFO Enhancement [cite: 1221]
[cite_start]The SCC's ability to receive high speed back-to-back SDLC frames is maximized by a 10-deep by 19-bit wide status FIFO. [cite: 1222] [cite_start]When enabled (through WR15, bit D2), it provides the DMA the ability to continue to transfer data into memory so that the CPU can examine the message later. [cite: 1223] [cite_start]For each SDLC frame, a 14-bit byte count and 5 status/error bits are stored. [cite: 1224] [cite_start]The byte count and status bits are accessed through read registers 6 and 7, which are only accessible when the SDLC FIFO is enabled. [cite: 1225] [cite_start]The $10 \times 19$ status FIFO is separate from the 3-byte receive data FIFO. [cite: 1140, 1226]

[cite_start][Image: Figure 13. SDLC Frame Status FIFO] [cite: 1310]
[cite_start][Image: Figure 14. SDLC Byte Counting Detail] [cite: 1352]

---
## [cite_start]Programming [cite: 1353]

### [cite_start]Z85C30 [cite: 1354]
[cite_start]The SCC contains write registers in each channel that are programmed by the system separately to configure the functional personality of the channels. [cite: 1355] [cite_start]In the SCC, the data registers are directly addressed by selecting a High on the D/$\overline{C}$ pin. [cite: 1356] [cite_start]With all other registers (except WR0 and RR0), programming the write registers requires two write operations and reading the read registers requires both a write and a read operation. [cite: 1357] [cite_start]The first write is to WR0 and contains three bits that point to the selected register. [cite: 1358] [cite_start]The second write is the actual control word for the selected register, and if the second operation is read, the selected read register is accessed. [cite: 1359]

### [cite_start]Z80C30 [cite: 1368]
[cite_start]All SCC registers are directly addressable. [cite: 1369] [cite_start]A command issued in WR0B controls how the SCC decodes the address placed on the address/data bus at the beginning of a read or write cycle. [cite: 1369] [cite_start]In the Shift Right Mode, the channel select A/$\overline{B}$ is taken from AD0 and the state of AD5 is ignored. [cite: 1370] [cite_start]In the Shift Left Mode, the channel select A/$\overline{B}$ is taken from AD5 and the state of AD0 is ignored. [cite: 1371]

### [cite_start]Z85C30/Z80C30 Setup [cite: 1373]
[cite_start]The system program first issues a series of commands to initialize the basic mode of operation. [cite: 1374] [cite_start]This is followed by other commands to qualify conditions within the selected mode. [cite: 1375]

#### [cite_start]Write Registers [cite: 1378]
[cite_start]The SCC contains 15 write registers for the 80C30, while there are 16 for the 85C30 (one more additional write register if counting the transmit buffer) in each channel. [cite: 1379] [cite_start]These write registers are programmed separately to configure the functional 'personality' of the channels. [cite: 1380] [cite_start]There are two registers (WR2 and WR9) shared by the two channels that are accessed through either of them. [cite: 1381] [cite_start]WR2 contains the interrupt vector for both channels, while WR9 contains the interrupt control bits and reset commands. [cite: 1382] [cite_start]Figures 15 through 18 show the format of each write register. [cite: 1383]

[cite_start][Image: Figure 15. Write Register Bit Functions] [cite: 1532]
[cite_start][Image: Figure 16. Write Register Bit Functions] [cite: 1581]
[cite_start][Image: Figure 17. Write Register Bit Functions] [cite: 1624]
[cite_start][Image: Figure 18. Write Register Bit Functions] [cite: 1707]

#### [cite_start]Read Registers [cite: 1747]
[cite_start]The SCC contains ten read registers (eleven, counting the receive buffer (RR8) in each channel). [cite: 1748] [cite_start]Four of these can be read to obtain status information (RR0, RR1, RR10, and RR15). [cite: 1749] [cite_start]Two registers (RR12 and RR13) are read to learn the Baud Rate Generator time constant. [cite: 1750] [cite_start]RR2 contains either the unmodified interrupt vector (Channel A) or the vector modified by status information (Channel B). [cite: 1751] [cite_start]RR3 contains the Interrupt Pending (IP) bits (Channel A only; see Figure 19). [cite: 1752] [cite_start]RR6 and RR7 contain the information in the SDLC Frame Status FIFO, but is only read when WR15 D2 is set (see Figures 19 and 20). [cite: 1753]

[cite_start][Image: Figure 19. Read Register Bit Functions, #1 of 2] [cite: 1800]
[cite_start][Image: Figure 20. Read Register Bit Functions, #2 of 2] [cite: 1848]

---
## Timing

### [cite_start]Z85C30 Timing [cite: 1838]
[cite_start]The SCC generates internal control signals from the $\overline{WR}$ and $\overline{RD}$ that are related to PCLK. [cite: 1857] [cite_start]The recovery time applies only between bus transactions involving the SCC. [cite: 1860] [cite_start]The recovery time required for proper operation is specified from the falling edge of $\overline{WR}$ or $\overline{RD}$ in the first transaction involving the SCC to the falling edge of $\overline{WR}$ or $\overline{RD}$ in the second transaction involving the SCC. [cite: 1861] [cite_start]This time must be at least 3 PCLKs regardless of which register or channel is being accessed. [cite: 1862]

[cite_start][Image: Figure 21. Read Cycle Timing] [cite: 1878]
[cite_start][Image: Figure 22. Write Cycle Timing] [cite: 1901]
[cite_start][Image: Figure 23. Interrupt Acknowledge Cycle Timing] [cite: 1919]

### [cite_start]Z80C30 Timing [cite: 1920]
[cite_start]The SCC generates internal control signals from $\overline{AS}$ and $\overline{DS}$ that are related to PCLK. [cite: 1921] [cite_start]The recovery time applies only between bus transactions involving the SCC. [cite: 1924]

[cite_start][Image: Figure 24. Read Cycle Timing] [cite: 1948]
[cite_start][Image: Figure 25. Write Cycle Timing] [cite: 1968]
[cite_start][Image: Figure 26. Interrupt Acknowledge Cycle Timing] [cite: 1989]

---
## [cite_start]Electrical Characteristics [cite: 1997]

### [cite_start]Absolute Maximum Ratings [cite: 1999]
[cite_start]Stresses greater than those listed in Absolute Maximum Ratings may cause permanent damage to the device. [cite: 2000] [cite_start]This is a stress rating only. [cite: 2000]

[cite_start]**Table 3. Absolute Maximum Ratings** [cite: 2003]

| | |
| :--- | :--- |
| Vcc Supply Voltage range | [cite_start]-0.3V to +7.0V [cite: 2004] |
| Voltages on all pins with respect to GND | [cite_start]-3V to VCC +0.3V [cite: 2004] |
| $T_{A}$ Operating Ambient Temperature | [cite_start]See the Ordering Information chapter on page 75 [cite: 2004] |
| Storage Temperature | [cite_start]$-65^{\circ}C$ to $+150^{\circ}C$ [cite: 2004] |

### [cite_start]Standard Test Conditions [cite: 2005]
[cite_start]The DC Characteristics and capacitance sections below apply for the following standard test conditions, unless otherwise noted. [cite: 2006]
* [cite_start]$+4.50V \le V_{cc} \le +5.50V$ [cite: 2008]
* [cite_start]$GND=0~V$ [cite: 2009]
* [cite_start]$T_{A}$ (see the Ordering Information section on page 75) [cite: 2010]

[cite_start][Image: Figure 27. Standard Test Load] [cite: 2022]
[cite_start][Image: Figure 28. Open-Drain Test Load] [cite: 2027]

### [cite_start]DC Characteristics [cite: 2045]

[cite_start]**Table 5. Z80C30/Z85C30 DC Characteristics** [cite: 2047]

| Symbol | Parameter | Min | Typ | Max | Unit | Condition |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| $V_{IH}$ | Input High Voltage | 2.2 | | $V_{CC}+0.3$ | V | |
| $V_{IL}$ | Input Low Voltage | -0.3 | | 0.8 | V | |
| $V_{OH1}$ | Output High Voltage | 2.4 | | | V | $I_{OH}=-1.6~mA$ |
| $V_{OH2}$ | Output High Voltage | $V_{CC}-0.8$ | | | V | $I_{OH}=-250\mu A$ |
| $V_{OL}$ | Output Low Voltage | | | 0.4 | V | $I_{OL}=+2.0~mA$ |
| $I_{IL}$ | Input Leakage | | | ±10.0 | µA | $0.4 < V_{IN} < +2.4V$ |
| $I_{OL}$ | Output Leakage | | | ±10.0 | µA | $0.4 < V_{OUT} < +2.4V$ |
| $I_{CC1}$ | Supply Current² $V_{CC}$ | | 7 | 12 (10 MHz) | mA | $V_{CC}=5~V$, $V_{IH}=4.8$, $V_{IL}=0$ |
| | | | 9 | 15 (16.384 MHz) | mA | Crystal Oscillator off |
| $I_{CCOSC}$ | Crystal OSC Current³ | | 4 | | mA | Current for each OSC in addition to $I_{CC1}$ |

[cite_start]*Table entries based on [cite: 2048, 2061]*

**Notes:**
1. [cite_start]$V_{CC}=$ 5V ±10% unless otherwise specified, over specified temperature range. [cite: 2050, 2063]
2. [cite_start]Typical $I_{CC}$ was measured with oscillator off. [cite: 2051, 2063]
3. [cite_start]No $I_{CC}$ (OSC) max is specified due to dependency on external circuit and frequency of oscillation. [cite: 2052, 2064]

### [cite_start]AC Characteristics [cite: 2065]

[cite_start][Image: Figure 29. Z85C30 Read/Write Timing Diagram] [cite: 2109]
[cite_start][Image: Figure 30. Z85C30 Interrupt Acknowledge Timing Diagram] [cite: 2135]
[cite_start][Image: Figure 31. Z85C30 Cycle Timing Diagram] [cite: 2136]
[cite_start][Image: Figure 32. Z85C30 Reset Timing Diagram] [cite: 2147]
[cite_start][Image: Figure 33. Z85C30 General Timing Diagram] [cite: 2264]
[cite_start][Image: Figure 34. Z85C30 System Timing Diagram] [cite: 2324]
[cite_start][Image: Figure 35. Z80C30 Read/Write Timing Diagram] [cite: 2395]
[cite_start][Image: Figure 36. Z80C30 Interrupt Acknowledge Timing Diagram] [cite: 2418]
[cite_start][Image: Figure 37. Z80C30 Reset Timing Diagram] [cite: 2424]
[cite_start][Image: Figure 38. Z80C30 General Timing Diagram] [cite: 2525]
[cite_start][Image: Figure 39. Z80C30 System Timing Diagram] [cite: 2578]

**Timing Tables**
* [cite_start]Table 6. Z85C30 Read/Write Timing [cite: 2149]
* [cite_start]Table 7. Z85C30 General Timing Table [cite: 2272]
* [cite_start]Table 8. Z85C30 System Timing Table [cite: 2332]
* [cite_start]Table 9. Z85C30 Read/Write Timing [cite: 2340]
* [cite_start]Table 10. Z80C30 Read/Write Timing [cite: 2432]
* [cite_start]Table 11. Z80C30 General Timing [cite: 2532]
* [cite_start]Table 12. Z80C30 System Timing [cite: 2585]

*Note: Due to their complexity, the detailed timing values from Tables 6-12 are not reproduced here. Please refer to the source document for specific timing parameters.*

---
## [cite_start]Packaging [cite: 2601, 2668]

[cite_start]Figure 40 shows the 40-pin DIP package available for the Z80C30 and Z85C30 devices. [cite: 2602]
[cite_start][Image: Figure 40. 40-Pin DIP Package Diagram] [cite: 2665]

[cite_start]Figure 41 shows the 44-pin Plastic Leaded Chip Carriers (PLCC) package diagram available for Z80C30 and Z85C30 devices. [cite: 2675]
[cite_start][Image: Figure 41. 44-Pin PLCC Package Diagram] [cite: 2731]

---
## [cite_start]Ordering Information [cite: 2739, 2762]

[cite_start]**Table 13. Z80C30/Z85C30 Ordering Information** [cite: 2741]

| 8 MHz | 10 MHz | 16 MHz |
| :--- | :--- | :--- |
| [cite_start]Z80C3008VSG [cite: 2742] | [cite_start]Z80C3010VSG [cite: 2742] | [cite_start]Z85C3016PSG [cite: 2742] |
| [cite_start]Z85C3008PSG/PEG [cite: 2742] | [cite_start]Z85C3010PSG/PEG [cite: 2742] | [cite_start]Z85C3016VSG [cite: 2742] |
| [cite_start]Z85C3008VSG/VEG [cite: 2742] | [cite_start]Z85C3010VSG/VEG [cite: 2742] | |

[cite_start]For complete details about Zilog's Z80C30 and Z85C30 devices, development tools and downloadable software, visit [www.zilog.com](https://www.zilog.com). [cite: 2743]

### [cite_start]Part Number Suffix Designations [cite: 2744]

[cite_start][Image: Diagram of Zilog part number components] [cite: 2747]

* [cite_start]**Zilog Prefix** [cite: 2761]
* [cite_start]**Product Number** [cite: 2760]
* [cite_start]**Speed** [cite: 2758]
    * [cite_start]$8 = 8\text{MHz}$ [cite: 2758]
    * [cite_start]$10 = 10\text{MHz}$ [cite: 2759]
    * [cite_start]$16 = 16\text{MHz}$ [cite: 2759]
* [cite_start]**Package** [cite: 2754]
    * [cite_start]P = Plastic DIP [cite: 2755]
    * [cite_start]V = Plastic Leaded Chip Carrier [cite: 2756]
    * [cite_start]D = Ceramic DIP [cite: 2757]
* [cite_start]**Ambient Temperature Range ($T_A$)** [cite: 2751]
    * [cite_start]$S = 0^{\circ}\text{C}$ to $+70^{\circ}\text{C}$ [cite: 2752]
    * [cite_start]$E = \text{Extended, } -40^{\circ}\text{C}$ to $+100^{\circ}\text{C}$ [cite: 2753]
* [cite_start]**Environmental Flow** [cite: 2749]
    * [cite_start]G = Lead Free [cite: 2750]

---
## [cite_start]Customer Support [cite: 2768]

[cite_start]To share comments, get your technical questions answered, or report issues you may be experiencing with our products, please visit Zilog's Technical Support page at [http://support.zilog.com](http://support.zilog.com). [cite: 2769]

[cite_start]To learn more about this product, find additional documentation, or to discover other facets about Zilog product offerings, please visit the Zilog Knowledge Base at [http://zilog.com/kb](http://zilog.com/kb) or consider participating in the Zilog Forum at [http://zilog.com/forum](http://zilog.com/forum). [cite: 2770]

[cite_start]This publication is subject to replacement by a later edition. [cite: 2771] [cite_start]To determine whether a later edition exists, please visit the Zilog website at [http://www.zilog.com](http://www.zilog.com). [cite: 2772]
