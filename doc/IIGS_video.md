# Chapter 4: The Video Displays

## Overview

The Apple IIGS can display several video modes. These include display modes that are compatible with the rest of the Apple II family (but with some enhancements to these existing modes) and some completely new display modes. These new video modes provide higher resolution, greater color flexibility, and greater programming ease than was previously available in the Apple II product line. This chapter describes:

- enhancements to the standard Apple II video modes
- new video features including the new video display modes

---

## Apple IIGS Display Features

The Apple IIGS brings new features to the existing Apple II video modes. These include:

- selectable screen border color
- selectable background color
- selectable text color
- selectable color or black-and-white composite video

These enhancements are described in this chapter. The new graphics modes—Super Hi-Res graphics and Color Fill mode—are also described in this chapter.

---

## Video from the Mega II IC

The Mega II generates all video information in standard Apple II video modes. The Mega II outputs a 4-bit linear-weighted **binary** code, which represents one of the 16 possible standard Apple II colors. This **digital** value is input into the Video Graphics Controller (VGC) and is used as a look-up address for an equivalent 12-bit resolution RGB color output value.

A digital-to-analog converter changes the 12-bit color code into three analog RGB video signals. The RGB output signals drive the video amplifiers and the NTSC video generator chip. The output of the video amplifier boosts the RGB signals, while the NTSC chip mixes the RGB and **sync signals**, resulting in a composite video signal.

---

## The Video Graphics Controller

The Video Graphics Controller (VGC) custom IC is responsible for generating all video output. The VGC provides these functions:

- takes standard Apple II video information from the Mega II and generates the video output
- adds enhancements to existing Apple II video modes
- supports the new video modes
- provides interrupt handling for two interrupt sources

---

The VGC generates all video output in all video modes, whereas the Mega II is responsible for maintaining the video RAM. All write operations to the video display buffers in bank $E0 and bank $E1 are done via the Mega II. Figure 4-1 shows the relationships of the VGC, Mega II, main RAM, and auxiliary RAM.

### Figure 4-1: Video components in the Apple IIGS

[*Diagram showing system architecture with Game port, Multiplexer, Slotmaker, Slots 1-7, Mega II with 128K RAM, Video Graphics Controller, Video amplifiers (Analog RGB video), NTSC generator (Composite video), Digital-to-analog converters, Serial Communications Controller, various memory components (128K or 256K ROM, 128K or 1MB RAM), and peripherals (Serial ports A & B, Disk port, ADB microcontroller, Retrofit keyboard, Apple Desktop Bus, Sound GLU, Ensoniq DOC, Audio amplifier, Speaker, External speaker)*]

---

## VGC Interrupts

Video display in the Apple IIGS is enhanced by VGC-generated interrupts. The VGC generates two internal interrupts: the one-second interrupt and the scan-line interrupt.

A 1-Hz input signal from the real-time clock (RTC) chip sets the one-second interrupt status bit. The scan-line interrupt occurs at the beginning of a video display scan line that has generate-interrupt bit set in the corresponding scan-line control byte. Scan-line interrupts are generated when the computer is operating in the Super Hi-Res video graphics modes only, and are not available in other video modes.

Figure 4-2 depicts the video screen, consisting of the text display area and the display border. The scan-line interrupt occurs at the beginning of the scan line, which is defined as the beginning of the right-hand border area.

### Figure 4-2: Scan-line interrupt

[*Diagram showing video display screen with text display area in center, border area around edges, and annotations showing "Scan-line interrupt occurs here for each scan line", "First scan line begins here", "And ends here"*]

---

## The VGC Interrupt Register

The VGC Interrupt register ($C023) contains a status bit and an enable bit for each of the two interrupts. When an interrupt occurs, the interrupt status bit for that interrupt is set. The VGC interrupt bit (bit 7) is set and the interrupt request (IRQ) line is asserted if the interrupt status bit *and* interrupt enable bit are set for one or more interrupts.

You enable an interrupt by writing to the appropriate positions in the VGC Interrupt register; the interrupt source hardware sets the status bits. Software can directly manipulate only the enable bits in the VGC Interrupt register; writing to the other bit positions has no effect. Figure 4-3 shows the format of the VGC Interrupt register. Table 4-1 gives a description of each register bit.

⚠️ **Warning**: Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

### Figure 4-3: VGC Interrupt register at $C023

| Bit | Name |
| :-- | :--- |
| 7 | VGC Interrupt status|
|6|      1-second Interrupt status|
 |5|     Scan-line Interrupt status|
 |4|     Reserved; do not modify|
 |3|     Reserved; do not modify|
|2|      1-second Interrupt enable|
|1|      Scan-line Interrupt enable|
|0|      Reserved; do not modify|



---

### Table 4-1: Bits in the VGC Interrupt register

| Bit | Value | Description |
|-----|-------|-------------|
| 7 | 1 | VGC interrupt status: This bit is set when the interrupt bit and the status bit are set for one or more of the interrupts. |
| | 0 | This bit is 0 when all interrupts have been cleared. |
| 6 | 1 | One-second interrupt status: 1 = interrupt has occurred. |
| | 0 | 0 = interrupt is cleared. |
| 5 | 1 | A scan-line interrupt status: 1 = interrupt has occurred. |
| | 0 | 0 = interrupt is cleared. |
| 4-3 | - | Reserved; do not modify. |
| 2 | 1 | One-second interrupt is enabled. |
| | 0 | Interrupt is disabled. |
| 1 | 1 | Scan-line interrupt is enabled. |
| | 0 | Interrupt is disabled. |
| 0 | - | Reserved; do not modify. |

---

## The VGC Interrupt-Clear Register

Once an interrupt has occurred, the interrupt routine must proceed to clear the interrupt and take some predetermined interrupt-handling action. To clear the scan-line and one-second status bits, write a 0 into the corresponding bit position in the VGC Interrupt-Clear register at $C032. Bit 5 clears the scan-line interrupt, and bit 6 clears the one-second interrupt in the VGC Interrupt-Clear register. Writing a 1 into these positions or writing into the other bit positions has no effect. Figure 4-4 shows the format of the VGC Interrupt-Clear register. Table 4-2 gives a description of each bit.

⚠️ **Warning**: Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

---

### Figure 4-4: VGC Interrupt-Clear register at $C032

| Bit | Name |
| :-- | :--- |
|7|Reserved; do not modify|
|6|Clear bit for 1-second interrupt|
|5| Clear bit for scan-line interrupt|
|4-0|Reserved; do not modify|





### Table 4-2: Bits in the VGC Interrupt-Clear register

| Bit | Value | Description |
|-----|-------|-------------|
| 7 | - | Reserved; do not modify. |
| 6 | 1 | Undefined result. |
| | 0 | Write a 0 here to clear the one-second interrupt. |
| 5 | 1 | Undefined result. |
| | 0 | Write a 0 here to clear the scan-line interrupt. |
| 4-0 | - | Reserved; do not modify. |

---

## Video Outputs

The Apple IIGS shares several display modes with previous Apple II computers. The Apple IIGS supports and enhances these existing Apple II video modes:

- 40-column and 80-column text modes
- mixed text/graphics mode
- Lo-Res graphics mode
- Hi-Res graphics mode
- Double Hi-Res graphics mode

---

Enhancements to the existing Apple II video modes include the following:

- The ability to select unique text and background colors from the list in Table 4-3.
- The ability to select the border color for the perimeter of the video image on an RGB monitor; you can choose this color from the list in Table 4-3.
- The ability to display gray-scale video; you can display color video output on **monochrome** monitors in shades of gray rather than in dot patterns that represent color, which increases contrast between graphics colors on a monochrome monitor.

### Table 4-3: Text and background colors

| Color value | Color | Color value | Color |
|-------------|-------|-------------|-------|
| $0 | Black | $8 | Brown |
| $1 | Deep red | $9 | Orange |
| $2 | Dark blue | $A | Light gray |
| $3 | Purple | $B | Pink |
| $4 | Dark green | $C | Green |
| $5 | Dark gray | $D | Yellow |
| $6 | Medium blue | $E | Aquamarine |
| $7 | Light blue | $F | White |

