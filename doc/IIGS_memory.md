# [cite\_start]Chapter 3 Memory [cite: 1]

[cite\_start]This chapter describes the internal memory of the Apple IIGS, and shows the RAM and ROM memory layout and how the memory is controlled[cite: 2]. [cite\_start]There is a memory map for the entire system, and there are individual maps for special features like standard Apple II compatibility and memory shadowing[cite: 3]. [cite\_start]The memory in the Apple IIGS is divided into several portions[cite: 4]. Figure 3-1 is a block diagram showing the different parts of memory in relation to the rest of the hardware; [cite\_start]Figure 3-2 is a memory map showing the addresses of the different parts of memory[cite: 5, 6]. [cite\_start]As described in Chapter 2, the greater part of the memory is controlled by the FPI, while two 64K banks ($E0 and $E1) are controlled by the Mega II so that the Apple IIGS may function like a standard Apple II[cite: 7].

### [cite\_start]Figure 3-1 Memory in the Apple IIGS [cite: 9]

[cite\_start]A block diagram illustrating the memory components and their connections within the Apple IIGS hardware[cite: 9]. Key components shown include:

  * [cite\_start]65C816 Microprocessor [cite: 34]
  * [cite\_start]FPI (Fast Processor Interface) [cite: 35]
  * [cite\_start]128K or 1 MB RAM [cite: 36]
  * [cite\_start]128K or 256K ROM [cite: 46]
  * [cite\_start]Memory expansion slot [cite: 49]
  * [cite\_start]Mega II [cite: 23]
  * [cite\_start]128K RAM (controlled by Mega II) [cite: 24]
  * [cite\_start]Video Graphics Controller [cite: 25]
  * [cite\_start]Sound GLU [cite: 55]
  * [cite\_start]64K RAM (for sound) [cite: 57]
  * [cite\_start]Ensoniq DOC [cite: 63]
  * [cite\_start]Serial Communications Controller [cite: 43]
  * [cite\_start]IWM (Integrated Woz Machine) [cite: 44]
  * [cite\_start]ADB (Apple Desktop Bus) microcontroller [cite: 45]
  * [cite\_start]Slots 1-7 [cite: 14, 15, 16, 17, 18, 19, 20]
  * [cite\_start]Real-time clock [cite: 31]

## [cite\_start]Built-in memory [cite: 69]

[cite\_start]The original Apple IIGS comes with 256K of main memory mounted on the circuit board, and the 1 MB Apple IIGS has 1 MB[cite: 70]. [cite\_start]Additional memory can be added by means of an optional memory expansion card you can plug into the memory expansion slot[cite: 71]. [cite\_start]Memory in the Apple IIGS is divided into several portions[cite: 72]. [cite\_start]The original Apple IIGS uses ten 64K-by-4-bit RAM ICs on the main logic board[cite: 73]. [cite\_start]Four RAM ICs make up the 128K controlled by the Mega II, and four more are the 128K of fast system memory controlled by the FPI[cite: 74]. [cite\_start]The 1 MB Apple IIGS varies from this configuration slightly, using eight 1-megabit RAM ICs for fast system memory[cite: 75]. [cite\_start]Besides the main memory, there are also two RAM ICs for the 64K of RAM dedicated to sound generation[cite: 76]. [cite\_start]The sound RAM is not directly addressable by application programs[cite: 77].

## [cite\_start]Memory map [cite: 79]

[cite\_start]The 65C816 microprocessor is capable of addressing up to 16 MB of memory, but only portions of this memory space are utilized in the Apple IIGS[cite: 80]. [cite\_start]Figure 3-2 shows how that memory space is allocated in the Apple IIGS[cite: 81]. [cite\_start]A maximum of 5 MB of the lower memory space is available for fast RAM under the control of the FPI[cite: 82]. [cite\_start]The first 128K is built into the original Apple IIGS, 1 MB in the 1 MB Apple IIGS; the rest can be added by means of a memory expansion card[cite: 83, 84]. [cite\_start]The 128K of RAM controlled by the Mega II occupies banks $E0 and $E1[cite: 85]. [cite\_start]No further expansion of this part of memory is possible[cite: 86]. [cite\_start]The highest 16 banks are allocated to ROM under the control of the FPI[cite: 87]. [cite\_start]The top 128K of ROM is built into the original Apple IIGS; the uppermost 256K of ROM is built into the 1 MB Apple IIGS[cite: 88, 89]. [cite\_start]Additional ROM can be added by means of a memory expansion card[cite: 90].

