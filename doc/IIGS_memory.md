# Chapter 3 Memory

This chapter describes the internal memory of the Apple IIGS, and shows the RAM and ROM memory layout and how the memory is controlled. There is a memory map for the entire system, and there are individual maps for special features like standard Apple II compatibility and memory shadowing. 

The memory in the Apple IIGS is divided into several portions. Figure 3-1 is a block diagram showing the different parts of memory in relation to the rest of the hardware; Figure 3-2 is a memory map showing the addresses of the different parts of memory. As described in Chapter 2, the greater part of the memory is controlled by the FPI, while two 64K banks ($E0 and $E1) are controlled by the Mega II so that the Apple IIGS may function like a standard Apple II.

### Figure 3-1 Memory in the Apple IIGS 

A block diagram illustrating the memory components and their connections within the Apple IIGS hardware. Key components shown include:

  * 65C816 Microprocessor 
  * FPI (Fast Processor Interface) 
  * 128K or 1 MB RAM 
  * 128K or 256K ROM 
  * Memory expansion slot 
  * Mega II 
  * 128K RAM (controlled by Mega II) 
  * Video Graphics Controller 
  * Sound GLU 
  * 64K RAM (for sound) 
  * Ensoniq DOC 
  * Serial Communications Controller 
  * IWM (Integrated Woz Machine) 
  * ADB (Apple Desktop Bus) microcontroller 
  * Slots 1-7 
  * Real-time clock 

## Built-in memory 

The original Apple IlGS comes with 256K of main memory mounted on the circuit board, and the 1 MB Apple IlGS has 1 MB. Additional memory can be added by means of an optional memory expansion card you can plug into the memory expansion slot, which is described in the latter part of this chapter.

As you can see by looking at the block diagram in Figure 3-1, memory in the Apple IlGS is divided into several portions. The original Apple IlGS uses ten 64K-by-4-bit RAM ICs on the main logic board. Four RAM ICs make up the 128K controlled by the Mega II, and four more are the 128K of fast system memory controlled by the FPL The 1 MB Apple IlGS varies from this configuration slightly, using eight 1-megabit RAM ICs for fast system memory. Besides the main memory, there are also two RAM ICs for the 64K of RAM dedicated to sound generation. The sound RAM is not directly addressable by application programs; for more information about the sound memory, refer to Chapter 5.


## Memory map 

The 65C816 microprocessor is capable of addressing up to 16 MB of memory, but only portions of this memory space are utilized in the Apple IIGS. Figure 3-2 shows how that memory space is allocated in the Apple IIGS. A portion of the lower memory space — a maximum of 5 MB— is available for fast RAM under the control of the FPI. The first 128K is built into the original Apple IlGS, 1 MB in the 1 MB Apple IlGS; the rest can be added by means of a memory expansion card.

The 128K of RAM controlled by the Mega II occupies banks `$E0` and `$E1`. No further expansion of this part of memory is possible.

The highest 16 banks are allocated to ROM under the control of the FPI. The top 128K of ROM is built into the original Apple IlGS; the uppermost 256K of ROM is built into the 1 MB Apple IIGS. Additional ROM can be added by means of a memory expansion card.


### Figure 3-2 Memory map of the Apple IIGS 

This diagram shows the memory allocation for both the 256K and 1 MB Apple IIGS models, with solid lines indicating built-in memory and dashed lines for expansion memory. The memory is divided into three main sections:

  * **Fast RAM (Controlled by FPI)**: Occupies banks like $00, $01, up to $7F.
      * In the 256K Apple IIGS, built-in Fast RAM is in Banks $00 and $01.
      * In the 1 MB Apple IIGS, built-in Fast RAM is in Banks $00 through $0F.
  * **Slow RAM (Controlled by Mega II)**: Occupies Banks $E0 and $E1.
  * **Fast ROM (Controlled by FPI)**: Occupies the highest banks, from $F0 up to $FF.
      * In the 256K Apple IIGS, built-in ROM is in Banks $FE and $FF.
      * In the 1 MB Apple IIGS, built-in ROM is in Banks $FC, $FD, $FE, and $FF.

## Memory bank allocation 