Removing color from the composite video signal in 40-column and 80-column text modes makes text more readable. Color is not removed when the computer is running in mixed text/graphics modes, and the four lines of text at the bottom of the display will exhibit **color fringing** on composite color monitors.

---

## Apple II Video

All Apple II computers can display video in several different ways, displaying text as well as color graphics. The standard Apple II text and graphics modes are discussed here, while the new Super Hi-Res graphics modes are discussed later in this chapter.

---

The primary output device is the video display. You can use any ordinary video monitor, either color or black-and-white, to display video information from the Apple IIGS. An ordinary monitor is one that accepts composite video compatible with the standard set by the National Television Standards Committee (NTSC). If you use standard Apple II color graphics with a monochrome (single-color) monitor, the display will appear as that color (black, for example) and various patterns made up of shades of that color.

If you are using only 40-column text and Lo-Res graphics modes, you can use a television set for your video display. If the television set has an input connector for composite video, you can connect it directly to your computer; if it does not, you'll need to attach a **radio-frequency (RF)** video modulator between the Apple IIGS and the television set.

◆ *Note:* The Apple IIGS can produce an 80-column text display. However, if you use an ordinary color or black-and-white television set, 80-column text will be too blurry to read. For a clear 80-column display, you must use a high-resolution video monitor with a bandwidth of 7 MHz or greater.

The specifications for the video display are summarized in Table 4-4.

The video signal produced by the Apple IIGS is NTSC-compatible composite color video. It is available at two places: at the RCA-type phono jack and at the RGB video connector, both on the back of the computer. Use the RCA-type phono jack to connect a composite video monitor or an external video modulator; use the RGB video connector to connect an analog-input RGB monitor.

The Apple IIGS can also display Super Hi-Res graphics, although it is not a standard Apple II video display mode. Super Hi-Res graphics are discussed more fully later in this chapter.

---

### Table 4-4: Standard Apple II video display specifications

| Feature | Specification |
|---------|---------------|
| Display modes | 40-column text; map: Figure 4-5.<br>80-column text; map: Figure 4-6.<br>Lo-Res color graphics; map: Figure 4-7.<br>Hi-Res color graphics; map: Figure 4-8.<br>Double Hi-Res color graphics; map: Figure 4-9. |
| Text capacity | 24 lines by 80 columns (character positions). |
| Character set | 128 **ASCII** characters. (See Appendix C for a list of display characters.) |
| Display formats | Normal, inverse, flashing, MouseText (Table 4-10). |
| Lo-Res color graphics | 16 colors (Table 4-14): 40 horizontal by 48 vertical; map: Figure 4-7. |
| Hi-Res color graphics | 6 colors (Table 4-15): 140 horizontal by 192 vertical (restricted). Black-and-white: 280 horizontal by 192 vertical; map: Figure 4-8. |
| Double Hi-Res color graphics | 16 colors (Table 4-16): 140 horizontal by 192 vertical (no restrictions). Black-and-white: 560 horizontal by 192 vertical; map: Figure 4-9. |

The 40-column and 80-column text modes can display all 128 ASCII (American Standard Code for Information Interchange) characters: uppercase and lowercase letters, numbers, and symbols. (See the display maps in Figures 4-5 and 4-6.) The Apple IIGS can also display MouseText characters.

Any of the graphics displays can have four lines of text at the bottom of the screen. The text may be either 40-column or 80-column, except that Double Hi-Res graphics may have only 80-column text at the bottom of the screen. Graphics displays with text at the bottom are called *mixed-mode displays*.

The Lo-Res graphics display is an array of colored blocks, 40 wide by 48 high, in any of 16 colors. (See the map in Figure 4-7.) In mixed mode, 4 lines of text replace the bottom 8 rows of blocks, leaving 40 rows of 40 blocks each.

The Hi-Res graphics display is an array of pixels, 280 wide by 192 high. (See the map in Figure 4-8.) There are six colors available in Hi-Res displays, but a given pixel can use only four of the six colors. If color is used, the display is 140 pixels wide by 192 high. If monochrome video is desired, the display is 280 pixels wide by 192 high. In mixed mode, the four lines of text replace the bottom 32 rows of pixels, leaving 160 rows of 140 (or 280) pixels each.

---

The Double Hi-Res graphics display uses main and auxiliary memory to display an array of pixels, 560 wide by 192 high. (See the map in Figure 4-9.) All the pixels are visible in black and white. If color is used, the display is 140 pixels wide by 192 high with 16 colors available. If monochrome video is desired, the display is 560 pixels wide by 192 high. In mixed mode, the four lines of text replace the bottom 32 rows of pixels, leaving 160 rows of 140 (or 560) pixels each. In mixed mode, the text lines can be 80 columns wide only.

### Figure 4-5: Map of 40-column text Page 1 display (Add 1024 [$400] to get Page 2 addresses.)

[*Memory map showing rows 0-23 with corresponding hex addresses from $400-$7D0, organized in a grid showing character positions $00-$27 across columns*]

---

### Figure 4-6: Map of 80-column text display

[*Memory map showing Main Memory (columns $00-$07) and Auxiliary Memory (columns $20-$27) for rows 0-23, with hex addresses ranging from $400-$7D0*]

---

### Figure 4-7: Map of Lo-Res graphics Page 1 display (Add 1024 [$400] to get Page 2 addresses.)

[*Memory map showing rows 0-46 (even rows only) with hex addresses from $400-$7D0 and columns $00-$27*]

---

### Figure 4-8: Map of Hi-Res graphics Page 1 display (Add 8192 [$2000] to get Page 2 addresses.)

[*Complex memory map showing rows 0-23 with hex addresses from $2000-$3FFF, displaying byte offsets and memory organization for hi-res graphics. Includes detail boxes showing byte arrangements with offsets like "+0 +$0000", "+1024 +$0400", etc.*]

---

### Figure 4-9: Map of Double Hi-Res graphics display

[*Similar to Figure 4-8 but showing both Main Memory and Auxiliary Memory regions, with rows 0-23 and hex addresses from $2000-$3FFF, including same byte offset details*]

---

## NTSC versus RGB Video

The composite video signal, available at the composite video connector at the rear of the Apple IIGS case, will drive a standard NTSC composite color video monitor.

The RGB video signals are three separate color signals, which individually control the three colors (red, green, and blue) within an RGB color video monitor. The RGB video connector is located at the rear of the computer. Connect only an RGB video monitor with analog inputs to this connector. Figure 4-10 shows the pin diagram of this connector, and Table 4-5 lists the signal associated with each pin.

### Figure 4-10: RGB video connector

```
   8   7   6   5   4   3   2   1
     15  14  13  12  11  10  9
```

### Table 4-5: RGB video signals

| Pin | Signal | Description |
|-----|--------|-------------|
| 1 | GND | Ground reference and supply |
| 2 | RED | Red analog video signal |
| 3 | COMP | Composite sync signal |
| 4 | N.C. | No connection |
| 5 | GREEN | Green analog video signal |
| 6 | GND | Ground reference and supply |
| 7 | -5V | -5-volt supply |
| 8 | +12V | +12-volt supply |
| 9 | BLUE | Blue analog video signal |
| 10 | N.C. | No connection |
| 11 | SOUND | Analog sound output |
| 12 | NTSC/PAL | Composite video output |
| 13 | GND | Ground reference and supply |
| 14 | N.C. | No connection |

---

## Video Display Pages

The Apple IIGS generates its video displays by using data stored in specific areas in memory. These areas, called display pages, serve as buffers where your programs can put data to be displayed. Each byte in a display buffer controls an object at a certain location on the display. In text mode, the object is a single character; in Lo-Res graphics mode, the object is two stacked colored blocks; and in Hi-Res and Double Hi-Res modes, it is a line of seven adjacent pixels.

The 40-column text and Lo-Res graphics modes use two display pages of 1024 bytes each. These are called text Page 1 and text Page 2, and they are located at 1024 through 2047 ($0400 through $07FF) and 2048 through 3071 ($0800 through $0BFF) in main memory. Normally, only text Page 1 is used, but you can put text or graphics data into text Page 2 and switch displays instantly. Either page can be displayed as 40-column text, Lo-Res graphics, or mixed mode (four rows of text at the bottom of a graphics display).