### [cite\_start]Figure 3-2 Memory map of the Apple IIGS [cite: 103]

[cite\_start]This diagram shows the memory allocation for both the 256K and 1 MB Apple IIGS models, with solid lines indicating built-in memory and dashed lines for expansion memory[cite: 103]. The memory is divided into three main sections:

  * [cite\_start]**Fast RAM (Controlled by FPI)**: Occupies banks like $00, $01, up to $7F[cite: 129, 132].
      * [cite\_start]In the 256K Apple IIGS, built-in Fast RAM is in Banks $00 and $01[cite: 138, 137].
      * [cite\_start]In the 1 MB Apple IIGS, built-in Fast RAM is in Banks $00 through $0F[cite: 135, 133, 130, 127, 125].
  * [cite\_start]**Slow RAM (Controlled by Mega II)**: Occupies Banks $E0 and $E1[cite: 116, 118]. [cite\_start]This is built-in for both models[cite: 115, 117, 114, 113].
  * [cite\_start]**Fast ROM (Controlled by FPI)**: Occupies the highest banks, from $F0 up to $FF[cite: 104].
      * [cite\_start]In the 256K Apple IIGS, built-in ROM is in Banks $FE and $FF[cite: 112, 111, 110].
      * [cite\_start]In the 1 MB Apple IIGS, built-in ROM is in Banks $FC, $FD, $FE, and $FF[cite: 105, 106, 107, 108, 109].

## [cite\_start]Memory bank allocation [cite: 142]

[cite\_start]The memory in the Apple IIGS is addressed as 64K banks[cite: 143]. [cite\_start]Bank numbers are in hexadecimal[cite: 144]. [cite\_start]The built-in memory banks are shown with solid outlines: banks $00 and $01, $E0 and $E1, and $FE and $FF in the 256K Apple IIGS[cite: 144]. [cite\_start]The parts of the memory space from bank $02 to bank $7F and from bank $F0 to bank $FD are allocated for memory expansion[cite: 145]. [cite\_start]Banks $F8 through $FF are reserved for current system and future expansion of system firmware[cite: 146]. [cite\_start]Memory spaces from $80 through $EF are not available in the Apple IIGS[cite: 147].

[cite\_start]The memory bank distribution in the 1 MB Apple IIGS is similar to that of the 256K system, with a few variations[cite: 148]. [cite\_start]The built-in banks are banks $00 through $0F, $E0 and $E1, and $FC through $FF[cite: 149]. [cite\_start]Banks $10 through $7F, and $F0 through $FB in the 1 MB system are available for memory expansion[cite: 150].

### [cite\_start]Address wrapping [cite: 151]

[cite\_start]In general, the 65C816 microprocessor used in the Apple IIGS addresses memory as continuous across bank boundaries, but there are exceptions[cite: 152]. [cite\_start]One kind of exception involves the 65C816's instructions themselves[cite: 153]. [cite\_start]For data at the highest address in a bank, the next byte is the lowest one in the next bank, but instructions themselves wrap around on bank boundaries, rather than advancing to the next bank[cite: 153]. [cite\_start]That means that the maximum size of a program segment is normally limited to 64K[cite: 154].

[cite\_start]Another exception to the continuity of memory arises from the way certain banks are used for special purposes[cite: 156]. [cite\_start]For example, parts of banks $E0 and $E1 are set aside as video display buffers and are not normally used for program code, although the hardware doesn't prevent such use[cite: 157]. [cite\_start]The Memory Manager, which is part of the Apple IIGS Toolbox, takes such restrictions into account[cite: 158].

### [cite\_start]ROM memory [cite: 160]

[cite\_start]The two highest banks in the 256K system, and the four highest banks in the 1 MB system, are used for built-in ROM that contains system programs and part of the Apple IIGS Toolbox[cite: 161]. [cite\_start]Additional memory in banks $F0 to $FD ($FB in the 1 MB system) is available for ROM on a memory expansion card[cite: 162]. [cite\_start]Of that memory, part is available for application programs stored as a ROM disk, and part is reserved for future expansion of system programs[cite: 163].

## [cite\_start]Bank $00 memory allocation [cite: 167]

[cite\_start]Memory bank $00 preserves many features found in the 64K of main memory in the Apple IIe or the Apple IIc that make it possible to run programs originally written for those machines or for the Apple II Plus[cite: 168].

### [cite\_start]Reserved memory pages [cite: 169]

