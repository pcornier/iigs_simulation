# Chapter 7 Built-in I/O Ports and Clock 

The Apple IIGS has several means for data input and output.  The primary output device is the video output, covered in Chapter 4.  Keyboards and mouse devices provide input.  Another means of I/O available is the I/O expansion slots, covered in Chapter 8.  

The disk port, the two **serial** ports, and the game port provide additional I/O.  Another I/O device, although internal to the Apple IIGS, is the real-time clock (RTC).  This chapter describes the disk-port connector, serial ports, the game port, and the real-time clock in the Apple IIGS.  Figure 7-1 shows the Apple IIGS block diagram and position of these I/O devices within the system. 

[Figure 7-1 I/O components of the Apple IIGS described in this chapter] 

## The disk port 

The Apple IIGS uses a disk-port connector, located on the back of the computer, which is compatible with all 3.5-inch Apple II disk drives and most 5.25-inch Apple II disk drives.  The firmware routines within the ROM make communicating with the disk drives reliable and consistent. 

> ▲ **Warning** 
> Using means other than documented entry points and Apple IIGS ROM firmware routines to communicate with the disk drives is extremely dangerous.  Not only do you run the risk of crashing the operating system, but the potential for damaging data on your system disk is high.  It is recommended that you use firmware calls when accessing all disk devices connected to your Apple IIGS. ▲

### Apple II compatibility 

The Apple IIGS uses the same disk drive interface as the Apple IIc and Ile.  Programs written for both of these earlier computers will run on the Apple IIGS.  The firmware recognizes ProDOS **block device** calls and **SmartPort** interface calls to both the Apple UniDisk™ 3.5-inch and Apple DuoDisk® 5.25-inch disk drives.  To find out how to use the ProDOS block device calls, see the *ProDOS 8 Technical Reference Manual*.  To find out how to use the SmartPort interface calls, see the *Apple IIGS Firmware Reference*. 

### The disk-port connector 

The disk-port connector is located at the rear of the Apple IIGS case.  It is a 19-pin connector.  Figure 7-2 shows the connector.  Table 7-1 gives a description of each pin. 

[Figure 7-2 Disk-port connector] 

**Table 7-1 Pins on the disk-port connector** 

| Pin | Signal | Description |
| :--- | :--- | :--- |
| 1,2,3  | GND  | Ground reference and supply  |
| 4  | 3.5DISK  | 3.5- or 5.25-inch drive select  |
| 5  | -12V  | -12-volt supply  |
| 6  | +5V  | +5-volt supply  |
| 7,8  | +12V  | +12-volt supply  |
| 9  | DR2  | Drive 2 select  |
| 10  | WRPROTECT  | Write-protect input  |
| 11  | Phase 0  | Motor phase 0 output  |
| 12  | Phase 1  | Motor phase 1 output  |
| 13  | Phase 2  | Motor phase 2 output  |
| 14  | Phase 3  | Motor phase 3 output  |
| 15  | WREQ  | Write request  |
| 16  | HDSEL  | Head select  |
| 17  | DR1  | Drive 1 select  |
| 18  | RDDATA  | Read data input  |
| 19  | WDATA  | Write data output  |

> ▲ **Warning** 
> The power connections on this disk port are for use by the disk drive only.  Do not use them for any other purpose.  Any other use of these connections may damage the computer's voltage regulator. ▲

### The Disk Interface register 

The Disk Interface register (`$C031`) serves as a control register for the disk drive.  By writing to this register, you select the type of disk drive being used and the side of the disk to be accessed.  

This register uses only two bits, which are both cleared on reset.  When the Disk Interface register is read, 0's are returned in the unused positions (bits 5 through 0).  Figure 7-3 shows the format for this register.  Descriptions of each bit are listed in Table 7-2. 

> **Warning** 
> Be careful when changing bits within this register.  Use only a read-modify-write instruction sequence when manipulating bits.  See the warning in the preface. 

### Figure 7-3 Disk Interface register at $C031
| Bit | Name |
| :-- | :--- |
| 7 | Read / write head select|
| 6 | Disk drive select |
| 5 - 0 | reserved, do not modify|