The 80-column text mode displays twice as much data as the 40-column mode—1920 bytes—but it cannot switch pages. The 80-column text display uses a combination page made up of text Page 1 in main memory plus another page in auxiliary memory. This additional memory is not the same as text Page 2—in fact, it occupies the same address space as text Page 1, and there is a special soft switch that enables you to store data into it. (See the next section, "Display Mode Switching.") The built-in firmware I/O routines, described in the *Apple IIGS Firmware Reference*, take care of this extra addressing automatically; that is one reason to use these routines for all your normal text output.

The Hi-Res graphics mode also has two display pages, but each page is 8192 bytes long. In the 40-column text and Lo-Res graphics modes, each byte controls a display area 7 pixels wide by 8 pixels high. In Hi-Res graphics mode each byte controls an area 7 pixels wide by 1 pixel high. Thus, a Hi-Res display requires 8 times as much data storage, as shown in Table 4-6.

The Double Hi-Res graphics mode uses Hi-Res graphics Page 1 in both main and auxiliary memory. Each byte in those pages of memory controls a display area 7 pixels wide by 1 pixel high. This gives you 560 pixels per line in black and white, and 140 pixels per line in color. A Double Hi-Res display requires twice the total memory of Hi-Res graphics, and 16 times as much as a Lo-Res display.

---

### Table 4-6: Video display locations

| Display mode | Display page | Lowest address<br>(Hex / Dec) | Highest address<br>(Hex / Dec) |
|--------------|--------------|-------------------------------|--------------------------------|
| 40-column text,<br>Lo-Res graphics | 1<br>2* | $0400 / 1024<br>$0800 / 2048 | $07FF / 2047<br>$0BFF / 3071 |
| 80-column text | 1<br>2* | $0400 / 1024<br>$0800 / 2048 | $07FF / 2047<br>$0BFF / 3071 |
| Hi-Res graphics | 1<br>2 | $2000 / 8192<br>$4000 / 16384 | $3FFF / 16383<br>$5FFF / 24575 |
| Double High-Res graphics | 1†<br>2† | $2000 / 8192<br>$4000 / 16384 | $3FFF / 16383<br>$5FFF / 24575 |

\* Lo-Res graphics on Page 2 is not supported by firmware; for instructions on how to switch pages, refer to the next section, "Display Mode Switching."

† See the section "Double Hi-Res Graphics" later in this chapter.

---

## Display Mode Switching

You select the display mode that is appropriate for your application by reading or writing to a reserved memory location called a soft switch. In the Apple IIGS, most soft switches have three memory locations reserved for them: one for turning the switch on, one for turning it off, and one for reading the current state of the switch.

Table 4-7 shows the reserved locations for the soft switches that control the display modes. For example, to switch from mixed mode to full-screen graphics in an assembly-language program, you could use the instruction

```
STA    $C052
```

To do this in a BASIC program, you could use the instruction

```
POKE   49234,0
```

Some of the soft switches in Table 4-7 must be read, some must be written to, and for some you can use either action. When writing to a soft switch, it doesn't matter what value you write; the action occurs when you address the location, and the value is ignored.

---

### Table 4-7: Display soft switches

| Name | Action* | Location | Function |
|------|---------|----------|----------|
| CLR80COL | W | $C000 (49152) | Disable 80-column store. |
| SET80COL | W | $C001 (49153) | Enable 80-column store. |
| CLR80VID | W | $C00C (49164) | Disable 80-column hardware. |
| SET80VID | W | $C00D (49165) | Enable 80-column hardware. |
| CLRALTCHAR | W | $C00E (49166) | Normal lowercase character set; flashing uppercase character set. |
| SETALTCHAR | W | $C00F (49167) | Normal, inverse character set; no flashing. |
| RD80COL | R7 | $C018 (49176) | Read CLR/SET80COL switch: 1 = 80-column store enabled. |
| RDVBL_BAR | R7 | $C019 (49177) | Read vertical blanking (VBL): 1 = not VBL. |
| RDTEXT | R7 | $C01A (49178) | Read TXTCLR/TXTSET switch: 1 = text mode enabled. |
| RDMIX | R7 | $C01B (49179) | Read MIXCLR/MIXSET switch: 1 = mixed mode enabled. |
| RDPAGE2 | R7 | $C01C (49180) | Read TXTPAGE1/TXTPAGE2 switch: 1 = text Page 2 selected. |
| RDHIRES | R7 | $C01D (49181) | Read HIRES switch: 1 = Hi-Res mode enabled. |
| ALTCHARSET | R7 | $C01E (49182) | Read CLRALTCHAR/SETALTCHAR switch: 1 = alternate character set in use. |
| RD80VID | R7 | $C01F (49183) | Read CLR80VID/SET80VID switch: 1 = 80-column hardware in use. |
| RDDHIRES | R5 | $C046 (49222) | Read SETAN3/CLRAN3 switch: 0 = Double Hi-Res graphics mode selected. |

*(Continued)*

---

### Table 4-7: Display soft switches (Continued)

| Name | Action* | Location | Function |
|------|---------|----------|----------|
| TXTCLR | R/W | $C050 (49232) | Select standard Apple II graphics mode, or, if MIXSET on, mixed mode. |
| TXTSET | R/W | $C051 (49233) | Select text mode only. |
| MIXCLR | R/W | $C052 (49234) | Clear mixed mode. |
| MIXSET | R/W | $C053 (49235) | Select mixed mode. |
| TXTPAGE1 | R/W | $C054 (49236) | Select text Page 1. |
| TXTPAGE2 | R/W | $C055 (49237) | Select text Page 2, or, if SET80COL on, text Page 1 in auxiliary memory. |
| LORES | R/W | $C056 (49238) | Select Lo-Res graphics mode. |
| HIRES | R/W | $C057 (49239) | Select Hi-Res graphics mode, or, if SETAN3 is on, select Double Hi-Res graphics mode. |
| CLRAN3 | R/W | $C05E (49246) | See Table 4-8. |
| SETAN3 | R/W | $C05F (49247) | See Table 4-8. |

\* *W* means write anything to the location, *R* means read the location, *R/W* means read or write, *R7* means read the location and then check bit 7, and *R5* means read the location and then check bit 5.

◆ *Note:* You may not need to deal with these functions by reading and writing directly to the memory locations in Table 4-7. Many of the functions shown here are selected automatically if you use the display routines in the various **high-level languages** on the Apple IIGS.

Any time you read a soft switch, you get a byte of data. However, the only information the byte contains is the state of the switch, and this occupies only one bit—bit 7, the high-order bit. The other bits in the byte are always 0.

If you read a soft switch from a BASIC program, you get a value between 0 and 255. Bit 7 has a value of 128, so if the switch is on, the value will be equal to or greater than 128; if the switch is off, the value will be less than 128.

---

## Mixing Address Modes

It is possible to display combinations of modes on the video display. The combination can be any mode of graphics combined with either 40-column or 80-column text, graphics only, or text-only modes. Table 4-8 lists the possible combinations, and the state of the soft switches to achieve the display modes.

### Table 4-8: Video display mode combinations

| New:Video reg.<br>($C029) bit 5 | AN3<br>($C046) | TEXT<br>($C01C) | HIRES<br>($C01D) | 80COL<br>($C018) | Video mode |
|----------------------------------|----------------|-----------------|------------------|------------------|------------|
| - | - | 1 | - | 0 | 40-column text |
| - | - | 1 | - | 1 | 80-column text |
| - | 1 | 0 | 0 | 0 | Lo-Res graphics and 40-column text |
| - | 1 | 0 | 0 | 1 | Lo-Res graphics and 80-column text |
| - | 0 | 0 | 0 | 1 | Medium-Res (80-column) graphics |
| - | 1 | 0 | 1 | 0 | Hi-Res graphics and 40-column text |
| - | 1 | 0 | 1 | 1 | Hi-Res graphics and 80-column text |
| 0 | 0 | 0 | 1 | 1 | Double-Hi-Res, 16-color |
| 1 | 0 | 0 | 1 | 1 | Double-Hi-Res, black-and-white |

---

## Addressing Display Pages Directly

Before you decide to use the display pages directly, consider the alternatives. Most high-level languages enable you to write statements that control the text and graphics displays. Similarly, if you are programming in assembly language, you may be able to use the display features of the built-in I/O firmware. You should store directly into display memory only if the existing programs can't meet your requirements.