[cite\_start]Most of bank $00 is available for storing programs and data[cite: 170]. [cite\_start]However, a few pages of bank $00 are reserved for the use of the Monitor firmware and the BASIC interpreter[cite: 171].

> **Important**
> [cite\_start]The system does not prevent your using these pages, but if you do use them, you must be careful not to disturb the system data they contain, or you will cause the system to malfunction[cite: 175].

> [cite\_start]**Apple II note**: Some of the reserved areas described in the sections that follow are used only by programs written for models of the Apple II that preceded the Apple IIGS[cite: 177]. [cite\_start]Programs written specifically for the Apple IIGS normally do not deal with hardware features directly, but rely on routines in the toolbox[cite: 178]. [cite\_start]Some reserved areas are used by the built-in firmware[cite: 179].

### [cite\_start]Direct page [cite: 180]

[cite\_start]Several of the 65C816 microprocessor's addressing modes require the use of addresses in a specified page of bank $00 called the direct page[cite: 180]. [cite\_start]Like the zero page in a 6502 microprocessor, the direct page is used for indirect addressing[cite: 181]. [cite\_start]The direct page works differently in the two microprocessor modes[cite: 182]. [cite\_start]When the 65C816 is in emulation mode, the direct page is located at address $0000 in bank $00, like the zero page in a 6502 microprocessor's 64K address space[cite: 183]. [cite\_start]When the 65C816 is in native mode, the direct page can be located anywhere in bank $00, making it possible for different programs to have different direct page locations[cite: 184]. [cite\_start]To use indirect addressing in your assembly-language programs, you must store base addresses in a direct page[cite: 186]. [cite\_start]At the same time, you must avoid interfering with direct-page memory used by other programs such as the Monitor program, the BASIC interpreter, and the disk operating systems[cite: 187]. [cite\_start]The best way to avoid conflicts is to request your own direct-page space from the Memory Manager[cite: 188].

### [cite\_start]The 65C816 stack [cite: 190]

[cite\_start]The 65C816 microprocessor uses a stack to store subroutine return addresses in last-in, first-out sequence[cite: 190]. [cite\_start]Many programs also use the stack for temporary storage of the registers and for passing parameters to subroutines[cite: 191]. [cite\_start]In emulation mode, the stack pointer is 8 bits long, and the stack is located in page 1 (locations $100 through $1FF, hexadecimal) and can hold 256 bytes of information[cite: 193]. [cite\_start]When you store the 257th byte in the stack, the stack pointer wraps around, so that the new byte replaces the first byte stored, which is then lost[cite: 194]. [cite\_start]This is called stack overflow[cite: 195].

> **Warning**
> [cite\_start]The wrapping around of the stack pointer does not occur consistently; in some addressing modes the stack will continue to page 2[cite: 197, 198]. [cite\_start]In either case, a system crash is imminent[cite: 198].

[cite\_start]In native mode, the stack pointer is 16 bits long, and the stack can hold up to 64K of information at a time[cite: 199].

### [cite\_start]The input buffer [cite: 201]

[cite\_start]The GETLN input routine, used by the built-in Monitor program and Applesoft BASIC interpreter, uses page 2 of bank $00 as its keyboard-input buffer[cite: 201]. [cite\_start]The size of this buffer sets the maximum size of input strings[cite: 202]. [cite\_start]Routines that use the input buffer run in emulation mode; programs running in native mode must first switch to emulation mode to call such routines[cite: 204, 205].

### [cite\_start]Link-address storage [cite: 207]

[cite\_start]The Monitor program, ProDOS®, and DOS 3.3 all use the upper part of page 3 for link addresses or vectors[cite: 207]. [cite\_start]BASIC programs sometimes use the lower part of page 3 for short assembly-language routines[cite: 208].

### [cite\_start]Shadowed display spaces [cite: 209]

[cite\_start]The display buffers in the Apple IIGS are actually located in banks $E0 and $E1, but programs written for the Apple II Plus, the Apple IIe, and the Apple IIc put display information into the corresponding locations in bank $00 and require display shadowing to be on[cite: 209]. [cite\_start]Figure 3-3 shows the shadowed display spaces[cite: 210].

> [cite\_start]**Note**: Display buffers in bank $00 are normally used only by programs written for earlier models of the Apple II, except for text Page 1, which is also used by the Control Panel desk accessory[cite: 213]. [cite\_start]Shadowing of the display buffers is enabled by a switch in the Shadow register[cite: 214].

### [cite\_start]Figure 3-3 Shadowed display spaces in banks $00 and $01 [cite: 215]