### Table 7-2 Bits in the Disk Interface register

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7  | 1  | Read/write head select bit: A 1 in this position selects head 1.  |
| | 0  | A 0 selects head 0.  |
| 6  | 1  | Disk drive select bit: A 1 in this position selects 3.5-inch disks.  |
| | 0  | A 0 selects 5.25-inch disks.  |
| 5-0  | - | Reserved; do not modify.  |

### The IWM 

The disk-port interface is enhanced by the Integrated Woz Machine (**IWM**), which simplifies the microprocessor's task of reading and writing serial group-code recording (GCR) encoded data to and from the disk drives.  To perform disk operations, the microprocessor simply reads or writes control and data bytes to or from the IWM. 

> ▲ **Warning** 
> Writing directly to the IWM is extremely dangerous.  Not only do you run the risk of crashing the operating system, but the potential for damaging data on your system disk is high.  It is recommended that you use firmware calls when accessing all disk devices connected to your Apple IIGS. ▲ 

The IWM contains several typical disk support circuits, which make writing data to the disk possible.  These are the discriminator, the phase-locked loop, the data separator, and the write current circuitry. 

The IWM contains several registers that allow you to control disk access: 

  * the Mode register 
  * the Status register 
  * the Handshake register 
  * the Data register 

The IWM is mapped as an internal device with soft switches at addresses `$C0E0` through `$C0EF`.  These are the same addresses as in the Apple IIc.  Table 7-3 shows these locations and their functions. 

### Table 7-3 Disk-port soft switches

| Address | Description |
| :--- | :--- |
| $C0E0  | Stepper motor phase 0 low  |
| $C0E1  | Stepper motor phase 0 high  |
| $C0E2  | Stepper motor phase 1 low  |
| $C0E3  | Stepper motor phase 1 high  |
| $C0E4  | Stepper motor phase 2 low  |
| $C0E5  | Stepper motor phase 2 high  |
| $C0E6  | Stepper motor phase 3 low  |
| $C0E7  | Stepper motor phase 3 high  |
| $C0E8  | Drive disabled  |
| $C0E9  | Drive enabled  |
| $C0EA  | Drive 0 select  |
| $C0EB  | Drive 1 select  |
| $C0EC  | Q6 select bit low  |
| $C0ED  | Q6 select bit high  |
| $C0EE  | Q7 select bit low  |
| $C0EF  | Q7 select bit high  |

Soft switches Q6 and Q7 are select bits for accessing registers within the IWM.  By setting or clearing the Q6, Q7, and spindle motor switches, you may read or write to one of the internal IWM registers, as listed in Table 7-4. 

### Table 7-4 IWM states 

| Q7 | Q6 | Spindle motor | Operation |
| :--- | :--- | :--- | :--- |
| 0  | 0  | 1  | Read Data register  |
| 0  | 1  | x  | Read Status register  |
| 1  | 0  | x  | Read Handshake register  |
| 1  | 1  | 0  | Write Mode register  |
| 1  | 1  | 1  | Write Data register  |

The drive-enable soft switches and the drive-select switches control the state of the disk-select signals DR1 and DR2 located at the disk-port connector.  Table 7-5 shows how these soft switches determine the state of the disk-select signals. 

### Table 7-5 Controlling the disk select signals

| Soft switches ||| | Disk port signals | |
| :--- | :--- | :--- | :--- | :--- | ---|
| **$C0E8** | **$C0E9**  | **$C0EA**  | **$C0EB**  | **DR1**  | **DR2**  |
| 1  | -|-|- | 0  | 0  |
| -|1  | 1  | -| 1  | 0  |
| -|1  | -| 1  | 0  | 1  |

### The Mode register 

The Mode register is a write-only register and contains bits that control the state of the IWM.  These bits are shown in Figure 7-4.  Table 7-6 gives a description of these bits.  To write to the Mode register, set the appropriate soft switches required to access the Mode register.  (See Table 7-4.)  Writing to any odd IWM address ($C0E0 through $C0EF) will write to this register. 

◆ *Note:* Writing to the Mode register will succeed only after the one-second timer has timed out. 


