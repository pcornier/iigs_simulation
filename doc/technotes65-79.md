Here are the Apple IIGS Technical Notes, converted to Markdown format.

-----

### Apple IIGS Technical Note \#65: Control-^ is Harder Than It Looks

[cite\_start]**Written by:** Dave Lyons [cite: 5]
[cite\_start]**Date:** September 1989 [cite: 6]

[cite\_start]This Technical Note describes a problem using Control-^ to change the text cursor with programs that use GETLN. [cite: 7]

[cite\_start]On the Apple IIGS, typing Control-^ changes the cursor to the next character typed. [cite: 8] [cite\_start]This feature works correctly from the keyboard, but there is an issue when programs print the control sequence. [cite: 9]

[cite\_start]To demonstrate this problem, enter the following from AppleSoft: [cite: 10]

```basic
[cite_start]NEW [cite: 11]
[cite_start]PRINT CHR$(30);"_" [cite: 12]
```

[cite\_start]This changes the cursor into a blinking underscore, as expected. [cite: 13] [cite\_start]But now enter the following: [cite: 14]

```basic
12345 HOME
LIST
```

[cite\_start]You should see `2345 HOME`, which shows that the first character is ignored. [cite: 15] [cite\_start]This is a problem with GETLN, which AppleSoft uses to read each line of input. [cite: 16] [cite\_start]Even if your program does not use this routine, you should be aware of this problem since it will occur the next time another program uses GETLN. [cite: 17]

[cite\_start]Since changing the cursor works fine when done from the keyboard, the workaround is to have your program simulate the appropriate keypresses for GETLN. [cite: 18]

```assembly
[cite_start]301: CLD [cite: 19]
[cite_start]302: STA ($28),Y [cite: 20]             [cite_start]; remove cursor if present [cite: 29]
[cite_start]304: LDY $0300 [cite: 21]               [cite_start]; get index into simulated-keys list [cite: 30]
[cite_start]307: LDA $310, Y [cite: 22]             [cite_start]; get a simulated keypress [cite: 31]
[cite_start]30A: INC $0300 [cite: 23]               [cite_start]; point to the next key for next time [cite: 32]
[cite_start]30B: RTS [cite: 24]                     [cite_start]; return the key to GETLN [cite: 33]
[cite_start]310: 9E DF 8D[cite: 25]; [cite_start]Ctrl-^, underscore, return [cite: 34]
```

```basic
[cite_start]100 POKE 768,0 [cite: 26]
110 INPUT ""; [cite_start]AS [cite: 27]              [cite_start]; required by BASIC.SYSTEM [cite: 28]
    PRINT CHR$(4); [cite_start]"IN#A$301" REM Start getting simulated keys [cite: 35]
120 PRINT CHR$(4); [cite_start]"IN#0" REM Get real keys again [cite: 36]
```

[cite\_start]From an assembly-language program, the equivalent of `IN#A$301` is storing $01 and $03 in locations $38 and $39, while the equivalent of `INPUT` is `JSR $FD6A` (GETLN). [cite: 37] (Store a harmless prompt character, like $80, into location $33 first.) [cite\_start][cite: 38]

**Further Reference**

  * Apple IIGS Firmware Reference, p. [cite\_start]77 [cite: 44]

-----

### Apple IIGS Technical Note \#66: ExpressLoad Philosophy

[cite\_start]**Written by:** Matt Deatherage [cite: 55]
[cite\_start]**Revised by:** Matt Deatherage [cite: 54]
[cite\_start]**Date:** September 1989, Revised May 1992 [cite: 53]

[cite\_start]This Technical Note discusses the ExpressLoad feature and how it relates to the standard Loader and your application. [cite: 56]

[cite\_start]**Changes since September 1990:** Clarified some changes now that ExpressLoad and the System Loader are combined to be "Loader 4.0" in System Software 6.0. [cite: 57] [cite\_start]Completely removed the note about not calling Close(0) since it's not relevant. [cite: 58]

#### Speedy the Loader Helper

