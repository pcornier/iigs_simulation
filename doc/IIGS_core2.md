# Chapter 2 The Core of the Apple IIGS

The design of the Apple IIgs is radically different from that of the standard Apple II. The difference arises primarily from three major components:

*  the 65C816 microprocessor 
*  the Mega II custom IC
*  the FPI (Fast Processor Interlace) custom IC

The most obvious of these is the 65C816 microprocessor, which is more powerful than the 6502 used in the standard Apple II, yet maintains the ability to execute programs written for the 6502. The 65C816 microprocessor is important enough to have an entire chapter, Chapter 10, devoted to it.

The 65C816 has a larger address space, bigger registers, and the ability to run faster than the standard 1.024-MHz speed of an Apple II. How can the Apple IIGS take advantage of all these capabilities and still be able to run programs written for a standard Apple II? The answer to that question is two custom integrated circuits: the Mega II and the FPI. This chapter describes the way those two ICs work together in the Apple IIGS.

## The Mega II custom IC

The Mega II custom IC combines the functions of several circuits found in the Apple IIe.Those circuits are* the MMU(Memory Management Unit) custom IC* the IOU (input/output unit) custom IC* the **character generator** ROMs* the video display circuitryExcept for central processor and memory, the Mega II incorporates the logic circuitry for all the major functions of an Apple IIe on a single chip. It works with the I/O expansion slots and the I/O ports built into the Apple IIGS and supports the part of memory that contains the video display buffers. The Mega II side of the machine consists of
* the Mega II* 128K of memory* the I/O expansion slots* the built-in I/O ports* the video display circuitryThe Mega II contains the circuitry that generates video display signals from the data in the display buffers, along with the **soft switches** that select the different display modes.
All I/O in the Apple IIGS is memory mapped. The Mega II provides the address decoding and the soft switches that control the I/O slots and the built-in ports. The Mega II also provides the refresh cycles for the 128K of dynamic RAM under its control.Because the memory controlled by the Mega II contains the display buffers, it always runs at the 1.024-MHsz peed. It is sometimes referred to as *Apple II standard memory*, to distinguish it from the rest of the memory in the Apple IIGS, which normally runs at 2.8 MHz and hence is called *fast memory*.

# The FPI custom IC
The FPI (Fast Processor Interface) custom IC supports the 65C816 microprocessor and its large, fast memory. Its name is doubly descriptive: The FPI controls the fast memory itself, and also mediates its interaction with the Mega II side of the machine. Independent control of the two sides enables the Apple IIGS to run programs at 2.8 MHz while maintaining the 1.024-MHz operation required for compatibility with the standard video and I/O circuitry.

For the 65C816 and its fast memory, the FPI provides address multiplexing and control signals. Memory under the control of the FPI includes 128K of built-in RAM (1 MB on the 1 MB Apple IIGS logic board), 128K of built-in ROM (256K on the 1 MB Apple IIGS logic board), up to 4 MB of expansion RAM, and up to 1 MB of expansion ROM. The FPI also generates the refresh cycles needed by the fast dynamic RAM devices. The time required for the refresh cycles reduces the effective processor speed for programs in RAM by about 8 percent. Programs in ROM run at the full 2.8-MHz speed.

The additional 128K of ROM storage on the 1 MB Apple IIGS logic board is used for storing toolbox utilities as well as enhancements to the system firmware. For complete information on the Apple IIGS firmware, refer to the *Apple IIGS Firmware Reference*. For information on the toolbox utilities, see the *Apple IIGS Toolbox Reference*.

# Synchronization

Whenever data have to be transferred between the FPI side and the Mega II side, the FPI IC must first synchronize itself with the 1.024-MHz Mega II.  Synchronization may consist of a single Mega II cycle, as when a single I/O location in the Mega II must be accessed, or consecutive Mega II cycles, as when Apple II software must be run at 1.024 MHz for compatibility.  For a single Mega II cycle, there is a delay of up to 1 microsecond (average 0.5 microsecond) while waiting for the beginning of the next cycle[cite: 51].  For consecutive Mega II cycles, the FPI generates one processor cycle for each Mega II cycle, thus running the processor at 1.024 MHz.

 In all Apple II computers, every 65th processor cycle is elongated, or stretched, by 140 nanoseconds.  This practice is required for correct colors in the **NTSC** (National Television Standards Committee) video display.
 