**Table 7-6 Bits in the Mode register** 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7  | | Reserved; do not modify.  |
| 6-5  | | Reserved; always write 0.  |
| 4  | 1  | 8-MHz read-clock speed selected.  |
| | 0  | 7-MHz read-clock speed selected.  Set this bit to 0 for all Apple IIGS disk accesses.  |
| 3  | 1  | Bit-cells are 2 microseconds; used in accesses to Apple 3.5-inch drives.  |
| | 0  | Bit-cells are 4 microseconds; used in accesses to SmartPort devices and all Apple 5.25-inch disk drives.  |
| 2  | 1  | One-second timer is disabled.  |
| | 0  | One-second timer is enabled.  When the current disk drive is deselected, the drive will remain enabled for 1 second if this bit is set.  |
| 1  | 1  | Asynchronous handshake protocol selected; for all except Apple 5.25-inch Apple disk drives.  |
| | 0  | Synchronous handshake protocol selected; for Apple 5.25-inch disk drives.  |
| 0  | 1  | Latch mode is enabled; read-data byte remains valid for full byte time (16 microseconds if using 2-microsecond bit-cells; 32 microseconds if using 4-microsecond bit-cells).  |
| | 0  | Latch mode is disabled; read-data byte remains valid for approximately 7 microseconds.  |

### Figure 7-4 Mode register

| Bit | Name |
| :-- | :--- |
| 7 | Reserved; do not modify|
| 6-5| Reserved; must be 0|
| 4 | Data rate|
|3 | Bit cell size|
| 2 | 1-second timer enable|
|1 |Synchronous/Asynchronous mode|
|0|Lath mode enable|




### The Status register 

The Status register is a read-only register and contains bits that refleet the current state of the disk interface.  These bits are shown in Figure 7-5.  Table 7-7 gives a description of each bit.  To read from the Status register, set the appropriate soft switches required to access the Status register.  (See Table 7-4).  Reading from any even IWM address (`$C0E0` through `$C0EF`) will read from this register. 

### Figure 7-5 Status register


| Bit | Name |
| :-- | :--- |
| 7 | Sense input |
| 6 | Reserved; do not modify |
| 5 | Drive enabled |
| 4 - 0 | Same as Mode register bits 0-4 |



### Table 7-7 Bits in the Status register 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7  | | Sense input line from disk device.  Multifunction input; use determined by disk device.  (Used as a write-protect sense in some Apple disk drives.)  |
| 6  | | Reserved; do not modify.  |
| 5  | 1  | Either drive 1 or drive 2 is selected and the drive motor is on.  |
| | 0  | No drive is currently selected.  |
| 4-0  | 1  | Same as Mode register bits 4-0.  (See Figure 7-4 and Table 7-6).  |

### The Handshake register 

The Handshake register is a read-only register that contains the status of the IWM when writing out the data to the disk drive.  The format of this register is shown in Figure 7-6.  Table 7-8 gives a description of the bits.  To read from the Handshake register, set the appropriate soft switches required to access the Handshake register.  (See Table 7-4.)  Reading from any even IWM address (`$C0E0` through `$C0EF`) will read from this register. 

### Figure 7-6 Handshake register 
| Bit | Name |
| :-- | :--- |
|7 | Read / Write data register ready |
| 6 | Write state | 
| 5 - 0 | Reserved; do not modify|



**Table 7-8 Bits in the Handshake register** 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7  | 1  | Read/write data register is ready for data.  |
| | 0  | Read/write data register is full.  |
| 6  | 1  | No write underrun has occurred; the last write to the disk drive was successful.  |
| | 0  | A write underrun has occurred; a recent data byte was missed and not written to the disk.  |
| 5-0  | 1  | Reserved; do not modify.  |

### The data register 

The Data register is a dual-function register.  Depending on the state of soft switches Q6 and Q7 (Table 7-3), this register functions as a Read-Data register and a Write-Data register.  See Table 7-4 for the state of these bits when reading from and writing to this register.  To read from the Data register, set the appropriate soft switches required to read the Data register.  (See Table 7-4.)  Reading from any even IWM address (`$C0E0` through `$C0EF`) will read from this register.  To write to the Data register, set the appropriate soft switches required to write to the Data register.  (See Table 7-4.)  Writing to any odd IWM address (`$C0E0` through `$C0EF`) will write to this register. 

