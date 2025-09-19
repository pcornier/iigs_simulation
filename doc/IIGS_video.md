[cite_start]The Apple IIGS supports multiple video modes, including those compatible with the earlier Apple II family and new, higher-resolution modes with greater color flexibility[cite: 723, 724]. [cite_start]This chapter details enhancements to standard Apple II video modes and introduces new features like Super Hi-Res graphics[cite: 725, 727, 728].

## Apple IIGS display features
[cite_start]The Apple IIGS enhances existing Apple II video modes with new features such as selectable colors for the screen border, background, and text, as well as the option for color or black-and-white composite video[cite: 731, 732, 733, 734, 735].

---
### Video from the Mega II IC
[cite_start]In standard Apple II video modes, the Mega II chip generates all video information[cite: 738]. [cite_start]It produces a 4-bit binary code representing one of 16 standard Apple II colors[cite: 739]. [cite_start]This code is sent to the Video Graphics Controller (VGC), which uses it as a lookup address to produce a 12-bit RGB color value[cite: 740]. [cite_start]A digital-to-analog converter then creates three analog RGB signals[cite: 741]. [cite_start]These signals are amplified and also processed by an NTSC generator to create a composite video signal[cite: 742, 743].

---
### The Video Graphics Controller
[cite_start]The Video Graphics Controller (VGC) is a custom IC that generates all video output on the Apple IIGS[cite: 745]. Its functions include:
* [cite_start]Generating video output from standard Apple II video information provided by the Mega II[cite: 746].
* [cite_start]Adding enhancements to these existing video modes[cite: 747].
* [cite_start]Supporting the new video modes[cite: 748].
* [cite_start]Handling two sources of interrupts[cite: 749].

[cite_start]While the VGC generates all video output, the Mega II is responsible for managing the video RAM[cite: 752]. [cite_start]All write operations to the video display buffers in banks $E0 and $E1 are handled by the Mega II[cite: 753].

---
### VGC Interrupts
[cite_start]The VGC can generate two types of internal interrupts: a one-second interrupt and a scan-line interrupt[cite: 811].
* [cite_start]**One-second interrupt**: Triggered by a 1-Hz signal from the real-time clock (RTC) chip[cite: 812].
* [cite_start]**Scan-line interrupt**: Occurs at the start of a video scan line when the corresponding "generate-interrupt" bit is set in that line's control byte[cite: 813]. [cite_start]This interrupt is only available in Super Hi-Res video modes[cite: 814]. [cite_start]The interrupt triggers at the beginning of the right-hand border area for the specified scan line[cite: 816].

---
### The VGC Interrupt register
[cite_start]Located at memory address $C023, the VGC Interrupt register contains status and enable bits for both the one-second and scan-line interrupts[cite: 827]. [cite_start]When an interrupt's status bit and enable bit are both set, the main VGC interrupt bit (bit 7) is set, and an interrupt request (IRQ) is sent[cite: 829]. [cite_start]You can enable interrupts by writing to the register, but only the enable bits can be directly manipulated by software[cite: 830, 831].

> **Warning**
> [cite_start]Use a read-modify-write instruction sequence when changing bits in this register[cite: 835].

[cite_start]**Figure 4-3: VGC Interrupt register at $C023** [cite: 838]
* [cite_start]**Bit 7**: VGC Interrupt status [cite: 844]
* [cite_start]**Bit 6**: 1-second Interrupt status [cite: 845]
* [cite_start]**Bit 5**: Scan-line Interrupt status [cite: 846]
* [cite_start]**Bits 4-3**: Reserved; do not modify [cite: 847, 848]
* [cite_start]**Bit 2**: 1-second Interrupt enable [cite: 849]
* [cite_start]**Bit 1**: Scan-line Interrupt enable [cite: 850]
* [cite_start]**Bit 0**: Reserved; do not modify [cite: 851]

[cite_start]**Table 4-1: Bits in the VGC Interrupt register** [cite: 854]

