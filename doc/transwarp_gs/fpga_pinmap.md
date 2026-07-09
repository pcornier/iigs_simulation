# XC2064 (U64) pin → net map — TransWarp GS

Package: PLC68 (68-pin PLCC). Designator U64. From schematic Release 1.

## Dedicated / config pins
| Pin | Name | Net |
|----|------|-----|
| 60 | CCLK | config clock |
| 59 | DOUT | FPGA_O59 (config data out / daisy) |
| 26 | M0   | CPU_RESET (mode0 / RTRIG readback trigger) |
| 25 | M1   | M1 |
| 45 | DONE/PROG | DONE |
| 44 | RESET | RESET |
| 30 | LDC  | LDC (low during config) |
| 10 | PWRDWN | +5V |
|  ? | HDC  | HDC (high during config) |

## Named-function I/O
| Pin | Pin name | Net |
|----|------|-----|
| 20 | P20 | C00X |
| 24 | P24 | C02X |
| 27 | P27 | C03X (approx) |
| 28 | P28 | C04X |
| 14 | P14 | C05X |
| 16 | P16 | C06X |
| 29 | P29 | C07X |
| 57 | P57/RCLK | FPGA_O57 (RCLK) |

## Data bus (to 27C256 EPROM + cache)
| Pin | net |
|----|-----|
| 58 | ROM_D0 |
| 56 | ROM_D1 |
| 54 | ROM_D2 |
| 51 | ROM_D3 |
| 50 | ROM_D4 |
| 48 | ROM_D5 |
| 42 | ROM_D6 |
| 41 | ROM_D7 |

## Address bus A0-A15 (pins around 2,3,4,5,6,7,8,9,65,66,67,68 ...)
A3=66, A4=68, A5=3, A6=5, A7=7, A8=9, A9=8, A10=6, A11=4, A12=2, A13=67, A14=65 (A0-A2,A15 on other pins)

## Generic I/O with FPGA_O<n> auto-nets (unnamed in schematic)
Pins 13,17,19,21,22,23,32,33,34,36,37,39,40,46 -> FPGA_O13..O46

## Generic P<n> (nets on far-left, GS_*/CPU_* bus - not all captured)
Pins 11,12,15,31,43,47,49,53,55

## Role summary
U64 is the master bus controller/glue:
 - Bridges Apple IIgs backplane bus (GS_A0-15, GS_D0-7, GS_PH2, GS_RW, GS_IRQ, GS_NMI, GS_RESET, GS_BE, GS_ABORT, GS_VP, GS_SPEED, GS_PAUSE)
 - to the accelerator 65C816 (CPU_PH2, CPU_RW, CPU_RESET, CPU_BE, CPU_MX, CPU_MLB, CPU_NMI)
 - Decodes I/O soft switches ($C00x..$C07x -> C00X..C07X strobes, via 74F138)
 - Controls EPROM + cache SRAM (A0-15, ROM_D0-7, ROM-OE, ROM-IN, RAM-OE, RAM-WE)
 - Config readback path (CCLK, DOUT, M0/RTRIG=CPU_RESET) verified by ROM FPGA_* routines

## Support chips near FPGA
 - U37 = X2444P  : Xicor 256-bit serial NVRAM (STORE/RECALL/CE/SK/DI/DO) = the NVRAM_CMD_* in ROM
 - U35B = 74F74D : D flip-flop clocked by CPU_PH2, involved with DONE
 - U40  = 74F04D : hex inverter (ROM-IN / RAM-WE)
 - 74F138        : $C0xx address decoder (C00X..C07X -> Y0..Y7)