[cite\_start]This diagram illustrates memory locations in banks $00 and $01 that are shadowed[cite: 215].

  * [cite\_start]**Bank $00**[cite: 216]:
      * [cite\_start]Text Pages 1: $0400 - $0800 [cite: 229, 223, 222]
      * [cite\_start]Hi-Res graphics Page 1: $2000 - $4000 [cite: 228, 221, 220]
      * [cite\_start]Hi-Res graphics Page 2: $4000 - $6000 [cite: 227, 220, 219]
      * [cite\_start]I/O space: starting at $C000 [cite: 226, 218]
      * [cite\_start]Language-card space: above I/O space to $FFFF [cite: 225, 217]
  * [cite\_start]**Bank $01** [cite: 230][cite\_start]: Contains the Super Hi-Res video buffer[cite: 241, 242].

[cite\_start]The primary text and Lo-Res graphics display buffer uses memory locations $0400 through $07FF[cite: 231]. [cite\_start]This 1024-byte area is called text Page 1, and it is not usable for program and data storage when shadowing is on[cite: 232]. [cite\_start]There are 64 locations in this area that are not displayed on the screen; these locations, called screen holes, are reserved for use by the peripheral cards and the built-in ports[cite: 233, 234].

### [cite\_start]Text Page 2 [cite: 248]

[cite\_start]The original Apple IIGS doesn't shadow text Page 2[cite: 248]. [cite\_start]To run Apple II programs that use text Page 2, the firmware includes a desk accessory, Alternate Display Mode, that automatically transfers data from text Page 2 of bank $00 into text Page 2 of bank $E0[cite: 248]. [cite\_start]The 1 MB Apple IIGS has a Shadow register bit that allows you to shadow Text Page 2[cite: 250].

[cite\_start]When the primary Hi-Res graphics display buffer, Hi-Res graphics Page 1, is shadowed, it uses memory locations $2000 through $3FFF[cite: 251]. [cite\_start]If your program doesn't use Hi-Res graphics, this area is usable for programs or data[cite: 252]. [cite\_start]Hi-Res graphics Page 2 uses memory locations $4000 through $5FFF[cite: 253]. [cite\_start]The primary Double Hi-Res graphics display buffer uses memory locations $2000 through $3FFF in both main and auxiliary memory (banks $00 and $01)[cite: 255].

### [cite\_start]Language-card memory space [cite: 257]

> [cite\_start]**Apple II note**: The language-card space is a carryover from earlier models of the Apple II and is normally used only by programs written for those machines and running in emulation mode[cite: 258].

[cite\_start]When the language-card feature is enabled, the memory address space from $D000 through $FFFF is doubly allocated: It is used for both ROM and RAM[cite: 262]. [cite\_start]The 12K of ROM in this address space contains the Monitor program and the Applesoft BASIC interpreter[cite: 263]. [cite\_start]Alternatively, there are 16K of RAM in this space[cite: 264].

[cite\_start]Switching different blocks of memory into the same address space is called bank switching[cite: 272]. [cite\_start]There are two examples of bank switching here: the entire address space from $D000 through $FFFF is switched between ROM and RAM, and the address space from $D000 to $DFFF is switched between two different blocks of RAM[cite: 273].

[cite\_start]You switch banks in the language-card space by using soft switches[cite: 291]. [cite\_start]Read operations to the soft-switch locations select either RAM or ROM, enable or inhibit writing to the RAM, and select the first or second 4K bank of RAM in the address space $D000 to $DFFF[cite: 292].

> **Warning**
> [cite\_start]Do not use these switches without careful planning[cite: 294]. [cite\_start]Careless switching between RAM and ROM is almost certain to have catastrophic effects on your program[cite: 294].

[cite\_start]Table 3-1 shows the addresses of the soft switches for enabling all combinations of reading and writing in this memory space[cite: 296]. [cite\_start]All the hexadecimal values of the addresses are of the form $C08x[cite: 297]. [cite\_start]Any address of the form $C08x with a 1 in the low-order bit enables the RAM for writing[cite: 299]. [cite\_start]Similarly, bit 3 of the address selects which 4K block of RAM to use for the address space $D000 to $DFFF[cite: 300].

### [cite\_start]Table 3-1 Language-card bank-select switches [cite: 306, 307]