The memory in the Apple IIGS is addressed as 64K banks, as shown in Figure 3-2. Bank numbers are in hexadecimal. The built-in memory banks are shown with solid outlines: banks `$00` and `$01`, `$E0` and `$E1`, and `$FE` and `$FF` in the 256K Apple IlGS. The parts of the memory space from bank `$02` to bank `$7F` and from bank `$F0` to bank `$FD` are allocated for memory expansion; banks `$F8` through `$FF` are reserved for current system and future expansion of system firmware. Memory spaces from `$80` through `$EF` are not available in the Apple IIGS.

The memory bank distribution in the 1 MB Apple IIGS is similar to that of the 256K system, with a few variations. The built-in banks are banks `$00` through `$0F`, `$E0` and `$E1`, and `$FC` through `$FF`. Banks `$10` through `$7F`, and `$F0` through `$FB` in the 1 MB system are available for memory expansion.


## Address wrapping 

In general, the 65C816 microprocessor used in the Apple IIGS addresses memory as continuous across bank boundaries, but there are exceptions. One kind of exception involves the 65C816's instructions themselves. For data at the highest address in a bank, the next **byte** is the lowest one in the next bank, but instructions themselves wrap around on bank boundaries, rather than advancing to the next bank. That means that the maximum size of a program segment is normally limited to 64K. For more information about the 65C816, refer to Chapter 10.

Another exception to the continuity of memory arises from the way certain banks are used for special purposes. For example, parts of banks `$E0` and `$E1` are set aside as video display buffers and are not normally used for program code, although the hardware doesn't prevent such use. The **Memory Manager**, which is part of the **Apple IIGS Toolbox**, takes such restrictions into account. For information about the Memory Manager, refer to the *Apple IIGS Toolbox Reference*.


## ROM memory 

The two highest banks in the 256K system, and the four highest banks in the 1 MB system, are used for built-in ROM that contains system programs and part of the Apple IIGS Toolbox. 
 
Additional memory in banks `$F0` to `$FD` (`$FB` in the 1 MB system) is available for ROM on a memory expansion card. Of that memory, part is available for application programs stored as a **ROM disk**, and part is reserved for future expansion of system programs. For information about ROM disks, refer to the *Apple IIGS ProDOS 16 Reference*.


## Bank $00 memory allocation 

Memory bank $00 preserves many features found in the 64K of main memory in the Apple IIe or the Apple IIc that make it possible to run programs originally written for those machines or for the Apple II Plus.

## Reserved memory pages 

Most of bank `$00` is available for storing programs and data. However, a few pages of bank `$00` are reserved for the use of the Monitor firmware and the BASIC interpreter. The reserved pages are described in the following sections.


> ▲ **Important**
> The system does not prevent your using these pages, but if you do use them, you must be careful not to disturb the system data they contain, or you will cause the system to malfunction.

> *♦ Apple II note*: Some of the reserved areas described in the sections that follow are used only by programs written for models of the Apple II that preceded the Apple IIGS. Programs written specifically for the Apple IIGS normally do not deal with hardware features directly, but rely on routines in the toolbox, as described in the *Apple IIGS Toolbox Reference* Some reserved areas are used by the built-in firmware: Refer to the *Apple IIGS Firmware Reference*.


**Direct page:**Several of the 65C816 microprocessor's addressing modes require the use of addresses in a specified page of bank `$00` called the **direct page**. Like the **zero page** in a 6502 microprocessor, the direct page is used for indirect addressing.

The direct page works differently in the two microprocessor modes. When the 65C816 is in **emulation mode**, the direct page is located at address `$0000` in bank `$00`, like the zero page in a 6502 microprocessor's 64K address space. When the 65C816 is in **native mode**, the direct page can be located anywhere in bank `$00`, making it possible for different programs to have different direct page locations. (For more information about emulation mode and native mode, see Chapter 10.)

To use indirect addressing in your assembly-language programs, you must store base addresses in a direct page. At the same time, you must avoid interfering with direct-page memory used by other programs such as the Monitor program, the BASIC interpreter, and the **disk operating systems**. The best way to avoid conflicts is to request your own direct-page space from the Memory Manager: Refer to the *Apple IIGS Toolbox Reference*.

**The 65C816 stack:** The 65C816 microprocessor uses a **stack** to store subroutine return addresses in last-in, first-out sequence. Many programs also use the stack for temporary storage of the registers and for passing parameters to subroutines.