## The serial ports 

The Apple IIGS has two RS-232-C serial ports located at the back of the computer, which provide synchronous and asynchronous serial communications.  Each of these ports may be used to drive a modem, printer, plotter, or other serial device, or as an **AppleTalk local area network port**.  These serial ports are called channel A and channel B, and are virtually identical except for the different addresses assigned to each.  Only the firmware differs in the way the routines utilize the hardware to provide RS-232 or AppleTalk protocol.  Figure 7-7 shows the pin organization of the serial-port connectors.  Table 7-9 gives a description of the signals. 

◆ *Note:* Remember that firmware for serial ports A and B is located in the ROM space for slots 1 and 2.  Because the AppleTalk firmware operates through either port A or port B, one of the slots (1 or 2) must be available to the AppleTalk firmware.  See the Apple IIGS Owner's Guide for details on choosing serial-port functions from the Control Panel. 

[Figure 7-7 Pin configuration of a serial-port connector] 

**Table 7-9 Pins on a serial-port connector** 

| Pin | Signal | Description |
| :--- | :--- | :--- |
| 1  | DTR  | Data terminal ready  |
| 2  | HSKI  | Handshake in  |
| 3  | TX Data -  | Transmit data  |
| 4  | GND  | Ground reference and supply  |
| 5  | RX Data  | Receive data  |
| 6  | TX Data +  | Transmit data +  |
| 7  | GPI  | General purpose input  |
| 8  | RX Data +  | Receive data +  |

### Noncompatibility with ACIA 

Previous Apple II computers use an asynchronous communications interface adapter (ACIA) chip, either built into the computer (as in the Apple IIc), or on a peripheral card (as used in the Apple Ile), to control the serial ports in the computer.  Due to the great difference in internal architecture of the ACIA and the Serial Communications Controller (SCC) chip, previous Apple II programs that do not use the serial-port firmware calls but rather communicate directly to the ACIA will be incompatible with the Apple IIGS serial ports.  Existing Apple II programs not using the serial-port firmware calls must be rewritten, using firmware routines or SCC commands. 

### The Serial Communications Controller 

The Apple IIGS uses a Zilog 8530 Serial Communications Controller (SCC) chip to control the two serial ports.  The SCC is a programmable, dual-channel, multiprotocol data communications chip as well as a parallel-to-serial/serial-to-parallel converter and controller.  The SCC has on-chip baud-rate generators and phase-locked loops, which reduce the need for additional support circuitry.  Figure 7-8 is a block diagram showing major functional segments of the Zilog SCC. 

[Figure 7-8 Zilog Serial Communications Controller chip (Reproduced by permission. © 1986 Zilog, Inc. This material may not be reproduced without the consent of Zilog, Inc.)] 

To communicate with the SCC, you must address one SCC Command register and one SCC Data register for each of the two serial ports.  These register addresses are listed in Table 7-10. 

**Table 7-10 SCC Command and SCC Data register addresses** 

| Register | Channel A | Channel B |
| :--- | :--- | :--- |
| SCC Command  | $C039  | $C038  |
| SCC data  | $C03B  | $C03A  |

Through these two registers, you can access the 9 SCC read registers and the 15 SCC write registers for each channel.  These registers and their functions are listed in Table 7-11 and Table 7-12.  Figure 7-9 is a diagram showing the major data paths within the Zilog SCC. 

**Table 7-11 SCC read register functions** 

| Read register | Functions |
| :--- | :--- |
| 0  | Transmit/receive buffer status |
|    | External status  |
| 1  | Receive status |
|    | Residue codes|
|    | Error conditions  |
| 2  | Interrupt vectors  |
| 3  | Interrupt pending bits (channel A)  |
| 8  | Receive buffer  |
| 10  | Transmit and receive status  |
| 12  | Baud-rate generator time constant, low byte  |
| 13  | Baud-rate generator time constant, high byte  |
| 15  | External status| 
|     | Interrupt control  |

