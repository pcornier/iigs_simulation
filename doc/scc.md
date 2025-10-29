# Z80C30/Z85C30 CMOS SCC Serial Communications Controller

## Product Specification
**Document Number:** PS011708-0115

**Copyright ©2015 Zilog®, Inc. All rights reserved.**

---

## Table of Contents

- Revision History (iii)
- List of Figures (vi)
- List of Tables (viii)
- Overview (1)
- Z85C30-Only Features (1)
- General Description (3)
- Pin Descriptions (5)
- Pin Diagrams (11)
- Functional Descriptions (15)
- I/O Interface Capabilities (16)
- SCC Data Communications Capabilities (22)
- Programming (32)
- Electrical Characteristics (47)
- Packaging (73)
- Ordering Information (75)
- Customer Support (76)

---

## Important Safety Information

⚠️ **Warning:** DO NOT USE THIS PRODUCT IN LIFE SUPPORT SYSTEMS.

### LIFE SUPPORT POLICY

ZILOG'S PRODUCTS ARE NOT AUTHORIZED FOR USE AS CRITICAL COMPONENTS IN LIFE SUPPORT DEVICES OR SYSTEMS WITHOUT THE EXPRESS PRIOR WRITTEN APPROVAL OF THE PRESIDENT AND GENERAL COUNSEL OF ZILOG CORPORATION.

**Life support devices or systems** are devices which (a) are intended for surgical implant into the body, or (b) support or sustain life and whose failure to perform when properly used can be reasonably expected to result in significant injury to the user.

**A critical component** is any component in a life support device or system whose failure can be reasonably expected to cause the failure of the life support device or system or affect its safety or effectiveness.

---

## Revision History

| Date | Revision Level | Description | Page |
|------|----------------|-------------|------|
| Jan 2015 | 08 | Updated Ordering Information chapter to delete Z80C3008PSG and Z80C3010PSG (EOL status) | 75 |
| Oct 2012 | 07 | Corrected state of RTSB pin on Z85C30 DIP package; corrected name of PCLK pin on Z85C30 PLCC package | 11, 12 |
| May 2011 | 06 | Corrected Ordering Information chapter to reflect lead-free parts; updated logo and style | 75, all |
| Jun 2008 | 05 | Updated Zilog logo, text, disclaimer per latest template | All |
| Aug 2001 | 01 | Original issue | All |

---

## Overview

The features of Zilog's Z80C30 and Z85C30 devices include:

- **Z85C30:** optimized for nonmultiplexed bus microprocessors
- **Z80C30:** optimized for multiplexed bus microprocessors
- Pin-compatible to NMOS versions
- Two independent 0 to 4.1 Mbps, full-duplex channels, each with separate crystal oscillator, Baud Rate Generator (BRG), and Digital Phase-Locked Loop (DPLL) for clock recovery
- Multiprotocol operation under program control; programmable for NRZ, NRZI or FM data encoding
- **Asynchronous Mode** with 5 to 8 bits and 1, 1½, or 2 stop bits per character, programmable clock factor, break detection and generation; parity, overrun, and framing error detection
- **Synchronous Mode** with internal or external character synchronization on 1 or 2 synchronous characters and CRC generation and checking with CRC-16 or CRC-CCITT preset to either 1s or 0s
- **SDLC/HDLC Mode** with comprehensive frame-level control, automatic zero insertion and deletion, I-Field residue handling, abort generation and detection, CRC generation and checking, and SDLC loop
- Software interrupt acknowledge feature (not available with NMOS)
- Local Loopback and Auto Echo modes
- Supports T1 Digital Trunk
- Enhanced DMA support (not available with NMOS), 10 × 19-bit status FIFO, 14-bit byte counter
- **Speeds:**
  - Z85C30: 8.5, 10, 16.384 MHz
  - Z80C30: 8, 10 MHz

---

## Z85C30-Only Features

Some features are available by default. Others (marked with *) are disabled by default to maintain compatibility with existing SCC designs and must be enabled through WR7:

- New programmable Write Register 7 prime (WR7') to enable new features
- **Improvements to support SDLC Mode:**
  - Improve functionality to ease sending back-to-back frames
  - Automatic SDLC opening Flag transmission
  - Automatic Tx Underrun/EOM Latch reset in SDLC Mode
  - Automatic RTS deactivation
  - TxD pin forced High in SDLC NRZI Mode after closing flag
  - Complete CRC reception
  - Improved response to Abort sequence in status FIFO
  - Automatic Tx CRC generator preset/reset
  - Extended read for write registers
  - Write data set-up timing improvement

- **Improved AC timing:**
  - 3 to 3.6 PCLK access recovery time
  - Programmable DTR/REQ timing
  - Write data to falling edge of WR setup time requirement eliminated
  - Reduced INT timing

- **Other features:**
  - Extended read function to read back written values to write registers
  - Latching RR0 during read
  - RR0 bit D7 and RR10 bit D6 now have reset default values

---

## General Description

The Z80C30/Z85C30 Serial Communications Controller (SCC) is a pin and software compatible CMOS member of the SCC family introduced by Zilog in 1981. It is a dual-channel, multiprotocol data communications peripheral that easily interfaces with CPUs with either multiplexed or nonmultiplexed address/data buses.

The advanced CMOS process offers lower power consumption, higher performance, and superior noise immunity. The programming flexibility of the internal registers allows the SCC to be configured for various serial communications applications.

Many on-chip features such as Baud Rate Generators (BRG), Digital Phase Locked Loops (DPLL), and crystal oscillators reduce the need for external logic.

Additional features include a 10 × 19-bit status FIFO and 14-bit byte counter to support high-speed SDLC transfers using DMA controllers.

The SCC handles:
- Asynchronous formats
- Synchronous byte-oriented protocols (e.g., IBM Bisync)
- Synchronous bit-oriented protocols (e.g., HDLC and IBM SDLC)
- Virtually any serial data transfer application (cassette, diskette, tape drives, etc.)

The device generates and checks CRC codes in any synchronous mode and can be programmed to check data integrity in various modes. The SCC contains facilities for modem controls in both channels. In applications where these controls are not required, the modem controls can be used for general-purpose I/O. The daisy-chain interrupt hierarchy is also supported.

---

## Block Diagram

**Figure 1: SCC Block Diagram**

The block diagram shows:
- Two channels (A and B) with identical architecture
- Each channel contains:
  - **Transmit Logic:** Transmit Buffer, Transmit MUX, Data Encoding & CRC Generation
  - **Receive Logic:** Receive MUX, CRC Checker, Data Decode & Sync Character Detection, 3-byte Receive Status FIFOs
  - **Clock Generation:** Digital Phase-Locked Loop, Baud Rate Generator, Crystal Oscillator Amplifier
  - **Modem/Control Logic**
  - **SDLC Frame Status FIFO** (10 × 19 bits)
  - **14-bit Byte Counter**
  
- **Central Components:**
  - CPU & DMA Bus Interface
  - Interrupt Control Logic (with INT, INTACK, IEI, IEO signals)
  - Channel A and B Registers
  - Data Bus interface

- **External Connections per Channel:**
  - Serial Data: TxD, RxD
  - Clocks: TRxC, RTxC
  - Control Signals: SYNC, W/REQ, DTR/REQ, RTS, CTS, DCD

---

## Pin Descriptions

### Common Pins (Z85C30 and Z80C30)

#### **CTSA, CTSB** (Clear To Send - inputs, active Low)
If programmed for Auto Enable, a Low enables the respective transmitters. Otherwise, can be used as general-purpose inputs. Both are Schmitt-trigger buffered to accommodate slow rise times. The SCC detects pulses and can interrupt the CPU on both transitions.

#### **DCDA, DCDB** (Data Carrier Detect - inputs, active Low)
Function as receiver enables if programmed for Auto Enable. Otherwise, used as general-purpose inputs. Both are Schmitt-trigger buffered. The SCC detects pulses and can interrupt the CPU on both transitions.

#### **DTR/REQA, DTR/REQB** (Data Terminal Ready/Request - outputs, active Low)
Follow the state programmed into the DTR bit. Can be used as general-purpose outputs or as Request lines for a DMA controller.

#### **IEI** (Interrupt Enable In - input, active High)
Used with IEO to form an interrupt daisy-chain. A High indicates no other higher priority device has an interrupt under service or is requesting an interrupt.

#### **IEO** (Interrupt Enable Out - output, active High)
High only if IEI is High and the CPU is not servicing the SCC interrupt or the SCC is not requesting an interrupt. Connected to the next lower priority device's IEI input.

#### **INT** (Interrupt Request - output, open-drain, active Low)
Activates when the SCC requests an interrupt.

#### **INTACK** (Interrupt Acknowledge - input, active Low)
Indicates an active Interrupt Acknowledge cycle. When RD is active, the SCC places an interrupt vector on the data bus (if IEI is High). Latched by the rising edge of PCLK.

#### **PCLK** (Clock - input)
Master SCC clock used to synchronize internal signals. TTL level signal. Not required to have any phase relationship with the master system clock. Maximum transmit rate is 1/4 PCLK.

#### **RxDA, RxDB** (Receive Data - inputs, active High)
Receive serial data at standard TTL levels.

#### **RTxCA, RTxCB** (Receive/Transmit Clocks - inputs, active Low)
Can be programmed in several modes. Can supply the receive clock, transmit clock, clock for the BRG, or clock for the DPLL. Can be programmed for use with SYNC pins as a crystal oscillator. Receive clock can be 1, 16, 32, or 64 times the data rate in Asynchronous modes.

#### **RTSA, RTSB** (Request To Send - outputs, active Low)
When the RTS bit in WR5 is set, signal goes Low. When reset in Asynchronous Mode with Auto Enable ON, goes High after transmitter is empty. In Synchronous Mode, strictly follows the RTS bit. When Auto Enable is OFF, can be used as general-purpose outputs.

#### **SYNCA, SYNCB** (Synchronization - inputs or outputs, active Low)
Function as inputs, outputs, or part of crystal oscillator circuit:
- In Asynchronous Receive Mode: inputs similar to CTS and DCD
- In External Synchronization Mode: must be driven Low for two receive clock cycles after last bit in sync character
- In Internal Synchronization Mode (Monosync/Bisync): outputs active during sync character recognition
- In SDLC Mode: outputs valid on receipt of flag

#### **TxDA, TxDB** (Transmit Data - outputs, active High)
Transmit serial data at standard TTL levels.

#### **TRxCA, TRxCB** (Transmit/Receive Clocks - inputs or outputs, active Low)
Can be programmed in several modes. May supply receive/transmit clock in input mode or supply output of DPLL, crystal oscillator, BRG, or transmit clock in output mode.

#### **W/REQA, W/REQB** (Wait/Request - outputs)
Open-drain when programmed for Wait function, driven High or Low when programmed for Request function. Dual-purpose outputs:
- As Request lines for DMA controller
- As Wait lines to synchronize CPU to SCC data rate
Reset state is Wait.

---

### Z85C30-Specific Pins

#### **A/B** (Channel A/Channel B - input)
Selects the channel for read or write operation.

#### **CE** (Chip Enable - input, active Low)
Selects the SCC for read or write operation.

#### **D7–D0** (Data Bus - bidirectional, tri-state)
Carry data and commands to and from the SCC.

#### **D/C** (Data/Control Select - input)
Defines the type of information transferred. High = data transfer; Low = command.

#### **RD** (Read - input, active Low)
Indicates a read operation. When SCC is selected, enables the SCC's bus drivers. During Interrupt Acknowledge, gates the interrupt vector onto the bus if SCC is highest priority.

#### **WR** (Write - input, active Low)
When SCC is selected, indicates a write operation. Coincidence of RD and WR is interpreted as a reset.

---

### Z80C30-Specific Pins

#### **AD7–AD0** (Address/Data Bus - bidirectional, active High, Tri-state)
Multiplexed lines carrying register addresses to the SCC as well as data or control information.

#### **AS** (Address Strobe - input, active Low)
Addresses on AD7–AD0 are latched by the rising edge of this signal.

#### **CS0** (Chip Select 0 - input, active Low)
Latched concurrently with addresses on AD7–AD0. Must be active for the intended bus transaction to occur.

#### **CS1** (Chip Select 1 - input, active High)
Second select signal. Must be active before the intended bus transaction can occur. Must remain active throughout the transaction.

#### **DS** (Data Strobe - input, active Low)
Provides timing for data transfer into and out of the SCC. If AS and DS coincide, interpreted as a reset.

#### **R/W** (Read/Write - input)
Specifies whether the operation is a read or write.

---

## Pin Diagrams

### DIP Package (40-pin)

**Figure 2: Z85C30 and Z80C30 DIP Pin Assignments**

**Z85C30 DIP Pin Configuration:**
```
        ╔═══════════════╗
   D1 ──┤1          40├── D0
   D3 ──┤2          39├── D2
   D5 ──┤3          38├── D4
   D7 ──┤4          37├── D6
  INT ──┤5          36├── RD
  IEO ──┤6          35├── WR
  IEI ──┤7   Z85C30 34├── A/B
INTACK ──┤8          33├── CE
  +5V ──┤9          32├── D/C
W/REQA ──┤10         31├── GND
SYNCA ──┤11         30├── W/REQB
RTxCA ──┤12         29├── SYNCB
 RxDA ──┤13         28├── RTxCB
TRxCA ──┤14         27├── RxDB
 TxDA ──┤15         26├── TRxCB
DTR/REQA┤16         25├── TxDB
 RTSA ──┤17         24├── DTR/REQB
 CTSA ──┤18         23├── RTSB
 DCDA ──┤19         22├── CTSB
 PCLK ──┤20         21├── DCDB
        ╚═══════════════╝
```

**Z80C30 DIP Pin Configuration:**
```
        ╔═══════════════╗
  AD1 ──┤1          40├── AD0
  AD3 ──┤2          39├── AD2
  AD5 ──┤3          38├── AD4
  AD7 ──┤4          37├── AD6
  INT ──┤5          36├── DS
  IEO ──┤6          35├── AS
  IEI ──┤7   Z80C30 34├── R/W
INTACK ──┤8          33├── CS0
  +5V ──┤9          32├── CS1
W/REQA ──┤10         31├── GND
SYNCA ──┤11         30├── W/REQB
RTxCA ──┤12         29├── SYNCB
 RxDA ──┤13         28├── RTxCB
TRxCA ──┤14         27├── RxDB
 TxDA ──┤15         26├── TRxCB
DTR/REQA┤16         25├── TxDB
 RTSA ──┤17         24├── DTR/REQB
 CTSA ──┤18         23├── RTSB
 DCDA ──┤19         22├── CTSB
 PCLK ──┤20         21├── DCDB
        ╚═══════════════╝
```

### PLCC Package (44-pin)

**Figure 3: Z85C30 and Z80C30 PLCC Pin Assignments**

Both devices are available in 44-pin PLCC packages with similar pin arrangements but optimized control signals for their respective bus types (multiplexed vs. non-multiplexed).

---

## Functional Descriptions

### Architecture

The SCC device functions as:
1. **A data communications device** - transmits and receives data in various protocols
2. **A microprocessor peripheral** - offers features like vectored interrupts and DMA support

### Data Path Diagrams

**Figure 6: SCC Transmit Data Path**

Shows the flow from:
- Internal Data Bus → TX Buffer (1 Byte) → 20-Bit TX Shift Register
- Through: CRC Generation, Zero Insert (5 Bits), Transmit MUX & 2-Bit Delay
- Data Encoding: NRZ Encode
- Output: Final TX MUX → TXD
- Sync control from WR6, WR7, WR8 registers

**Figure 7: SCC Receive Data Path**

Shows the flow:
- RXD input → 1-Bit delay → MUX → NRZI Decode → MUX
- Through: SYNC Register & Zero Delete, 3-Bit Receive Shift Register
- DPLL for clock recovery
- CRC Checker and CRC Delay Register (8 bits)
- Receive Error Logic and Error FIFOs (3-byte deep)
- Status FIFO (10 × 19 Frame)
- 14-Bit Counter for byte counting
- Hunt Mode support for BISYNC
- Output: I/O Data Buffer → Internal Data Bus → CPU/I/O
- BRG: 16-Bit Down Counter with Time Constant (WR12/WR13)

---

## I/O Interface Capabilities

System communication to/from the SCC is performed through the register set:
- **16 Write Registers (WR0-WR15)**
- **8 Read Registers (RR0-RR15)**

### Notation Convention
- **WR** = Write Registers (e.g., WR4A = Write Register 4 for Channel A)
- **RR** = Read Registers (e.g., RR3 = Read Register 3 for either/both channels)

### Read Register Functions (Table 1)

| Register | Function |
|----------|----------|
| RR0 | Transmit/Receive buffer status and External status |
| RR1 | Special Receive Condition status |
| RR2 | Modified interrupt vector (Channel B only); Unmodified vector (Channel A only) |
| RR3 | Interrupt Pending bits (Channel A only) |
| RR8 | Receive Buffer |
| RR10 | Miscellaneous status |
| RR12 | Lower byte of Baud Rate Generator time constant |
| RR13 | Upper byte of Baud Rate Generator time constant |
| RR15 | External/Status interrupt information |

### Write Register Functions (Table 2)

| Register | Function |
|----------|----------|
| WR0 | CRC initialize, initialization commands, register pointers |
| WR1 | Transmit/Receive interrupt and data transfer mode definition |
| WR2 | Interrupt vector (accessed through either channel) |
| WR3 | Receive parameters and control |
| WR4 | Transmit/Receive miscellaneous parameters and modes |
| WR5 | Transmit parameters and controls |
| WR6 | Sync characters or SDLC address field |
| WR7 | Sync character or SDLC flag |
| WR7' | Extended Feature and FIFO Control (Z85C30 Only) |
| WR8 | Transmit buffer |
| WR9 | Master interrupt control and reset (accessed through either channel) |
| WR10 | Miscellaneous transmitter/receiver control bits |
| WR11 | Clock mode control |
| WR12 | Lower byte of Baud Rate Generator time constant |
| WR13 | Upper byte of Baud Rate Generator time constant |
| WR14 | Miscellaneous control bits |
| WR15 | External/Status interrupt control |

---

## Data Transfer Methods

Three methods move data, status, and control information:

### 1. Polling
- All interrupts disabled
- Three status registers automatically updated
- CPU periodically reads status registers
- Continues until register indicates need for data transfer
- Two bits indicate need for data transfer
- Alternative: poll Interrupt Pending register to determine interrupt source

### 2. Interrupts
The SCC supports vectored and nested interrupts with INTACK pin support.

**Interrupt Structure:**
- CPU recognizes interrupt occurrence and re-enables higher priority interrupts
- INTACK cycle releases INT pin from active state
- Higher priority SCC interrupt or other device can interrupt CPU
- Interrupt vector placed on data bus during INTACK
- Vector written in WR2, read in RR2A or RR2B
- Channel A read: status never included
- Channel B read: status always included

**Six Interrupt Sources** (three bits each):
1. Channel A Transmit
2. Channel A Receive
3. Channel A External/Status
4. Channel B Transmit
5. Channel B Receive
6. Channel B External/Status

**Interrupt Priority Chain:**

**Figure 8: SCC Interrupt Priority Schedule**
```
[Shows daisy-chain configuration with multiple peripherals]
+5V → IEI → Peripheral → IEO → IEI → Peripheral → IEO → IEI → Peripheral
      ↓                          ↓                          ↓
    D7-D0                      D7-D0                      D7-D0
    INT ←────────────────────────────────────────────────────┘
    INTACK ←─────────────────────────────────────────────────┘
```

**Interrupt Bits:**
- **IE (Interrupt Enable):** If set, source can request interrupts (except when MIE in WR9 is reset)
- **IP (Interrupt Pending):** Signals need for interrupt servicing; readable in RR3A
- **IUS (Interrupt Under Service):** Set during Interrupt Acknowledge; prevents lower priority interrupts

**Interrupt Types:**

1. **Transmit Interrupts**

2. **Receive Interrupts** (three modes when enabled):
   - Interrupt on First Receive Character or Special Condition
   - Interrupt on All Receive Characters or Special Conditions
   - Interrupt on Special Conditions Only
   
   Special Receive Conditions:
   - Receiver overrun
   - Framing error (Asynchronous Mode)
   - End-of-frame (SDLC Mode)
   - Optionally, parity error

3. **External/Status Interrupts** - caused by:
   - Signal transitions on CTS, DCD, and SYNC pins
   - Transmit Underrun condition
   - Zero count in Baud Rate Generator
   - Detection of Break (Async), Abort (SDLC), or EOP (SDLC Loop)
   - Special feature: interrupt on Abort/EOP detection or termination

**Software Interrupt Acknowledge** (Z85C30 Only):
- If WR9 bit D5 is set, reading RR2 executes internal interrupt acknowledge cycle
- Like hardware INTACK: INT returns High, IEO goes Low, IUS latch set
- Requires Reset Highest IUS command in interrupt service routine
- VIS and NV bits in WR9 ignored when bit D5 = 1
- When INTACK and IEI pins unused, pull up to VCC through ~10K resistor

### 3. CPU/DMA Block Transfer

**Block Transfer Mode** accommodates:
- CPU block transfer functions
- DMA controllers

**WAIT/REQUEST Output:**
- Programmable via Wait/Request bits in WR1
- **WAIT mode (CPU Block Transfer):** Indicates SCC not ready; CPU extends I/O cycle
- **REQUEST mode (DMA Block Transfer):** Indicates SCC ready to transfer data to/from memory
- DTR/REQUEST line allows full-duplex operation under DMA control

---

# Z80C30/Z85C30 CMOS SCC Serial Communications Controller
## Product Specification (Continued)

---

## SDLC Frame Status FIFO Enhancement (Continued)

### Read Operation

When WR15 bit D2 is set and the FIFO is not empty, the next read to status register RR1 or registers RR7 and RR6 is from the FIFO. Reading status register RR1 causes one location of the FIFO to become empty. Status is read after reading the byte count, otherwise the count is incorrect. Before the FIFO underflows, it is disabled. In this case, the multiplexer is switched allowing status to read directly from the status register. Reads from RR7 and RR6 contain bits that are undefined. Bit D6 of RR7 (FIFO Data Available) determines if status data is coming from the FIFO or directly from the status register, which sets to 1 when the FIFO is not empty. Not all status bits are stored in the FIFO. The All Sent, Parity, and EOF bits bypass the FIFO. Status bits sent through the FIFO are Residue Bits (3), Overrun, and CRC Error.

---

**Figure 13: SDLC Frame Status FIFO**

This figure shows a detailed block diagram of the Frame Status FIFO Circuitry:

**Components:**
- **SCC Status Register** (RR1) providing Residue Bits (3), Overrun, CRC Error (5 bits)
- **Byte Counter** (14 bits) with controls:
  - Reset on Flag Detect
  - Increment on Byte Detection
  - Enable Count in SDLC
  - End of Frame Signal
  - Status Read Comp
- **FIFO Array** (10 Deep by 19 Bits Wide)
- **Tail Pointer** (4-Bit Counter)
- **Head Pointer** (4-Bit Counter)
- **4-Bit Comparator** (Over/Equal outputs)
- **6-Bit MUX**
- **Output Multiplexing:**
  - 2 Bits → RR1
  - 6 Bits → RR1 (Bits 5-0)
  - 6 Bits + 8 Bits → RR7 (D5-D0) + RR6 (D7-D0)

**Register Definitions (SDLC Mode):**
- **WR15 Bit 2:** Set Enables Status FIFO
- **RR7 D7:** FIFO Overflow Status Bit (MSB set on Status FIFO overflow)
- **RR7 D6:** FIFO Data Available status bit (set to 1 when reading from FIFO)
- **RR7 D5-D0 + RR6 D7-D0:** Byte Counter (14 bits for 16 KByte maximum count)

**EOF Control:** When EOF = 1, enables 6-bit MUX to select appropriate data path.

---

The sequence for operation of the byte count and FIFO logic is to read the registers in the following order: RR7, RR6, and RR1 (reading RR6 is optional). Additional logic prevents the FIFO from being emptied by multiple reads from RR1. The read from RR7 latches the FIFO empty/full status bit (D6) and steers the status multiplexer to read from the SCC megacell instead of the status FIFO (since the status FIFO is empty). The read from RR1 allows an entry to be read from the FIFO (if the FIFO was empty, logic was added to prevent a FIFO underflow condition).

### Write Operation

When the end of an SDLC frame (EOF) is received and the FIFO is enabled, the contents of the status and byte-count registers are loaded into the FIFO. The EOF signal is used to increment the FIFO. If the FIFO overflows, RR7, bit D7 (FIFO Overflow) sets to indicate the overflow. This bit and the FIFO control logic is reset by disabling and re-enabling the FIFO control bit (WR15, bit 02). For details of FIFO control timing during an SDLC frame, see Figure 14.

---

**Figure 14: SDLC Byte Counting Detail**

This timing diagram shows SDLC frame processing:

```
Frame Structure:
    0              7   0                              7   0
    F | A | D | D | D | D | C | C | F  ....  F | A | D | D | D | D | C | C | F
```

**Key Events:**
- **Don't Load Counter On 1st Flag**
- **Reset Byte Counter Here** (at first flag)
- **Internal Byte Strobe Increments Counter** (during data bytes)
- **Reset Byte Counter / Load Counter Into FIFO and Increment PTR** (at closing flag)

The diagram illustrates how the byte counter is reset at the opening flag, increments with each data byte, and loads into the FIFO at the closing flag.

---

## Programming

The SCC contains write registers in each channel that are programmed by the system separately to configure the functional personality of the channels.

### Z85C30

In the SCC, the data registers are directly addressed by selecting a High on the D/C pin. With all other registers (except WR0 and RR0), programming the write registers requires two write operations and reading the read registers requires both a write and a read operation. The first write is to WR0 and contains three bits that point to the selected register. The second write is the actual control word for the selected register, and if the second operation is read, the selected read register is accessed. All the SCC registers, including the data registers, can be accessed in this fashion. The pointer bits are automatically cleared after the read or write operation so that WR0 (or RR0) is addressed again.

### Z80C30

All SCC registers are directly addressable. A command issued in WR0B controls how the SCC decodes the address placed on the address/data bus at the beginning of a read or write cycle. In the Shift Right Mode, the channel select A/B is taken from AD0 and the state of AD5 is ignored. In the Shift Left Mode, the channel select A/B is taken from AD5 and the state of AD0 is ignored. AD7 and AD6 are always ignored as address bits and the register address occupies AD4-AD1.

### Z85C30/Z80C30 Setup

The system program first issues a series of commands to initialize the basic mode of operation. This is followed by other commands to qualify conditions within the selected mode. For example, in Asynchronous Mode, character length, clock rate, number of stop bits, and even or odd parity must be set first. The interrupt mode is set, and finally, the receiver and transmitter are enabled.

---

## Write Registers

The SCC contains 15 write registers for the 80C30, while there are 16 for the 85C30 (one more additional write register if counting the transmit buffer) in each channel. These write registers are programmed separately to configure the functional 'personality' of the channels. There are two registers (WR2 and WR9) shared by the two channels that are accessed through either of them. WR2 contains the interrupt vector for both channels, while WR9 contains the interrupt control bits and reset commands. Figures 15 through 18 show the format of each write register.

---

### **Figure 15: Write Register Bit Functions**

**Write Register 0 (non-multiplexed bus mode)**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

**Bits D5-D3 (Register Pointer):**
- 000 = Register 0
- 001 = Register 1
- 010 = Register 2
- 011 = Register 3
- 100 = Register 4
- 101 = Register 5
- 110 = Register 6
- 111 = Register 7
- (with Point High: Registers 8-15)

**Bits D7-D6 (Command Codes):**
- 00 = Null Code
- 01 = Point High*
- 10 = Reset Ext/Status Interrupts
- 11 = Send Abort (SDLC)

**Bits D2-D0 (CRC & Reset Commands):**
- 000 = Null Code
- 001 = Reset Rx CRC Checker
- 010 = Reset Tx CRC Generator/Checker
- 011 = Reset Tx Underrun/EOM Latch
- 100 = Enable Int on Next Rx Character
- 101 = Reset Tx Int Pending
- 110 = Error Reset
- 111 = Reset Highest IUS

*With Point High Command

---

**Write Register 0 (multiplexed bus mode)**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

**Same as above, plus:**

**Bits D1-D0 (Shift Mode):**
- 00 = Null Code
- 01 = Null Code
- 10 = Select Shift Left Mode* (B Channel Only)
- 11 = Select Shift Right Mode*

---

**Write Register 1**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Ext Int Enable
- **D6:** Tx Int Enable
- **D5:** Parity is Special Condition
- **D4-D3:** Rx Interrupt Mode
  - 00 = Rx Int Disable
  - 01 = Rx Int on First Character or Special Condition
  - 10 = Int on all Rx Characters or Special Condition
  - 11 = Rx Int on Special Condition Only
- **D2:** WAIT/DMA Request on Receive/Transmit
- **D1:** WAIT/DMA Request Function
- **D0:** WAIT/DMA Request

---

**Write Register 2**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
V7 | V6 | V5 | V4 | V3 | V2 | V1 | V0
```
Interrupt Vector (8 bits)

---

**Write Register 3**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7-D6:** Rx Character Length
  - 00 = Rx 5 Bits/Character
  - 01 = Rx 7 Bits/Character
  - 10 = Rx 6 Bits/Character
  - 11 = Rx 8 Bits/Character
- **D5:** Auto Enables
- **D4:** Enter Hunt Mode
- **D3:** Rx CRC Enable
- **D2:** Address Search Mode (SDLC)
- **D1:** Sync Character Load Inhibit
- **D0:** Rx Enable

---

### **Figure 16: Write Register Bit Functions**

**Write Register 4**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Parity Enable
- **D6:** Parity EVEN/ODD
- **D5-D4:** Stop Bits
  - 00 = Sync Modes Enable
  - 01 = 1 Stop Bit/Character
  - 10 = 1½ Stop Bits/Character
  - 11 = 2 Stop Bits/Character
- **D3-D2:** Sync Mode
  - 00 = 8-Bit Sync Character
  - 01 = 16-Bit Sync Character
  - 10 = SDLC Mode (01111110 Flag)
  - 11 = External Sync Mode
- **D1-D0:** Clock Mode
  - 00 = X1 Clock Mode
  - 01 = X16 Clock Mode
  - 10 = X32 Clock Mode
  - 11 = X64 Clock Mode

---

**Write Register 5**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** DTR
- **D6-D5:** Tx Character Length
  - 00 = Tx 5 Bits (or Less)/Character
  - 01 = Tx 7 Bits/Character
  - 10 = Tx 6 Bits/Character
  - 11 = Tx 8 Bits/Character
- **D4:** Send Break
- **D3:** Tx Enable
- **D2:** SDLC/CRC-16
- **D1:** RTS
- **D0:** Tx CRC Enable

---

### **Figure 17: Write Register Bit Functions**

**Write Register 6**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

**Mode-dependent bit assignments:**
- **Monosync, 8 Bits:** Sync7-Sync0
- **Monosync, 6 Bits:** Sync5-Sync0 (with x in bits 7-6)
- **Bisync, 16 Bits:** Sync7-Sync0 (lower byte)
- **Bisync, 12 Bits:** Sync5-Sync0 (lower 6 bits, with x and 1 in upper bits)
- **SDLC:** ADR7-ADR0 (address field)
- **SDLC (Address Range):** ADR7-ADR0 (address range)

---

**Write Register 7**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

**Mode-dependent bit assignments:**
- **Monosync, 8 Bits:** Sync7-Sync0
- **Monosync, 6 Bits:** Sync5-Sync0 (with x in bits 7-6)
- **Bisync, 16 Bits:** Sync15-Sync8 (upper byte)
- **Bisync, 12 Bits:** Sync11-Sync4 (upper bits)
- **SDLC:** 01111110 (Flag = 0x7E)

---

**WR7' Prime (85C30 only)**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Reserved (Program as 0)
- **D6:** Extended Read Enable
- **D5:** Complete CRC Reception
- **D4:** DTR/REQ Fast Mode
- **D3:** Force TxD High
- **D2:** Auto RTS Deactivation
- **D1:** Auto EOM Reset
- **D0:** Auto Tx Flag

---

### **Figure 18: Write Register Bit Functions**

**Write Register 9**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7-D6:** Reset Commands
  - 00 = No Reset
  - 01 = Channel Reset B
  - 10 = Channel Reset A
  - 11 = Force Hardware Reset
- **D5:** Software INTACK Enable
- **D4:** Status High/Status Low
- **D3:** MIE (Master Interrupt Enable)
- **D2:** DLC (Disable Lower Chain)
- **D1:** NV (No Vector)
- **D0:** VIS (Vector Includes Status)

---

**Write Register 10**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** 6-Bit/8-Bit Sync
- **D6:** Loop Mode
- **D5:** Abort/Flag on Underrun
- **D4:** Mark/Flag Idle
- **D3:** Go Active on Poll
- **D2:** CRC Preset I/O
- **D1-D0:** Data Encoding
  - 00 = NRZ
  - 01 = NRZI
  - 10 = FM1 (Transition = 1)
  - 11 = FM0 (Transition = 0)

---

**Write Register 11**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** RTxC Xtal/No Xtal
- **D6-D5:** Receive Clock Source
  - 00 = Receive Clock = RTxC Pin
  - 01 = Receive Clock = TRxC Pin
  - 10 = Receive Clock = BR Generator Output
  - 11 = Receive Clock = DPLL Output
- **D4-D3:** Transmit Clock Source
  - 00 = Transmit Clock = RTxC Pin
  - 01 = Transmit Clock = TRxC Pin
  - 10 = Transmit Clock = BR Generator Output
  - 11 = Transmit Clock = DPLL Output
- **D2:** TRxC O/I (Output/Input)
- **D1-D0:** TRxC Output Source
  - 00 = TRxC Out = Xtal Output
  - 01 = TRxC Out = Transmit Clock
  - 10 = TRxC Out = BR Generator Output
  - 11 = TRxC Out = DPLL Output

---

**Write Register 12**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
TC7| TC6| TC5| TC4| TC3| TC2| TC1| TC0
```
Lower Byte of Time Constant

---

**Write Register 13**
```
D7  | D6  | D5  | D4  | D3  | D2  | D1  | D0
TC15| TC14| TC13| TC12| TC11| TC10| TC9 | TC8
```
Upper Byte of Time Constant

---

**Write Register 14**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7-D5:** DPLL Commands
  - 000 = Null Command
  - 001 = Enter Search Mode
  - 010 = Reset Missing Clock
  - 011 = Disable DPLL
  - 100 = Set Source = BR Generator
  - 101 = Set Source = RTxC
  - 110 = Set FM Mode
  - 111 = Set NRZI Mode
- **D4:** Local Loopback
- **D3:** Auto Echo
- **D2:** DTR/Request Function
- **D1:** BR Generator Source
- **D0:** BR Generator Enable

---

**Write Register 15**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Break/Abort IE
- **D6:** Tx Underrun/EOM IE
- **D5:** CTS IE
- **D4:** Sync/Hunt IE
- **D3:** DCD IE
- **D2:** SDLC FIFO Enable
- **D1:** Zero Count IE
- **D0:** 0 (Reserved)

---

## Read Registers

The SCC contains ten read registers (eleven, counting the receive buffer (RR8) in each channel). Four of these can be read to obtain status information (RR0, RR1, RR10, and RR15). Two registers (RR12 and RR13) are read to learn the Baud Rate Generator time constant. RR2 contains either the unmodified interrupt vector (Channel A) or the vector modified by status information (Channel B). RR3 contains the Interrupt Pending (IP) bits (Channel A only; see Figure 19). RR6 and RR7 contain the information in the SDLC Frame Status FIFO, but is only read when WR15 D2 is set (see Figures 19 and 20).

---

### **Figure 19: Read Register Bit Functions, #1 of 2**

**Read Register 0**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Break/Abort
- **D6:** Tx Underrun/EOM
- **D5:** CTS
- **D4:** Sync/Hunt
- **D3:** DCD
- **D2:** Tx Buffer Empty
- **D1:** Zero Count
- **D0:** Rx Character Available

---

**Read Register 1**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** End of Frame (SDLC)
- **D6:** CRC/Framing Error
- **D5:** Rx Overrun Error
- **D4:** Parity Error
- **D3-D1:** Residue Code (bits 2-0)
- **D0:** All Sent

---

**Read Register 2**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
V7 | V6 | V5 | V4 | V3 | V2 | V1 | V0
```
Interrupt Vector*
(*Modified in B Channel)

---

**Read Register 3**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7-D6:** 0 (Reserved)
- **D5:** Channel A Rx IP
- **D4:** Channel A Tx IP
- **D3:** Channel A Ext/Status IP
- **D2:** Channel B Rx IP
- **D1:** Channel B Tx IP
- **D0:** Channel B Ext/Status IP

*Always 0 in B Channel

---

**Read Register 10**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** One Clock Missing
- **D6:** Two Clocks Missing
- **D5:** 0
- **D4:** Loop Sending
- **D3-D2:** 0
- **D1:** On Loop
- **D0:** 0

---

**Read Register 12**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
TC7| TC6| TC5| TC4| TC3| TC2| TC1| TC0
```
Lower Byte of Time Constant

---

### **Figure 20: Read Register Bit Functions, #2 of 2**

**Read Register 13**
```
D7  | D6  | D5  | D4  | D3  | D2  | D1  | D0
TC15| TC14| TC13| TC12| TC11| TC10| TC9 | TC8
```
Upper Byte of Time Constant

---

**Read Register 15**
```
D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0
```

- **D7:** Break/Abort IE
- **D6:** Tx Underrun/EOM IE
- **D5:** CTS IE
- **D4:** Sync/Hunt IE
- **D3:** DCD IE
- **D2:** 0
- **D1:** Zero Count IE
- **D0:** 0

---

## Z85C30 Timing

The SCC generates internal control signals from the WR and RD that are related to PCLK. PCLK has no phase relationship with WR and RD, the circuitry generating the internal control signals provides time for meta-stable conditions to disappear. This gives rise to a recovery time related to PCLK. The recovery time applies only between bus transactions involving the SCC.

The recovery time required for proper operation is specified from the falling edge of WR or RD in the first transaction involving the SCC to the falling edge of WR or RD in the second transaction involving the SCC. This time must be at least 3 PCLKs regardless of which register or channel is being accessed. The remainder of this section describes the read cycle, write cycle and interrupt acknowledge cycle timing for the Z85C30 device.

---

### Read Cycle Timing

**Figure 21: Read Cycle Timing**

This timing diagram shows:
- **A/B, D/C:** Address Valid (stable throughout cycle)
- **INTACK:** Status valid (stable throughout cycle)
- **CE:** Active Low (chip enable)
- **RD:** Active Low (read strobe)
- **D7-D0:** Data Valid (output during RD Low)

If CE falls after RD falls, or if CE rises before RD rises, the effective RD is shortened.

---

### Write Cycle Timing

**Figure 22: Write Cycle Timing**

This timing diagram shows:
- **A/B, D/C:** Address Valid (stable throughout cycle)
- **INTACK:** Status valid (stable throughout cycle)
- **CE:** Active Low (chip enable)
- **WR:** Active Low (write strobe)
- **D7-D0:** Data Valid (must be valid before rising edge of WR)

If CE falls after WR falls, or if CE rises before WR rises, the effective WR is shortened. Data must be valid before the rising edge of WR.

---

### Interrupt Acknowledge Cycle Timing

**Figure 23: Interrupt Acknowledge Cycle Timing**

This timing diagram shows:
- **INTACK:** Active Low
- **RD:** Active Low (after INTACK)
- **D7-D0:** Vector output (during RD Low)

Between the time INTACK goes Low and the falling edge of RD, the internal and external IEI/IEO daisy chains settle. If there is an interrupt pending in the SCC and IEI is High when RD falls, the Acknowledge cycle is intended for the SCC. In this case, the SCC can be programmed to respond to RD Low by placing its interrupt vector on D7-D0. It then sets the appropriate Interrupt-Under-Service latch internally.

If the external daisy chain is not used, AC parameter #38 is required to settle the interrupt priority daisy chain internal to the SCC. If the external daisy chain is used, you must follow the equation in Table 6 on page 53 for calculating the required daisy-chain settle time.

---

## Z80C30 Timing

The SCC generates internal control signals from AS and DS that are related to PCLK. Because PCLK has no phase relationship with AS and DS, the circuitry generating these internal control signals must provide time for metastable conditions to disappear. This gives rise to a recovery time related to PCLK. The recovery time applies only between bus transactions involving the SCC. The recovery time required for proper operation is specified from the falling edge of DS in the first transaction involving the SCC to the falling edge of DS in the second transaction involving the SCC. The remainder of this section describes read cycle, write cycle and interrupt acknowledge cycle timing for the Z80C30 device.

---

### Read Cycle Timing

**Figure 24: Read Cycle Timing**

This timing diagram shows:
- **AS:** Address Strobe (latches address)
- **CS0:** Chip Select 0 (latched with address)
- **INTACK:** Interrupt Acknowledge (latched with address)
- **AD7-AD0:** Address → Data Valid (multiplexed bus)
- **R/W:** Must be High for read cycle
- **CS1:** Must be High for cycle to occur
- **DS:** Data Strobe (enables output drivers when Low)

The address on AD7–AD0 and the state of CS0 and INTACK are latched by the rising edge of AS. R/W must be High to indicate a read cycle. CS1 must also be High for the read cycle to occur. The data bus drivers in the SCC are then enabled while DS is Low.

---

### Write Cycle Timing

**Figure 25: Write Cycle Timing**

This timing diagram shows:
- **AS:** Address Strobe (latches address)
- **CS0:** Chip Select 0 (latched with address)
- **INTACK:** Interrupt Acknowledge (latched with address)
- **AD7-AD0:** Address → Data (multiplexed bus)
- **R/W:** Must be Low for write cycle
- **CS1:** Must be High for cycle to occur
- **DS:** Data Strobe (strobes data into SCC when Low)

The address on AD7–AD0 and the state of CS0 and INTACK are latched by the rising edge of AS. R/W must be Low to indicate a write cycle. CS1 must be High for the write cycle to occur. DS Low strobes the data into the SCC.

---

### Interrupt Acknowledge Cycle Timing

**Figure 26: Interrupt Acknowledge Cycle Timing**

This timing diagram shows:
- **AS:** Address Strobe
- **CS0:** (Ignored during INTACK)
- **INTACK:** Active Low
- **AD7-AD0:** (Ignored) → Vector
- **DS:** Data Strobe (triggers vector output)

The address on AD7–AD0 and the state of CS0 and INTACK are latched by the rising edge of AS. If INTACK is Low, the address and CS0 are ignored. The state of the R/W and CS1 are also ignored for the duration of the Interrupt Acknowledge cycle. Between the rising edge of AS and the falling edge of DS, the internal and external IEI/IEO daisy chains settle. If there is an interrupt pending in the SCC, and IEI is High when DS falls, the Acknowledge cycle was intended for the SCC. In this case, the SCC is programmed to respond to RD Low by placing its interrupt vector on D7-D0 and internally setting the appropriate Interrupt-Under-Service latch.

---
# CMOS SCC Serial Communications Controller
## Electrical Characteristics (Continued)

---

## Absolute Maximum Ratings

Stresses greater than those listed in Absolute Maximum Ratings may cause permanent damage to the device. This is a stress rating only. Operation of the device at any condition above those indicated in the operational sections of these specifications is not implied. Exposure to absolute maximum rating conditions for extended periods may affect device reliability.

### Table 3: Absolute Maximum Ratings

| Parameter | Rating |
|-----------|--------|
| VCC Supply Voltage range | –0.3 V to +7.0 V |
| Voltages on all pins with respect to GND | –3 V to VCC +0.3 V |
| TA Operating Ambient Temperature | See the Ordering Information chapter on page 75 |
| Storage Temperature | –65°C to +150°C |

---

## Standard Test Conditions

The DC Characteristics and capacitance sections below apply for the following standard test conditions, unless otherwise noted. All voltages are referenced to GND. Positive current flows into the referenced pin. See Figures 27 and 28.

- +4.50 V ≤ VCC ≤ +5.50 V
- GND = 0 V
- TA (see the Ordering Information section on page 75)

---

### Figure 27: Standard Test Load

```
               +5 V
                |
              2.1 KΩ
                |
From Output ----+----+----+
Under Test      |    |    |
             100 pF  |  250 μA
                |    |    |
               GND  GND  GND
```

---

### Figure 28: Open-Drain Test Load

```
               +5 V
                |
              2.2 KΩ
                |
From Output ----+
                |
              50 pF
                |
               GND
```

---

## Capacitance

Capacitance lists the input, output and bidirectional capacitance.

### Table 4: Capacitance

| Symbol | Parameter | Min | Max | Unit | Test Condition |
|--------|-----------|-----|-----|------|----------------|
| CIN | Input Capacitance | | 10 | pF¹ | Unmeasured Pins Returned to Ground² |
| COUT | Output Capacitance | | 15 | pF | |
| CI/O | Bidirectional Capacitance | | 20 | pF | |

**Notes:**
1. pF = 1 MHz, over specified temperature range.
2. Unmeasured pins returned to Ground.

---

## Miscellaneous

The Gate Count is 6800.

---

## DC Characteristics

Z80C30/Z85C30 DC Characteristics lists the DC characteristics for the Z80C30 and Z85C30 devices.

### Table 5: Z80C30/Z85C30 DC Characteristics¹

| Symbol | Parameter | Min | Typ | Max | Unit | Condition |
|--------|-----------|-----|-----|-----|------|-----------|
| VIH | Input High Voltage | 2.2 | | VCC +0.3¹ | V | |
| VIL | Input Low Voltage | –0.3 | | 0.8 | V | |
| VOH1 | Output High Voltage | 2.4 | | | V | IOH = –1.6 mA |
| VOH2 | Output High Voltage | VCC–0.8 | | | V | IOH = –250 μA |
| VOL | Output Low Voltage | | | 0.4 | V | IOL = +2.0 mA |
| IIL | Input Leakage | | | ±10.0 | μA | 0.4 VIN + 2.4 V |
| IOL | Output Leakage | | | ±10.0 | μA | 0.4 VOUT + 2.4 V |
| ICC1 | VCC Supply Current² | | 7 | 12 (10 MHz) | mA | VCC = 5 V; VIH = 4.8 VIL = 0 |
| | | | 9 | 15 (16.384 MHz) | mA | Crystal Oscillator off |
| ICCOSC | Crystal OSC Current³ | | 4 | | mA | Current for each OSC in addition to ICC1 |

**Notes:**
1. VCC = 5V ±10% unless otherwise specified, over specified temperature range.
2. Typical ICC was measured with oscillator off.
3. No ICC (OSC) max is specified due to dependency on external circuit and frequency of oscillation.

---

## AC Characteristics

Figures 29 through 32 show read and write timing for the Z85C30 device.

---

### Figure 29: Z85C30 Read/Write Timing Diagram

This comprehensive timing diagram shows the relationships between:
- **PCLK** (system clock)
- **A/B, D/C** (address signals)
- **INTACK** (interrupt acknowledge)
- **CE** (chip enable)
- **RD** (read strobe)
- **WR** (write strobe)
- **D7-D0** (data bus for read/write operations)
- **W/REQ** (wait/request signals)
- **DTR/REQ** (DTR/request signal)
- **INT** (interrupt output)

The diagram includes numbered timing parameters (1-44) that correspond to the specifications in Table 6.

---

### Figure 30: Z85C30 Interrupt Acknowledge Timing Diagram

This timing diagram illustrates interrupt acknowledge cycle timing showing:
- **PCLK** synchronization
- **INTACK** signal
- **RD** during acknowledge
- **D7-D0** vector output
- **IEI/IEO** daisy chain signals
- **INT** response

---

### Figure 31: Z85C30 Cycle Timing Diagram

Shows the minimum recovery time between bus cycles:
- **PCLK** reference
- **CE** chip enable timing
- **RD or WR** strobe relationship

---

### Figure 32: Z85C30 Reset Timing Diagram

Illustrates reset sequence timing:
- **WR** and **RD** must both be low
- Minimum pulse width requirements
- Recovery after reset

---

### Table 6: Z85C30 Read/Write Timing

This comprehensive table provides detailed AC timing specifications for three speed grades:

| No | Symbol | Parameter | 8.5 MHz | 10 MHz | 16 MHz |
|----|--------|-----------|---------|--------|--------|
|    |        |           | Min/Max | Min/Max | Min/Max |

**Key timing parameters include:**

1. **PCLK Timing (1-5):**
   - TwPCl: PCLK Low Width (45/40/26 ns min)
   - TwPCh: PCLK High Width (45/40/26 ns min)
   - TfPC: PCLK Fall Time (10/10/5 ns max)
   - TrPC: PCLK Rise Time (10/10/5 ns max)
   - TcPC: PCLK Cycle Time (118-4000/100-4000/61-4000 ns)

2. **Address Setup/Hold Times (6-9):**
   - Setup times to WR/RD: 66/50/35 ns min
   - Hold times: 0 ns (all speeds)

3. **INTACK Timing (10-15):**
   - Setup and hold times relative to PCLK and control signals

4. **Chip Enable Timing (16-21):**
   - CE setup/hold relative to WR/RD

5. **Read Cycle Timing (22-27):**
   - RD pulse width: 145/125/70 ns min
   - Data valid delays: 135/120/70 ns max
   - Data float delays: 38/35/30 ns max

6. **Write Cycle Timing (28-30):**
   - WR pulse width: 145/125/75 ns min
   - Data setup/hold times

7. **Wait/Request Timing (31-36):**
   - Delays to W/REQ and DTR/REQ outputs

8. **Interrupt Timing (37-45):**
   - INT signal delays
   - Interrupt acknowledge timing
   - IEI/IEO daisy chain timing

9. **Recovery Times (46-49b):**
   - Valid Access Recovery Time: 3.5 TcPC
   - Reset pulse width: 145/100/75 ns min

**Important Notes:**
1. Parameter does not apply to Interrupt Acknowledge transactions.
2. Open-drain output, measured with open-drain test load.
3. Parameter applies to enhanced request mode only (WR7' D4 = 1).
4. Parameter is system-dependent. For any SCC in the daisy chain, TdIAi(RD) must be greater than the sum of TdPC(IEO) for the highest priority device plus delays for intervening devices.
5. Parameter applies only between transactions involving the Z85C30. If WR/RD falling edge is synchronized to PCLK falling edge, then TrC = 3TcPc.
6. This specification is only applicable when Valid Access Recovery Time is less than 35 PCLK.

---

### Figure 33: Z85C30 General Timing Diagram

This detailed timing diagram shows the relationships between serial I/O signals and control signals:

**Receive Path:**
- RxD (receive data)
- RTxC/TRxC (receive clock)
- SYNC input
- W/REQ request/wait signals

**Transmit Path:**
- TxD (transmit data)
- RTxC/TRxC (transmit clock)
- W/REQ signals

**Control Signals:**
- PCLK (peripheral clock)
- CTS/DCD (control inputs)
- SYNC output
- INT (interrupt)

Numbered timing parameters (1-22) reference specifications in Table 7.

---

### Table 7: Z85C30 General Timing Table

| No | Symbol | Parameter | 8.5MHz | 10MHz | 16MHz |
|----|--------|-----------|--------|-------|-------|
|    |        |           | Min/Max | Min/Max | Min/Max |

**Key Parameters:**

1. **Request/Wait Timing (1-2):**
   - TdPC(REQ): PCLK to W/REQ Valid (250/150/80 ns max)
   - TdPC(W): PCLK to Wait Inactive (350/250/180 ns max)

2. **Receive Clock Timing (3-9):**
   - TsRXC(PC): RxC to PCLK Setup (N/A - eliminated in ÷4 mode)
   - RxD setup times: 0 ns min
   - RxD hold times: 150/125/50 ns min
   - SYNC timing relative to RxC

3. **Transmit Clock Timing (10-13):**
   - TsTXC(PC): TxC to PCLK Setup (N/A - eliminated in ÷4 mode)
   - TxD output delays: 200/150/80 ns max
   - TRxC output delay: 200/140/80 ns max

4. **Clock Specifications (14-17):**
   - **RTxC Widths:**
     - Normal mode: 150/120/80 ns min (high/low)
     - Enhanced mode (DPLL): 50/40/15.6 ns min
   - **RTxC Cycle Time:**
     - Normal: 488/400/244 ns min (≤ 1/4 PCLK max)
     - Enhanced: 125/100/31.25 ns min
   - Crystal period: 125-1000/100-1000/62-1000 ns

5. **TRxC Timing (18-20):**
   - High/low widths: 150/120/180 ns and 150/120/80 ns min
   - Cycle time: 488/400/244 ns min

6. **Control Input Timing (21-22):**
   - DCD/CTS pulse width: 200/120/70 ns min
   - SYNC pulse width: 200/120/70 ns min

**Important Notes:**
1. RxC is RTxC or TRxC, whichever is supplying the receive clock.
2. Synchronization of RxC to PCLK is eliminated in divide by four operation.
3. Parameter applies only to FM encoding/decoding.
4. TxC is TRxC or RTxC, whichever is supplying the transmit clock.
5. External PCLK to RTxC or TxC synchronization requirement eliminated for PCLK divide-by-four operation. TRxC and RTxC rise and fall times are identical to PCLK.
6. Parameter applies only for transmitter and receiver; DPLL and Baud Rate Generator timing requirements are identical to PCLK requirements.
7. Enhanced Feature — RTxC used as input to internal DPLL only.
8. The maximum receive or transmit data rate is 1/4 PCLK.
9. Both RTxC and SYNC have 30 pF capacitors to ground connections.

---

## Z80C30 Timing

The SCC generates internal control signals from AS and DS that are related to PCLK. Because PCLK has no phase relationship with AS and DS, the circuitry generating these internal control signals must provide time for metastable conditions to disappear. This gives rise to a recovery time related to PCLK. The recovery time applies only between bus transactions involving the SCC. The recovery time required for proper operation is specified from the falling edge of DS in the first transaction involving the SCC to the falling edge of DS in the second transaction involving the SCC.

---

### Z80C30 Bus Cycle Timing Diagrams

**Figure 35: Z80C30 Read/Write Timing Diagram** shows the complete bus cycle including:
- **AS** (Address Strobe)
- **CS0/CS1** (Chip Selects)
- **INTACK** (Interrupt Acknowledge)
- **R/W** (Read/Write control)
- **DS** (Data Strobe)
- **AD7-AD0** (Multiplexed Address/Data bus)
- **W/REQ** (Wait/Request signals)
- **DTR/REQ** (DTR/Request)
- **INT** (Interrupt)
- **PCLK** (Peripheral Clock)

**Figure 36: Z80C30 Interrupt Acknowledge Timing Diagram** illustrates:
- Interrupt acknowledge cycle
- IEI/IEO daisy chain timing
- Vector placement on data bus

**Figure 37: Z80C30 Reset Timing Diagram** shows:
- AS and DS coincident low for reset
- Minimum pulse width requirements

---

### Table 10: Z80C30 Read/Write Timing¹

Comprehensive timing specifications for 8 MHz and 10 MHz operation:

| No | Symbol | Parameter | 8 MHz | 10 MHz |
|----|--------|-----------|-------|--------|
|    |        |           | Min/Max | Min/Max |

**Major Timing Categories:**

1. **AS (Address Strobe) Timing (1-8, 15-16):**
   - TwAS: AS Low Width (35/30 ns min)
   - Address setup/hold times relative to AS

2. **CS (Chip Select) Timing (3-6):**
   - Setup and hold times relative to AS and DS

3. **INTACK Timing (7-8):**
   - Setup/hold relative to AS

4. **R/W Timing (9-11):**
   - Setup times for read/write operations

5. **DS (Data Strobe) Timing (2, 12-13):**
   - TwDSl: DS Low Width (150/125 ns min)
   - Relationship to AS

6. **Data Timing (17-24):**
   - Write data setup/hold
   - Read data access times (140/120 ns max)
   - Data float delay (40/35 ns max)
   - Address to data delay (250/210 ns max)

7. **Wait/Request Timing (25-27):**
   - DS to Wait/Request delays (170/160 ns max)

8. **Interrupt Timing (28-36):**
   - AS to INT delay (500 ns max)
   - Acknowledge cycle timing
   - IEI/IEO daisy chain delays (90 ns max)

9. **Recovery Timing (14, 37-39):**
   - TrC: Valid Access Recovery Time (4 TcPC)
   - TwRES: Reset pulse width (150/100 ns min)

10. **PCLK Specifications (40-44):**
    - Low width: 50/40 ns min
    - High width: 50/40 ns min
    - Cycle time: 125-2000/100-2000 ns
    - Rise/fall times: 10 ns max

**Critical Notes:**
1. Units in nanoseconds (ns) unless otherwise noted.
2. Parameter does not apply to Interrupt Acknowledge transactions.
3. Parameter applies only between transactions involving the SCC.
4. Float delay is defined as the time required for a ±0.5 V change with maximum DC load and minimum AC load.
5. Open-drain output, measured with open-drain test load.
6. Parameter is system dependent for daisy chain timing.
7. Parameter applies only to a Z-SCC pulling INT Low at the beginning of the Interrupt Acknowledge transaction.
8. Internal circuitry allows for the reset to be recognized as a reset by the Z-SCC. All timing references assume 2.0 V for logic "1" and 0.8 V for logic "0".

---

### Figure 38: Z80C30 General Timing Diagram

Shows serial I/O timing relationships:
- Receive data timing
- Transmit data timing
- Clock relationships
- Control signal timing
- Numbered parameters (1-22) reference Table 11

---

### Table 11: Z80C30 General Timing¹

| No | Symbol | Parameter | 8MHz | 10MHz |
|----|--------|-----------|------|-------|
|    |        |           | Min/Max | Min/Max |

**Serial I/O Timing Specifications:**

1. **Request/Wait (1-2):**
   - PCLK to W/REQ Valid: 250/200 ns max
   - PCLK to Wait Inactive: 350/300 ns max

2. **Receive Timing (3-9):**
   - RxC to PCLK setup: N/A (eliminated in ÷4 mode)
   - RxD setup: 0 ns min
   - RxD hold: 150/125 ns min (for both edges in FM mode)
   - SYNC setup: -200/-150 ns min
   - SYNC hold: 5 TcPc

3. **Transmit Timing (10-13):**
   - TxC to PCLK setup: N/A (eliminated in ÷4 mode)
   - TxC to TxD delay: 190/150 ns max
   - TxD to TRxC delay: 200/140 ns max

4. **Clock Specifications (14-20):**
   - **RTxC/TRxC widths:**
     - High: 130/120 ns min
     - Low: 130/120 ns min
   - **Cycle times:**
     - Normal: 472/400 ns min (max rate = 1/4 PCLK)
     - DPLL: 59/50 ns min (with 50% duty cycle)
   - Crystal period: 118-1000/100-1000 ns

5. **Control Inputs (21-22):**
   - DCD/CTS pulse width: 200/120 ns min
   - SYNC pulse width: 200/120 ns min

**Important Notes:**
1. Units in nanoseconds (ns) otherwise noted.
2. RxC is RTxC or TRxC, whichever is supplying the receive clock.
3. Synchronization of RxC to PCLK is eliminated in divide by four operation.
4. Parameter applies only to FM encoding/decoding.
5. TxC is TRxC or RTxC, whichever is supplying the transmit clock.
6. Parameter applies only for transmitter and receiver; DPLL and Baud Rate Generator timing requirements are identical to PCLK requirements.
7. The maximum receive or transmit data rate is 1/4 PCLK.
8. Applies to DPLL clock source only. Maximum data rate of 1/4 PCLK still applies. DPLL clock should have a 50% duty cycle.
9. Both RTxC and SYNC have 30 pF capacitors to ground connected to them.

---

### Figure 39: Z80C30 System Timing Diagram

System-level timing showing interaction between:
- Serial I/O (RxD, TxD)
- Clocks (RTxC, TRxC)
- Control signals (SYNC, CTS, DCD)
- Request/Wait signals
- PCLK synchronization

---

### Table 12: Z80C30 System Timing

| No | Symbol | Parameter | 8MHz | 10MHz |
|----|--------|-----------|------|-------|
|    |        |           | Min/Max² | Min/Max² |

**System Timing Parameters (in TcPC units):**

1. **Receive System Timing (1-4):**
   - RxC to W/REQ Valid: 8-12 TcPC
   - RxC to Wait Inactive: 8-14 TcPC
   - RxC to SYNC Valid: 4-7 TcPC
   - RxC to INT Valid: 8-12 TcPC (basic), 24-34 TcPC (extended)

2. **Transmit System Timing (5-8):**
   - TxC to W/REQ Valid: 5-8 TcPC
   - TxC to Wait Inactive: 5-11 TcPC
   - TxC to DTR/REQ Valid: 4-7 TcPC
   - TxC to INT Valid: 4-6 TcPC (basic), 24-34 TcPC (extended)

3. **Control Input Timing (9-10):**
   - SYNC to INT Valid: 2-6 TcPC (basic), 2-3 TcPC (AS units)⁴
   - DCD/CTS to INT Valid: 2-3 TcPC

**Notes:**
1. RxC is RTxC or TRxC whichever is supplying the receive clock.
2. Units equal to TcPC (PCLK period).
3. Open-drain output, measured with open-drain test load.
4. Units equal to AS (Address Strobe period).
5. TxC is TRxC or RTxC, whichever is supplying the transmit clock.

---

## Packaging

### Figure 40: 40-Pin DIP Package Diagram

**Package dimensions for standard 40-pin Dual In-line Package:**

| Symbol | Millimeter | Inch |
|--------|------------|------|
|        | MIN / MAX | MIN / MAX |
| A1 | 0.51 / 0.46 | .020 / .018 |
| A2 | 4.83 / 3.18 | .190 / .125 |
| B | 0.38 / 0.53 | .015 / .021 |
| B1 | 1.02 / 1.52 | .040 / .060 |
| C | 0.23 / 0.38 | .009 / .015 |
| D | 52.07 / 52.58 | 2.050 / 2.070 |
| E | 15.24 / 15.75 | .600 / .620 |
| E1 | 13.59 / 14.22 | .535 / .560 |
| #8 | 2.54 TYP | .100 TYP |
| #A | 15.49 / 16.51 | .610 / .650 |
| L | 3.18 / 3.81 | .125 / .150 |
| Q1 | 1.52 / 1.91 | .060 / .075 |
| S | 1.52 / 8.29 | .060 / .090 |

**CONTROLLING DIMENSIONS: INCH**

Standard through-hole mounting configuration with 0.100" pin spacing.

---

### Figure 41: 44-Pin PLCC Package Diagram

**Package dimensions for 44-pin Plastic Leaded Chip Carrier:**

**TOP VIEW:** Square package with leads on all four sides
**SIDE VIEW:** Shows lead profile and seating plane

| Symbol | Millimeter | Inch |
|--------|------------|------|
|        | MIN / MAX | MIN / MAX |
| A | 4.27 / 4.57 | .168 / .180 |
| A1 | 2.67 / 2.92 | .105 / .115 |
| D/E | 17.40 / 17.65 | .685 / .695 |
| D1/E1 | 16.51 / 16.66 | .650 / .656 |
| DP | 15.24 / 16.00 | .600 / .630 |
| #8 | 1.27 TYP | .050 TYP |

**NOTES:**
1. CONTROLLING DIMENSIONS: INCH
2. LEADS ARE COPLANAR WITHIN .004 IN.
3. DIMENSION: _MM_
             INCH

Surface mount configuration with J-leads for PCB mounting.

---

## Ordering Information

### Table 13: Z80C30/Z85C30 Ordering Information

| 8 MHz | 10 MHz | 16 MHz |
|-------|--------|--------|
| Z80C3008VSG | Z80C3010VSG | Z85C3016PSG |
| Z85C3008PSG/PEG | Z85C3010PSG/PEG | Z85C3016VSG |
| Z85C3008VSG/VEG | Z85C3010VSG/VEG | |

For complete details about Zilog's Z80C30 and Z85C30 devices, development tools and downloadable software, visit **www.zilog.com**.

---

## Part Number Suffix Designations

Zilog part numbers consist of a number of components, as indicated in the following example:

**Part number Z80C3016PSG** is a Z80C30, 16 MHz, PLCC, 0°C to +70°C, Lead Free

```
Z  80C30  16  P  S  G
|    |     |   |  |  |
|    |     |   |  |  └─ Environmental Flow
|    |     |   |  |     G = Lead Free
|    |     |   |  |
|    |     |   |  └──── Ambient Temperature Range (TA)
|    |     |   |        S = 0°C to +70°C
|    |     |   |        E = Extended, –40°C to +100°C
|    |     |   |
|    |     |   └─────── Package
|    |     |            P = Plastic DIP
|    |     |            V = Plastic Leaded Chip Carrier
|    |     |            D = Ceramic DIP
|    |     |
|    |     └─────────── Speed
|    |                  8 = 8 MHz
|    |                  10 = 10 MHz
|    |                  16 = 16 MHz
|    |
|    └───────────────── Product Number
|
└────────────────────── Zilog Prefix
```

---

## Customer Support

To share comments, get your technical questions answered, or report issues you may be experiencing with our products, please visit Zilog's Technical Support page at **http://support.zilog.com**.

To learn more about this product, find additional documentation, or to discover other facets about Zilog product offerings, please visit the Zilog Knowledge Base at **http://zilog.com/kb** or consider participating in the Zilog Forum at **http://zilog.com/forum**.

This publication is subject to replacement by a later edition. To determine whether a later edition exists, please visit the Zilog website at **http://www.zilog.com**.

---

**Document Number:** PS011708-0115  
**Product Specification**

---