| Bit | Value | Description |
| :-- | :--- | :--- |
| 7 | 1 | [cite_start]VGC interrupt status: Set when an enabled interrupt has occurred[cite: 853]. |
| | 0 | [cite_start]All interrupts have been cleared[cite: 853]. |
| 6 | 1 | [cite_start]One-second interrupt has occurred[cite: 853]. |
| | 0 | [cite_start]One-second interrupt is cleared[cite: 853]. |
| 5 | 1 | [cite_start]A scan-line interrupt has occurred[cite: 853]. |
| | 0 | [cite_start]Scan-line interrupt is cleared[cite: 853]. |
| 4-3 | | [cite_start]Reserved; do not modify[cite: 853]. |
| 2 | 1 | [cite_start]One-second interrupt is enabled[cite: 853]. |
| | 0 | [cite_start]One-second interrupt is disabled[cite: 853]. |
| 1 | 1 | [cite_start]Scan-line interrupt is enabled[cite: 853]. |
| | 0 | [cite_start]Scan-line interrupt is disabled[cite: 853]. |
| 0 | | [cite_start]Reserved; do not modify[cite: 853]. |

---
### The VGC Interrupt-Clear register
[cite_start]To clear the status bits for the scan-line and one-second interrupts, you must write a 0 to the corresponding bit in the VGC Interrupt-Clear register at memory address $C032[cite: 857]. [cite_start]Writing a 1 has no effect[cite: 859]. [cite_start]Bit 5 clears the scan-line interrupt, and bit 6 clears the one-second interrupt[cite: 858].

> **Warning**
> Be careful when changing bits within this register. [cite_start]Use only a read-modify-write instruction sequence[cite: 862].

[cite_start]**Table 4-2: Bits in the VGC Interrupt-Clear register** [cite: 875]

| Bit | Value | Description |
| :-- | :--- | :--- |
| 7 | | [cite_start]Reserved; do not modify[cite: 872]. |
| 6 | 0 | [cite_start]Write a 0 here to clear the one-second interrupt[cite: 872]. |
| | 1 | [cite_start]Undefined result[cite: 872]. |
| 5 | 0 | [cite_start]Write a 0 here to clear the scan-line interrupt[cite: 872]. |
| | 1 | [cite_start]Undefined result[cite: 872]. |
| 4-0 | | [cite_start]Reserved; do not modify[cite: 872]. |

## Video outputs
[cite_start]The Apple IIGS supports and enhances several standard Apple II video modes[cite: 878]:
* [cite_start]40-column and 80-column text modes [cite: 879]
* [cite_start]Mixed text/graphics mode [cite: 880]
* [cite_start]Lo-Res graphics mode [cite: 881]
* [cite_start]Hi-Res graphics mode [cite: 882]
* [cite_start]Double Hi-Res graphics mode [cite: 883]

[cite_start]Enhancements include selectable text, background, and border colors from a 16-color palette, as well as the ability to display gray-scale video on monochrome monitors, which improves contrast[cite: 887, 888, 890]. [cite_start]Removing color from the composite signal in text modes makes text more readable, though color fringing can still occur in mixed text/graphics modes[cite: 893, 894].

[cite_start]**Table 4-3: Text and background colors** [cite: 891]

| Color value | Color | Color value | Color |
| :--- | :--- | :--- | :--- |
| $0 | Black | $8 | Brown |
| $1 | Deep red | $9 | Orange |
| $2 | Dark blue | $A | Light gray |
| $3 | Purple | $B | Pink |
| $4 | Dark green | $C | Green |
| $5 | Dark gray | $D | Yellow |
| $6 | Medium blue | $E | Aquamarine |
| $7 | Light blue | $F | White |

---
### Apple II video
[cite_start]The Apple IIGS can be used with any standard NTSC-compatible composite video monitor, either color or monochrome[cite: 900, 901]. [cite_start]For 40-column text and Lo-Res graphics, a television set can also be used, either with a direct composite connection or via an RF modulator[cite: 903, 904, 905]. [cite_start]However, 80-column text will be blurry on a standard TV; a high-resolution monitor with at least 7 MHz bandwidth is required for a clear display[cite: 907, 908].

[cite_start]The computer provides an NTSC-compatible composite color video signal at both an RCA-type phono jack and the RGB video connector[cite: 910, 911]. [cite_start]The RCA jack is for composite monitors, while the RGB connector is for analog-input RGB monitors[cite: 912, 913].