| Name | Action | Location | Function |
| :--- | :--- | :--- | :--- |
| | R | $C080 | Read this location to read RAM, write-protect RAM, and use $D000 bank 2. |
| ROMIN | RR | $C081 | Read this location twice to read ROM, write-enable RAM, and use $D000 bank 2. |
| | R | $C082 | Read this location to read ROM, write-protect RAM, and use $D000 bank 2. |
| LCBANK2 | RR | $C083 | Read this location twice to read RAM, write-enable RAM, and use $D000 bank 2. |
| | R | $C088 | Read this location to read RAM, write-protect RAM, and use $D000 bank 1. |
| | RR | $C089 | Read this location twice to read ROM, write-enable RAM, and use $D000 bank 1. |
| | R\<br\>RR | $C08A\<br\>$C08B | Read this location to read ROM, write-protect RAM, and use $D000 bank 1.\<br\>Read this switch twice to read RAM, write-enable RAM, and use $D000 bank 1. |
| RDLCBNK2 | R7 | $C011 | Read this location and test bit 7 for switch status: $D000 bank 2 (1) or bank 1 (0). |
| RDLCRAM | R7 | $C012 | Read this location and test bit 7 for switch status: RAM (1) or ROM (0). |
| SETSTDZP | W | $C008 | Write this location to use main bank, page 0 and page 1. |
| SETALTZP | W | $C009 | Write this location to use auxiliary bank, page 0 and page 1. |
| RDALTZP | R7 | $C016 | Read this location and test bit 7 for switch status: auxiliary (1) or main (0) bank. |
[cite\_start][cite: 308]

[cite\_start]When you turn power on or reset the Apple IIGS, the bank switches are initialized for reading from the ROM and writing to the RAM, using the second bank of RAM[cite: 311].

[cite\_start]You can find out which language-card bank is currently switched in by reading the soft switch at $C011[cite: 360]. [cite\_start]You can find out whether the language card or ROM is switched in by reading $C012[cite: 361]. [cite\_start]The only way to find out if the language-card RAM is write-enabled is by trying to write data to it[cite: 362].

An example of assembly language for setting soft switches:

```assembly
    LDA $C083   ; [cite_start]SELECT 2ND 4K BANK & READ/WRITE [cite: 321, 323]
    LDA $C083   ; [cite_start]BY TWO CONSECUTIVE READS [cite: 322, 324]
    [cite_start]*SET UP.. [cite: 325]
    [cite_start]LDA #$DO    [cite: 326]
    STA BEGIN   ; [cite_start]...NEW... [cite: 327, 328]
    LDA #$FF    ; [cite_start]...MAIN-MEMORY... [cite: 329, 330]
    STA END     ; [cite_start]...POINTERS... [cite: 331, 332]
    JSR YOURPRG ; [cite_start]... FOR 12K BANK [cite: 333]
    LDA $C08B   ; [cite_start]SELECT 1ST 4K BANK [cite: 334]
    [cite_start]JSR YOURPRG [cite: 335]
    * [cite_start]USE ABOVE POINTERS [cite: 336]
    LDA $C088   ; [cite_start]SELECT 1ST BANK & WRITE PROTECT [cite: 337, 338]
    [cite_start]LDA #$80    [cite: 339]
    [cite_start]INC SUM     [cite: 340]
    [cite_start]JSR YOURSUB [cite: 341]
    LDA $C080   ; [cite_start]SELECT 2ND BANK & WRITE PROTECT [cite: 342, 343]
    [cite_start]INC SUM     [cite: 344]
    [cite_start]LDA #PAT12K [cite: 345]
    [cite_start]JSR YOURSUB [cite: 346]
    LDA $C08B   ; [cite_start]SELECT 1ST BANK & READ/WRITE [cite: 347, 348]
    LDA $C08B   ; [cite_start]BY TWO CONSECUTIVE READS [cite: 349, 350]
    INC NUM     ; [cite_start]FLAG RAM IN READ/WRITE [cite: 351, 352]
    [cite_start]INC SUM     [cite: 353]
```

[cite\_start]The `LDA` instruction is used for setting the soft switches[cite: 354]. [cite\_start]The sequence of two consecutive `LDA` instructions performs the two consecutive reads that write-enable this area of RAM[cite: 355, 356].

### [cite\_start]The State register [cite: 363]

[cite\_start]The State register is a read/write register at $C068 containing eight commonly used standard Apple II soft switches[cite: 364, 371]. [cite\_start]The single-byte format of the State register simplifies interrupt handling[cite: 365]. [cite\_start]Storing this byte before executing interrupt routines allows you to restore the system soft switches quickly after returning from the interrupt[cite: 366].

