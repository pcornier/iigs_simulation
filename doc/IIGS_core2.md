I/O space addresses
The I/O space in the Apple IGs consists of all the addresses from $C000 through $CFFF.
All internal device addresses, register addresses, soft switch addresses, and slot addresses
fall within this 4K address range. Any of these addresses can be accessed through banks
SEO, SE1, $00, and $01. Access from banks $E0 and $E1 is always enabled; access from
banks $00 and $01 is controlled by bit 6 of the Shadow register, and must always be
enabled for correct system operation.
When estimating the performance of timing-critical code, you must consider the impact
processor speed changes have on execution speed. The Apple IIGS can operate at 2.8
MHz, but must slow down to 1.024 MHz when accessing certain I/O addresses. These 1/О
addresses include 1/O reads and writes, and instruction reads of firmware at slot addresses
of $C100 through $CFFF. Additionally, all reads and writes to soft switches and slot I/O
devices at addresses $C090 through $COFF also occur at 1.024 MHz.
Note: In order to guarantee that your code will remain compatible with future Apple II
computers, do not develop timing-critical code that will not function at system
speeds greater than 2.8 MHz.
A microprocessor instruction consists of between two and nine individual cycles. For
instructions executed from fast RAM or ROM, only the specific instruction cycles that
read from or write to I/O addresses will slow the system to 1.024 MHz. All other cycles of
such an instruction will execute as fast cycles. The result is that the majority of instruction
cycles occur at high speed. The few that occur at low speed are of variable length. This
length can, however, be estimated. The following rules provide a simple method of
calculating the minimum and maximum time that an entire instruction will require to
execute:
1.  If a single (8-bit) slow 1/0 read or write cycle is perfectly synchronized, it takes nearly
three fast cycles to complete. A double (16-bit) slow 1/O read or write cycle takes
nearly 6 fast cycles to complete. Thus, an 8-bit read or write instruction that would
normally take four fast cycles will take at least six fast cycles, an increase of two
cycles. A 16-bit read or write instruction that would normally take five fast cycles will
take at least nine fast cycles, an increase of four cycles.
2.  If either a single or double slow cycle is not synchronized, the maximum delay for
synchronization is one extra slow cycle, adding the equivalent of three fast cycles to
the count. Thus, the worst-case 8-bit access becomes 2 + 3 or 5 extra fast cycles, and
the 16-bit worst case becomes 4 + 3 or 7 extra fast cycles.
These rules can be applied to the cycle times for any instruction executing in fast RAM or
ROM to approximate the minimum and maximum times for instructions that reference
1/O addresses. Remember to allow an additional 10% in total cycle time to account for
RAM refresh delays.

Certain registers internal to the FPI (the DMA register, the Speed register, and the Shadow
register) are read and written at high speed. Similarly, reading the interrupt ROM
addresses (SC071 through $C07F) does not slow the system. In addition, two registers
(the State register and the Slot ROM Select register) that exist in both the FPI and the
Mega II ICs are written at 1.024 MHz and read at 2.8 MHz in the FPI address space.



# Bits
Table 2-1 Bits in the Shadow register
BIT | VALUE | Description
7 | - | Do not use
6 | 0 | The I/O and language-card (IOLC) inhibit bit: This bit controls whether the 4K range from $C000 to SCFFF in banks $00 and $01 acts as RAM or as 1/O. When this bit is 0, I/O is enabled in the $Cxxx space and the RAM that would normally occupy this space becomes a second $DXXX RAM space in banks $00 and $01, forming a language card. Note that the I/O space and language card in banks SEO and $E1 are not affected by this bit: this space is always enabled. 
6 | 1 | When this bit is 1, the I/O space and language card are
inhibited, and contiguous RAM is available from $0000
through $FFFF. (For more information on I/O and
language-card memory spaces, see
Chapter 3, "Memory.")
5 | 1 | Text Page 2 inhibit (available only on the 1 MB logic board): When this bit is 1, shadowing is disabled for text Page 2 and auxiliary text Page 2.
5 | 0 | When this bit is 0, shadowing is enabled for text Page 2 and auxiliary text Page 2
4 | 1 | Inhibit shadowing for auxiliary Hi-Res graphics pages: When this bit is 1, shadowing is disabled for Hi-Res graphics pages 1 and 2 (as determined by bits 0 through 3 in this register) in all auxiliary (odd) banks.  Shadowing of Hi-Res g
4 | 0 | When this bit is 0, shadowing is enabled for Hi-Res graphics pages (as determined by bit 1).
3 | 1 | Super Hi-Res graphics buffer inhibit: When this bit is 1, shadowing is disabled for the entire 32K video buffer. 
3 | 0 | When this bit is 0, shadowing is enabled for the Super Hi-Res graphics buffer
2 | 1 | Hi-Res graphics Page 2 inhibit: When this bit is 1, shadowing is disabled for Hi-Res graphics Page 2 and auxiliary Hi-Res graphics Page 2.
2 | 0 | When this bit is 0, shadowing is enabled for Hi-Res video Page 2 and auxiliary Hi-Res video Page 2, unless auxiliary Hi-Res graphics Page 2 shadowing is prohibited by bit 4 of this register.
1 | 1 | Hi-Res graphics Page 1 inhibit: When this bit is 1.  shadowing is disabled for Hi-Res graphics Page 1 and auxiliary Hi-Res graphics Page 1.
1 | 0 |When this bit is 0, shadowing is enabled for Hi-Res graphics Page 1 and auxiliary Hi-Res graphics Page 1, unless auxiliary Hi-Res graphics Page 1 shadowing is prohibited by bit 4 of this register.
0 | 1 |Text Page 1 inhibit: When this bit is 1, shadowing is disabled for text Page 1 and auxiliary text Page 1.
0 | 0 | When this bit is 0, shadowing is enabled for text Page 1 and auxiliary text Page 1.

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