[cite_start]**Table 4-4: Standard Apple II video display specifications** [cite: 919]
* [cite_start]**Text capacity**: 24 lines by 80 columns, with 128 ASCII characters available[cite: 927]. [cite_start]Text can be displayed in normal, inverse, flashing, or MouseText formats[cite: 930].
* [cite_start]**Lo-Res color graphics**: 40 horizontal by 48 vertical blocks in 16 colors[cite: 930]. [cite_start]In mixed mode, the bottom 8 rows are replaced by 4 lines of text[cite: 942].
* [cite_start]**Hi-Res color graphics**: 140 horizontal by 192 vertical pixels in 6 colors (with restrictions), or 280x192 in black-and-white[cite: 932, 933]. [cite_start]In mixed mode, the bottom 32 rows are replaced by text, leaving 160 rows of pixels[cite: 947].
* [cite_start]**Double Hi-Res color graphics**: 140 horizontal by 192 vertical pixels in 16 colors (no restrictions), or 560x192 in black-and-white[cite: 935]. [cite_start]Mixed mode is only available with 80-column text[cite: 939].

---
### NTSC versus RGB video
[cite_start]The computer provides both a composite video signal and separate RGB (red, green, blue) signals[cite: 1151, 1152]. [cite_start]The RGB video connector is for analog-input RGB monitors only[cite: 1154].

[cite_start]**Table 4-5: RGB video signals** [cite: 1163]

| Pin | Signal | Description |
| :-- | :--- | :--- |
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
### Video display pages
[cite_start]Video displays are generated from data stored in specific memory areas called display pages[cite: 1168, 1169]. [cite_start]Each byte in a display page controls an object on the screen, such as a character, a pair of colored blocks, or a line of pixels[cite: 1170, 1171, 1172].

* [cite_start]**40-column text and Lo-Res graphics**: Use two 1024-byte pages, Page 1 ($0400-$07FF) and Page 2 ($0800-$0BFF), in main memory[cite: 1173, 1174].
* [cite_start]**80-column text**: Uses a combination of text Page 1 in main memory and a corresponding page in auxiliary memory[cite: 1178]. [cite_start]It does not support page switching[cite: 1177].
* [cite_start]**Hi-Res graphics**: Uses two 8192-byte pages[cite: 1182].
* [cite_start]**Double Hi-Res graphics**: Uses Hi-Res graphics Page 1 in both main and auxiliary memory[cite: 1186].

[cite_start]**Table 4-6: Video display locations** [cite: 1193]

| Display mode | Display page | Lowest address (Hex/Dec) | Highest address (Hex/Dec) |
| :--- | :--- | :--- | :--- |
| 40-column text, Lo-Res graphics | 1 | $0400 / 1024 | $07FF / 2047 |
| | 2 | $0800 / 2048 | $0BFF / 3071 |
| 80-column text | 1 | $0400 / 1024 | $07FF / 2047 |
| | 2 | $0800 / 2048 | $0BFF / 3071 |
| Hi-Res graphics | 1 | $2000 / 8192 | $3FFF / 16383 |
| | 2 | $4000 / 16384 | $5FFF / 24575 |
| Double High-Res graphics | 1+ | $2000 / 8192 | $3FFF / 16383 |
| | 2+ | $4000 / 16384 | $5FFF / 24575 |

---
### Display mode switching
[cite_start]Display modes are selected by reading from or writing to reserved memory locations known as "soft switches"[cite: 1199]. [cite_start]Most switches have separate locations for turning a feature on, turning it off, and reading its current status[cite: 1200]. [cite_start]When writing to a soft switch, the value written is ignored; the action occurs simply by addressing the location[cite: 1209].

[cite_start]**Table 4-7: Display soft switches** [cite: 1212]