**Note:** If you wish to use the SCC without utilizing the firmware routines, you must initialize and communicate with the SCC in proper sequence.  Details of how to program the SCC may be found in the 28530 SCC Serial Communications Controller Technical Manual (September, 1986), from Zilog Corporation. 

**Table 7-12 SCC write register functions** 

| Write register | Functions |
| :--- | :--- |
| 0  | Register pointers | 
|    | CRC initialization |
|    | Mode resets  |
| 1  | Interrupt conditions |
|    | Wait/DMA request control  |
| 2  | Interrupt vector  |
| 3  | Receive byte format|
|    | Receive CRC enable  |
| 4  | Transmit/receive clock rate, sync byte format  |
| 5  | Transmit byte format|
|    | Transmit CRC enable  |
| 6  | Sync/SDLC byte format  |
| 8  | Transmit buffer  |
| 9  | Master interrupt bits|
|    | Reset bits|
|    | Interrupt daisy chain  |
| 10  | Transmit/receive control|
|     | Data encoding format  |
| 11  | Receive and transmit clock control  |
| 12  | Baud-rate generator time constant, low byte  |
| 13  | Baud-rate generator time constant, high byte  |
| 14  | Baud-rate generator control|
|     | Phase-locked loop control|
|     | Echo and loopback  |
| 15  | External interrupt control status  |

[Figure 7-9 Data paths in the Zilog SCC (Reproduced by permission. © 1986 Zilog, Inc. This material may not be reproduced without the consent of Zilog, Inc.)] 

## The game I/O port 

All Apple II computers have a game I/O port to which joysticks or hand-controls can connect.  These controls allow users to provide mechanical input to a game program, which analyzes these inputs and responds accordingly.  Four digital switch inputs (SW0 through SW3) are provided, as well as four analog hand control inputs (PDL0 through PDL3) and four digital annunciator outputs (ANO through AN3).  The following sections describe these inputs and outputs in detail. 

### Game I/O 

The Mega II supports hand-control inputs PDL0 through PDL3 and switch inputs SWO through SW3.  These inputs are available through the 16-pin DIP game connector (J21) located below slot 4, and through the 9-pin connector (J9) that is located at the rear panel.  Annunciator outputs ANO through AN3 are provided by the Slotmaker IC and are available only through the 16-pin DIP connector.  Unlike previous Apple II computers, the STROBE output is not available on the game I/O port.  Figure 7-10 shows the two Apple IIGS game connectors.  Table 7-13 lists the locations of the game I/O signals. 

[Figure 7-10 Game I/O connectors] 

**Table 7-13 Game I/O signals** 

| Pin number | | Signal | Description |
| :--- | :--- | :--- | :--- |
| **J21**  | **D**  | | |
| 1  | 2  | +5V  | +5 volts  |
| 2  | 7  | SWO  | Switch input 0  |
| 3  | 1  | SW1  | Switch input 1  |
| 4  | 6  | SW2  | Switch input 2  |
| 5  | | +5V  | +5-volt pullup  |
| 6  | 5  | PDLO  | Analog input 0  |
| 7  | 4  | PDL2  | Analog input 2  |
| 8  | 3  | GND  | Power and signal ground  |
| 9  | | SW3  | Switch input 3  |
| 10  | 8  | PDL1  | Analog input 1  |
| 11  | 9  | PDL3  | Analog input 3  |
| 12  | | AN3  | Digital output 3  |
| 13  | | AN2  | Digital output 2  |
| 14  | | AN1  | Digital output 1  |
| 15  | | ANO  | Digital output 0  |
| 16  | | N.C.  | No connection  |

### The hand-control signals 

Several inputs and outputs are available at the 16-pin IC connector on the main logic board: four 1-bit inputs, or switches (SW0 through SW3);  four analog inputs (PDL0 through PDL3); and four 1-bit outputs (ANO through AN3).  You can access all these inputs and outputs from your application program.  Note that the SW3 input is new to the Apple IIGS. 