The 65C816 uses the stack two ways— in emulation mode and native mode. In emulation mode, the stack **pointer** is 8 bits long, and the stack is located in page 1 (locations `$100` through `$1FF`, hexadecimal) and can hold 256 bytes of information. When you store the 257th byte in the stack, the stack pointer repeats itself, or wraps around, so that the new byte replaces the first byte stored, which is then lost. This writing over old data is called *stack overflow*. The program continues to run normally until the lost information is needed, whereupon the program may behave unpredictably, or, possibly, terminate catastrophically.



> ▲ **Warning**
> The wrapping around of the stack pointer does not occur consistently; in some addressing modes the stack will continue to page 2. In either case, a system crash is imminent. ▲

In native mode, the stack pointer is 16 bits long, and the stack can hold up to 64K of information at a time. To read more about using the 65C816 stack, see Chapter 10.

**The input buffer:** The GETLN input routine, which is used by the built-in Monitor program and Applesoft BASIC interpreter, uses page 2 of bank `$00` as its keyboard-input buffer. The size of this buffer sets the maximum size of input strings. (Note that BASIC uses only the first 237 bytes, although it permits you to type in 256 **characters**.) If you know that you won't be typing any long input strings, you can store temporary data at the upper end of page 2.

♦ *Note:* Routines that use the input buffer mn in emulation mode; programs running in native mode must first switch to emulation mode to call such routines. Refer to the *Apple IIGS Firmware Reference* for more information.

**Link-address storage:** The Monitor program, **ProDOS**®, and **DOS** 3.3 all use the upper part of page 3 for link addresses or vectors. BASIC programs sometimes need short assembly-language routines. These routines are usually stored in the lower part of page 3.


### Shadowed display spaces 

**Shadowed display spaces:** The display buffers in the Apple IIGS are actually located in banks `$E0` and `$E1`, but programs written for the Apple II Plus, the Apple IIc, and the Apple IIe put display information into the corresponding locations in bank `$00` and require display shadowing to be on. Figure 3-3 shows the shadowed display spaces. For more information about shadowing, refer to Chapter 2.

> **Note**: Display buffers in bank `$00 ` are normally used only by programs written for earlier models of the Apple II, except for text Page 1, which is also used by the Control Panel desk accessory. Shadowing of the display buffers is enabled by a switch in the Shadow register, described in Chapter 2.

### Figure 3-3 Shadowed display spaces in banks $00 and $01 

This diagram illustrates memory locations in banks $00 and $01 that are shadowed.

  * **Bank $00**:
      * Text Pages 1: $0400 - $0800 
      * Hi-Res graphics Page 1: $2000 - $4000 
      * Hi-Res graphics Page 2: $4000 - $6000 
      * I/O space: starting at $C000 
      * Language-card space: above I/O space to $FFFF 
  * **Bank $01** .

The primary text and Lo-Res graphics display buffer uses memory locations `$0400` through `$07FF`. This 1024-byte area is called text Page 1, and it is not usable for program and data storage when shadowing is on. There are 64 locations in this area that are not displayed on the screen; these locations, called **screen holes**, are reserved for use by the peripheral cards and the built-in ports. See the section "Peripheral-Card RAM Space," in Chapter 8, for the locations of the screen holes.

>♦ *Text Page 2*:  The original Apple IIGS doesn't shadow text Page 2. To make it possible to run Apple II programs that use text Page 2 for their displays, the firmware includes a desk accessory, Alternate Display Mode, that automatically transfers data from text Page 2 of bank `$00` into text Page 2 of bank `$EO`, where it can be displayed. Refer to the *Apple IIGS Firmware Reference* for more information. Note that the 1 MB Apple IIGS has available a Shadow register bit that allows you to shadow Text Page 2.


When the primary Hi-Res graphics display buffer. Hi-Res graphics Page 1, is shadowed, it uses memory locations `$2000` through `$3FFF`. If your program doesn't use Hi-Res graphics, this area is usable for programs or data.

Hi-Res graphics Page 2 uses memory locations `$4000` through `$5FFF`. Most programs do not use Hi-Res graphics Page 2, so they can use this area for program or data storage.

The primary Double Hi-Res graphics display buffer, called Double Hi-Res graphics Page 1, uses memory locations `$2000` through `$3FFF` in both main and auxiliary memory (banks `$00` and `$01`). If your program doesn't use Hi-Res or Double Hi-Res graphics, this area of memory is usable for programs or data.