The display memory maps are shown in Figures 4-5, 4-6, 4-7, 4-8, and 4-9. All the different display modes use the same basic addressing scheme: Characters or graphics bytes are stored as rows of 40 contiguous bytes, but the rows themselves are not stored at locations corresponding to their locations on the display. Instead, the display address is transformed so that three rows that are eight rows apart on the display are grouped together and stored in the first 120 locations of each block of 128 bytes ($80 hexadecimal). By folding the display data into memory this way, the Apple IIGS stores all 960 characters of displayed text within 1K of memory.

---

The Hi-Res graphics display is stored in much the same way as text, but there are eight times as many bytes to store, because eight rows of pixels occupy the same space on the display as one row of characters. The subset consisting of all the first rows from the groups of eight is stored in the first 1024 bytes of the Hi-Res display page. The subset consisting of all the second rows from the groups of eight is stored in the second 1024 bytes, and so on for a total of eight times 1024, or 8192 bytes. In other words, each 1024 bytes of Hi-Res video memory contains one row of pixels from every group of eight rows. The individual rows are stored in sets of three 40-byte rows, the same as the text display.

All of the display modes except 80-column text mode and Double Hi-Res and Super Hi-Res graphics modes can use either of two display pages. The display maps show addresses for each mode's Page 1 only. To obtain addresses for text or Lo-Res graphics Page 2, add 1024 ($400) to the Page 1 addresses; to obtain addresses for Hi-Res graphics Page 2, add 8192 ($2000) to the Page 1 addresses.

The 80-column text display and Double Hi-Res graphics modes work a little differently. Half of the data are stored in the normal text Page 1 main memory, and the other half are stored in auxiliary memory using the same addresses as for text Page 1. The display circuitry fetches bytes from these two memory areas simultaneously and displays them sequentially: first the byte from the auxiliary memory, then the byte from the main memory. The main memory stores the characters in the odd columns of the display, and the auxiliary memory stores the characters in the even columns.

To store display data in the 80-column text display, first turn on the SET80COL soft switch by writing to location $C001. With SET80COL on, the page-select switch, TXTPAGE2, selects between the portion of the 80-column display memory in Page 1 of main memory and the portion stored in the 80-column text display memory. To enable the 80-column text display, turn the TXTPAGE2 soft switch on by reading or writing at location $C055.

---

## The Text Window

After you have started up the computer or after a reset, the firmware uses the entire video display. However, you can restrict video activity to any rectangular portion of the display you wish. The active portion of the display is called the **text window**. You can set the top, bottom, left side, and width of the text window by storing the appropriate values into four locations in memory. Using these memory locations allows you to control the placement of text in the display and to protect other portions of the screen from being written over by new text.

Memory location $20 contains the number of the leftmost column in the text window. This number is normally 0, the number of the leftmost column in the display. In a 40-column display, the maximum value for this number is $27; in an 80-column display, the maximum value is $4F.

---

Memory location $21 holds the width of the text window. For a 40-column display, it is normally $28; for an 80-column display, it is normally $50.

⚠️ **Warning**: Be careful not to let the sum of the window width and the leftmost position in the window exceed the width of the display you are using (40 or 80). If this happens, it is possible to put characters into memory locations outside the display page, which might destroy programs or data. ▲

Memory location $22 contains the number of the top line of the text window. This is normally 0, the topmost line in the display. Its maximum value is $17.

Memory location $23 contains the number of the bottom line of the screen, plus 1. It is normally $18 for the bottom line of the display. Its minimum value is $01.

After you have changed the text window boundaries, nothing is affected until you send a character to the screen.

⚠️ **Warning**: Any time you change the boundaries of the text window, you should make sure that the current cursor horizontal position (CH, stored at $24) and cursor vertical position (CV, stored at $25) are within the new window values. If they are outside, it is possible to put characters into memory locations outside the display page, which might destroy programs or data. ▲

Table 4-9 summarizes the memory locations and the possible values for the window parameters.

### Table 4-9: Text window memory locations

| Window parameter | Location | Minimum value | Normal values | Maximum values |
|------------------|----------|---------------|---------------|----------------|
| | Dec / Hex | Dec / Hex | 40-column<br>Dec / Hex | 80-column<br>Dec / Hex | 40-column<br>Dec / Hex | 80-column<br>Dec / Hex |
| Left edge | 32 / $20 | 00 / $00 | 00 / $00 | 00 / $00 | 39 / $27 | 79 / $4F |
| Width | 33 / $21 | 00 / $00 | 40 / $28 | 80 / $50 | 40 / $28 | 80 / $50 |
| Top edge | 34 / $22 | 00 / $00 | 00 / $00 | 00 / $00 | 23 / $17 | 23 / $17 |
| Bottom edge | 35 / $23 | 01 / $01 | 24 / $18 | 24 / $18 | 24 / $18 | 24 / $18 |


# Text Displays (Continued from Chapter 4)

## Text displays

The Apple IIGS, like all standard Apple II computers, can display text in two ways: 40 columns wide by 24 rows, or 80 columns wide by 24 rows. Many character sets are available, including standard alphanumeric characters, special characters, and MouseText characters.

Text on the Apple IIGS can also be displayed in color: The text, background, and border each can be a different color. The following sections give details about the text displays.

---

## Text modes

The text characters displayed include the uppercase and lowercase letters, the ten numerical digits, punctuation marks, and special characters. Each character is displayed in an area of the screen that is seven pixels wide by eight pixels high. The characters are formed by a pixel matrix five pixels wide, leaving two blank columns of pixels between characters in a row, except for MouseText characters, some of which are seven pixels wide. Except for lowercase letters with descenders and some MouseText characters, the characters are only seven pixels high, leaving one blank line of pixels between rows of characters.

The normal display has white pixels on a medium blue background. (Other color text on other color backgrounds is also possible, as described later in this chapter.) Characters can also be displayed in inverse format with blue pixels on a white background.

### Text character sets

The Apple IIGS can display either of two selected text character sets: the primary set or an alternate set. The forms of the characters in the two sets are actually the same, but the available display formats are different. The display formats are:

- normal
- inverse
- flashing, alternating between normal and inverse

With the primary character set, the Apple IIGS can display uppercase and special characters in all three formats: normal, inverse, and flashing. Lowercase letters can be displayed in normal format only. The primary character set is compatible with most software written for other Apple II models, which can display text in flashing format but which don't have lowercase characters.

---

The alternate character set displays characters in either normal or inverse format. In normal format, you can get:

- uppercase letters
- lowercase letters
- numbers
- special characters

In inverse format, you can get:

- MouseText characters
- uppercase letters
- lowercase letters
- numbers
- special characters

You select the character sets by means of the alternate-text soft switch, SETALTCHAR, described earlier in this chapter in the section "Display Mode Switching." Table 4-10 shows the character codes in hexadecimal for the primary and alternate character sets in normal, inverse, and flashing formats.

Each character on the screen is stored as one byte of display data. The low-order six bits make up the ASCII code of the character being displayed. The remaining two (high-order) bits select inverse or flashing format and uppercase or lowercase characters. In the primary character set, bit 7 selects inverse or normal format and bit 6 controls character flashing. In the alternate character set, bit 6 selects between uppercase and lowercase, according to the ASCII character codes, and flashing format is not available.

### Table 4-10: Display character sets

| Hex values | Primary character set |  | Alternate character set |  |
|------------|----------------------|---------|------------------------|---------|
|            | Character type | Format | Character type | Format |
| $00-$1F | Uppercase letters | Inverse | Uppercase letters | Inverse |
| $20-$3F | Special characters | Inverse | Special characters | Inverse |
| $40-$5F | Uppercase letters | Flashing | MouseText | Inverse |
| $60-$7F | Special characters | Flashing | Lowercase letters | Inverse |
| $80-$9F | Uppercase letters | Normal | Uppercase letters | Normal |
| $A0-$BF | Special characters | Normal | Special characters | Normal |
| $C0-$DF | Uppercase letters | Normal | Uppercase letters | Normal |
| $E0-$FF | Lowercase letters | Normal | Lowercase letters | Normal |

---

### 40-column versus 80-column text

