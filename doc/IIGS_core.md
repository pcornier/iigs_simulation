[cite_start]The Apple IIGS has a significantly different design from a standard Apple II, primarily because of three components: the **65C816 microprocessor**, the **Mega II custom IC**, and the **FPI (Fast Processor Interface) custom IC**[cite: 2, 3, 4, 5, 6, 7]. [cite_start]The 65C816 processor is more powerful than the 6502 in older Apple IIs but can still run 6502 programs[cite: 8]. [cite_start]It features a larger address space and can operate faster than the standard 1.024 MHz speed[cite: 9]. [cite_start]The ability to use these features while maintaining backward compatibility is managed by two custom integrated circuits: the Mega II and the FPI[cite: 10, 11].

[cite_start]A block diagram of the Apple IIGS shows that the system is broadly separated into two parts: one controlled by the Mega II and the other by the FPI[cite: 15, 16].

---
## The Mega II Custom IC

[cite_start]The Mega II custom IC integrates the functions of several circuits from the Apple IIe, including the Memory Management Unit (MMU), the Input/Output Unit (IOU), character generator ROMs, and video display circuitry[cite: 78, 79, 80, 81, 82]. [cite_start]It essentially contains the logic for all major functions of an Apple IIe on a single chip, excluding the processor and memory[cite: 83].

[cite_start]The "Mega II side" of the computer consists of the Mega II itself, 128K of memory, I/O expansion slots, built-in I/O ports, and video display circuitry[cite: 85, 86, 87, 88, 89, 90]. [cite_start]This side of the system, which includes the video display buffers, always runs at a **1.024 MHz speed** and is sometimes called "Apple II standard memory" or "slow memory"[cite: 94, 95]. [cite_start]The Mega II handles video signal generation, I/O address decoding, and refresh cycles for the 128K of RAM it controls[cite: 91, 92, 93].

---
## The FPI Custom IC

[cite_start]The FPI (Fast Processor Interface) custom IC manages the 65C816 microprocessor and its large, fast memory[cite: 99]. [cite_start]It controls the fast memory and also mediates the interaction between the fast side of the system and the slower Mega II side[cite: 100]. [cite_start]This division allows the Apple IIGS to run programs at **2.8 MHz** while still maintaining the 1.024 MHz operation needed for video and I/O compatibility[cite: 100].

[cite_start]Memory controlled by the FPI includes built-in RAM (128K or 1MB), built-in ROM (128K or 256K), and expansion memory[cite: 102]. [cite_start]The FPI also provides the necessary refresh cycles for this fast RAM[cite: 103]. [cite_start]These refresh cycles reduce the effective processor speed by about 8% for programs running in RAM, but programs running from ROM operate at the full 2.8 MHz speed[cite: 104, 105].

### Synchronization
[cite_start]When data needs to be transferred between the FPI and Mega II sides of the system, the FPI must synchronize with the 1.024 MHz clock of the Mega II[cite: 110]. [cite_start]For a single access to the Mega II side, this can cause a delay of up to 1 microsecond[cite: 112]. [cite_start]If consecutive Mega II cycles are needed (for example, to run older Apple II software), the FPI generates one processor cycle for each Mega II cycle, effectively slowing the processor to 1.024 MHz[cite: 113].

[cite_start]Additionally, to ensure correct NTSC video color display, every 65th processor cycle is "stretched" by 140 nanoseconds, a practice common to all Apple II computers[cite: 114, 115].

### The Mega II Cycle
[cite_start]A Mega II cycle is required for any operation that needs to access the 1.024 MHz side of the system[cite: 129]. These operations include:
* [cite_start]Most I/O operations[cite: 131].
* [cite_start]Shadowed video-write operations[cite: 132].
* [cite_start]Inhibited memory accesses[cite: 133].
* [cite_start]Accesses to memory banks $E0 and $E1[cite: 134].

[cite_start]When the FPI detects an address that requires a Mega II cycle, it holds the processor's ø2 clock high until it synchronizes with the Mega II, after which the memory or I/O access can begin[cite: 136, 139, 140].

---
## Memory Management

### Memory Allocation
[cite_start]The FPI controller can access a minimum of 128K of fast RAM (or 1 MB on newer logic boards), which is separate from the 128K of slow RAM controlled by the Mega II[cite: 149, 150]. [cite_start]The FPI also has access to 128K of ROM (or 256K), which can be expanded[cite: 151]. [cite_start]The memory map shows fast RAM in banks like $00-$01, slow RAM in banks $E0-$E1, and fast ROM in banks starting at $F0[cite: 156].