## Language-card memory space 

> ♦ *Apple II note*: The language-card space is a carryover from earlier models of the Apple II and is normally used only by programs written for those machines and running in emulation mode. Like the bank `$00` shadowing of the display buffers, the peculiar features of the language-card space are enabled by a switch in the Shadow register, which is described in Chapter 2.

> ♦ *Memory banks*: The language-card space is a feature both of bank `$00` and of bank `$01`. Refer to the section "Bank $01 (Auxiliary Memory)," later in this chapter, for more information.

When the language-card feature is enabled, the memory address space from `$D000` through `$FFFF` is doubly allocated: It is used for both ROM and RAM. The 12K of ROM in this address space contains the Monitor program and the Applesoft BASIC interpreter. Alternatively, there are 16K of RAM in this space. The RAM is normally used by the disk **operating system**.

You may be wondering why this part of memory has such a split personality. Some of the reasons are historical: The Apple IIGS is able to run software written for a standard Apple II because it uses this part of memory in the same way a standard Apple II does. It's convenient to have the Applesoft BASIC interpreter in ROM, but the Apple IIGS is also able to use that address space for other things when Applesoft is not needed.

You may also be wondering how 16K of RAM are mapped into only 12K of address space. The usual answer is that it's done with mirrors, and that isn't a bad analogy: The 4K address space from `$D000` through `$DFFF` is used twice.



Switching different blocks of memory into the same address space is called *bank switching*. There are actually two examples of bank switching going on here: First, the entire address space from `$DOOO` through `$FFFF` is switched between ROM and RAM, and second, the address space from `$D000` to `$DFFF` is switched between two different blocks of RAM. If the language card is not enabled, the first of these blocks of RAM, block 1, occupies address space from `$COOO` to `$CFFF`, as shown in Figure 3-4. (Note that the banks involved here are not the same as the 64K memory banks.)

**Setting language-card bank switches:** You switch banks in the language-card space in the same way you switch other functions in a standard Apple II: by using soft switches. Read operations to the soft-switch locations do three things: select either RAM or ROM in this memory space, enable or inhibit writing to the RAM, and select the first or second 4K bank of RAM in the address space `$DOOO` to `$DFFF`.



> ▲ **Warning**
> Do not use these switches without careful planning. Careless switching between RAM and ROM is almost certain to have catastrophic effects on your program. ▲


Table 3-1 shows the addresses of the soft switches for enabling all combinations of reading and writing in this memory space. All the hexadecimal values of the addresses are of the form `$C08x`. Notice that several addresses perform the same function: This is because the functions are activated by single address bits. For example, any address of the form `$C08x` with a 1 in the **low-order** bit enables the RAM for writing. Similarly, bit 3 of the address selects which 4K block of RAM to use for the address space `$D000` to `$DFFF;` if bit 3 is 0, the first bank of RAM is used, and if bit 3 is 1, the second bank is used.
When RAM is not enabled for reading, the ROM in this address space is enabled. Even when RAM is not enabled for reading, it can still be written to if it is write-enabled.



### Table 3-1 Language-card bank-select switches 

| Name | Action | Location | Function |
| :--- | :--- | :--- | :--- |
| | R | `$C080` | Read this location to read RAM, write-protect RAM, and use `$D000` bank 2. |
| ROMIN | RR | `$C081` | Read this location twice to read ROM, write-enable RAM, and use `$D000` bank 2. |
| | R | `$C082` | Read this location to read ROM, write-protect RAM, and use `$D000` bank 2. |
| LCBANK2 | RR | `$C083` | Read this location twice to read RAM, write-enable RAM, and use $D000 bank 2. |
| | R | `$C088` | Read this location to read RAM, write-protect RAM, and use `$D000` bank 1. |
| | RR | `$C089` | Read this location twice to read ROM, write-enable RAM, and use `$D000` bank 1. |
| | R| `$C08A` | Read this location to read ROM, write-protect RAM, and use `$D000` bank 1. |
| | RR | `$C08B` | Read this switch twice to read RAM, write-enable RAM, and use `$D000` bank 1. |
| RDLCBNK2 | R7 | `$C011` | Read this location and test bit 7 for switch status: `$D000` bank 2 (1) or bank 1 (0). |
| RDLCRAM | R7 | `$C012` | Read this location and test bit 7 for switch status: RAM (1) or ROM (0). |
| SETSTDZP | W | `$C008` | Write this location to use main bank, page 0 and page 1. |
| SETALTZP | W | `$C009` | Write this location to use auxiliary bank, page 0 and page 1. |
| RDALTZP | R7 | `$C016` | Read this location and test bit 7 for switch status: auxiliary (1) or main (0) bank. |