The Apple IIGS has two modes of text display: 40-column and 80-column. The number of pixels in each character does not change, but the characters in 80-column mode are only half as wide as the characters in 40-column mode. Compare Figures 4-11 and 4-12. On an ordinary color or black-and-white television set, the narrow characters in the 80-column display blur together; you must use the 40-column mode to display text on a television set.

#### Figure 4-11: 40-column text display

```
/UTILITIES

NAME        CREATED      TYPE    BLOCKS   MODIFIED
                                 ENDFILE  SUBTYPE
*STARTUP                 BAS     3        31-JUL-85
 0:00      <NO DATE>                      1005
*SI                      BAS     3        31-JUL-85
 0:00      <NO DATE>                      1005
*SU2C                    BAS     38       31-JUL-85
 0:00      <NO DATE>                      18886
*SU2E                    BAS     34       31-JUL-85
 0:00      <NO DATE>                      16465
*SU1.OBJ                 BIN     31       31-JUL-85
 0:00      <NO DATE>                      15211 A=$3200
*SU2.OBJ                 BIN     3        31-JUL-85
 0:00      <NO DATE>                      3696  A=$2000
*SU3.OBJ                 BIN     62       31-JUL-85
 0:00      <NO DATE>                      31152 A=$0E00
*SU4.OBJ                 VAR     18       31-JUL-85
 0:00      <NO DATE>                      8535
*SU5.OBJ                 BIN     1        31-JUL-85
 0:00      <NO DATE>                      95    A=$86AC
*PRODOS                  SYS     30       18-SEP-84
 0:00      <NO DATE>                      14848
*BASIC.SYSTEM            SYS     21       18-JUN-84
 0:00      <NO DATE>                      10240

BLOCKS FREE: 1328        BLOCKS USED: 272
TOTAL BLOCKS: 1600
```

#### Figure 4-12: 80-column text display

```
/UTILITIES

NAME          TYPE  BLOCKS  MODIFIED       CREATED          ENDFILE SUBTYPE

*STARTUP      BAS   3       31-JUL-85 0:00 <NO DATE>        1005
*SI           BAS   3       31-JUL-85 0:00 <NO DATE>        1005
*SU2C         BAS   38      31-JUL-85 0:00 <NO DATE>        18886
*SU2E         BAS   34      31-JUL-85 0:00 <NO DATE>        16465
*SU1.OBJ      BIN   31      31-JUL-85 0:00 <NO DATE>        15211 A=$3200
*SU2.OBJ      BIN   9       31-JUL-85 0:00 <NO DATE>        3696  A=$2000
*SU3.OBJ      BIN   62      31-JUL-85 0:00 <NO DATE>        31152 A=$0E00
*SU4.OBJ      VAR   18      31-JUL-85 0:00 <NO DATE>        8535
*SU5.OBJ      BIN   1       31-JUL-85 0:00 <NO DATE>        95    A=$86AC
*PRODOS       SYS   30      18-SEP-84 0:00 <NO DATE>        14848
*BASIC.SYSTEM SYS   21      18-JUN-84 0:00 <NO DATE>        10240

BLOCKS FREE: 1328    BLOCKS USED: 272    TOTAL BLOCKS: 1600
```

---

## Color text

New to the Apple IIGS is the ability to display the text, background, and border in color. These colors may be set manually through the Control Panel, or under program control, via **control registers.**

### Text and background color

The Apple IIGS provides the capability of colored text on a colored background on an RGB monitor. To select colors for text and background, write the appropriate color values to the Screen Color register located at $C022.

The Screen Color register is an 8-bit dual-function register. First, the most significant 4 bits determine the text color. Second, the least significant 4 bits determine the background color. You can choose these colors from the 16 available Apple II colors given in Table 4-3. The user can also select these colors from the Control Panel. Figure 4-13 shows the format of the Screen Color register. Table 4-11 gives a description of each bit in the register.

#### Figure 4-13: Screen Color register at $C022

```
Text color    Background color
    |               |
    7  6  5  4  3  2  1  0
```

#### Table 4-11: Bits in the Screen Color register

| Bit | Value | Description |
|-----|-------|-------------|
| 7-4 | - | Text color |
| 3-0 | - | Background color |

---

### Border color

The colored border area surrounds the video display text area. You may select a color for the border by writing the appropriate color value to the Border Color register located at $C034. You can choose this color from the 16 Apple II colors listed in Table 4-3. Alternately, the user can select the border color from the Control Panel.

---

The Border Color register is an 8-bit read/write register serving two functions. First, the least significant 4 bits determine the border color. Second, the most significant 4 bits are the control bits for the real-time clock chip interface logic. See the section on the real-time clock interface in Chapter 7, "Built-in I/O Ports and Clock," for more information on the RTC. Figure 4-14 shows the Border Color register format. Table 4-12 gives a description of each bit.

⚠️ **Warning**: Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

#### Figure 4-14: Border Color register at $C034

```
Real-time clock    Border color
        |               |
        7  6  5  4  3  2  1  0
```

#### Table 4-12: Bits in the Border Color register

| Bit | Value | Description |
|-----|-------|-------------|
| 7-4 | - | Real-time clock control bits; do not modify bits 7-4 when changing bits 3-0 |
| 3-0 | - | Border color |

---

### Monochrome/Color register

The Apple IIGS video is displayed in either color or black-and-white. Located at $C021, the Monochrome/Color register controls whether the composite video signal consists of color or gradations of gray. If bit 7 is a 1, video displays in black-and-white; if it is a 0, video displays in color.

---

If you are using a monochrome monitor, set bit 7 to 1. Displaying text in black-and-white results in a better-looking, more readable display. In text mode, all color information is removed from the composite video signal, resulting in a monochrome text display. The exception to this is the mixed text and graphics mode, which results in color text and color fringing.

The remaining bits in the Monochrome/Color register are reserved; do not modify them when writing to this location. You can also select color or monochrome video from the Control Panel. Figure 4-15 shows the format of the Monochrome/Color register. Table 4-13 gives a description of each bit in the register.

⚠️ **Warning**: Be careful when changing bit 7 in this register. Use only a read-modify-write instruction sequence when manipulating bit 7. See the warning in the preface. ▲

#### Figure 4-15: Monochrome/Color register at $C021

```
                Reserved; do not modify
                        |
        7  6  5  4  3  2  1  0
        |
Color or monochrome video select
```

#### Table 4-13: Bits in the Monochrome/Color register

| Bit | Value | Description |
|-----|-------|-------------|
| 7* | 1 | Composite gray-scale video output |
|    | 0 | Composite color video output |
| 6-0 | - | Reserved; do not modify |

\* Changing bit 7 does not affect the RGB outputs.

◆ *Note:* Reading the Monochrome/Color register returns a meaningless value. Bit 7, therefore, can be referred to as write-only.

---

## Graphics displays

The Apple IIGS can produce standard Apple II video graphics in three different modes, as well as two new graphics resolutions. All the graphics modes treat the screen as a rectangular array of spots. Normally, your programs will use the features of some high-level language to draw graphics dots, lines, and shapes in these arrays; this section describes the way the resulting graphics data are stored in memory.

---

## Standard Apple II graphics modes

Apple IIGS graphics can be displayed in several different resolutions. All standard Apple II graphics modes are supported:

- Lo-Res graphics mode
- Hi-Res graphics mode
- Double Hi-Res graphics mode

Each of these graphics modes is described in the following sections.

### Lo-Res graphics

In the Lo-Res graphics mode, the Apple IIGS displays an array of 48 rows by 40 columns of colored blocks. Each block can be any of 16 colors, including black-and-white. On a black-and-white monitor or television set, these colors appear as black, white, and three shades of gray. There are no blank pixels between blocks; adjacent blocks of the same color merge to make a larger shape.

Data for the Lo-Res graphics display are stored in the same part of memory as the data for the 40-column text display. Each byte contains data for two Lo-Res graphics blocks. The two blocks are displayed one atop the other in a display space the same size as a 40-column text character, 7 pixels wide by 8 pixels high.

Half a byte—4 bits, or 1 nibble—is assigned to each graphics block. Each nibble can have a value from 0 to 15, and this value determines which one of 16 colors appears on the screen. The colors and their corresponding nibble values are shown in Table 4-14. In each byte, the low-order nibble sets the color for the top block of the pair, and the high-order nibble sets the color for the bottom block. Thus, a byte containing the hexadecimal value $D8 produces a brown block atop a yellow block on the screen.