[cite\_start]ExpressLoad is a GS/OS feature which is usually present with System Software 5.0 (if the ExpressLoad file is present and there's more than 512K of RAM), and always on System Software 5.0.4 and later. [cite: 60] [cite\_start]In System Software 6.0, ExpressLoad is no longer a separate file; it's included in the System Loader version 4.0. [cite: 61, 62] [cite\_start]Even though ExpressLoad is part of the Loader, we refer to its functionality separately to distinguish how the Loader takes special advantage of "expressed" files. [cite: 62]

[cite\_start]ExpressLoad operates on Object Module Format (OMF) files which have been "expressed," using either the APW tool Express (or its MPW counterpart, ExpressIIGS) or created that way by a linker. [cite: 63] [cite\_start]Expressed files contain a dynamic data segment named either `ExpressLoad` or `-ExpressLoad` at the beginning of the file. [cite: 64] (Current versions of Express and ExpressIIGS create `-ExpressLoad` segments, which is the preferred naming convention; older versions created `ExpressLoad` segments, and should be re-Expressed for future compatibility.) [cite\_start][cite: 65] [cite\_start]This segment contains information that allows the Loader to load these files more quickly, including file offsets to segment headers, mappings of old segment numbers to new ones, and file offsets to relocation dictionaries. [cite: 65]

#### Two Loader Components, Two Missions, One Function

[cite\_start]The System Loader's function is to interpret OMF. [cite: 67] [cite\_start]It transforms files from load files into relocated 65816 code. [cite: 67] [cite\_start]It does this in a very straightforward way. [cite: 68] [cite\_start]For example, when it sees an instruction to right-shift a value *n* times, it loads a register and performs a right-shift *n* times. [cite: 69]

[cite\_start]ExpressLoad has a different mission. [cite: 70] [cite\_start]It relies on the System Loader to handle OMF in a straightforward fashion so it can concentrate on handling the most common OMF cases in the fastest possible way. [cite: 70] [cite\_start]For example, when asked for a specific segment in a load file, the System Loader "walks" the OMF until it finds the desired segment. [cite: 71] [cite\_start]ExpressLoad, however, goes directly to the desired segment since an Expressed file contains precalculated offsets to each segment in the `ExpressLoad` segment. [cite: 72]

[cite\_start]Since ExpressLoad focuses on common operations, it may not support applications that rely on certain features of OMF or the System Loader. [cite: 77] [cite\_start]In these cases, the System Loader loads the file as expected. [cite: 78] [cite\_start]ExpressLoad always gets the first chance to load a file, and if it is an Expressed file that ExpressLoad can handle, it loads it. [cite: 79] [cite\_start]If the file is not an Expressed file, the regular System Loader loads it instead. [cite: 80] [cite\_start]Because an Expressed file is a standard OMF file with an additional segment, they are almost fully compatible with the System Loader (though it cannot load them any faster). [cite: 82]

#### Working With ExpressLoad

[cite\_start]Most applications work seamlessly with ExpressLoad; however, there are some potential problems to be aware of. [cite: 85, 86]

  * [cite\_start]Don't mix Expressed files and normal OMF files with the same user ID. [cite: 87] [cite\_start]For example, if your application uses InitialLoad with a separate file, make sure that if it and your main application share the same user ID that they are both either Expressed files or normal OMF files. [cite: 88]
  * [cite\_start]Don't use a user ID of zero. [cite: 89] [cite\_start]Previously, zero told the System Loader to use the current user ID; however, now both the System Loader and ExpressLoad have a current user ID. [cite: 89, 90] [cite\_start]Be specific about user IDs when loading. [cite: 90] [cite\_start]This is fixed in 6.0, but is still a good thing to avoid for compatibility with System Software 5.0 through 5.0.4. [cite: 91]
  * [cite\_start]Avoid loading and unloading segments by number. [cite: 92] [cite\_start]Since Expressed files may have their segments rearranged, if an Expressed file is loaded by the System Loader, references to segments by number may be incorrect. [cite: 92]
  * [cite\_start]Avoid using GetLoadSegInfo before System Software 6.0. [cite: 93] [cite\_start]This call returns System Loader data structures which are not supported by ExpressLoad prior to 6.0. [cite: 93] [cite\_start]In System Software 6.0 and later, the combined Loaders return correct information for this call regardless of whether the load file is expressed or not. [cite: 94]
  * [cite\_start]Don't try to load segments in files which have not been loaded with the call InitialLoad. [cite: 95] [cite\_start]This was never a good idea and is now likely to cause problems. [cite: 96]
  * [cite\_start]Don't have segments that link to other files. [cite: 97] [cite\_start]ExpressLoad does not support this type of link. [cite: 97]

**Further Reference**

  * [cite\_start]GS/OS Reference [cite: 99]

-----

### Apple IIGS Technical Note \#67: LaserWriter Font Mapping

[cite\_start]**Written by:** Suki Lee & Jim Luther [cite: 110]
[cite\_start]**Revised by:** Matt Deatherage [cite: 109]
[cite\_start]**Date:** September 1989, Revised May 1992 [cite: 111]

[cite\_start]This Technical Note discusses the methods used by the Apple IIGS Print Manager to map IIGS fonts to the PostScript® fonts available with an Apple LaserWriter printer. [cite: 112]

[cite\_start]**Changes since November 1989:** Corrected typographical errors and added Carta and Sonata, two fonts the LaserWriter driver knows about but aren't built into any LaserWriter. [cite: 113]

[cite\_start]Version 2.2 and earlier of the Apple IIGS LaserWriter driver depend solely upon font family numbers as unique font identifiers. [cite: 114] [cite\_start]A table built into the driver maps known font family numbers to the built-in LaserWriter family fonts. [cite: 115] [cite\_start]Any fonts not built-in are created in the printer from its bitmap font strike. [cite: 116] [cite\_start]Under this implementation, all font family numbers not known when the driver was written print using bitmap fonts. [cite: 117] [cite\_start]This driver knows nothing of any other fonts which may reside in the printer. [cite: 118]

[cite\_start]The Apple IIGS LaserWriter driver version 3.0 and later makes use of most resident PostScript fonts in the LaserWriter. [cite: 122] [cite\_start]If the font is not available, then the bitmap font is used. [cite: 123] [cite\_start]At the start of a job, the driver queries the printer for the font directory listing, which consists of the names of all fonts in the printer (built-in or downloaded). [cite: 124, 125] [cite\_start]This information is kept locally for look up using the name of the requested font. [cite: 126] [cite\_start]Currently there is no way to download a PostScript font with an Apple IIGS. [cite: 121]

#### Issues

[cite\_start]All Apple IIGS fonts contain a family name and a family number. [cite: 128] [cite\_start]The Apple IIGS currently identifies fonts using the family number; however, this may change in the future. [cite: 129, 130] [cite\_start]PostScript identifies its fonts by name (case sensitive) and knows nothing of any font family numbering system. [cite: 131] [cite\_start]Most PostScript font families include plain, bold, italic, and bold italic fonts. [cite: 137] [cite\_start]Font names are generally created by adding a style suffix to the base family name, but there is no uniform naming method. [cite: 139, 140]

[cite\_start]**Table 1 - Example Font Names** [cite: 148]
| Style | Helvetica | Times | AvantGarde |
| :--- | :--- | :--- | :--- |
| **plain** | Helvetica | Times-Roman | AvantGarde-Book |
| **bold** | Helvetica-Bold | Times-Bold | AvantGarde-Demi |
| **italic** | Helvetica-Oblique | Times-Italic | AvantGarde-BookOblique |
| **bold italic** | Helvetica-BoldOblique | Times-BoldItalic | AvantGarde-DemiOblique |

[cite\_start]There are no resources similar to the Macintosh 'FOND' resource on the Apple IIGS, which means the Apple IIGS LaserWriter driver has no way to match PostScript fonts to Apple IIGS fonts. [cite: 151] [cite\_start]Instead, the driver has full knowledge of all LaserWriter built-in fonts (plus Carta and Sonata) and uses the correct name for all style variations. [cite: 153] [cite\_start]For all other fonts, the driver uses a standard set of suffixes for style modifications: `-Bold`, `Italic`, and `-BoldItalic`. [cite: 154, 155] [cite\_start]The appropriate suffix is appended to the font's family name, and this name is used to search the font directory table obtained from the printer. [cite: 155] [cite\_start]If a match is found, the document is printed using the corresponding PostScript font. [cite: 156] [cite\_start]If no match is found, the driver tries to find the plain form of the font and creates the style modification in PostScript. [cite: 157] [cite\_start]If both searches fail, a bitmap of the font is downloaded to the printer. [cite: 158]

[cite\_start]If you intend for your application to take advantage of PostScript fonts, ensure you provide an Apple IIGS font whose family name is identical to the PostScript font family name. [cite: 159]

[cite\_start]**Table 2 - Built-in LaserWriter Fonts** [cite: 165]
| [cite\_start]All LaserWriters [cite: 160] | [cite\_start]LaserWriter Plus and LaserWriter II [cite: 162] | |
| :--- | :--- | :--- |
| Courier | AvantGarde | Palatino |
| Carta | Bookman | Symbol |
| Helvetica | Courier | Times |
| Sonata | Helvetica | ZapfChancery |
| Symbol | Helvetica-Narrow | ZapfDingbats |
| Times | NewCenturySchlbk | |

**Trademarks**

  * [cite\_start]Carta is a trademark of Adobe Systems Incorporated. [cite: 170]
  * [cite\_start]PostScript and Sonata are registered trademarks of Adobe Systems Incorporated. [cite: 171]
  * [cite\_start]Helvetica®, Palatino®, and Times® are registered trademarks of Linotype Co. [cite: 172]
  * [cite\_start]ITC Avant Garde®, ITC Bookman®, ITC Zapf Chancery®, and ITC Zapf Dingbats® are registered trademarks of International Typeface Corporation. [cite: 172]

**Further Reference**

  * [cite\_start]Apple IIGS Toolbox Reference, Volumes 1 & 2 [cite: 169]
  * [cite\_start]Apple LaserWriter Reference [cite: 169]

-----

### Apple IIGS Technical Note \#70: Fast Graphics Hints

[cite\_start]**Written by:** Don Marsh & Jim Luther [cite: 597]
[cite\_start]**Date:** September 1989 [cite: 600]

[cite\_start]This Technical Note discusses techniques for fast animation on the Apple IIGS. [cite: 599]

[cite\_start]QuickDraw II is a very generalized way to draw to the Super Hi-Res screen, but its overhead makes it unacceptable for all but simple animations. [cite: 601, 602] [cite\_start]If you bypass QuickDraw II, your application has to write pixel data directly to the Super Hi-Res graphics display buffer. [cite: 603] [cite\_start]It also has to control the New-Video register at $C029, and set up the scan-line control bytes and color palettes. [cite: 604] [cite\_start]Chapter 4 of the *Apple IIGS Hardware Reference* documents the graphics display buffer and how its components are used. [cite: 605] [cite\_start]The techniques described here should be used with discretion; we do not recommend bypassing the Toolbox unless absolutely necessary. [cite: 606]

#### Map the Stack Onto Video Memory

[cite\_start]To achieve the fastest screen updates, you must remove all unnecessary overhead from the instructions that write to graphics memory. [cite: 608] [cite\_start]The obvious method uses an index register, which must be incremented or decremented between writes. [cite: 609] [cite\_start]These operations can be avoided by using the stack. [cite: 610] [cite\_start]Each time a byte or word is pushed onto the stack, the stack pointer is automatically decremented, which is faster than an indexed store followed by a decrement. [cite: 610, 611]

[cite\_start]The stack can be located in bank $01 by writing to the `WrCardRAM` auxiliary-memory select switch at $C005. [cite: 613] [cite\_start]Bank $01 is shadowed into $E1 by clearing bit 3 of the Shadow register at $C035. [cite: 614] [cite\_start]Under these conditions, if the stack pointer is set to $3000, the next byte pushed is written to $013000, then shadowed into $E13000. [cite: 615] [cite\_start]The stack pointer is automatically decremented, setting the stage for the next write to $E12FFF. [cite: 16]

[cite\_start]**Warning:** While the stack is mapped into bank $01, you may not call any firmware, toolbox or operating system routines (ProDOS 8 or GS/OS). [cite: 618]

#### Unroll All Loops

[cite\_start]Another source of overhead is branching instructions in loops. [cite: 625] [cite\_start]By "straight-lining" the code to move a scan-line's worth of memory at one time, branch instructions are avoided. [cite: 625]

```assembly
[cite_start]; accumulator is 16 bits for best efficiency [cite: 634]
    [cite_start]lda    164,y [cite: 631, 632]
    [cite_start]pha [cite: 633]
    [cite_start]lda    162,y [cite: 635, 636]
    [cite_start]pha [cite: 637]
    [cite_start]lda    160,y [cite: 638, 639]
    [cite_start]pha [cite: 640]
```

[cite\_start]In this example, the Y register points to the data, and hard-coded offsets are used to avoid register operations between writes. [cite: 641]

#### Hard-Code Instructions and Data

[cite\_start]For desperate circumstances, overhead can be removed from the previous example by hard-coding pixel data into your code instead of loading it from a separate data space. [cite: 643, 644] [cite\_start]If you are writing an arbitrary pattern of three or fewer constant values, the following method is the fastest known: [cite: 645]

```assembly
    [cite_start]lda    #val1 [cite: 646, 647]
    [cite_start]ldx    #val2 [cite: 648, 649]
    [cite_start]ldy    #val3 [cite: 650, 651]
    [cite_start]pha          ; arbitrary pattern of pushes [cite: 652, 653]
    [cite_start]phx [cite: 654]
    [cite_start]phy [cite: 655]
    [cite_start]phy [cite: 656]
    [cite_start]phx [cite: 657]
```

[cite\_start]Where many different values must be written, pixel data can be written using immediate push instructions: [cite: 658]

```assembly
[cite_start]; some arbitrary pixel values [cite: 659]
    [cite_start]pea    $5389 [cite: 660, 661]
    [cite_start]pea    $2378 [cite: 662, 663]
    [cite_start]pea    $A3C1 [cite: 664, 665]
    [cite_start]pea    $39AF [cite: 666, 667]
```

[cite\_start]Your program can generate this mixture of PEA instructions and pixel data, or it could load pixel data that already has PEA instructions intermixed. [cite: 668]

#### Be Aware of Slow-Side and Fast-Side Synchronization

[cite\_start]Estimating execution speed is tricky when writing to graphics memory, which resides on the 1 MHz "slow side" of the IIGS system. [cite: 670, 671] [cite\_start]All writes to this memory require the "fast side" to synchronize with the "slow side," a process handled automatically by the Fast Processor Interface (FPI) chip. [cite: 671, 672] [cite\_start]Animation programmers must worry about these synchronization delays, as slight code changes can affect their frequency and the program's speed. [cite: 673]

[cite\_start]A careful analysis leads to the following tables for estimating speed based on cycles consumed during consecutive write instructions. [cite: 680, 681] [cite\_start]For example, a series of PEA instructions requires five cycles for each 16-bit write. [cite: 682]

| Fast Cycles per Write (byte) | Actual Speed ($\\mu$sec./byte) |
| :--- | :--- |
| [cite\_start]3 to 5 [cite: 686] | [cite\_start]2.0 [cite: 687] |
| [cite\_start]6 to 8 [cite: 688] | [cite\_start]3.0 [cite: 689] |
| [cite\_start]9 to 11 [cite: 690] | [cite\_start]4.0 [cite: 691] |

| Fast Cycles per Write (word) | Actual Speed ($\\mu$sec./word) |
| :--- | :--- |
| [cite\_start]4 to 6 [cite: 693] | [cite\_start]3.0 [cite: 696] |
| [cite\_start]7 to 8 [cite: 694] | [cite\_start]4.0 [cite: 697] |
| [cite\_start]9 to 11 [cite: 695] | [cite\_start]5.0 [cite: 698] |

[cite\_start]These times apply only if the same number of fast cycles separate each consecutive write. [cite: 699] [cite\_start]The first write in a set usually takes longer due to the initial synchronization. [cite: 700] [cite\_start]Memory refresh also causes unpredictable delays, affecting byte-wide writes more often than word-wide writes. [cite: 701] [cite\_start]Therefore, it is usually preferable to use word-wide writes. [cite: 702]

#### Use Change Lists

[cite\_start]It is not possible to perform full-screen updates in the time it takes the IIGS to scan the entire screen. [cite: 705] [cite\_start]It is necessary to update only those pixels which have changed from the previous frame. [cite: 707] [cite\_start]One method is to precalculate the pixels that change by comparing each frame against the previous one. [cite: 708] [cite\_start]For interactive animation, fast methods must be developed to predict which areas of the screen need updating. [cite: 709]

#### Using the Video Counters

[cite\_start]For "tear-free" screen updates, it is necessary to monitor the location of the scan-line beam. [cite: 711] [cite\_start]The `VertCnt` and `HorizCnt` video counter registers at $C02E-C02F allow you to determine which scan line is currently being drawn. [cite: 712] [cite\_start]By using only the `VertCnt` register and ignoring the low bit of the 9-bit vertical counter in `HorizCnt`, you can determine the scan line within 2 lines. [cite: 717] [cite\_start]The `VertCnt` register contains the current scan line number divided by two, offset by $80. [cite: 718] [cite\_start]For example, if the beam was on scan line four or five, `VertCnt` would contain $82. [cite: 719] [cite\_start]Vertical blanking occurs during `VertCnt` values $7D through $7F and $E4 through $FF. [cite: 720]

[cite\_start]Clever updates can modify twice as many pixels by running at 30 frames per second instead of 60. [cite: 725] The technique is:

1.  [cite\_start]Wait for the scan line beam to reach the first scan line. [cite: 726]
2.  [cite\_start]Start updates from the top of the screen, staying ahead of the beam. [cite: 727]
3.  [cite\_start]Continue updates as the beam progresses to the bottom, goes into vertical blanking, and restarts at the top. [cite: 728]
4.  [cite\_start]Finish the update before the beam catches up. [cite: 729]
    [cite\_start]This method allows a frame to be updated during two screen scans instead of one. [cite: 730]

[cite\_start]**Note:** The main logic board's Mega II-VGC registers and interrupts are not synchronous to the Apple II Video Overlay Card and should not be used for time synchronization with it, but they can be used with the Apple IIGS video output. [cite: 732, 733]

#### Interrupts

[cite\_start]It is not possible to support interrupts while sustaining a high graphics update rate without accepting jerkiness or tearing. [cite: 736] [cite\_start]Be aware that many system activities like GS/OS and AppleTalk depend on interrupts and will not function if they are disabled. [cite: 737]

**Further Reference**

  * [cite\_start]Apple IIGS Firmware Reference [cite: 739]
  * [cite\_start]Apple IIGS Hardware Reference [cite: 740]
  * [cite\_start]Apple II Video Overlay Card Development Kit [cite: 741]
  * [cite\_start]Apple IIGS Technical Note \#39, Mega II Video Counters [cite: 742]
  * [cite\_start]Apple IIGS Technical Note \#68, Tips for I/O Expansion Slot Card Design [cite: 744]

-----

### Apple IIGS Technical Note \#71: DA Tips and Techniques

[cite\_start]**Written by:** Dave Lyons [cite: 753]
[cite\_start]**Revised by:** Dave "Mr. Tangent" Lyons [cite: 752]
[cite\_start]**Date:** November 1989, Revised May 1992 [cite: 755, 754]

[cite\_start]This Technical Note presents tips and techniques for writing Desk Accessories. [cite: 756]

[cite\_start]**Changes since December 1991:** Reworked discussion of NDAs and Command-keystrokes. [cite: 757] [cite\_start]Marked obsolete steps in "NDAs Can Have Resource Forks." [cite: 757]

#### Classic Desk Accessory (CDA) Tips and Techniques

**Reading the Keyboard**

  * [cite\_start]**For GS/OS only CDAs:** The Console Driver is the best choice. [cite: 760]
  * [cite\_start]**Other CDAs:** You must handle two cases: the Event Manager may or may not be started. [cite: 761] [cite\_start]You can call `EMStatus` to check. [cite: 763]
      * [cite\_start]**Event Manager active:** Call `GetNextEvent` to read keypresses. [cite: 764]
      * [cite\_start]**Event Manager not active:** Read keys directly from the keyboard hardware by waiting for bit 7 of location $E0C000 to turn on. [cite: 765] [cite\_start]The lower seven bits represent the key. [cite: 766] [cite\_start]After detecting a keypress, write to location $E0C010 to clear the buffer. [cite: 767]

**Just One Page of Stack Space**
[cite\_start]CDAs normally have only a single 256-byte page of stack space. [cite: 771] [cite\_start]Your CDA may or may not be able to allocate additional stack space from bank 0. [cite: 772] [cite\_start]If ProDOS 8 is active, your CDA cannot allocate additional space. [cite: 774] [cite\_start]The provided code in the source document shows a safe way to try to allocate more stack space. [cite: 773] [cite\_start]When the routine `RealCDAentry` is called, the carry flag is set if no extra stack space is available. [cite: 885] [cite\_start]If the carry is clear, additional space was allocated. [cite: 886] [cite\_start]Interrupts are disabled while the page-one stack is being restored. [cite: 896]

**Interrupts, Event Manager, Memory, and CDAs**
[cite\_start]When the user hits Apple-Ctrl-Esc, the internal behavior differs depending on whether the Event Manager is active. [cite: 899, 900]

  * [cite\_start]**Event Manager Active:** This is normal for Desktop applications. [cite: 901] [cite\_start]Hitting Apple-Ctrl-Esc posts a `deskAcc` event. [cite: 901] [cite\_start]The CDA menu appears only when the application calls `GetNextEvent` or `EventAvail`. [cite: 902] [cite\_start]The CDA runs in the "foreground," and the Memory Manager can compact and purge memory for allocation requests. [cite: 903, 904]
  * [cite\_start]**Event Manager Not Active:** Hitting Apple-Ctrl-Esc either enters the CDA menu immediately (if the system Busy Flag is zero) or uses `SchAddTask` to make the menu appear later. [cite: 906] [cite\_start]If the menu appears during a `DECBUSYFLG` call, normal memory management is possible. [cite: 907] [cite\_start]However, if the Busy Flag was zero, the CDA menu appears inside an interrupt. [cite: 908] [cite\_start]In this case, the Memory Manager knows an interrupt is in progress, `CompactMem` takes no action, and memory allocation requests will not move unlocked blocks or purge purgeable blocks. [cite: 915]

#### New Desk Accessory (NDA) Tips and Techniques

**An NDA Can Find its Menu Item ID**
[cite\_start]After an application calls `FixAppleMenu`, an NDA can look at its menu item template in its header to find the menu ID for its name in the Apple menu. [cite: 923] [cite\_start]This can be useful for calls to `OpenNDA` or the Menu Manager. [cite: 924]

**NDAs and Command- Keystrokes**
[cite\_start]To provide a consistent way to close NDA windows, System 6.0 handles Command-W automatically for system windows. [cite: 928] [cite\_start]It calls `CloseNDAbyWinPtr` without the NDA or application seeing the event. [cite: 929] [cite\_start]However, an NDA can accept an `optionalCloseAction` code to handle the close request itself, allowing it to offer a cancel option to the user. [cite: 930, 931] [cite\_start]There is no way for an NDA to accept some keystrokes and pass others to applications. [cite: 933] [cite\_start]If your NDA does not want keystroke events, turn off the `eventMask` bits in the header to allow the application to receive them. [cite: 933]

**Calling InstallNDA From Within an NDA**
[cite\_start]It is possible for an NDA to install other NDAs. [cite: 935] [cite\_start]However, with System Software 5.0 and later, `InstallNDA` returns an error when called from an NDA because the Desk Manager's data structures are in use. [cite: 936, 937] [cite\_start]The solution is to use `SchAddTask` to postpone the `InstallNDA` call until the system is not busy. [cite: 938]

**Processing mouseUp Events**
[cite\_start]When an NDA's action routine receives a `mouseUp` event, it is not always safe to draw in its window. [cite: 941] [cite\_start]For example, when a user drags a window or chooses a menu item, the NDA receives the `mouseUp` event before the window is moved or the menu image is removed, and drawing at this time can cause a mess. [cite: 942, 948, 949] [cite\_start]The solution is to avoid drawing in direct response to a `mouseUp`. [cite: 950] [cite\_start]Instead, invalidate part of the window to force an update event to happen later. [cite: 951]

**NDAs Can Have Resource Forks**
[cite\_start]The recommended way for an NDA to use its resource fork is as follows: [cite: 957]

  * [cite\_start]**In the Open routine:** (Steps marked with an asterisk are obsolete with System 6.0+) [cite: 958]
    1.  [cite\_start]Call `GetCurResourceApp` and save the result. [cite: 959]
    2.  [cite\_start]If needed, call `MMStartUp` to get the NDA's Memory Manager user ID. [cite: 960]
    3.  [cite\_start]Call `ResourceStartUp` using the NDA's user ID. [cite: 961]
    4.  [cite\_start]Call `LGetPathname2` to get a pointer to the NDA's pathname. [cite: 962]
    5.  [cite\_start]\* Use `GetLevel` and `SetLevel` to protect your resource fork. [cite: 965]
    6.  [cite\_start]Use `GetSysPrefs` and `SetSysPrefs` to ensure the user is prompted to insert a disk if necessary. [cite: 967]
    7.  [cite\_start]Call `OpenResourceFile` and save the returned fileID. [cite: 969]
    8.  [cite\_start]Use `SetSysPrefs` to restore the original OS preferences. [cite: 971]
    9.  [cite\_start]\* Use `SetLevel` to restore the original file level. [cite: 972]
    10. [cite\_start]Call `SetCurResourceApp` with the value saved in step one. [cite: 973]
  * [cite\_start]**In the action routine:** No special calls are needed; the Desk Manager calls `SetCurResourceApp` automatically. [cite: 974]
  * **In the Close routine:**
    1.  [cite\_start]Call `CloseResourceFile` with the saved fileID. [cite: 977]
    2.  [cite\_start]Call `ResourceShutDown`. [cite: 978]

**NDAs Must Be Careful Handling Modal Windows**
[cite\_start]If your NDA uses its resource fork and calls `TaskMaster` for a modal window, be careful not to allow `TaskMaster` to update application windows. [cite: 985] [cite\_start]The application window's drawing routine assumes the application's resource path is current, but `TaskMaster` does not set it, which can lead to a system crash if the application's resources are not in the search path. [cite: 986, 987]

**Avoid Hard-Coding Your Pathname**
[cite\_start]If an NDA needs its own pathname, it should call `LGetPathname` or `LGetPathname2` with its User ID. [cite: 991] [cite\_start]This is better than hard-coding a path, as the user may move or rename the file. [cite: 992]

**Avoid Extra GetNewID calls**
[cite\_start]Normally, a Desk Accessory does not need to call `GetNewID`. [cite: 994] [cite\_start]Call `MMStartUp` to find your own User ID and use it. [cite: 995] [cite\_start]This conserves the limited supply of IDs and makes debugging easier. [cite: 997]

**Open is Not Called if NDA is Already Open**
[cite\_start]An NDA's Open routine is not called if the user chooses it from the Apple menu while it is already open. [cite: 999] [cite\_start]The Desk Manager simply calls `SelectWindow` on the existing window. [cite: 1000]

**Further Reference**

  * [cite\_start]Apple IIGS Toolbox Reference, Volumes 1-3 [cite: 1003]
  * [cite\_start]GS/OS Reference [cite: 1004]
  * [cite\_start]Apple IIGS Technical Note \#69, The Ins and Outs of Slot Arbitration [cite: 1011]

-----

### Apple IIGS Technical Note \#79: Integer Math Data Types

[cite\_start]**Written by:** Dan Strnad [cite: 2012]
[cite\_start]**Revised by:** Jim Luther [cite: 2010]
[cite\_start]**Date:** March 1990, Revised May 1990 [cite: 2011]

[cite\_start]This Technical Note describes the format of `Fixed` and `Frac` data types used by the Integer Math tool set. [cite: 2013] [cite\_start]The Integer Math tool set provides Integer, LongInt, Fixed, Frac, and Extended numerical data types. [cite: 2015]

[cite\_start]**Revised since March 1990:** Fixed original date, bit numbering of diagrams, and a multiplication sign in an equation. [cite: 2014]

#### Fixed Data Type

[cite\_start]The `Fixed` data type is a 32-bit signed value with 16 bits of fraction. [cite: 2022] [cite\_start]This means the low-order 16 bits are considered a fraction of $2^{16}$ ($$10000$). [cite: 2023] [cite\_start]It is equivalent to a long integer value where the binary point has been moved 16 places to the left. [cite: 2024]

  * The high-order word represents the integer part.
  * The low-order word represents the fractional part. [cite\_start]For example, a value of $$8000$ in the low-order part equals $1/2$. [cite: 2025]
  * [cite\_start]**Range:** -32768 to 32767 and $65,535/65,536$. [cite: 2026, 2027]

#### Frac Data Type

[cite\_start]The `Frac` data type is a 32-bit signed value with 30 bits of fraction. [cite: 2061] [cite\_start]The low-order 30 bits are considered a fraction of $2^{30}$ ($$40000000$). [cite: 2062] [cite\_start]This is like a long integer with the binary point moved 30 places to the left. [cite: 2063]

  * [cite\_start]The high-order 2 bits are treated as follows: the high bit has a value of -2, and the next bit has a value of 1. [cite: 2064, 2065]
  * [cite\_start]**Range:** -2 to 1 and $((2^{30})-1)/2^{30}$. [cite: 2065]

[cite\_start]For `LongInt`, `Fixed`, and `Frac` values, the hexadecimal representations of the largest and smallest values are $$7FFFFFFF$ and $$80000000$, respectively. [cite: 2093]

[cite\_start]A key property of `Fixed` and `Frac` data types is that two values of the same type can be added or subtracted as if they were 32-bit integers. [cite: 2094] [cite\_start]This works because of the distributive property of multiplication over addition: [cite: 2097]
$$\frac{(C \times V1) + (C \times V2)}{C} = \frac{C \times (V1 + V2)}{C} = V1 + V2$$
[cite\_start]Where $C$ is the scaling factor ($2^{16}$ for `Fixed` or $2^{30}$ for `Frac`). [cite: 2099] [cite\_start]Similarly, `Fixed` and `Frac` values can be compared just like `LongInts`. [cite: 2111]

**Further Reference**

  * [cite\_start]Apple IIGS Technical Reference Manual [cite: 2114]
  * [cite\_start]Apple Numerics Manual, Second Edition [cite: 2114]