When you turn power on or reset the Apple IIGS, the bank switches are initialized for reading from the ROM and writing to the RAM, using the second bank of RAM. Note that this is different from the reset on the Apple II Plus, which doesn't affect the **bank-switched memory** (the language card). On the Apple IIGS, you can't use the reset key sequence to return control to a program in bank-switched memory, as you can on the Apple II Plus.

♦ *Reading and writing to RAM banks:* You can't read one RAM bank and write to the other; if you select either RAM bank for reading, you get that one for writing as well.

♦ *Reading RAM and ROM:* You can't read from ROM in part of the bank-switched memory and read from RAM in the rest. Specifically, you can't read the Monitor program in ROM while reading bank-switched RAM. If you want to use the Monitor firmware with a program in bank-switched RAM, copy the Monitor program from ROM (locations `$F800` through `$FFFF`) into bank-switched RAM. You can't do this from Pascal or ProDOS.

To see how to use these switches, look at the following section of an assembly-language program:


```assembly
    LDA $C083   ; SELECT 2ND 4K BANK & READ/WRITE 
    LDA $C083   ; BY TWO CONSECUTIVE READS 
    LDA #$DO    ; SET UP.. 
    STA BEGIN   ; ...NEW... 
    LDA #$FF    ; ...MAIN-MEMORY... 
    STA END     ; ...POINTERS... 
    JSR YOURPRG ; ... FOR 12K BANK 
    LDA $C08B   ; SELECT 1ST 4K BANK 
    JSR YOURPRG ; USE ABOVE POINTERS 
    LDA $C088   ; SELECT 1ST BANK & WRITE PROTECT 
    LDA #$80    
    INC SUM     
    JSR YOURSUB 
    LDA $C080   ; SELECT 2ND BANK & WRITE PROTECT 
    INC SUM     
    LDA #PAT12K 
    JSR YOURSUB 
    LDA $C08B   ; SELECT 1ST BANK & READ/WRITE 
    LDA $C08B   ; BY TWO CONSECUTIVE READS 
    INC NUM     ; FLAG RAM IN READ/WRITE 
    INC SUM     
```

The `LDA` instruction, which performs a read operation to the specified memory location, is used for setting the soft switches. The unusual sequence of two consecutive LDA instructions performs the two consecutive reads that write-enable this area of RAM; in this case, the data that are read are not used.

**Reading bank switches:** You can find out which language-card bank is currently switched in by reading the soft switch at `$C011`. You can find out whether the language card or ROM is switched in by reading `$C012`. The only way that you can find out whether or not the language-card RAM is write-enabled is by trying to write some data to the card's RAM space.


## The State register 

The State register is a read/write register containing eight commonly used standard Apple II soft switches. Compared to the use of separate soft switches, the single-byte format of the State register simplifies the process of interrupt handling. Reading and storing this byte before executing interrupt routines allows you to restore the system soft switches to the previous state in minimum time after returning from the interrupt routine. Write operations to the State register will slow the system momentarily. (See Figure 3-5 and Table 3-2.)

>**▲ Warning** 
> Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

### Figure 3-5 State register at $C068 

| Bit | Name |
| :-- | :--- |
| 7 | ALTZP  |
| 6 | PAGE 2  |
| 5 | RAMRD  |
| 4 | RAMWRT  |
| 3 | RDROM  |
| 2 | LCBNK2  |
| 1 | ROMBANK  |
| 0 | INTCXROM  |

AJS -- TO HERE

### Table 3-2 Bits in the State register 