> **Warning**
> [cite\_start]Be careful when changing bits within this register[cite: 369]. [cite\_start]Use only a read-modify-write instruction sequence when manipulating bits[cite: 369].

### [cite\_start]Figure 3-5 State register at $C068 [cite: 371]

| Bit | Name |
| :-- | :--- |
| 7 | [cite\_start]ALTZP [cite: 378] |
| 6 | [cite\_start]PAGE 2 [cite: 379] |
| 5 | [cite\_start]RAMRD [cite: 380] |
| 4 | [cite\_start]RAMWRT [cite: 381] |
| 3 | [cite\_start]RDROM [cite: 382] |
| 2 | [cite\_start]LCBNK2 [cite: 383] |
| 1 | [cite\_start]ROMBANK [cite: 384] |
| 0 | [cite\_start]INTCXROM [cite: 385] |

### [cite\_start]Table 3-2 Bits in the State register [cite: 389]

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
[cite\_start][cite: 388]

## [cite\_start]Bank $01 (auxiliary memory) [cite: 392]

> [cite\_start]**Apple II note**: The following sections describe the operation of the auxiliary memory (bank $01) as it applies to programs originally written for the Apple IIc or for 128K versions of the Apple IIe[cite: 393]. [cite\_start]Programs written specifically for the Apple IIGS don't normally use bank $01 in this fashion[cite: 394].

[cite\_start]When display shadowing is on, some of the display modes use memory in bank $01[cite: 395]. [cite\_start]This includes half of the 80-column text display, half of each of the Double Hi-Res graphics display pages, and all of the Super Hi-Res display buffer, if shadowed[cite: 396].

> **Warning**
> [cite\_start]Do not attempt to switch in the auxiliary memory from a BASIC program[cite: 399]. [cite\_start]If you switch to alternate memory in areas used by the BASIC interpreter, like the stack and direct page, it will fail and you must reset the system[cite: 400, 401].

[cite\_start]Auxiliary memory is divided into two large sections and one small one[cite: 403]. [cite\_start]The largest section is switched into the memory address space from $0200 through $BFFF[cite: 404]. [cite\_start]The other large section is the language-card space, switched into the memory address space from $D000 through $FFFF[cite: 411]. [cite\_start]The soft switches for the language-card memory do not change when you switch to auxiliary RAM[cite: 431]. [cite\_start]When you switch in the auxiliary RAM in the language-card space, you also switch in the first two pages, from $0000 through $01FF[cite: 434]. [cite\_start]This area contains the direct page and the 65C816 stack when in 6502 emulation mode[cite: 435].

### [cite\_start]Bank switching for auxiliary memory [cite: 437]

[cite\_start]Switching the 48K section of memory is done by two soft switches: `RDMAINRAM` and `RDCARDRAM` select main or auxiliary memory for reading, and `WRMAINRAM` and `WRCARDRAM` select it for writing[cite: 438]. [cite\_start]Enabling read and write functions independently allows a program fetching instructions from one memory space to store data into the other[cite: 440].

> **Warning**
> [cite\_start]Do not use these switches without careful planning[cite: 442]. [cite\_start]Careless switching between main and auxiliary memories is almost certain to have catastrophic effects[cite: 442].

### [cite\_start]Table 3-3 Auxiliary-memory select switches [cite: 453, 454]

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
[cite\_start][cite: 455]

[cite\_start]When `SET80COL` is enabled, `TXTPAGE2` and `TXTPAGE1` select main or auxiliary display memory[cite: 456]. [cite\_start]When `SET80COL` is enabled, `HIRES` and `LORES` allow you to use `TXTPAGE2` and `TXTPAGE1` to switch between the Hi-Res Page 1 area in main or auxiliary memory[cite: 457]. [cite\_start]If you are using both auxiliary RAM control switches and auxiliary display page control switches, the display page control switches take priority[cite: 463].

[cite\_start]A single soft switch named `ALTZP` switches the bank-switched memory and the associated stack and direct-page area between main and auxiliary memory[cite: 468].

## [cite\_start]Banks $E0 and $E1 [cite: 476]

[cite\_start]Banks $E0 and $E1 are controlled by the Mega II[cite: 477]. [cite\_start]These banks contain the display buffers, so they must run at the standard 1.024-MHz speed[cite: 479]. [cite\_start]Because these banks are broken up by special allocations, they are a logical place for working storage used by the toolbox and other firmware programs[cite: 480]. [cite\_start]Using banks $E0 and $E1 for these purposes leaves the higher-speed memory in low-numbered banks for applications[cite: 481]. [cite\_start]In banks $E0 and $E1, language-card mapping, I/O space, and display buffers are always active[cite: 484, 485].