### Memory Shadowing
[cite_start]**Memory shadowing** is a technique where an I/O location or video buffer is duplicated in the fast RAM space[cite: 206, 207]. [cite_start]Its purpose is to optimize system speed[cite: 252]. [cite_start]When shadowing is enabled, a write to a shadowed video address in fast RAM (e.g., in bank $00 or $01) results in a duplicate write to the corresponding slow RAM location in bank $E0 or $E1[cite: 208, 254]. [cite_start]This write operation forces the system to slow down to 1.024 MHz briefly[cite: 253]. [cite_start]However, read operations can access the "shadowed" copy in high-speed RAM directly, minimizing the performance impact of video updates[cite: 255, 256].

[cite_start]Shadowing is typically enabled only for banks **$00 and $01**[cite: 259]. [cite_start]Enabling it for all RAM banks is not recommended, as it can corrupt firmware and cause a system crash[cite: 260, 261, 262].

### The Shadow Register ($C035)
[cite_start]The Shadow register, located at address **$C035**, controls which specific address ranges are shadowed[cite: 266]. [cite_start]Each bit in this register can be used to inhibit (turn off) shadowing for a particular memory area, such as Text Page 1, Hi-Res graphics pages, or the I/O space[cite: 267, 299].

| Bit | [cite_start]Function [cite: 287] |
| :-- | :--- |
| **7** | [cite_start]Reserved; do not modify[cite: 288]. |
| **6** | `0` = Enable I/O and language-card space in banks $00/$01. [cite_start]`1` = Inhibit (disable)[cite: 288]. |
| **5** | [cite_start]`1` = Inhibit shadowing for Text Page 2[cite: 288]. |
| **4** | [cite_start]`1` = Inhibit shadowing for Hi-Res graphics pages in auxiliary (odd) banks[cite: 293]. |
| **3** | [cite_start]`1` = Inhibit shadowing for the 32K Super Hi-Res graphics buffer[cite: 293]. |
| **2** | [cite_start]`1` = Inhibit shadowing for Hi-Res graphics Page 2[cite: 293]. |
| **1** | [cite_start]`1` = Inhibit shadowing for Hi-Res graphics Page 1[cite: 293]. |
| **0** | [cite_start]`1` = Inhibit shadowing for Text Page 1[cite: 293]. |

### The Speed Register ($C036)
[cite_start]The Speed register, at address **$C036**, controls the processor's operating speed and shadowing options[cite: 302].

| Bit | [cite_start]Function [cite: 325] |
| :-- | :--- |
| **7** | [cite_start]System speed: `1` = **2.8 MHz** (fast), `0` = **1.024 MHz** (slow)[cite: 327, 340, 341]. |
| **6** | [cite_start]Power-on status (read-write)[cite: 330, 342, 345]. |
| **5** | [cite_start]Reserved; do not modify[cite: 332, 347]. |
| **4** | Bank shadowing: `1` = Shadow all RAM banks, `0` = Shadow banks $00/$01 only. [cite_start]Must be `0` for the OS[cite: 333, 348, 350, 351]. |
| **3-0**| [cite_start]Disk II motor-on detectors for slots 7, 6, 5, and 4. When enabled (`1`), accessing a drive motor address automatically slows the system to 1.024 MHz[cite: 337, 338, 351]. |

---
## I/O Space Addresses

[cite_start]The I/O space in the Apple IIGS covers addresses from **$C000 through $CFFF**[cite: 378]. [cite_start]Accessing these addresses is always possible through banks $E0 and $E1, and can be enabled for banks $00 and $01 via the Shadow register[cite: 380, 381].

[cite_start]When writing timing-critical code, it's important to remember that the system must slow to 1.024 MHz when accessing most I/O addresses, including soft switches and slot I/O devices ($C090-$COFF)[cite: 384, 385, 387]. [cite_start]For an instruction executed from fast RAM or ROM, only the specific cycles that read from or write to a slow I/O address are executed at 1.024 MHz; the other cycles run at full speed[cite: 390, 391].

[cite_start]However, some registers internal to the FPI can be accessed at high speed[cite: 403]. These include:
* [cite_start]The DMA, Speed, and Shadow registers (read and write at high speed)[cite: 403].
* [cite_start]Interrupt ROM addresses ($C071-$C07F) (read at high speed)[cite: 404].
* [cite_start]The State and Slot ROM Select registers (read at high speed, but write at 1.024 MHz)[cite: 405].