| Bit | Value | Description |
| :--- | :--- | :--- |
| 7 | 1 | **ALTZP**: bank-switched memory, stack, and direct page are in main memory. |
| | 0 | bank-switched memory, stack, and direct page are in auxiliary memory. |
| 6 | 1 | **PAGE2**: text Page 2 is selected. |
| | 0 | text Page 1 is selected. |
| 5 | 1 | **RAMRD**: auxiliary RAM bank is read-enabled. |
| | 0 | main RAM bank is read-enabled. |
| 4 | 1 | **RAMWRT**: auxiliary RAM bank is write-enabled. |
| | 0 | main RAM bank is write-enabled. |
| 3 | 1 | **RDROM**: the selected language-card ROM is read-enabled. |
| | 0 | the selected language-card RAM bank is read-enabled. |
| 2 | 1 | **LCBNK2**: language-card RAM bank 1 is selected. |
| | 0 | language-card RAM bank 2 is selected. |
| 1 | | **ROMBANK**: The ROM bank select switch must always be 0. Do not modify this bit. |
| 0 | 1 | **INTCXROM**: the internal ROM at $Cx00 is selected. |
| | 0 | the peripheral-card ROM at $Cx00 is selected. |


## Bank $01 (auxiliary memory) 

> **Apple II note**: The following sections describe the operation of the auxiliary memory (bank $01) as it applies to programs originally written for the Apple IIc or for 128K versions of the Apple IIe.

When display shadowing is on, some of the display modes use memory in bank $01.

> **Warning**
> Do not attempt to switch in the auxiliary memory from a BASIC program.

Auxiliary memory is divided into two large sections and one small one.

### Bank switching for auxiliary memory 

Switching the 48K section of memory is done by two soft switches: `RDMAINRAM` and `RDCARDRAM` select main or auxiliary memory for reading, and `WRMAINRAM` and `WRCARDRAM` select it for writing.

> **Warning**
> Do not use these switches without careful planning.

### Table 3-3 Auxiliary-memory select switches 

| Name | Function | Location (Dec) | Location (Hex) | Notes |
| :--- | :--- | :--- | :--- | :--- |
| RDCARDRAM | Read auxiliary memory | 49155 | $C003 | Write |
| RDMAINRAM | Read main memory | 49154 | $C002 | Write |
| RDRAMRD | Read switch status | 49171 | $C013 | Read and test bit 7 (1=auxiliary, 0=main) |
| WRCARDRAM | Write auxiliary memory | 49157 | $C005 | Write |
| WRMAINRAM | Write main memory | 49156 | $C004 | Write |
| RDRAMWRT | Read switch status | 49172 | $C014 | Read and test bit 7 (1=auxiliary, 0=main) |
| SET80COL | Access display page | 49153 | $C001 | Write |
| CLR80COL | Use RAM switches | 49152 | $C000 | Write |
| RD80COL | Read switch status | 49176 | $C018 | Read and test bit 7 (1=80-column on, 0=off) |
| TXTPAGE2 | Text Page 2 on (auxiliary) | 49237 | $C055 | Read or write |
| TXTPAGE1 | Text Page 1 on (main) | 49236 | $C054 | Read or write |
| RDPAGE2 | Read switch status | 49180 | $C01C | Read and test bit 7 (1=Page 2, 0=Page 1) |
| HIRES | Access Hi-Res pages | 49239 | $C057 | Read or write |
| LORES | Use RAM switches | 49238 | $C056 | Read or write |
| RDHIRES | Read switch status | 49181 | $C01D | Read and test bit 7 (1=HIRES on, 0=off) |
| SETALTZP | Auxiliary stack and direct page | 49161 | $C009 | Write |
| SETSTDZP | Main stack and direct page | 49160 | $C008 | Write |
| RDALTZP | Read switch status | 49174 | $C016 | Read and test bit 7 (1=auxiliary, 0=main) |


When `SET80COL` is enabled, `TXTPAGE2` and `TXTPAGE1` select main or auxiliary display memory.

A single soft switch named `ALTZP` switches the bank-switched memory and the associated stack and direct-page area between main and auxiliary memory.

## Banks $E0 and $E1 

Banks $E0 and $E1 are controlled by the Mega II.

### The display buffers 