# The Mega II cycle
 A Mega II cycle is needed for any central processor or direct memory access (DMA) operation that requires access to the 1.024-MHz side of the system[cite: 61]. (Refer to Chapter 8, “I/O Expansion Slots,” for more information about direct memory access.) These operations are:
*  all external and most internal I/O operations
*  shadowed video-write operations (described in “Memory Shadowing,” later in this chapter)
*  inhibited memory accesses
*  Mega II memory accesses to **banks** `$E0` and `$E1`

 A Mega II cycle consists of these steps:
1. A Mega II cycle begins when the FPI recognizes an address that requires access to the 1.024-MHz side of the system—one of the operations just listed. 
2. Approximately 90 nanoseconds after the processor Φ2 clock signal goes low, the location address and bank address from the processor become valid.  The FPI decodes these addresses and determines the type of cycle to be executed before the Φ2 clock rises.
3. If the cycle is a Mega II cycle, the FPI holds the Φ2 clock high until it synchronizes itself with the Mega II.
4. Memory or I/O access begins.

#  Mega II auxiliary memory bank access 
 To allow direct access to the Mega II auxiliary memory bank, the FPI passes the least significant bit (lsb) of the bank address to the Mega II during each Mega II cycle.  If **shadowing** is enabled (as described in “Memory Shadowing,” later in this chapter) or the software is addressing bank `$E0` or `$E1`, an odd-numbered bank address will access the Mega II auxiliary memory automatically, without using the soft switches.  For this setup to work, the programmer must first set bit 0 in the New-Video register at `$C029` to 1[. (See Chapter 4 for information about the New-Video register.) Otherwise, the Mega II ignores the bank bit, and the soft switches must then be used to access the auxiliary 64K through an even-numbered, shadowed bank.

#  Memory allocation
 The FPI controller can access a minimum of 128K of RAM (1 MB on the 1 MB Apple IlGS logic board), which is expandable to 4.3 MB, and to 5 MB on the 1 MB Apple IIGS logic board.  This RAM is separate from the 128K of RAM supported by the Mega II.  The FPI also has access to 128K of ROM (256K on the 1 MB Apple IlGS logic board), expandable to 1 MB.  
 
For a full description of memory in the Apple IlGS, refer to Chapter 3.

#  Memory shadowing
 Memory shadowing is the process of reading or writing at one memory location in two different banks.  Enabling shadowing duplicates the I/O locations and portions of the video buffers you select (via the Shadow register) in the shadow-enabled RAM banks.  Writing into those locations in banks for which shadowing has been enabled results in duplicate writes to those locations in banks `$E0` or `$E1`.  Direct access to I/O and the video buffers is not inhibited and may still be obtained through banks `$E0` and `$E1`.

 The purpose of shadowing is to provide optimum system speed.  By shadowing the I/O and video buffer locations in the high-speed FPI address space, only write instructions to the video locations require the system to operate at 1.024 MHz.  A write instruction actually writes to an address in both banks, the Mega II bank, `$E0` or `$E1`, and the shadow-enabled bank, `$00` or `$01`.  Read instructions access the high-speed shadowed bank, `$00` or `$01`. Shadowing, therefore, helps minimize the impact of video display updates on the overall system speed. (See "I/O Space Addresses," later in thischapter, for more information on the impact of I/O read operations and write operations on system speed.)

 The shadowing options are:
*  Enable shadowing in banks `$00` and `$01` only.
*  Enable shadowing in all RAM banks (not recommended).

♦ *Note*: Although shadowing is possible in other banks, shadowing in banks other than `$00` and `$01` should not be attempted under normal operating circumstances; firmware operating in other banks will be corrupted if shadowing is enabled in those banks, resulting in a system crash.

 Note that slowing of the system for each write operation is very brief and won’t affect program execution speed significantly. Only continuous write accesses would actually be noticeable.

###  The Shadow register [cite: 160]
 The Shadow register, located at `$C035`, determines which address ranges of each shadowed 1.024-MHz RAM bank are duplicated in the FPI RAM display areas.  The Shadow register also determines whether or not the I/O space and language-card (IOLC) areas for each bank are activated.

>▲ **Warning** Be careful when changing bits within this register.  Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface.  ▲ 

**Table 2-1 Bits in the Shadow register**
|BIT | VALUE | Description|
|----|-------|------------|
|7 | - | Reserved; do not modify.|
|6 | 0 | The I/O and language-card (IOLC) inhibit bit: This bit controls whether the 4K range from $C000 to SCFFF in banks $00 and $01 acts as RAM or as 1/O. When this bit is 0, I/O is enabled in the `$Cxxx` space and the RAM that would normally occupy this space becomes a second `$DXXX` RAM space in  banks `$00` and `$01`, forming a **language card**. Note that the I/O space and language card in banks SEO and `$E1` are not affected by this bit: this space is always enabled. |
|6 | 1 | When this bit is 1, the I/O space and language card are inhibited, and contiguous RAM is available from `$0000` through `$FFFF`. (For more information on I/O and language-card memory spaces, see Chapter 3, "Memory.”)|
|5 | 1 | Text Page 2 inhibit (available only on the 1 MB logic board): When this bit is 1, shadowing is disabled for text Page 2 and auxiliary text Page 2.|
|5 | 0 | When this bit is 0, shadowing is enabled for text Page 2 and auxiliary text Page 2|
|4 | 1 | Inhibit shadowing for auxiliary Hi-Res graphics pages: When this bit is 1, shadowing is disabled for Hi-Res graphics pages 1 and 2 (as determined by bits 0 through 3 in this register) in all auxiliary (odd) banks.  Shadowing of Hi-Res graphics pages in the main bank remains unaffected|
|4 | 0 | When this bit is 0, shadowing is enabled for Hi-Res graphics pages (as determined by bit 1).|
|3 | 1 | **Super Hi-Res** graphics buffer inhibit: When this bit is 1, shadowing is disabled for the entire 32K video buffer. |
|3 | 0 | When this bit is 0, shadowing is enabled for the Super Hi-Res graphics buffer|
|2 | 1 | Hi-Res graphics Page 2 inhibit: When this bit is 1, shadowing is disabled for Hi-Res graphics Page 2 and auxiliary Hi-Res graphics Page 2.|
|2 | 0 | When this bit is 0, shadowing is enabled for Hi-Res video Page 2 and auxiliary Hi-Res video Page 2, unless auxiliary Hi-Res graphics Page 2 shadowing is prohibited by bit 4 of this register.|
|1 | 1 | Hi-Res graphics Page 1 inhibit: When this bit is 1.  shadowing is disabled for Hi-Res graphics Page 1 and auxiliary Hi-Res graphics Page 1.|
|1 | 0 |When this bit is 0, shadowing is enabled for Hi-Res graphics Page 1 and auxiliary Hi-Res graphics Page 1, unless auxiliary Hi-Res graphics Page 1 shadowing is prohibited by bit 4 of this register.|
|0 | 1 |Text Page 1 inhibit: When this bit is 1, shadowing is disabled for text Page 1 and auxiliary text Page 1.|
|0 | 0 | When this bit is 0, shadowing is enabled for text Page 1 and auxiliary text Page 1.|

You can turn shadowing on and off for areas within each shadow-enabled 64K bank by setting the corresponding bit or bits in the Shadow register. You can turn off shadowing (no banks shadowed) by setting all bits in the Shadow register. When the Shadow register is cleared on reset, it defaults to shadowing all video areas.

Each bit in the Shadow register is active high, which means that the shadowing of the selected area is inhibited if the corresponding bit is set. Programs that use the Shadow register can turn off shadowing in unused video areas by setting the appropriate bits, thus reclaiming the memory space in the unu,sed video buffers in Mega II banks `$00` and `$01`.

# The Speed register

The Speed register, located at `$C036`, contains bits that control the speed of operation and that determine whether a specific area within a bank is shadowed. The Speed register is cleared on reset or power up, except for bit 6, which on power up is set. Figure 2-6 shows the format of the Speed register. Table 2-2 contains a description of the bits.

> ▲ A Warning Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

**Table 2-2 Bits in the Speed register** 
| Bit | Value | Description |
| --- | ----- | ----------- |
| 7* | 1     | System operating speed. When this bit is 1, the system operates at 2.8 MHz. |
| 7    | 0     | When this bit is 0, the system operates at 1.024 MHz (as in other Apple II computers). |
| 6   | 1     | Power-on status (available only on the 1 MB logic board): This bit is set to 1 when the system is turned on using the power switch. A boot initiated by any key combination will not alter this bit. This is a read-write bit. |
|6    |   0    | n/a |
|5    |   -    |Reserved; do not modify .|
| 4   | 1     | Bank shadowing bit: This bit determines memory shadowing in the RAM banks. Shadow register bits 0 through 4 will determine which portion, if any, of the banks will be shadowed. To enable shadowing in all RAM banks, `$00` through `$7F`, set this bit to 1.|
|  4   | 0     | To enable shadowing in banks `$00` and `$01` only, clear this bit. For proper operation of the Apple IIGS operating system, this bit must always be set to 0. |
| 0—3†| 1     | Disk II motor-on address detectors: To retain Apple II peripheral compatibility, the motor-on detectors change the system speed to 1.024 MHz whenever a Disk II motor-on address is detected.‡ When the disk motor-off address is accessed, the system speed increases to 2.8 MHz again. For example, when bit 1 is 1, the FPI switches to 1.024 MHz when address `$C0D9` is accessed, and returns to 2.8 MHz following a `$C0D8` access. (See list of addresses below.)  |
|  0-3   | 0     | When this bit is 0, the Disk II motor detectors are turned off. |


\* Drives designed for the Apple IIGS system should use the speed bit (Speed register bit 7) to change the processor speed when accessing disks, rather than the disk motor-on detectors (Speed register bits 0 through 3). By using bit 7, you access drives in slots other than slots 4 through 7 by changing the system speed manually. Be aware that central processor speed changes for drive compatibility may affect **application program** timing; avoid using the motor addresses unless they are used in a fashion consistent with the drive’s central processor speed requirements.

† For compatibility with future Apple products, use firmware calls only to manipulate bits 0 to 3 of the Speed register.

‡ Drives designed for previous Apple II computers will function as Apple IIGS peripherals only if the system speed is changed to 1.024 MHz before disk access is attempted.

Bits 0 through 3 detect the following addresses:

| Bit | Slot | Motor on | Motor off |
| --- | ---- | -------- | --------- |
| 0   | 4    | `$C0C9`  | `$C0C8`   |
| 1   | 5    | `$C0D9`  | `$C0D8`   |
| 2   | 6    | `$C0E9`  | `$C0E8`   |
| 3   | 7    | `$C0F9`  | `$C0F8`   |

# RAM control
 The FPI alone controls the high-speed RAM.  This high-speed memory consists of a minimum of 128K of RAM (1 MB in the 1 MB Apple IlGS) on the main logic board and additional expansion RAM on the extended memory card, for a total of 4.3 MB in the 256K logic board, and 5 MB in the 1 MB version of the board.  
 The FPI provides memory refresh for the high-speed RAM, which incorporates internal refresh-address counters.  This refresh scheme frees the address bus so that the FPI can execute ROM cycles while RAM refresh cycles are occurring, thus allowing full-speed operation in the ROM.  These cycles occur approximately every 3.5 microseconds and reduce the 2.8-MHz processing speed by approximately 8 percent for programs that run in RAM.  When running at 1.024 MHz, refresh cycles are executed during an unused portion of the processor cycle and do not affect the processor speed.

# I/O Space Addresses
The I/O space in the Apple IIgs consists of all the addresses from `$C000` through `$CFFF`. All internal device addresses, register addresses, soft switch addresses, and slot addresses
fall within this 4K address range. Any of these addresses can be accessed through banks `$EO`, `$E1`, `$00`, and `$01`. Access from banks `$E0` and `$E1` is always enabled; access from
banks `$00` and `$01` is controlled by bit 6 of the Shadow register, and must always be enabled for correct system operation. 

When estimating the performance of timing-critical code, you must consider the impact processor speed changes have on execution speed. The Apple IIGS can operate at 2.8 MHz, but must slow down to 1.024 MHz when accessing certain I/O addresses. These I/О addresses include I/O reads and writes, and instruction reads of firmware at slot addresses of `$C100` through `$CFFF`. Additionally, all reads and writes to soft switches and slot I/O devices at addresses `$C090` through `$COFF` also occur at 1.024 MHz.

▲ Note: In order to guarantee that your code will remain compatible with future Apple II computers, do not develop timing-critical code that will not function at system speeds greater than 2.8 MHz.

A microprocessor instruction consists of between two and nine individual cycles. For instructions executed from fast RAM or ROM, only the specific instruction cycles that read from or write to I/O addresses will slow the system to 1.024 MHz. All other cycles of such an instruction will execute as fast cycles. The result is that the majority of instruction cycles occur at high speed. The few that occur at low speed are of variable length. This length can, however, be estimated. The following rules provide a simple method of calculating the minimum and maximum time that an entire instruction will require to execute:
1. If a single (8-bit) slow I/0 read or write cycle is perfectly synchronized, it takes nearly three fast cycles to complete. A double (16-bit) slow 1/O read or write cycle takes nearly 6 fast cycles to complete. Thus, an 8-bit read or write instruction that would normally take four fast cycles will take at least six fast cycles, an increase of two cycles. A 16-bit read or write instruction that would normally take five fast cycles will take at least nine fast cycles, an increase of four cycles.
2. If either a single or double slow cycle is not synchronized, the maximum delay for synchronization is one extra slow cycle, adding the equivalent of three fast cycles to the count. Thus, the worst-case 8-bit access becomes 2 + 3 or 5 extra fast cycles, and the 16-bit worst case becomes 4 + 3 or 7 extra fast cycles. 

These rules can be applied to the cycle times for any instruction executing in fast RAM or ROM to approximate the minimum and maximum times for instructions that reference I/O addresses. Remember to allow an additional 10% in total cycle time to account for RAM refresh delays.

Certain registers internal to the FPI (the DMA register, the Speed register, and the Shadow register) are read and written at high speed. Similarly, reading the interrupt ROM addresses (`$C071` through `$C07F`) does not slow the system. In addition, two registers
(the State register and the Slot ROM Select register) that exist in both the FPI and the Mega II ICs are written at 1.024 MHz and read at 2.8 MHz in the FPI address space.





Language-card memory space
+ Apple II note: The language-card space is a carryover from earlier models ofthe Apple II
and is normally used only by programs written for those machines and running in
emulation mode. Like the bank $00 shadowing of the display buffers, the peculiar
features of the language-card space are enabled by a switch in the Shadow register,
which is described in Chapter 2.
Memory banks: The language-card space is a feature both of bank $00 and of bank
$01. Refer to the section "Bank $01 (Auxiliary Memory),"later in this chapter, for more
information.
When the language-card feature is enabled, the memory address space from SD000 through
SFFFF is doubly allocated: It is used for both ROM and RAM. The 12K of ROM in this
address space contains the Monitor program and the Applesoft BASIC interpreter.
Alternatively, there are 16K of RAM in this space. The RAM is normally used by the disk
operating system.
You may be wondering why this part of memory has such a splitpersonality. Some of the
reasons are historical: The Apple IIGS is able to run software written for a standard
Apple II because it uses this part of memory in the same way a standard Apple II does. It's
convenient to have the Applesoft BASIC interpreter in ROM, but the Apple IIGS is also
able to use that address space for other things when Applesoft is not needed.
You may also be wondering how 16K of RAM are mapped into only 12K of address space.
The usual answer is that it's done with mirrors, and that isn't a bad analogy: The 4K address
space from $D000 through $DFFF is used twice.
Switching different blocks of memory into the same address space is called bank
switching. There are actually two examples of bank switching going on here: First, the
entire address space from $D000 through $FFFF is switched between ROM and RAM, and
second, the address space from $D000 to $DFFF is switched between two different
blocks of RAM. If the language card is not enabled, the first ofthese blocks of RAM,
block 1, occupies address space from $C000 to $CFFF, as shown in Figure 3-4. (Note that
the banks involved here are not the same as the 64K memory banks.)

Setting language-card bank switches: You switch banks in the language-card space in
the same way you switch other functions in a standard Apple II: by using soft switches.
Read operations to the soft-switch locations do three things: select either RAM or ROM in
this memory space, enable or inhibit writing to the RAM, and select the first or second 4K
bank of RAM in the address space SD000 to SDFFF.
Warning Do not use these switches without careful planning. Careless switching
between RAM and ROM is almost certain to have catastrophic effects
on your program. ▲
Table 3-1 shows the addresses of the soft switches for enabling all combinations of
reading and writing in this memory space. All the hexadecimal values of the addresses are
of the form SC08x. Notice that several addresses perform the same function: This is
because the functions are activated by single address bits. For example, any address of
the form $C08x with a 1 in the low-order bit enables the RAM for writing. Similarly, bit 3
of the address selects which 4K block of RAM to use for the address space $D000 to
$DFFF; if bit 3 is 0, the first bank of RAM is used, and if bit 3 is 1, the second bank is used