---

#### Table 4-14: Lo-Res graphics colors

| Nibble value | | Nibble value | |
|--------------|-------|--------------|-------|
| Dec | Hex | Color | Dec | Hex | Color |
| 0 | $00 | Black | 8 | $08 | Brown |
| 1 | $01 | Deep red | 9 | $09 | Orange |
| 2 | $02 | Dark blue | 10 | $0A | Light gray |
| 3 | $03 | Purple | 11 | $0B | Pink |
| 4 | $04 | Dark green | 12 | $0C | Light green |
| 5 | $05 | Dark gray | 13 | $0D | Yellow |
| 6 | $06 | Medium blue | 14 | $0E | Aquamarine |
| 7 | $07 | Light blue | 15 | $0F | White |

*Note:* Colors may vary, depending on the controls on the monitor or television set.

As explained earlier in this chapter in the section "Video Display Pages," the text display and the Lo-Res graphics display use the same area in memory. Most programs that generate text and graphics clear this part of memory when they change display modes, but it is possible to store data as text and display them as graphics, or vice versa. All you have to do is change the mode switch, described earlier in this chapter in the section "Display Mode Switching," without changing the display data. This usually produces meaningless jumbles on the display, but some programs have used this technique to good advantage for producing complex Lo-Res graphics displays quickly.

### Hi-Res graphics

In the Hi-Res graphics mode, the Apple IIGS displays an array of 192 rows of 280 monochrome pixels, or 140 colored pixels. The smaller number of pixels in color is due to the fact that it takes two bits in display memory to make one color pixel on the screen; in monochrome, one bit makes one pixel. The colors available are black, white, purple, green, orange, and blue.

Data for the Hi-Res graphics displays are stored in either of two 8192-byte areas in memory. These areas are called Hi-Res graphics Page 1 and Page 2. It is in these buffer areas that your high-level language program creates and manipulates the bit images that will appear on the screen. This section describes the way the graphics data bits are converted to pixels on the screen.

---

The Hi-Res graphics display is bit-mapped: Each pixel on the screen corresponds to a bit (or, in color, 2 bits) in memory. The 7 low-order bits of each display memory byte control a row of 7 adjacent pixels on the screen, and 40 adjacent bytes in memory control a row of 280 (7 times 40) pixels. The least significant bit of each byte is displayed as the leftmost pixel in a row of 7, followed by the second least significant bit, and so on, as shown in Figure 4-16. The eighth bit (the most significant) of each byte is not displayed; it selects one of two color sets, as described later in this chapter.

#### Figure 4-16: Hi-Res graphics display bits

```
        Bits in data byte
        
  7   |  6  5  4  3  2  1  0  |
  
           ↓  ↓  ↓  ↓  ↓  ↓  ↓
           
  |  0  1  2  3  4  5  6  |
  
  Dots on graphics screen
```

On a black-and-white monitor, there is a simple correspondence between bits in memory and pixels on the screen. A pixel is white if the bit controlling it is on (1), and the pixel is black if the bit is off (0). On a black-and-white television set, pairs of pixels blur together; alternating black-and-white pixels merge to a continuous gray.

On an NTSC color monitor or a color television set, a pixel whose controlling bit is off (0) is black. If the bit is on, the pixel will be white or a color, depending on its position, the pixels on either side, and the setting of the high-order bit of the byte.

Call the leftmost column of pixels column 0 and assume (for the moment) that the high-order bits of all the data bytes are off (0). If the bits that control pixels in even-numbered columns (0, 2, 4, and so forth) are on, the pixels are purple; if the bits that control odd-numbered columns are on, the pixels are green—but only if the pixels on both sides of a given pixel are black. If two adjacent pixels are both on, they are both white.

You can select the other two colors, blue and orange, by turning the high-order bit (bit 7) of a data byte on (1). The colored pixels controlled by a byte with the high-order bit on are either blue or orange: The pixels in even-numbered columns are blue, and the pixels in odd-numbered columns are orange—again, only if the pixels on both sides are black.

---

Within each horizontal line of seven pixels controlled by a single byte, you can have black, white, and one pair of colors. To change the color of any pixel to one of the other pair of colors, you must change the high-order bit of its byte, which affects the colors of all seven pixels controlled by the byte.

In other words, Hi-Res graphics displayed on a color monitor or television set are made up of colored pixels, according to the following rules:

- Pixels in even columns can be black, purple, or blue.
- Pixels in odd columns can be black, green, or orange.
- If adjacent pixels in a row are both on, they are both white.
- The colors in each row of seven pixels controlled by a single byte are either purple and green, or blue and orange, depending on whether the high-order bit is off (0) or on (1).

These rules are summarized in Table 4-15. The blacks and whites are numbered to remind you that the high-order bit is different.

#### Table 4-15: Hi-Res graphics colors

| Bits 0-6 | Bit 7 off | Bit 7 on |
|----------|-----------|----------|
| Adjacent columns off | Black 1 | Black 2 |
| Even columns on | Purple | Blue |
| Odd columns on | Green | Orange |
| Adjacent columns on | White 1 | White 2 |

*Note:* Colors may vary, depending on the controls on the monitor or television set.

The peculiar behavior of the Hi-Res colors reflects the way NTSC color television works. The pixels that make up the Apple IIGS video signal are spaced to coincide with the **frequency** of the color subcarrier used in the NTSC system. Alternating black-and-white pixels at this spacing causes a color monitor or TV set to produce color, but 2 or more white pixels together do not. Effective horizontal resolution with color is 140 pixels per line (280 divided by 2).

### Double Hi-Res graphics

In the Double Hi-Res graphics mode, the Apple IIGS displays an array of 140 colored pixels or 560 monochrome pixels wide and 192 rows deep. There are 16 colors available for use with Double Hi-Res graphics. (See Table 4-16.)

---

#### Table 4-16: Double Hi-Res graphics colors

| Repeated color pattern | ab0 | mb1 | ab2 | mb3 | Bit |
|------------------------|-----|-----|-----|-----|-----|
| Black | $00 | $00 | $00 | $00 | 0000 |
| Deep red | $08 | $11 | $22 | $44 | 0001 |
| Brown | $44 | $08 | $11 | $22 | 0010 |
| Orange | $4C | $19 | $33 | $66 | 0011 |
| Dark green | $22 | $44 | $08 | $11 | 0100 |
| Dark gray | $2A | $55 | $2A | $55 | 0101 |
| Green | $66 | $4C | $19 | $33 | 0110 |
| Yellow | $6E | $5D | $3B | $77 | 0111 |
| Dark blue | $11 | $22 | $44 | $08 | 1000 |
| Purple | $19 | $33 | $66 | $4C | 1001 |
| Light gray | $55 | $2A | $55 | $2A | 1010 |
| Pink | $5D | $3B | $77 | $6E | 1011 |
| Medium blue | $33 | $66 | $4C | $19 | 1100 |
| Light blue | $3B | $77 | $6E | $5D | 1101 |
| Aquamarine | $77 | $6E | $5D | $3B | 1110 |
| White | $7F | $7F | $7F | $7F | 1111 |

Double Hi-Res graphics is a bit-mapping of the low-order 7 bits of the bytes in the main-memory and auxiliary-memory pages at $2000 through $3FFF. The bytes in the main-memory and auxiliary-memory pages are interleaved in exactly the same manner as the characters in 80-column text: Of each pair of identical addresses, the auxiliary-memory byte is displayed first, and the main-memory byte is displayed second. Horizontal resolution is 560 pixels when displayed on a monochrome monitor.

Unlike Hi-Res color, Double Hi-Res color has no restrictions on which colors can be adjacent. Color is determined by any 4 adjacent pixels along a line. Think of a 4-pixel-wide window moving across the screen: At any given time, the color displayed will correspond to the 4-bit value from Table 4-16 that corresponds to the window's position (Figure 4-9). Effective horizontal resolution with color is 140 (560 divided by 4) pixels per line.