The display buffers are permanently assigned to locations in banks $E0 and $E1 because they are tied directly to the Mega II IC that generates the display signals.

  * **Text/Lo-Res**: The primary text and Lo-Res graphics display buffers occupy memory locations $0400 through $07FF in banks $E0 and $E1.
  * **Text Page 2**: The alternate text buffer, occupies locations $0800 through $0BFF.
  * **Hi-Res**: There are two Hi-Res graphics buffers, each 8K.
  * **Double Hi-Res**: These buffers require 16384 bytes each.
  * **Super Hi-Res**: This buffer occupies 32K of memory at locations $2000 through $9FFF in bank $E1.

Programs should call on the Memory Manager to allocate space for data storage, as it keeps track of available display spaces.

### Firmware workspace 

Banks $E0 and $E1 are the logical place for working storage used by the toolbox and other system programs because they are always broken up by display buffers.

> **Warning**
> To avoid conflicts with built-in programs that use RAM areas in banks $E0 and $E1, applications must not use these areas and should instead request memory from the Memory Manager.

## Apple II program memory use 

For programs written for earlier Apple II models to run on an Apple IIGS, all of the Apple II features must be present in banks $00 and $01, which correspond to main and auxiliary memory. These features include:

  * direct (zero) page, from $0000 to $00FF of bank $00 
  * stack, from $0100 to $01FF of bank $00 
  * text Page 1, from $0400 to $07FF of both banks 
  * text Page 2, from $0800 to $0BFF of both banks (available in the 1 MB Apple IIGS only) 
  * Hi-Res graphics Page 1, from $2000 to $3FFF of bank $00 
  * Hi-Res graphics Page 2, from $4000 to $5FFF of bank $00 
  * Double Hi-Res graphics Page 1, from $2000 to $3FFF of both banks 
  * Double Hi-Res graphics Page 2, from $4000 to $5FFF of both banks 
  * I/O space, from $C000 to $CFFF of either bank 
  * language-card space, from $D000 to $FFFF of both banks 

## Shadowing 

The Apple IIGS display buffers are in banks $E0 and $E1.

### Screen holes 

When shadowing is on for text Page 1, programs and peripheral cards that use the text Page 1 locations known as screen holes run normally.

## Memory expansion 

The original Apple IIGS has 256K of RAM and 128K of ROM built in, while the 1 MB model has 1 MB RAM and 256K of ROM.

### The memory expansion slot 

The memory expansion slot allows for adding a memory card with up to 4 MB of RAM and 786K of ROM.

### Memory expansion signals 

The memory expansion slot provides signals to support dynamic RAM and additional signals for ROM decoding.

### Table 3-4 Memory-card interface signals 

| Pin | Signal | Description |
| :--- | :--- | :--- |
| | FRA0-9 | 10 bits of multiplexed RAM address for RAM cycles—the 10 least significant bits of the ROM address |
| 12 | FR/W | Write enable to RAMS; R/W from microprocessor or DMA |
| 17 | /CCAS | RAM column address strobe |
| 18-19 | CROW0-1 | 2 bits select one of four RAM rows |
| 20 | /CROMSEL | Card ROM select; low for accesses to banks $F0-$FD |
| 26 | /CSEL | Card data buffer direction control; signal goes high when reading card data |
| 27 | MSIZE | Output from card; indicates RAM row size |
| | D0-D7 | 8 bits of bidirectional data—microprocessor data bus |
| 31 | 2CLK | Microprocessor clock; rising edge indicates valid bank address on D0-D7 |
| | A10-15 | The 6 high-order address bits; used to decode ROM address |
| 32 | ABORT | Connects to 65C816 ABORT pin |
| 35 | /CRAS | RAM row address strobe |
| | +5V | +5 volts ±5 percent; 600 mA maximum |


### Extended RAM 

Up to 4 MB of RAM can be installed in the extended memory card.

The FPI provides `/CRAS` (card row address strobe), `/CCAS` (card column address strobe), `CROW0` (card row select 0), and `CROW1` (card row select 1) signals to control RAM rows.

### Extended RAM mapping 

A 1 MB expansion card is enabled for accesses in banks $2 through $80 in the 256K system, and banks $10 through $80 in the 1 MB system.

The MSIZE signal flags the type of memory chips on the expansion card.

### Extended ROM 

Additional ROM space is available in banks $F0 through $FD ($F0 through $FB on the 1MB logic board).

### Address multiplexing 

The FPI multiplexes RAM addresses onto eight, nine, or ten RAM address lines to support 64-kilobit, 256-kilobit, or 1-megabit RAM ICs.