| Name | Action | Location | Function |
| :--- | :--- | :--- | :--- |
| CLR80COL | W | $C000 (49152) | [cite_start]Disable 80-column store[cite: 1213]. |
| SET80COL | W | $C001 (49153) | [cite_start]Enable 80-column store[cite: 1213]. |
| CLR80VID | W | $C00C (49164) | [cite_start]Disable 80-column hardware[cite: 1213]. |
| SET80VID | W | $C00D (49165) | [cite_start]Enable 80-column hardware[cite: 1213]. |
| CLRALTCHAR | W | $C00E (49166) | [cite_start]Normal lowercase character set; flashing uppercase character set[cite: 1213]. |
| SETALTCHAR | W | $C00F (49167) | [cite_start]Normal, inverse character set; no flashing[cite: 1213]. |
| RDTEXT | R7 | $C01A (49178) | [cite_start]Read TXTCLR/TXTSET switch: 1=text mode enabled[cite: 1213]. |
| RDPAGE2 | R7 | $C01C (49180) | [cite_start]Read TXTPAGE1/TXTPAGE2 switch: 1=text Page 2 selected[cite: 1213]. |
| RDHIRES | R7 | $C01D (49181) | [cite_start]Read HIRES switch: 1=Hi-Res mode enabled[cite: 1213]. |
| TXTCLR | R/W | $C050 (49232) | [cite_start]Select standard Apple II graphics mode[cite: 1218]. |
| TXTSET | R/W | $C051 (49233) | [cite_start]Select text mode only[cite: 1218]. |
| MIXCLR | R/W | $C052 (49234) | [cite_start]Clear mixed mode[cite: 1218]. |
| MIXSET | R/W | $C053 (49235) | [cite_start]Select mixed mode[cite: 1218]. |
| TXTPAGE1 | R/W | $C054 (49236) | [cite_start]Select text Page 1[cite: 1218]. |
| TXTPAGE2 | R/W | $C055 (49237) | [cite_start]Select text Page 2[cite: 1218]. |
| LORES | R/W | $C056 (49238) | [cite_start]Select Lo-Res graphics mode[cite: 1218]. |
| HIRES | R/W | $C057 (49239) | [cite_start]Select Hi-Res graphics mode[cite: 1218]. |
| CLRAN3 | R/W | $C05E (49246) | [cite_start]See Table 4-8[cite: 1218]. |
| SETAN3 | R/W | $C05F (49247) | [cite_start]See Table 4-8[cite: 1218]. |

---
### The text window
[cite_start]You can restrict video output to a rectangular portion of the screen called the text window[cite: 1263, 1264]. [cite_start]This is done by storing values in specific memory locations that define the window's top, bottom, left side, and width[cite: 1265].

[cite_start]**Table 4-9: Text window memory locations** [cite: 1287]

| Window parameter | Location (Dec/Hex) | Normal values (40/80-col) | Maximum values (40/80-col) |
| :--- | :--- | :--- | :--- |
| Left edge | 32 / $20 | 00 / 00 | 39 / 79 |
| Width | 33 / $21 | 40 / 80 | 40 / 80 |
| Top edge | 34 / $22 | 00 / 00 | 23 / 23 |
| Bottom edge | 35 / $23 | 24 / 24 | 24 / 24 |

> **Warning**
> [cite_start]The sum of the window's width and its leftmost position should not exceed the display width (40 or 80)[cite: 1276]. [cite_start]Also, ensure the cursor position is within the new window boundaries after a change[cite: 1284]. [cite_start]Doing otherwise could destroy programs or data[cite: 1277, 1285].

---
### Text displays
[cite_start]The Apple IIGS can display text in 40x24 or 80x24 modes[cite: 1291]. [cite_start]The 80-column characters are half as wide as the 40-column characters[cite: 1337]. [cite_start]Each character occupies a 7x8 pixel area on the screen[cite: 1297]. [cite_start]The system offers two main character sets: a primary set and an alternate set, selected via a soft switch[cite: 1303, 1324].
* [cite_start]**Primary set**: Compatible with older Apple II software, it supports normal, inverse, and flashing formats for uppercase letters, but only normal format for lowercase letters[cite: 1309, 1310].
* [cite_start]**Alternate set**: Supports normal and inverse formats for both uppercase and lowercase letters, as well as MouseText characters in inverse format[cite: 1313, 1319]. [cite_start]Flashing is not available in this set[cite: 1330].

[cite_start]**Table 4-10: Display character sets** [cite: 1332]

| Hex values | Primary character set (Type/Format) | Alternate character set (Type/Format) |
| :--- | :--- | :--- |
| $00-$1F | Uppercase letters / Inverse | Uppercase letters / Inverse |
| $20-$3F | Special characters / Inverse | Special characters / Inverse |
| $40-$5F | Uppercase letters / Flashing | MouseText / Inverse |
| $60-$7F | Special characters / Flashing | Lowercase letters / Inverse |
| $80-$9F | Uppercase letters / Normal | Uppercase letters / Normal |
| $A0-$BF | Special characters / Normal | Special characters / Normal |
| $C0-$DF | Uppercase letters / Normal | Uppercase letters / Normal |
| $E0-$FF | Lowercase letters / Normal | Lowercase letters / Normal |