### [cite\_start]The display buffers [cite: 508]

[cite\_start]The display buffers are permanently assigned to locations in banks $E0 and $E1 because they are tied directly to the Mega II IC that generates the display signals[cite: 509]. [cite\_start]Display-memory shadowing allows old-style Apple II programs that store display data in banks $00 and $01 to run[cite: 510].

  * [cite\_start]**Text/Lo-Res**: The primary text and Lo-Res graphics display buffers occupy memory locations $0400 through $07FF in banks $E0 and $E1[cite: 512]. [cite\_start]The 1024-byte area in bank $E0 is text Page 1, used for 40-column text mode[cite: 513]. [cite\_start]80-column text display uses text Page 1 locations in both bank $E0 and bank $E1[cite: 514].
  * [cite\_start]**Text Page 2**: The alternate text buffer, occupies locations $0800 through $0BFF[cite: 518].
  * [cite\_start]**Hi-Res**: There are two Hi-Res graphics buffers, each 8K[cite: 521]. [cite\_start]Page 1 is at $2000-$3FFF in bank $E0, and Page 2 is at $4000-$5FFF in bank $E0[cite: 522, 523].
  * [cite\_start]**Double Hi-Res**: These buffers require 16384 bytes each[cite: 524]. [cite\_start]Page 1 is at $2000-$3FFF in banks $E0 and $E1[cite: 525]. [cite\_start]Page 2 is at $4000-$5FFF in banks $E0 and $E1[cite: 526].
  * [cite\_start]**Super Hi-Res**: This buffer occupies 32K of memory at locations $2000 through $9FFF in bank $E1[cite: 527]. [cite\_start]It does not use space in bank $E0[cite: 528].

[cite\_start]Programs should call on the Memory Manager to allocate space for data storage, as it keeps track of available display spaces[cite: 530].

### [cite\_start]Firmware workspace [cite: 532]

[cite\_start]Banks $E0 and $E1 are the logical place for working storage used by the toolbox and other system programs because they are always broken up by display buffers[cite: 533]. [cite\_start]System programs that use RAM in banks $E0 and $E1 include the Monitor, desk accessories, the Memory Manager, the Tool Locator, the Apple Desktop Bus tool set, and the AppleTalk driver[cite: 535, 536, 537, 538, 539, 540, 541].

> **Warning**
> [cite\_start]To avoid conflicts with built-in programs that use RAM areas in banks $E0 and $E1, applications must not use these areas and should instead request memory from the Memory Manager[cite: 547, 548, 549].

## [cite\_start]Apple II program memory use [cite: 550]

[cite\_start]For programs written for earlier Apple II models to run on an Apple IIGS, all of the Apple II features must be present in banks $00 and $01, which correspond to main and auxiliary memory[cite: 553]. [cite\_start]With the 65C816 microprocessor in emulation mode and shadowing set appropriately, all standard features are present[cite: 556]. These features include:

  * [cite\_start]direct (zero) page, from $0000 to $00FF of bank $00 [cite: 557]
  * [cite\_start]stack, from $0100 to $01FF of bank $00 [cite: 558]
  * [cite\_start]text Page 1, from $0400 to $07FF of both banks [cite: 559]
  * [cite\_start]text Page 2, from $0800 to $0BFF of both banks (available in the 1 MB Apple IIGS only) [cite: 560]
  * [cite\_start]Hi-Res graphics Page 1, from $2000 to $3FFF of bank $00 [cite: 561]
  * [cite\_start]Hi-Res graphics Page 2, from $4000 to $5FFF of bank $00 [cite: 562]
  * [cite\_start]Double Hi-Res graphics Page 1, from $2000 to $3FFF of both banks [cite: 563]
  * [cite\_start]Double Hi-Res graphics Page 2, from $4000 to $5FFF of both banks [cite: 564]
  * [cite\_start]I/O space, from $C000 to $CFFF of either bank [cite: 565]
  * [cite\_start]language-card space, from $D000 to $FFFF of both banks [cite: 566]

## [cite\_start]Shadowing [cite: 570]

[cite\_start]The Apple IIGS display buffers are in banks $E0 and $E1[cite: 571]. [cite\_start]For compatibility with standard Apple II programs, shadowing must be switched on for the display buffers they need[cite: 572].

### [cite\_start]Screen holes [cite: 574]