Ordinarily, you connect a pair of hand controls to the 16-pin connector.  The rotary controls use two analog inputs, and the push buttons use two 1-bit inputs.  But you can also use these inputs and outputs for many other jobs.  For example, two analog inputs can be used with a two-axis joystick.  Figure 7-10 shows the connector pin numbers. 

The Apple Desktop Bus will accept ADB hand controls, joysticks, and graphics tablets as well as those keyboards and mouse devices specifically designed for the ADB.  The ADB microcontroller handles mouse and keyboard input devices transparently;  that is, simply reading the standard locations will return the current values of these devices.  See Chapter 6 for more information. 

**Annunciator outputs:** The four 1-bit outputs (ANO through AN3) are called annunciators.  Each annunciator can be used to turn a lamp, a relay, or some similar electronic device on and off. 

> ▲ **Warning** 
> When driving a device with the annunciator outputs, be sure not to load any one output with more than one standard TTL load. ▲ 

Each annunciator is controlled by a soft switch, and each switch uses a pair of memory locations.  These memory locations are shown in Table 7-14.  Any reference to the lower address of an address pair turns the corresponding annunciator off;  a reference to the higher address turns the annunciator on.  You can determine the state of only one annunciator, AN3.  To do this, read the RDDHIRES switch at location $C064 and test bit 5.  If this bit is a 0, then AN3 is cleared.  If this bit is a 1, then AN3 is set.  Annunciator 3 serves a dual purpose in the Apple IIGS: It also serves as a switch, allowing you to toggle between two display modes.  Refer to Chapter 4 for more information about the role of annunciator 3 in video.  Table 7-14 shows the annunciator memory locations. 

**Switch inputs:** The four 1-bit inputs (SWO through SW3) can be connected to the output of another electronic device or to a push button.  When you read a byte from one of these locations, only the high-order bit-bit 7-is valid information;  the rest of the byte is undefined.  The soft switch locations that reflect the state of these switch inputs are 49249 through 49251 (`$C060` through `$C063`), as shown in Table 7-15. 

**Table 7-14 Annunciator memory locations** 

| Annunciator | | | Address | |
| :--- | :--- | :--- | :--- | :--- |
| **Number**  | **Pin**  \*| **State**  | **Hex**  | **Dec**  |
| 0  | 15  | Off  | $C058  | 49240  |
| | | On  | $C059  | 49241  |
| 1  | 14  | Off  | $C05A  | 49242  |
| | | On  | $C05B  | 49243  |
| 2  | 13  | Off  | $C05C  | 49244  |
| | | On  | $C05D  | 49245  |
| 3  | 12  | Off  | $C05E  | 49246  |
| | | On  | $C05F  | 49247  |

\* Pin numbers given are for the 16-pin IC connector on the circuit board. 

**Analog inputs:** The four analog inputs (PDL0 through PDL3) are designed for use with 150,000-ohm variable resistors or potentiometers.  The variable resistance is connected between the +5-volt supply and each input, so that it makes up part of a timing circuit.  The circuit changes state when its time constant has elapsed, and the time constant varies as the resistance varies.  Your program can measure this time by counting in a loop until the circuit changes state, or times out. 

Before a program can read the analog inputs, it must first reset the timing circuits.  Accessing memory location 49264 (`$C070`) does reset these circuits.  As soon as you reset the timing circuits, the high bits of the bytes at locations 49252 through 49255 (`$C064` through `$C067`) are set to 1.  Within about 3 milliseconds, these bits will change back to 0 and remain there until you reset the timing circuits again.  The exact time each of the four bits remains high is directly proportional to the resistance connected to the corresponding input.  If these inputs are open-no resistances are connected the corresponding bits may remain high indefinitely. 

To read the analog inputs, use a program loop that resets the timers and then increments a counter until the bit at the appropriate memory location changes to 0.  High-level languages, such as BASIC, also include convenient means of reading the analog inputs: Refer to your language manuals. 

### Summary of secondary I/O locations 

Table 7-15 shows the memory locations for all of the built-in I/O devices except the keyboard and the video display and other primary I/O locations.  As explained earlier, some soft switches should be accessed only by means of read operations; those switches are marked. 