---
### Color text
[cite_start]A new feature of the Apple IIGS is the ability to set separate colors for the text, background, and border[cite: 1432]. [cite_start]These can be set through the Control Panel or programmatically via registers[cite: 1433, 1456].
* [cite_start]**Text and Background Color**: The Screen Color register at $C022 controls these[cite: 1436]. [cite_start]The upper 4 bits set the text color, and the lower 4 bits set the background color, chosen from the 16 colors in Table 4-3[cite: 1437, 1438, 1439].
* [cite_start]**Border Color**: The Border Color register at $C034 controls the border color[cite: 1454]. [cite_start]Its lower 4 bits set the color[cite: 1459]. [cite_start]The upper 4 bits are used for the real-time clock and should not be modified when changing the border color[cite: 1460, 1475].
* [cite_start]**Monochrome/Color**: The Monochrome/Color register at $C021 controls whether the composite video signal is in color or grayscale[cite: 1478]. [cite_start]Setting bit 7 to 1 produces black-and-white (grayscale) output, which improves text readability on monochrome monitors[cite: 1479, 1482]. [cite_start]This setting does not affect the RGB outputs[cite: 1503].

## Graphics displays
[cite_start]The Apple IIGS supports three standard Apple II graphics modes, plus two new Super Hi-Res modes[cite: 1507].

---
### Lo-Res graphics
[cite_start]This mode displays a 48x40 grid of colored blocks, with 16 colors available[cite: 1518, 1519]. [cite_start]Data is stored in the same memory area as 40-column text[cite: 1522]. [cite_start]Each byte defines two vertically stacked blocks; the low-order 4 bits (nibble) control the top block's color, and the high-order nibble controls the bottom block's color[cite: 1523, 1527].

---
### Hi-Res graphics
[cite_start]This mode displays a 192-row array of either 280 monochrome pixels or 140 colored pixels[cite: 1539]. [cite_start]The lower number of colored pixels is because it takes two bits to define one colored pixel on screen[cite: 1540]. [cite_start]The display is bit-mapped, with the 7 low-order bits of each byte in the display page controlling 7 adjacent pixels on the screen[cite: 1546, 1547]. [cite_start]The most significant bit (bit 7) is not displayed but is used to select one of two color sets[cite: 1549, 1550].

[cite_start]On a color monitor, color is determined by pixel position and adjacent pixels[cite: 1571].
* [cite_start]Pixels in even-numbered columns can be purple or blue[cite: 1573, 1578].
* [cite_start]Pixels in odd-numbered columns can be green or orange[cite: 1574, 1578].
* [cite_start]Two adjacent "on" pixels will both appear white[cite: 1575].
* [cite_start]The choice between the purple/green set and the blue/orange set is controlled by bit 7 of the data byte[cite: 1576, 1586].

---
### Double Hi-Res graphics
[cite_start]This mode displays a 192-row array that is 560 pixels wide in monochrome or 140 pixels wide in color[cite: 1596]. [cite_start]It uses 16 colors with no restrictions on which colors can be adjacent[cite: 1597, 1605]. [cite_start]The display is a bit-mapping of the bytes in both main and auxiliary memory from $2000 to $3FFF[cite: 1602]. [cite_start]The bytes from main and auxiliary memory are interleaved, similar to 80-column text[cite: 1603]. [cite_start]Color is determined by any 4 adjacent pixels along a line[cite: 1606].

---
### Super Hi-Res graphics
[cite_start]The Apple IIGS introduces two new graphics modes: 320-pixel and 640-pixel Super Hi-Res[cite: 1615]. [cite_start]These modes increase the vertical resolution to 200 lines and are managed by the VGC[cite: 1615, 1616]. Features include:
* [cite_start]Horizontal resolution of 320 or 640 pixels[cite: 1617].
* [cite_start]A choice of colors from a palette of 4096[cite: 1619].
* [cite_start]16 colors available for each of the 200 scan lines[cite: 1620].
* [cite_start]A "Color Fill" mode for rapidly filling areas with a single color[cite: 1621].
* [cite_start]Scan-line interrupts[cite: 1622].
* [cite_start]A linear display buffer[cite: 1624].

