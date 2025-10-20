# Chapter 8 I/O Expansion Slots

The main logic board of the Apple IlGS has seven empty peripheral-card connectors or slots on it. These slots make it possible to add features by plugging in peripheral cards with additional hardware. This chapter describes the hardware that supports these slots, including the signals available at the expansion slots. Figure 8-1 is a block diagram of the Apple IlGS that shows the relationship of the slots in the computer.


[Figure 8-1 Expansion slots and other components in the Apple IIGS 

◆ *Note:* The Apple IIGS has seven expansion slots plus a memory expansion slot.

-----

## The expansion slots

The seven connectors lined up across the back part of the Apple IIGS main circuit card are the expansion slots (also called *peripheral* slots or simply *slots*), numbered from 1 to 7. They are 50-pin card-edge connectors with pins on 0.10-inch centers. A circuit card plugged into one of these connectors has access to all the signals necessary to perform input and output and to execute programs in RAM or ROM on the card. These signals are described in Table 8-1 and are shown in Figure 8-2.


[Figure 8-2 Peripheral-expansion slot pins 

**Table 8-1 Expansion slot signals** 

| Pin | Signal | Description |
| :--- | :--- | :--- |
| 1 | /IOSEL | Normally high; goes low during 00 when the 65C816 addresses location $Cnxx, where n is the connector number |
| 2-17 | A0-A15 | Three-state address bus: The address becomes valid during ø1 and remains valid during 00 |
| 18 | A2R/W | Three-state read/write line: Valid at the same time as the address bus; high during a read cycle, low during a write cycle |
| 19 | /SYNC | Composite horizontal and vertical sync, on expansion slot 7 only |
| 20 | /IOSTRB | Normally high; goes low during 00 when the 65C816 addresses a location between $C800 and $CFFF. |
| 21 | RDY | Input to the 65C816: Pulling this line low during ø1 halts the 65C816 with the address bus holding the address of the location currently being fetched. |
| 22 | /DMA | Input to the address bus buffers: Pulling this line low during ø1 disconnects the 65C816 from the address bus. |
| 23 | INT OUT | Interrupt priority daisy-chain output: Usually connected to pin 28 (INT IN). |
| 24 | DMA OUT | DMA priority daisy-chain output: Usually connected to pin 27 (DMA IN). |
| 25 | +5V | +5-volt power supply: A total of 500 mA is available for all peripheral cards. |
| 26 | GND | System common ground |
| 27 | DMA IN | DMA priority daisy-chain input: Usually connected to pin 24 (DMA OUT). |
| 28 | INT IN | Interrupt priority daisy-chain input: Usually connected to pin 23 (INT OUT). |
| 29 | /NMI | Nonmaskable interrupt to 65C816: Pulling this line low starts an interrupt cycle with the interrupt-handling routine at location $03FB. |
| 30 | /IRQ | Interrupt request to 65C816: Pulling this line low starts an interrupt cycle only if the interrupt-disable (I) flag in the 65C816 is not set. |
| 31 | /RST | Pulling this line low initiates a reset routine. |
| 32 | /INH | Pulling this line low during ø1 inhibits (disables) the memory on the main circuit board. |
| 33 | -12V | -12-volt power supply: A total of 200 mA is available for all peripheral cards. |
| 34 | -5V | -5-volt power supply: A total of 200 mA is available for all peripheral cards. |
| 35 | CREF | 3.58-MHz color-reference signal: slot 7 only |
| 35 | M2B0 | Mega II bank 0 signal. |
| 36 | 7M | System 7-MHz clock: This line can drive 2 LS TTL loads."  |
| 37 | Q3 | System 2-MHz asymmetrical clock: This line can drive 2 LS TTL loads. |
| 38 | 01 | 01 clock: This line can drive 2 LS TTL loads."  |
| 39 | /M2SEL | The Mega II select signal: This signal goes low whenever the Mega II is addressing a location within the 128K of Mega II RAM. |
| 40 | 00 | 00 clock: This line can drive 2 LS TTL loads."  |
| 41 | /DEVSEL | Normally high; goes low during 00 when the 650816 addresses location $C0nx, where n is the connector number plus 8. |
| 42-49 | D7-D0 | Three-state buffered bidirectional data bus: Data become valid during 00 high and remain valid until 20 goes low. |
| 50 | +12V | +12-volt power supply: A total of 250 mA is available for all peripheral cards. |

\*Loading limits are for each card.

-----

### Apple II compatibility

The seven I/O slots in the Apple IlGS are almost identical to the slots in the Apple He, the only exceptions being signals /M2SEL and M2B0. /M2SEL replaces uPSYNC on pin 39, and M2B0 is available at pin 35, only at slot 3; CREF is still available at pin 35, at slot 7.

The slots behave like their counterparts in the Apple II with only a few differences, the most important being the behavior of the address bus. Since the Apple IlGS computer can operate at 2.8 MHz and has a 24-bit address, the address bus to the slots is not always valid as it was in the Apple II. The signal /M2SEL indicates when a valid address for banks 224 or 225 ($E0 or $E1) is present on the address bus and so should be used to qualify any address decoding that does not use /lOSEL. Since these memory spaces contain video buffers and I/O addresses, peripheral video cards can make extensive use of these two signals.


-----

### Direct memory access

Direct memory access (DMA) supports the address range $00 through $4F.

During DMA cycles (memory access cycles that are controlled by a DMA peripheral card), the address bus is turned off until the bank address has been latched.

◆ **Note:** To increase read/write data timing margins to the high-speed RAMs, the FPI generates an early CAS (card address strobe) signal for read cycles and a late CAS signal for write cycles.

-----

## I/O in the Apple IIGS

The input and output functions are made possible by built-in I/O devices and the use of peripheral-slot $I/O$ and DMA cards.

### Slot I/O cards

Most I/O cards used in the Apple II also work in the Apple IIGS. Cards that use the /lOSEL and /DEVSEL bus signals will work especially well, because they do not have to deal with the larger address range of the Apple IlGS.

The 65C816 processor operates with a 24-bit address; however, the I/O slots receive only a l6-bit address. Therefore, cards that use the l6-bit address decode select method rather than the /DEVSEL and /lOSEL signals will not work properly. These cards include the multifunction I/O cards that emulate multiple I/O cards and most add-on RAM cards. In general, these types of cards will not be needed because of the extensive built-in I/O and high-speed RAM expansion already provided.

Cards that use /INH will work properly if

* the system is running at 1.024 MHz
* they assert /INH within 200 nanoseconds of the 0O falling edge

However, compatibility with this type of card must be determined on an individual basis, because many Monitor firmware calls execute code in bank `$FF`, and many cards are not designed to decode bank information.

The FPI will ignore any occurrence of /INH when the system is running fast (2.8 MHz), or when it is not in a bank where I/O and language-card operation are enabled. By ignoring /INH, compatibility with existing cards is improved.


### DMA cards

Many DMA cards that work successfully in previous Apple II models will work in the Apple IlGS, but may require changes in their firmware or associated software to function properly with the DMA bank register. In general, DMA cards that assert and remove the /DMA signal within the first 120 nanoseconds of the øO rising edge will probably work properly; this allows sufficient time for /M2SEL to be activated by the FPI when video and I/O accesses are required.


◆ **Note:** Normally the system should be running at 1.024 MHz when performing DMA :

  * Only high-speed RAM or ROM can be accessed (access to $1/O$, video, or the Mega II banks does not work properly).
  * Fast DMA may cause a repeated cycle to occur to the location currently being accessed by the processor.
  * The 65C816 can be stopped indefinitely for DMA and does not require any processor refresh cycles from a DMA card.

-----

## Expansion-slot signals

Many of the expansion-slot signals can be grouped into three general categories:

  * those that constitute and support the address bus 
  * those that constitute and support the data bus 
  * those that support the functions of DMA and interrupts 

These signals are described in the following paragraphs.

### The buffered address bus

The microprocessor's address bus is buffered by two 74HCT245 octal three-state bidirectional buffers

Another signal that can be used to disable normal operation of the Apple IIGS is /INH.

The peripheral devices should use /IOSEL and /DEVSEL as enables.

-----

### The slot data bus

The Apple IIGS has three versions of the microprocessor data bus (shown in Figure 8-3):

  * the internal data bus, **DBUS**, connected directly to the microprocessor and the FPI chip and all main RAM 
  * the Mega II data bus, **MDBUS**, connecting the Mega II, VGC, Serial Communications Controller (SCC), Integrated Woz Machine (IWM), ADB and Sound General Logic Units (GLUs), and the Mega II RAM main bank 
  * the slot data bus, **SDBUS**, common to all expansion slots 

[Figure 8-3 Data buses within the Apple IIGS 

The 65C816 is fabricated with MOS (Metal Oxide Semiconductor) circuitry, so it can drive capacitive loads of up to about 130 picoFarads.

-----

### Interrupt and DMA daisy chains

The interrupt requests (/IRQ and /NMI) and the direct memory access (/DMA) signal are available at all seven expansion slots.

Each daisy chain works like this: The output from each connector goes to the input of the next higher numbered one.

-----

### Loading and driving rules

Do not overload any pin on the expansion slots; the driving capability of each pin is listed under each signal description in Table 8-1.

The total power-supply current available for all seven expansion slots is:

  * 500 mA at +5 volts 
  * 250 mA at +12 volts 
  * 200 mA at -5 volts 
  * 200 mA at-12 volts 

The support circuitry for the slots is designed to handle a DC load of two LS TTL loads per slot pin and an AC load of no more than 15 pF per slot pin.

-----

## Peripheral programming

The seven expansion slots on the main logic board are used for installing circuit cards containing the hardware and firmware needed to interface peripheral devices to the Apple IIGS.

### Selecting a device

The Apple IIGS supports several built-in devices and traditional slot devices, with each device taking up one logical slot.

### The Slot register

The Slot register, located at `$C02D`, is used to select which device is enabled for each of the seven slots. That device can be either the internal or a peripheral-card device. If the enable bit for a slot is 1, accesses for that slot's ROM space (`$Cnxx`) are directed to the ROM on the peripheral card. If the enable bit is cleared, the built-in I/O device is selected, and the system ROM code associated with the slot is executed. The user can select the appropriate slot device through the Control Panel. The user can access the Control Panel by pressing the Command-Control-Esc keys simultaneously. The Slot register format is given in Figure 8-4. Table 8-2 gives a description of each bit.



♦ *Note*: Slot 3 device hardware addresses are always available. However, the slot 3 ROM space is controlled by the SETSL0TC3R0M and SETINTC3R0M soft switches to maintain compatibility with existing Apple II products.

> **▲ Warning** You are encouraged not to manipulate the Slot register bits under software control; you run a great risk of crashing the operating system. ▲


> **▲ Warning** Be careful when changing bits within this register. Use only a read-modify-write instniction sequence when manipulating bits. See the warning in the preface. ▲

### Figure 8-4 Slot register at $C02D 
| Bit | Name |
| :-- | :--- |
| 7 | Slot 7 device select|
| 6 | Slot 6 device select|
| 5 | Slot 5 device select|
| 4 | Slot 4 device select|
| 3 | Reserved; do not modify|
| 2 | Slot 2 device select|
| 1 | Slot 1 device select|
| 0 | Reserved; do not modify|

**Table 8-2 Bits in the Slot register** 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7 | 0 | Selects the internal-device (AppleTalk) ROM code for slot 7. |
| | 1 | Enables both the slot-card ROM space (location $C700 to $C7FF) and $1/O$ space $C0F0 to $C0FF. |
| 6 | 0 | Selects the internal-device (5.25-inch disk drive) ROM code for slot 6. |
| | 1 | Enables both the slot-card ROM space (location $C600 to $C6FF) and $1/O$ space $C0E0 to $C0EF. |
| 5 | 0 | Selects the internal-device (3.5-inch disk drive) ROM code for slot 5. |
| | 1 | Enables both the slot-card ROM space (location $C500 to $C5FF) and $1/O$ space $C0D0 to $C0DF. |
| 4 | 0 | Selects the internal-device (mouse) ROM code for slot 4. |
| | 1 | Enables the slot-card ROM space (location $C400 to $C4FF). |
| 3 | | Reserved; do not modify. |
| 2 | 0 | Selects the internal-device (serial port B, the modem port) ROM code for slot 2. |
| | 1 | Enables both the slot-card ROM space (location $C200 to $C2FF) and I/O space $C0A0 to $C0AF. |
| 1 | 0 | Selects the internal-device (serial port A, the printer port) ROM code for slot 1. |
| | 1 | Enables both the slot-card ROM space (location $C100 to $C1FF) and I/O space $C090 to $C09F. |
| 0 | | Reserved; do not modify. |

*Note:* I/O space for slots 3 (`$C0B0` to `$C0BF`) and 4 (`$C0C0` to `$C0CF`) is always enabled.

-----

### Peripheral-card memory spaces
Because the Apple IIGS microprocessor does all its I/O through memory locations, portions of the memory space have been allocated for the exclusive use of the cards in the expansion slots. In addition to the memory locations used for actual I/O, there are memory spaces available for programmable memory (RAM) in the main memory and for read-only memory (ROM or **PROM**) on the peripheral cards themselves.

The memory spaces allocated for the peripheral cards are described below. These memory spaces are used for small dedicated programs such as I/O drivers. Peripheral cards that contain their own driver routines in firmware are called *intelligent peripherals*. They make it possible for you to add peripheral hardware to your Apple IIGS without having to change your programs, provided that your programs follow normal practice for data input and output.


#### Peripheral-card I/O space

Each expansion slot has the exclusive use of 16 memory locations for data input and output in the memory space beginning at location $C090. Slot 1 uses locations $C090 through $C09F slot 2 uses locations $C0A0 through $C0AF, and so on through location $C0FF as shown in Table 8-3.

These memory locations are used for different I/O functions, depending on the design of each peripheral card. Whenever the Apple IIGS addresses one of the 16 I/O locations allocated to a particular slot, the signal on pin 41 of that slot, called /DEVSEL, switches to the active (low) state. This signal can be used to enable logic on the peripheral card that uses the four low-order address lines (AO through A3) to determine which of its 16 I/O locations is being accessed.


**Table 8-3 Peripheral-card I/O memory locations enabled by /DEVSEL** 

| Slot | Locations | Slot | Locations |
| :--- | :--- | :--- | :--- |
| 1 | $C090-$C09F | 5 | $C0D0-$C0DF |
| 2 | $C0A0-$C0AF | 6 | $C0E0-$C0EF |
| 3 | $C0B0-$C0BF | 7 | $C0F0-$C0FF |
| 4 | $C0C0-$C0CF | | |

#### Peripheral-card ROM space

One 256-byte page of memory space is allocated to each accessory card. This space is normally used for read-only memory (ROM or PROM) on the card, and contains driver programs that control the operation of the peripheral device connected to the card.

The page of memory allocated to each expansion slot begins at location $CnOO, where n is the slot number, as shown in Table 8-3 and Table 8-4. Whenever the Apple IlGS addresses one of the 256 ROM memory locations allocated to a particular slot, the signal on pin 1 of that slot, called /lOSEL, switches to the active (low) state. This signal enables the ROM or PROM devices on the card, and the eight low-order address lines determine which of the 256 memory locations is being accessed.


**Table 8-4 Peripheral-card $I/O$ memory locations enabled by /IOSEL** 

| Slot | Locations | Slot | Locations |
| :--- | :--- | :--- | :--- |
| 1 | $C100-$C1FF | 5 | $C500-$C5FF |
| 2 | $C200-$C2FF | 6 | $C600-$C6FF |
| 3 | $C300-$C3FF | 7 | $C700-$C7FF |
| 4 | $C400-$C4FF | | |

#### Expansion ROM space

In addition to the small areas of ROM memory allocated to each expansion slot, peripheral cards can use the 2K memory space from $C800 to $CFFE for larger programs in ROM or PROM. This memory space is called expansion ROM space. (See the memory map in Figure 87, shown later in this chapter.) Besides being larger, the expansion ROM memory space is always at the same locations, regardless of which slot is occupied by the card, making programs that occupy this memory space easier to write.

This memory space is available to any peripheral card that needs it. More than one peripheral card can use the expansion ROM space, but only one of them can be active at a time.

Each peripheral card that uses expansion ROM must have a circuit on it to enable the ROM. The circuit does this by a two-stage process: First, it sets a flip-flop when the /lOSEL signal, pin 1 on the slot, becomes active (low); the /IOSEL signal on a particular slot becomes active whenever the Apple IlGS microprocessor addresses a location in the 256-byte ROM address space allocated to that slot. Second, the circuit enables the expansion ROM devices when the /IOSTRB signal, pin 20 on the slot, becomes active (low); the /IOSTRB signal on all the expansion slots becomes active (low) when the microprocessor addresses a location in the expansion ROM memory space, $C800 to $CFFE. The /lOSTRB signal is then used to enable the expansion ROM devices on a peripheral card. Figure 8-5 shows a typical ROM enable circuit.


[Figure 8-5 Expansion ROM enable circuit 

A program on a peripheral card can get exclusive use of the expansion ROM memory space by referring to location $CFFF in its initialization phase. This location is special: All peripheral cards that use expansion ROM must recognize a reference to $CFFF as a signal to disable their expansion ROMs. Of course, doing so also disables the expansion ROM on the card that is about to use it, but the next instruction in the initialization code sets the expansion ROM enable circuit on the card.

A card that needs to use the expansion ROM space must first insert its slot address ($Cn) in location $07F8 (known as MSLOT) before it refers to $CFFF. This allows interrupting devices to re-enable the card's expansion ROM after interaipt handling is finished. Once its slot address has been written in MSLOT, the peripheral card has exclusive use of the expansion memory space ana its program can jump directly into the expansion ROM.

As described eariier, the expansion ROM disable circuit resets the enable flip-flop whenever the microprocessor addresses location $CFFF. To do this, the peripheral card must detect the presence of $CFFF on the address bus. You can use the /lOSTRB signal for part of the address decoding, since it is active for addresses from $C800 through $CFFF. If you can afford to sacrifice some ROM space, you can simplify the address decoding even further and save circuitry on the card. For example, if you give up the last 256 bytes of expansion ROM space, your disable circuit needs to detect only addresses of the form SCFxx, and you can use the minimal disable decoding circuitry shown in Figure 8-6.


[Figure 8-6 ROM disable address decoding 

#### Peripheral-card RAM space

There are 56 bytes of main memory allocated to the peripheral cards, 8 bytes per card, as shown in Table 8-5. These 56 locations are actually in the RAM memory space reserved for the text and Lo-Res graphics displays, but these particular locations (called screen holes) are not displayed on the screen and their contents are not changed by the built-in output routine COUT1. Programs in ROM on peripheral cards use these locations for temporary data storage.


**Table 8-5 Peripheral-card RAM memory locations** 

| Base address | Slot number | | | | | | |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| | **1** | **2** | **3** | **4** | **5** | **6** | **7** |
| $0478 | $0479 | $047A | $047B | $047C| $047D | $047E | $047F |
| $04F8 | $04F9 | $04FA | $04FB | $04FC| $04FD | $04FE | $04FF |
| $0578 |  $0579| $057A | $057B | $057C | $057D | $057E | $057F |
| $05F8 | $05F9 | $05FA | $05FB | $05FC| $05FD | $05FE | $05FF |
| $0678 | $0679 | $067A | $067B | $067C| $067D | $067E | $067F |
| $06F8 | $06F9 | $06FA | $06FB | $06FC| $06FD | $06FE | $06FF |
| $0778 | $0779 | $077A | $077B | $077C| $077D | $077E | $077F |
| $07F8 | $07F9 | $07FA | $07FB | $07FC| $07FD | $07FE | $07FF |

A program on a peripheral card can use the eight base addresses shown in the table to access the eight RAM locations allocated for its use, as shown in the next section, "I/O Programming Suggestions." 

-----

### I/O programming suggestions

A program in ROM on a peripheral card should work no matter which slot the card occupies, excepting any hardware restrictions (such as a signal not available at some slots).


> **Important** To function properly no matter which slot a peripheral card is installed in, the program in the card's 256-byte memory space must not make any absolute references to itself. Instead of using jump instructions, you should force conditions on branch instructions, which use relative addressing.




The first thing a peripheral card used as an I/O device must do when called is to save the contents of the microprocessor's registers. (Peripheral cards not being used as I/O devices do not need to save the registers.) The device should save the registers' contents on the stack, and restore them just before returning control to the calling program. If there is RAM on the peripheral card, the information may be stored there.


#### Finding the slot number with ROM switched in

The memory addresses used by a program on a peripheral card differ depending on which expansion slot the card is installed in.

> **Important**
> Make sure the return address is located in Apple IIGS RAM, not the memory on the peripheral card.

```assembly
PHP           ; save status 
SEI           ; inhibit interrupts 
JSR KNOWNRTS  ; ->a known RTS instruction... 
              ; ...that you set up 
TSX           ; get high byte of the... 
LDA $0100, X  ; return address from stack 
AND #$OF      ; low-order digit is slot no. 
PLP           ; restore status 
```

The slot number can now be used in addressing the memory allocated to the peripheral card, as shown in the next section.

#### I/O addressing

Once your peripheral-card program has the slot number, the card can use the number to address the I/O locations allocated to the slot.

Starting with the slot number in the accumulator, the following example computes this difference by four left shifts, then loads it into an index register and uses the base address to specify one of 16 $1/O$ locations.

```assembly
ASL           
ASL           
ASL           
ASL           ; get n into... 
TAX           ; ...high-order nibble... 
              ; ...of index register. 
LDA $C080,X   ; load from first I/O location 
```

**Table 8-6 Peripheral-card I/O base addresses** 

| Base address | Slot number | | | | | | |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| | **1** | **2** | **3** | **4** | **5** | **6** | **7** |
| $C080 | $C090 | $C0A0 | $C0B0 | $C0C0 | $C0D0 | $C0E0 | $C0F0 |
| $C081 | $C091 | $C0A1 | $C0B1 | $C0C1 | $C0D1 | $C0E1 | $C0F1 |
| $C082 | $C092 | $C0A2 | $C0B2 | $C0C2 | $C0D2 | $C0E2 | $C0F2 |
| $C083 | $C093 | $C0A3 | $C0B3 | $C0C3 | $C0D3 | $C0E3 | $C0F3 |
| $C084 | $C094 | $C0A4 | $C0B4 | $C0C4 | $C0D4 | $C0E4 | $C0F4 |
| $C085 | $C095 | $C0A5 | $C0B5 | $C0C5 | $C0D5 | $C0E5 | $C0F5 |
| $C086 | $C096 | $C0A6 | $C0B6 | $C0C6 | $C0D6 | $C0E6 | $C0F6 |
| $C087 | $C097 | $C0A7 | $C0B7 | $C0C7 | $C0D7 | $C0E7 | $C0F7 |
| $C088 | $C098 | $C0A8 | $C0B8 | $C0C8 | $C0D8 | $C0E8 | $C0F8 |
| $C089 | $C099 | $C0A9 | $C0B9 | $C0C9 | $C0D9 | $C0E9 | $C0F9 |
| $C08A | $C09A | $C0AA | $C0BA | $C0CA | $C0DA | $C0EA | $C0FA |
| $C08B | $C09B | $C0AB | $C0BB | $C0CB | $C0DB | $C0EB | $C0FB |
| $C08C | $C09C | $C0AC | $C0BC | $C0CC | $C0DC | $C0EC | $C0FC |
| $C08D | $C09D | $C0AD | $C0BD | $C0CD | $C0DD | $C0ED | $C0FD |
| $C08E | $C09E | $C0AE | $C0BE | $C0CE | $C0DE | $C0EE | $C0FE |
| $C08F | $C09F | $C0AF | $C0BF | $C0CF | $C0DF | $C0EF | $C0FF |

**Selecting your target.** You must make sure that you get an appropriate value into the index register when you address $I/O$ locations this way.

#### RAM addressing

A program on a peripheral card can use the eight base addresses shown in Table 8-5 to access the eight RAM locations allocated for its use.

If you start with the correct slot number in the accumulator (by using the example shown earlier in this chapter, in the section "Finding the Slot Number With ROM Switched In"), then the following example uses all eight RAM locations allocated to the slot:

```assembly
TAY           
LDA           
$0478, Y      
STA           
$04F8, Y      
LDA           
$0578, Y      
STA           
$05F8, Y      
LDA           
$0678, Y      
STA           
$06F8, Y      
LDA           
$0778, Y      
STA           
$07F8, Y      
```

> **Warning**
> You must be very careful when you have your peripheral-card program store data at the base-address locations themselves because they are temporary storage locations .

-----

### Other uses of I/O memory space

The portion of memory space from location $C000 through $CFFF is normally allocated to I/O and program memory on the peripheral cards, but this computer has built-in functions that also use this memory space.

[Figure 8-7 I/O memory map 



-----

### Switching I/O memory

The built-in firmware uses two sets of soft switches to control the allocation of the I/O memory space from $C000 to $CFFF.

◆ **Note:** Like the display switches described earlier in this chapter, these soft switches share their locations with the keyboard data and strobe functions.

**Table 8-7 $I/O$ memory switches** 

| Name | Function | Location | | Notes |
| :--- | :--- | :--- | :--- | :--- |
| | | **Hex** | **Dec** | |
| SETSLOTC3ROM | Enable slot ROM at $C300 | $C00B | 49163 | Write  |
| SETINTC3ROM | Enable internal ROM at $C300 | $C00A | 49162 | Write  |
| RDC3ROM | Read SLOTC3ROM switch | $C017 | 49175 | Read ( $1=$ slot 3 ROM enabled, $0=$ internal ROM enabled)  |
| SETSLOTCXROM | Enable slot ROM at $Cx00 | $C006 | 49159 | Write  |
| SETINTCXROM | Enable internal ROM at $Cx00 | $C007 | 49158 | Write  |
| RDCXROM | Read SLOTCXROM switch | $C015 | 49173 | Read ( $1=$ slot ROM enabled, $0=$ internal ROM enabled)  |

When SETSLOTC3ROM is on, the 256-byte ROM area at $C300 is available to a peripheral card in slot 3, which is the slot normally used for a terminal interface.

When SETSLOTCXROM is on, the I/O memory space from $C100 to $C7FF is allocated to the expansion slots, as described earlier in this chapter, in the section "Peripheral-Card ROM Space." .

◆ **Note:** Setting SETINTCXROM enables built-in ROM in all of the I/O memory space (except the soft-switch area), including the $C300 space, which contains the 80-column firmware.

-----

### Developing cards for slot 3

In the original Apple IIe firmware, the internal slot 3 firmware was always switched on if there was an **80-column text card** (either 1K or 64K) in the auxiliary slot.

When programming for cards in slot 3:

  * You must support the AUXMOVE and XFER firmware routines.
  * Don't use unpublished entry points into the internal $Cn00 firmware, because they may change in future Apple II firmware versions.
  * If your peripheral card is a character I/O device, you must follow the Pascal 1.1 firmware protocol.

-----

### Interrupts

The original Apple Ile offered little firmware support for interrupts.

The main purpose of the interrupt handler is to support interrupts in any memory configuration.

#### What is an interrupt?

An interrupt is a hardware signal that tells the computer to stop what it is currently doing and devote its attention to a more important task.

Interrupt priority is handled by a daisy-chain arrangement using two pins, INT IN and INT OUT, on each peripheral-card slot.

When the /IRQ line on the Apple IIGS microprocessor is activated (pulled low), the microprocessor transfers control through the vector in locations $FFFE to $FFFF

The interrupt ROM code is available when shadowing is enabled and the inhibit I/O and language-card operation (IOLC) bit in the Shadow register is set.

-----

### Timing diagrams

The following pages contain timing diagrams for the slot signals required to handle DMA and general slot I/O.

[Figure 8-8 I/O clock and control timing 

**Table 8-8 I/O clock and control timing parameters** 
(Time in nanoseconds )

| Number | Description | Minimum | Maximum |
| :--- | :--- | :--- | :--- |
| 1 | 00 low time | 480 | |
| 2 | 00 high time | 480 | |
| 3 | ø1 high time | 480 | |
| 4 | Ø1 low time | 480 | |
| 5 | 7M low time | 60 | |
| 6 | Fall time, all clocks | 0 | 10 |
| 7 | Rise time, all clocks | 0 | 10 |
| 8 | 7M high time | 60 | |
| 9 | Q3 high time | 270 | |
| 10 | Q3 low time | 200 | |
| 11 | Skew, 60 to other clock signals | -10 | 10 |
| 12 | Control signal setup time | 140 | |

◆ **Note:** All clock signals present on the I/O slots are buffered by the Slotmaker custom IC.

The standard Apple IIGS slot I/O timing is shown in Figure 8-9.

[Figure 8-9 $I/O$ read and write timing 

**Table 8-9 I/O read and write timing parameters** 
(Time in nanoseconds )

| Number | Description | Minimum | Maximum |
| :--- | :--- | :--- | :--- |
| 1 | /M2SEL low from 00 low | 0 | 160 |
| 2 | /M2SEL hold time | -10 | |
| 3 | I/O enable low from 00 high (DEVn, /IOSELn, /IOSTRB) | 0 | 15 |
| 4 | I/O enable high from 60 low (DEVn, /IOSELn, /IOSTRB) | 10 | |
| 5 | Address and A2R/W valid from 00 low | 0 | 100 |
| 6 | Address and A2R/W hold time | 15 | |
| 7 | Write data valid delay | 0 | 30 |
| 8 | Write data hold time | 30 | |
| 9 | Read data setup time to 00 | 140 | |
| 10 | Read data hold time | 10 | |

Read and write cycles that are directed to the I/O slots by /INH have the same timing parameters as normal I/O read and write cycles, as shown in Figure 8-10 and Table 8-10.

Cards that use the /INH signal will function properly only if the computer is running at 1.024 MHz.

[Figure 8-10 I/O read and write timing with /INH active 

**Table 8-10 I/O read and write timing parameters with /INH active** 
(Time in nanoseconds )

| Number | Description | Minimum | Maximum |
| :--- | :--- | :--- | :--- |
| 1 | /INH valid after 00 low | 0 | 175 |
| 2 | /INH hold time | 15 | |
| 3 | /INH low to /M2SEL low delay | 0 | 30 |
| 4 | /INH high to/M2SEL high delay | 0 | 30 |
| 5 | Address and A2R/W valid from 00 low | 0 | 100 |
| 6 | Address and A2R/W hold time | 15 | |
| 7 | Write data valid delay | 30 | |
| 8 | Write data hold time | 30 | |
| 9 | Read data setup time to 00 | 140 | |
| 10 | Read data hold time | 10 | |

DMA devices will work in the Apple IIGS computer only in 1.024-MHz mode.

[Figure 8-11 /DMA read and write timing 

**Table 8-11 /DMA read and write timing parameters** 
(Time in nanoseconds )

| Number | Description | Minimum | Maximum |
| :--- | :--- | :--- | :--- |
| 1 | /DMA low from 00 low | | 120 |
| 2 | /DMA high from 00 low | | 120 |
| 3 | A15-A0 and R/W float from/DMA | | 30 |
| 4 | DMA address and A2R/W valid before 00 goes high | 300 | |
| 5 | DMA address and A2R/W hold time | 10 | |
| 6 | /DMA high to A15-A0 and A2R/W active | | 30 |
| 7 | DMA address valid to /M2SEL low | | 30 |
| 8 | DMA address float to /M2SEL high | | 30 |
| 9 | 00 high to write data valid | 100 | |
| 10 | DMA write data hold time | 10 | |
| 11 | DMA read data setup time | 125 | |
| 12 | DMA read data hold time | 30 | |