[cite\_start]When shadowing is on for text Page 1, programs and peripheral cards that use the text Page 1 locations known as screen holes run normally[cite: 575].

## [cite\_start]Memory expansion [cite: 577]

[cite\_start]The original Apple IIGS has 256K of RAM and 128K of ROM built in, while the 1 MB model has 1 MB RAM and 256K of ROM[cite: 578]. [cite\_start]Memory can be expanded to a total of 5 MB of RAM and 1 MB of ROM[cite: 579]. [cite\_start]While expansion up to 8 MB of RAM is possible via the memory expansion slot, complications with memory support logic make it impractical[cite: 580]. [cite\_start]The hardware and firmware are designed to support a 5 MB maximum memory space[cite: 581].

### [cite\_start]The memory expansion slot [cite: 583]

[cite\_start]The memory expansion slot allows for adding a memory card with up to 4 MB of RAM and 786K of ROM[cite: 584]. [cite\_start]The slot is only for additional memory[cite: 585]. [cite\_start]RAM cards of 1 MB or 4 MB can be made using 256K or 1 MB rows of RAM ICs[cite: 586].

### [cite\_start]Memory expansion signals [cite: 589]

[cite\_start]The memory expansion slot provides signals to support dynamic RAM and additional signals for ROM decoding[cite: 590].

### [cite\_start]Table 3-4 Memory-card interface signals [cite: 596, 597]

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
[cite\_start][cite: 598]

### [cite\_start]Extended RAM [cite: 599]

[cite\_start]Up to 4 MB of RAM can be installed in the extended memory card[cite: 600]. [cite\_start]This memory corresponds to 64 banks of 64K each[cite: 601]. [cite\_start]The memory on the card is organized as 4 rows of 8 ICs each[cite: 602]. [cite\_start]Using 256-kilobit-by-1-bit RAMs, each row holds 256K for a total of 1 MB; with 1-megabit by 1-bit RAMs, each row holds 1 MB for a total of 4 MB[cite: 603, 604]. [cite\_start]Memory expansion cards larger than 4 MB are not recommended because locations beyond 4 MB cannot be accessed via direct memory access (DMA) and require on-board memory refresh support[cite: 606, 607].

[cite\_start]The FPI provides `/CRAS` (card row address strobe), `/CCAS` (card column address strobe), `CROW0` (card row select 0), and `CROW1` (card row select 1) signals to control RAM rows[cite: 608].

### [cite\_start]Extended RAM mapping [cite: 614]

[cite\_start]A 1 MB expansion card is enabled for accesses in banks $2 through $80 in the 256K system, and banks $10 through $80 in the 1 MB system[cite: 624]. [cite\_start]The card provides 1 MB of actual RAM (banks $2 through $11 in the 256K system, and banks $10 through $19 in the 1 MB system)[cite: 625]. [cite\_start]This method of card selection causes multiple images or "ghosts" of the RAM areas[cite: 628].

[cite\_start]The MSIZE signal flags the type of memory chips on the expansion card[cite: 620, 621]. [cite\_start]If the MSIZE pin is not connected (for 256-kilobit RAMs), the FPI multiplexes 18 address bits[cite: 622]. [cite\_start]If it is tied to ground (for 1-megabit RAMs), the FPI multiplexes 20 address bits[cite: 623].

### [cite\_start]Extended ROM [cite: 630]

[cite\_start]Additional ROM space is available in banks $F0 through $FD ($F0 through $FB on the 1MB logic board)[cite: 631]. [cite\_start]This requires an additional bank-address latch-decoder on the memory card[cite: 632]. [cite\_start]The FPI provides a `CROMSEL` signal that selects one bank, but the card must provide additional decoding to select individual ROMs within that bank[cite: 633, 634].

### [cite\_start]Address multiplexing [cite: 713]

[cite\_start]The FPI multiplexes RAM addresses onto eight, nine, or ten RAM address lines to support 64-kilobit, 256-kilobit, or 1-megabit RAM ICs[cite: 714]. [cite\_start]On the 256K Apple IIGS, the main logic board RAMs are 64-kilobit chips[cite: 715]. [cite\_start]On the 1 MB Apple IIGS, they are 1-megabit chips[cite: 716]. [cite\_start]The RAM expansion slot can support cards with 256-kilobit-by-1-bit, 256-kilobit-by-4-bit, 1-megabit-by-1-bit, or 1-megabit-by-4-bit RAMs[cite: 717]. [cite\_start]The MSIZE signal from the card indicates the word size of the RAMs[cite: 718].