---
### The New-Video register
[cite_start]The New-Video register at $C029 contains bits to enable Super Hi-Res graphics and configure the memory map[cite: 1629]. [cite_start]Bit 7 enables Super Hi-Res modes, giving the VGC sole access to the video buffers[cite: 1628, 1638].

[cite_start]**Table 4-17: Bits in the New-Video register** [cite: 1637]

| Bit | Value | Description |
| :-- | :--- | :--- |
| 7 | 0 | [cite_start]Selects standard Apple II video modes[cite: 1638]. |
| | 1 | [cite_start]Selects Super Hi-Res graphics modes (320 or 640)[cite: 1638]. |
| 6 | 0 | [cite_start]Memory map is the same as the Apple IIe[cite: 1638]. |
| | 1 | [cite_start]Reconfigures memory map for a contiguous Super Hi-Res video buffer ($2000-$9D00)[cite: 1638]. |
| 5 | 0 | [cite_start]Double Hi-Res graphics is displayed in color (140x192)[cite: 1638]. |
| | 1 | [cite_start]Double Hi-Res graphics is displayed in black-and-white (560x192)[cite: 1638]. |
| 4-1 | | [cite_start]Reserved; do not modify[cite: 1638]. |
| 0 | 0/1 | [cite_start]Enables bank latch to select main or auxiliary memory bank using address bit 17[cite: 1638]. |

---
### The Super Hi-Res graphics buffer
[cite_start]The Super Hi-Res buffer is located in a contiguous block of memory in bank $E1, from $2000 to $9FFF[cite: 1657]. [cite_start]It contains three types of data: pixel data, scan-line control bytes, and color palettes[cite: 1655].

* [cite_start]**Scan-line control bytes ($9D00-$9DC7)**: There is one 8-bit control byte for each of the 200 scan lines[cite: 1674]. [cite_start]Each byte allows you to set the resolution (320 or 640), enable an interrupt, enable Color Fill mode, and select one of 16 color palettes for that specific line[cite: 1675, 1676, 1677].
* [cite_start]**Color palettes ($9E00-$9FFF)**: This area holds 16 color palettes, with each palette containing 16 colors[cite: 1707, 1731]. [cite_start]Each color is a 12-bit value (4 bits each for red, green, and blue), allowing for a total of 4096 possible colors[cite: 1708, 1710]. [cite_start]Each scan line can be assigned one of these 16 palettes[cite: 1707].
* [cite_start]**Pixels ($2000-$9CFF)**: The pixel data is stored in a linear fashion, with $2000 corresponding to the top-left corner of the screen[cite: 1743, 1744].
    * In **320-pixel mode**, each pixel is represented by 4 bits, allowing it to be any of the 16 colors in the selected palette. [cite_start]Two pixels are stored per byte[cite: 1741, 1758].
    * In **640-pixel mode**, each pixel is represented by 2 bits. [cite_start]Four pixels are stored per byte[cite: 1742, 1760]. [cite_start]A pixel can be one of 4 colors, with the available 4 colors determined by the pixel's position within a 4-pixel group[cite: 1742, 1761, 1762].

---
### Dithering
[cite_start]In 640-pixel Super Hi-Res mode, more colors can be simulated by using a technique called **dithering**[cite: 1789]. [cite_start]By alternating adjacent pixels of different colors, the eye perceives a new, mixed color[cite: 1790]. [cite_start]For example, alternating red and yellow pixels can create the appearance of orange[cite: 1792]. [cite_start]This technique can generate up to 16 apparent colors[cite: 1793].

---
### Color Fill mode
[cite_start]Available only in 320-pixel mode, **Color Fill** is a feature that simplifies filling large areas with a single color[cite: 1795, 1796]. [cite_start]When enabled for a scan line, any pixel with the data value $0 will take on the color of the previous pixel on that line[cite: 1797, 1798]. [cite_start]This allows a programmer to define a color at the start of a region and then fill the rest of the region with zeroes, which is much faster than writing the same color value repeatedly[cite: 1804]. [cite_start]The first pixel on a line cannot be 0, as this would result in an undetermined color[cite: 1806, 1807].