To use Table 4-16, divide the display column number by 4, and use the remainder to find the correct column in the table: ab0 is a byte residing in auxiliary memory, corresponding to a remainder of zero (byte 0, 4, 8, and so on); mb1 is a byte residing in main memory, corresponding to a remainder of one (byte 1, 5, 9 and so on), and similarly for ab3 and mb4.

---

## Super Hi-Res graphics

The Apple IIGS has two graphics modes that are new to the Apple II family. These are the 320-pixel and 640-pixel Super Hi-Res graphics modes, which increase horizontal resolution to either 320 or 640 pixels and increase vertical resolution to 200 lines. The VGC is primarily responsible for implementing the Super Hi-Res video graphics, which provide these capabilities:

- 320- or 640-pixel horizontal resolution
- 200-line vertical resolution
- 12-bit color resolution that allows choices from 4096 available colors
- 16 colors for each of the 200 lines—up to 256 colors per frame
- Color Fill mode
- scan-line interrupts
- all new video mode features, programmable for each scan line
- linear display buffer
- pixels contained within byte boundaries

### The New-Video register

When a standard Apple II video mode (Lo-Res, Hi-Res, or Double Hi-Res graphics) is enabled, the Mega II accesses the video memory buffers and generates video. When Super Hi-Res mode is enabled, the Video Graphics Controller has sole access to the video buffers. The bit to enable this access, along with the memory map configuration switch, is in the New-Video register located at $C029. The bit descriptions for this register are shown in Figure 4-17. Table 4-17 gives a description of each bit.

⚠️ **Warning**: Be careful when changing bits within this register. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

---

#### Table 4-17: Bits in the New-Video register

| Bit | Value | Description |
|-----|-------|-------------|
| 7 | 0 | Selects Apple II video mode. If this bit is 0, all existing Apple II-compatible video modes are enabled. The Mega II alone reads the video memory during the video cycles and generates the video. |
|   | 1 | Selects Super Hi-Res graphics video modes. If this bit is 1, all standard Apple II video modes are disabled; either 320-pixel resolution (and Color Fill mode) or 640-pixel resolution graphics are enabled. (The selection of 320 or 640 is made in the scan-line control byte for each line.) Also, when this bit is 1, bit 6 is overridden, and the memory map is changed to support the Super Hi-Res graphics video buffer, as described below. (See the description of bit 6.) |
| 6* | 0 | If this bit is 0, the 128K memory map is the same as the Apple IIe. |
|   | 1 | If this bit is 1, the memory map is reconfigured for use with Super Hi-Res graphics video mode: The video buffer becomes one contiguous, linear address space from $2000 through $9D00. (Figure 4-18 shows the Super Hi-Res graphics buffer.) |
| 5 | 0 | If this bit is 0, Double Hi-Res graphics is displayed in color (140 by 192, 16 colors). |
|   | 1 | If this bit is 1, Double Hi-Res graphics is displayed in black-and-white (560 by 192). |
| 4-1 | - | Reserved; do not modify. |
| 0 | 0 | Enable bank latch. If this bit is 1, the 17th address bit is used to select either the main or auxiliary memory bank. If the address bit is 1, then the auxiliary bank is enabled. (Actually data bit 0 is used as the 17th address bit). If the address bit is 0, the state of the memory configuration soft switches determines which memory bank is enabled. See Chapter 3 for descriptions of the memory configuration soft switches. Table 4-18 shows how to use this bit to select a memory bank. |
|   | 1 | The 17th address bit is ignored. |

\* Set bit 6 to 0 whenever using Double Hi-Res graphics mode. This is necessary to ensure that the video display will function properly.

---

#### Figure 4-17: New-Video register

```
                Reserved; do not modify
                        |
        7  6  5  4  3  2  1  0
        |  |  |              |
Enable Super Hi-Res graphics mode
Linearize Super Hi-Res graphics video memory
Color or black-and-white Double Hi-Res graphics
                    Enable bank latch
```

#### Table 4-18: Memory bank selection using bit 0 of the New-Video register

| New-Video register Bit 0 | Data bit 0 | Memory bank enabled |
|---------------------------|------------|---------------------|
| 0 | 1 | Auxiliary |
|   | 0 | Determined by state of memory configuration soft switches |
| 1 | Ignored | - |

---

### The Super Hi-Res graphics buffer

The Super Hi-Res graphics display buffer contains three types of data: scan-line control bytes, color palettes, and pixel data. Figure 4-18 shows a memory map of the display buffer. This buffer resides in contiguous bytes of the auxiliary 64K bank of the slow RAM ($E1) from $2000 through $9FFF. Note that this display buffer uses memory space used for the Apple II Double Hi-Res graphics buffers, but leaves the other graphics and text display buffers untouched.

The next three sections describe the scan-line control bytes, color palettes, and pixel data bytes used in Super Hi-Res graphics mode.

---

#### Figure 4-18: Super Hi-Res graphics display buffer

```
Memory bank $E1
        |
        |
        |
        $9FFF
        
        Color
        palettes
        
        $9E00
        
        Scan-line
        control bytes
        
        $9D00
        
        
        
        
        Pixel
        data
        
        
        
        
        $2000
        |
        |
        |
```

### Scan-line control bytes ($9D00-$9DC7)

An added advantage of the new Apple IIGS video graphics is the ability to select the Super Hi-Res graphics horizontal resolution for each video scan line. The 200 scan-line control bytes (located from $9D00 through $9DC7 as shown in Figure 4-18) control the features for each scan line. There is one 8-bit control byte for each of the 200 scan lines. For each line, you can select:

- the palette (16 colors) to be used on the scan line
- Color Fill mode on the scan line
- an interrupt to be generated on the scan line
- either 320-pixel or 640-pixel resolution for the scan line

---

The scan-line control byte bits and their functions are listed in Figure 4-19. Table 4-19 gives a description of each bit.

⚠️ **Warning**: Be careful when changing bits within this byte. Use only a read-modify-write instruction sequence when manipulating bits. See the warning in the preface. ▲

#### Figure 4-19: Scan-line control byte format

```
                Palette select code
                        |
        7  6  5  4  3  2  1  0
        |  |  |  |
320 or 640 mode
Generate interrupt
Color Fill mode
Reserved; do not modify
```

#### Table 4-19: Bits in a scan-line control byte

| Bit | Value | Description |
|-----|-------|-------------|
| 7 | 1 | Horizontal resolution = 640 pixels. |
|   | 0 | Horizontal resolution = 320 pixels. |
| 6 | 1 | Interrupt enabled for this scan line. (When this bit is a 1, the scan-line interrupt status bit is set at the beginning of the scan line.) |
|   | 0 | Scan-line interrupts disabled for this scan line. |
| 5 | 1 | Color Fill mode enabled. (This mode is available in Super Hi-Res graphics 320-pixel resolution mode only; in 640-pixel mode, Color Fill mode is disabled.) |
|   | 0 | Color Fill mode disabled. |
| 4 | - | Reserved; write 0. |
| 0-3 | - | Palette chosen for this scan line. |

---

The location of the scan-line control byte for each scan line is $9Dxx, where *xx* is the hexadecimal value of the line. For example, the control byte for the first scan line (line 0) is located in memory location $9D00; the control byte for the second scan line (line 1) is in location $9D01, and so forth.

◆ *Note:* The first 200 bytes of the 256 bytes in the memory page beginning at $9D00 are scan-line control bytes, and the remaining 56 bytes are reserved for future expansion. For compatibility with future Apple products, do not modify these 56 bytes.

### Color palettes ($9E00-$9FFF)

A color palette is a group of 16 colors to be displayed on the scan line. Each scan line can have one of 16 color palettes assigned to it. You can choose the 16 colors in each palette from any of the 4096 possible colors. You can draw each pixel on the scan line in any of these 16 colors.

These colors are determined by a 12-bit value made up of three separate 4-bit values. (12 bits allows 2¹² or 4096 possible combinations for each palette color.) Each 4-bit quantity represents the intensity of each red, green, and blue. The combination of the magnitudes of each of the three primary colors determines the resulting color. Figure 4-20 shows the format of each of these 4-bit values that make up a palette color.

#### Figure 4-20: Color palette format

```
Even byte:    Green         Blue
              |             |
              7  6  5  4  3  2  1  0


Odd byte:     Reserved; do not modify    Red
                        |                 |
              7  6  5  4  3  2  1  0
```