**Table 7-15 Secondary I/O memory locations** 

| Soft switch | Address | | Definition |
| :--- | :--- | :--- | :--- |
| | **Hex**  | **Dec**  | |
| SPKR  | $C030  | 49200  | Toggle speaker (read only).  |
| CLRANO  | $C058  | 49240  | Clear annunciator 0.  |
| SETANO  | $C059  | 49241  | Set annunciator 0.  |
| CLRAN1  | $C05A  | 49242  | Clear annunciator 1.  |
| SETANI  | $C05B  | 49243  | Set annunciator 1.  |
| CLRAN2  | $C05C  | 49244  | Clear annunciator 2.  |
| SETAN2  | $C05D  | 49245  | Set annunciator 2.  |
| CLRAN3  | $C05E  | 49246  | Clear annunciator 3.  |
| SETAN3  | $C05F  | 49247  | Set annunciator 3.  |
| BUTN3  | $C060  | 49248  | Read switch 3 (read only).  |
| BUTNO  | $C061  | 49249  | Read switch 0 (read only).  |
| BUTNI  | $C062  | 49250  | Read switch 1 (read only).  |
| BUTN2  | $C063  | 49251  | Read switch 2 (read only).  |
| PADDLO  | $C064  | 49252  | Read analog-input 0.  |
| PADDL1  | $C065  | 49253  | Read analog-input 1.  |
| PADDL2  | $C066  | 49254  | Read analog-input 2.  |
| PADDL3  | $C067  | 49255  | Read analog-input 3.  |
| PTRIG  | $C070  | 49264  | Analog-input reset.  |

## Built-in real-time clock 

The real-time clock (RTC) chip provides the system with calendar and clock information as well as parameter RAM preserved by battery power.  These functions are performed through two read/write registers: the control and data registers. 

◆ *Note:* The parameter RAM in the RTC is used for system parameters, and is not available to, nor should it be used by, programs other than the system. 

The control register (located at `$C034`), shown in Figure 7-11, serves a dual function: as the control register for the RTC and as the Border Color register.  Refer to "Border Color" in Chapter 4 for more information on controlling the color of the display border. 

Serial data communication to and from the RTC is carried out one byte at a time.  (The terms read and write are used in perspective of the system: A read transfers data from the clock chip, while a write transfers data to the clock chip.)  To write to the clock chip, the program must first write the data into the Data register (`$C033`), then set the appropriate bits in the control register (`$C034`).  To read from the clock chip, set the appropriate control register bits, and then read the data from the Data register. 

*Note:* To remain compatible with future Apple II products, use the firmware calls to read and write data to the RTC.  See the Apple IIGS Firmware Reference for how to use the firmware. 

> ▲ **Warning** 
> Be careful when changing bits within this register.  Use only a read-modify-write instruction sequence when manipulating bits.  See the warning in the preface. ▲

### Figure 7-11 Control register at $C034
| Bit | Name |
| :-- | :--- |
| 7 | Start/finished|
| 6 | Read/write |
| 5 | Last byte |
| 4| Reserved;do not modify|
|3-0| Border color|



**Table 7-16 Bits in the control register** 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7  | 1  | A read or write to the the clock chip begins by setting this bit to 1.  |
| | 0  | This bit is set to 0 automatically by the RTC when the data exchange is complete.  The program can detect that the exchange has been completed by polling bit 7 for a 0.  |
| 6  | 1  | The read/write bit: Set this bit to 1 prior to a read from the RTC.  |
| | 0  | Set this bit to 0 prior to a write to the RTC.  |
| 5  | 1  | The last-byte control bit: After the last byte has been read or written, this bit must be set to 1.  This last step is necessary to avoid corrupting the data in the clock chip after the transactions are completed.  |
| | 0  | A data transfer typically involves an exchange of two or three bytes.  Set this bit to 0 before transferring any bytes to or from the RTC.  |
| 4  | | Reserved; do not modify.  |
| 3-0  | | Border Color register: See "Border Color" in Chapter 4 for details on selecting the video display border color.  |