---

The color palettes are located in video buffer locations $9E00 through $9FFF in bank $E0. There are 16 color palettes in this space, with 32 bytes per palette. Each color palette represents 16 colors, with 2 bytes per color. The palette indicated in the scan-line control byte is used to display the pixels in color on the scan line. The starting address for each of the color palettes and the colors within them are listed in Table 4-20. The 16 colors within a palette have numbers $0 through $F. Note that each color begins on an even address.

Once you have filled the palettes with the colors to be used and selected the display modes within each of the scan-line control bytes, you must choose which of the 16 colors you are going to display for each pixel.

#### Table 4-20: Palette and color starting addresses

| Palette number | Color$0 | Color $1 | ... | Color $E | Color $F |
|----------------|---------|----------|-----|----------|----------|
| $0 | $9E00-01 | $9E02-03 | ... | $9E1C-1D | $9E1E-1F |
| $1 | $9E20-21 | $9E22-23 | ... | $9E3C-3D | $9E3E-3F |
| $2 | $9E40-41 | $9E42-43 | ... | $9E5C-5D | $9E5E-5F |
| . | . | . | . | . | . |
| . | . | . | . | . | . |
| . | . | . | . | . | . |
| $F | $9FE0-E1 | $9FE2-E3 | ... | $9FFC-FD | $9FFE-FF |

---

### Pixels

The Super Hi-Res graphics color information for each pixel is different for each of the two resolution modes: 4 bits represent each pixel color in 320-pixel mode; 2 bits represent the pixel color in 640-pixel mode. Higher resolution comes with a slight penalty, however: Although in 320 mode a pixel may be any of 16 colors chosen from the palette, a pixel may be one of only 4 colors in 640 mode.

The pixel data are located in the display buffer in a linear and contiguous manner; $2000 corresponds to the upper-left corner of the display, and $9CFF corresponds to the lower-right corner. Each scan line uses 160 ($A0) bytes. Figure 4-21 shows the format in which the pixel color data are stored in both the 320-pixel and 640-pixel modes.

---

#### Figure 4-21: Pixel data byte format

```
Bits in byte:  7  6  5  4  3  2  1  0
               |  |  |  |  |  |  |  |
               
640 mode:      Pixel 1  Pixel 2  Pixel 3  Pixel 4
               
320 mode:      Pixel 1         Pixel 2
```

In 320-pixel mode, four bits determine each pixel color, and data are stored two pixels to a byte of the display buffer. Since four bits determine the pixel color, in 320 mode each pixel can be any of the 16 colors from that palette.

In 640-pixel mode, color selection is more complicated. The 640 pixels in each horizontal line occupy 160 adjacent bytes of memory, each byte representing 4 pixels that appear side-by-side on the screen. The 16 colors in the palette are divided into four groups of 4 colors each. The first pixel in each horizontal line can select one of 4 colors from the third group of 4 in the palette. The second pixel selects from the fourth group of 4 colors in the palette. The third pixel selects from the first group of 4 colors, and the fourth pixel selects from the second group, as shown in Table 4-21. The process repeats for each successive group of 4 pixels in a horizontal line. Thus, even though a given pixel can be one of 4 colors, different pixels in a line can take on any of the 16 colors in a palette.

#### Table 4-21: Color selection in 640 mode

| Pixel | Value | Palette color | Pixel | Value | Palette color |
|-------|-------|---------------|-------|-------|---------------|
| 3 | 0 | $0 | 1 | 0 | $8 |
|   | 1 | $1 |   | 1 | $9 |
|   | 2 | $2 |   | 2 | $A |
|   | 3 | $3 |   | 3 | $B |
| 4 | 0 | $4 | 2 | 0 | $C |
|   | 1 | $5 |   | 1 | $D |
|   | 2 | $6 |   | 2 | $E |
|   | 3 | $7 |   | 3 | $F |

---

Figure 4-22 shows the display screen and the pixels that make up each scan line. Also shown are the pixel data bytes for both 640- and 320-pixel Super Hi-Res graphics mode. The scan-line control bytes, one for each scan line, are shown at the right.

#### Figure 4-22: Drawing pixels on the screen

[*Diagram showing a video display screen with two magnified views:*

1. **640-pixel mode** (top circle): Shows a pixel data byte divided into positions 1, 2, 3, 4 and how these map to 8 pixels on screen

2. **320-pixel mode** (bottom circle): Shows a pixel data byte divided into positions 1, 2 and how these map to 4 pixels on screen

The main screen shows scan lines running horizontally with scan-line control bytes shown on the right side from $9D00 at top to $9DC7 at bottom]

---

### Dithering

In Super Hi-Res graphics mode using 640-pixel resolution, colors other than the available 4 palette colors may be displayed by patterns called **dithering**. By choosing 2 adjacent pixel colors that mix to obtain a third desired color, you can increase the number of hues available. For example, in Figure 4-23, when red is selected from the available colors, the scan line appears as red. Alternating red and yellow results in orange, and so on. Through the use of dithering, as many as 16 colors can be generated.

### Color Fill mode

Another feature of Apple IIGS video graphics is Color Fill, an option that simplifies the task of painting continuous color on any one line. Color Fill, which is available in 320-pixel mode only, is used to fill rapidly a large area of the video display with a single color. In this mode, color $0 in the palette takes on a unique definition. Any pixel data byte containing the color value $0 causes that pixel to take on the color of the previous pixel instead of displaying a palette color. This means that only 15 unique palette colors ($1 through $F) are available for each scan line, rather than 16 colors. For example, assume that A, B, and C represent 3 different palette colors, 4 bits per pixel. These colors do not include color $0. The desired color pattern for a series of pixels on a line might be as follows without Color Fill mode:

```
AAAAAAAAAAAAABBBBBBBBBBBBBCCCCCCCCCCCC
```

The same color pattern would be created by using Color Fill mode as follows:

```
A00000000000B00000000000C00000000000
```

Method 2 would save time: The program only needs to fill the pixel area of the scan line once with 0, and then to write a color value into those locations where a color should begin or change. In the example just given, only one byte needs to be written to implement each new color on the scan line using the Color Fill method, as opposed to six bytes per color without Color Fill.

The only restriction of the Color Fill mode is that the first pixel value on a scan line must not be 0; if the first pixel value is 0, then an undetermined color results.

---

### Figure 4-23: Examples of dithering

```
                Color
             ┌─────────┐
             │  White  │
Minipalette 1├─────────┤     Selecting the red palette color
             │   Red   │     will result in a red scan line
             ├─────────┤
             │  Blue   │     Pixels─ R  R  R  R  R  R  R  R  R
             ├─────────┤                    ↓
             │  Black  │                Scan line
             ├─────────┤
             │  White  │
             ├─────────┤
Minipalette 2│   Red   │
             ├─────────┤
             │  Blue   │
             ├─────────┤
             │  Black  │
             ├─────────┤
             │  White  │
             ├─────────┤
Minipalette 3│   Red   │
             ├─────────┤
             │  Blue   │
             ├─────────┤
             │  Black  │
             ├─────────┤
             │  White  │
Minipalette 4├─────────┤
             │   Red   │
             ├─────────┤
             │  Blue   │
             ├─────────┤
             │  Black  │
             └─────────┘


                Color
             ┌─────────┐
             │  White  │
Minipalette 1├─────────┤
             │ Yellow  │
             ├─────────┤     Selecting alternate red and yellow palette
             │  Green  │     color will result in an orange scan line
             ├─────────┤
             │  Black  │     Pixels─ Y  R  Y  R  Y  R  Y  R  Y
             ├─────────┤                    ↓
             │  White  │                Scan line
Minipalette 2├─────────┤
             │   Red   │
             ├─────────┤
             │  Blue   │
             ├─────────┤
             │  Black  │
             ├─────────┤
             │  White  │
Minipalette 3├─────────┤
             │ Yellow  │
             ├─────────┤
             │  Green  │
             ├─────────┤
             │  Black  │
             ├─────────┤
             │  White  │
Minipalette 4├─────────┤
             │   Red   │
             ├─────────┤
             │  Blue   │
             ├─────────┤
             │  Black  │
             └─────────┘
```

---

