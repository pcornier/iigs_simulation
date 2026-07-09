# ZipGS Instruction Manual

### for the ZipChipGS, ZipChipGS Plus and ZipGSX

**Model 1500 · Model 1525 · Model 1600**

*Version 1.04*

---

## Introduction

The *ZipGS* series of accelerator products has been designed for easy installation. Therefore, this manual will present the basics of *ZipGS* insertion and removal, and will also include some of the configurations possible utilizing the DIP switches available to the ZipGSX board user.

The *ZipGS* series comes in three iterations—the ZipChipGS (Model 1500) and ZipChipGS Plus (Model 1525), which are socket-only based, and the ZipGSX (Model 1600), which is slot/socket based. All three iterations follow a simple installation procedure (add a couple of extra steps for the ZipGSX) and require no software pre-booting. With that in mind, let's get to it!

> *Fig. 1 — The ZipGS series of accelerator products exist as a chip and slot based product.*

---

## Installation Preparation

Check your parts. You should have the ZipGS product, a 3½-inch *utility* floppy disk, this paper manual, and a small metal chip puller.

**BEFORE CONTINUING WITH THIS INSTALLATION PROCEDURE, PLEASE FIRST RUN THE *ZipGS* HyperStudio™ stack Manual ON YOUR UTILITY DISK!**

> **Note:** The disk is not a boot-up disk. First boot your system and then run the `RunMe.Sys16` program.

> ***REMEMBER: MAKE AND USE ONLY A <ins>COPY</ins> OF YOUR UTILITY DISK!***

It contains important information that will graphically help in the installation of your *ZipGS* accelerator.

Please proceed with the disassembly of your Apple IIGS ONLY after you have carefully reviewed this visual material. THANK YOU!

> *Fig. 2 — Before attempting to disassemble your Apple IIGS, PLEASE run the ZipGS HyperStudio™ stack Manual!!*

### After Using the Graphical Manual

Now that you are familiar with the steps outlined in the *ZipGS* HyperStudio™ stack Manual, we will go over them again as we step-by-step install your ZipGS accelerator.

> *Fig. 3 — To prepare for ZipGS insertion, first power down your Apple IIGS, remove the cover and touch the power supply to ground yourself.*

---

## Step One — Ground Yourself

BEFORE attempting to remove any static-sensitive devices from your Apple IIGS computer (these include peripheral cards **AND** the 65C816), power down your computer, remove the cover, and <ins>touch</ins> the power supply. ***DO NOT UNPLUG THE POWER CORD.***

---

## Step Two — Removing the Processor

First, find the chip silk-screened on the motherboard "CPU". Then remove any peripherals that hinder access to your removal of the 65C816 CPU.

Now, using the short end of your chip puller, <ins>ease</ins> the processor up from its socket. Be extra *careful* in inserting the chip puller between the CPU and the socket. Make sure you are <ins>not</ins> between the motherboard and the socket instead.

Now, wedge your chip puller back to put some space between the socket and the 65C816. Insert the chip puller longways between the CPU and the socket and carefully wiggle out the CPU.

When the 65C816 CPU is loose on the top of the socket, use your fingers to hold the CPU at its long edges. Lift out the CPU and set it aside.

If you have the ZipChipGS Plus or the ZipGSX (or if you have the ZipChipGS with the DMA upgrade kit [Model 1501]), you can now place the processor in its storage area on the slot card. This area is marked **ORIGINAL 65816**.

> *Fig. 4 — You may park your original 65C816 in storage if you have the appropriate product.*

---

## Step Three — Insertion of *ZipGS* Product

If you are installing a socket-only based *ZipGS* (Model 1500 or Model 1525), you will simply insert the accelerator into the now-vacant processor socket. It will only seat in one direction. Make <ins>sure</ins> that all pins are straight and making firm contact in the socket by *carefully* putting pressure on the top of the accelerator above the socket. The *ZipGS* processor socket replacement pins are designed to stand up to a number of insertions BUT they can be BROKEN! *BE CAREFUL!*

If your socket-only based accelerator includes a slot card (or you have the DMA upgrade kit), you may place that card in ANY unused slot. As it does not "USE" the slot, the slot's built-in "INTERNAL" function can continue to be used.

If you are installing a slot/socket based ZipGSX (Model 1600), you will insert the header from the processor cable into the now-vacant processor socket. Carefully insert the header and press firmly on the top of it to verify solid contact with the socket. Remember, though the header is designed for a number of insertions, **PINS CAN BE BROKEN!** *BE CAREFUL!*

In choosing the slot in which the ZipGSX board will reside, here are some facts to remember. The cable length allows you to reach from slot 1 to slot 4 in your Apple IIGS. As the ZipGSX does not use the slot's I/O register area, you may use an "INTERNAL" slot for its position. The ZipGSX is designed only to take up one slot position width-wise, thus it will easily fit between two peripheral cards in adjacent slots.

> *Fig. 5 — Once the ZipGS product is installed into the socket, press firmly to ensure good contact. BE CAREFUL NOT TO BEND ANY PINS!*

> *Fig. 6 — The ZipGSX may reside in any unused slot (1 to 4) on your Apple IIGS. It does not defeat the slot's internal functionality.*

---

## Step Four — Powering Up

Once you are sure of the placement of your *ZipGS*, switch on the power and verify that your system comes up properly. If so, CONGRATULATIONS! You have just successfully installed your *ZipGS* accelerator.

> **NOTE:** Unless the *ZipGS* is disabled, it will at times fail the Apple IIGS internal test `0BXXXXXX` (as this test depends on 2.8 MHz speed). The *ZipGS* will also fail internal test `0CXXXXXX`. **THIS IS NOT AN ERROR.**

---

## Troubleshooting Problems

If your system does NOT power up as before, simply power down and check that all the pins are making connection in the processor socket (and, if it is a ZipGSX, check that the slot fingers are correctly seated in the slot). Once you have checked that all connections are in place, again switch on the power and verify that your system comes up properly.

At times the processor socket is too loose for the cable header. Be sure to press firmly on the header to ensure good contact. If that does not suffice, simply bend one row of pins inward and reinsert. The header will now grasp at the sides of the socket to ensure connection.

If you must reinsert your original 65C816 CPU, be sure to point the *notched* side toward the slots (back of the IIGS).

---

## Technical Support

If you continue to encounter a problem, contact Zip Technology Technical Support at **(213) 337-1734** between the hours of 9 AM and 4 PM Pacific Time.

Have ready your *ZipGS* model numbers and its serial number, any upgrade model numbers installed on that Zip and their serial numbers, and your Apple IIGS configuration (this includes whether it is a ROM 01 or ROM 03 machine, how much memory is installed, the peripheral cards used and their slot locations). Give a concise error report to the technician, as this will help him/her to solve your problem.

The serial number is located on the *non-component* side of the PC board (ZipGSX, Model 1600) behind the 65816 storage area.

You may also FAX this information to Zip Technology if you choose (remember, all the above information [model numbers, serial numbers and your Apple IIGS configuration] must accompany the FAX, *including* the purchase invoices). Zip Technology Technical Support will do its utmost to answer FAXes in a timely manner. The FAX number is **(213) 337-9337**.

> *Fig. 7 — Make sure the RMA number is on the box when you send it!*

---

## RMA Procedure

If all else fails, the technician will give you an RMA (Return Merchandise Authorization) number. Package up the ZipGS product which is not functioning in its original packaging, including a copy of your invoice. Address the package to Zip Technology (always include a return address on the outside of your package) with your RMA number nearby and, to protect your investment, send your package *insured*.

---

## ZipGSX DIP Switch Configuration

The ZipGSX has two *DIP switches* onboard that allow the user to configure his or her own custom power-up *ZipGS* parameters.

This section will describe each switch, the *ZipGS* default setting for it, and why you may wish to change it.

Let's start at the top left-hand corner. Look for the DIP switch marked **SW1**. A little lower there is also a DIP switch marked **SW2**. On the left-hand side of each DIP switch there will be numbers starting at 1, going to 8. On the right-hand side of the DIP switch there will be dots coinciding with the Zip Technology ON default. From now on the designation will be, for example, SW1/1 to describe *DIP switch #1 / position #1*.

> *Fig. 8 — Set your ZipGSX DIP switches the way you like. That's what they're there for.*
>
> *Fig. 9 — The ZipGSX DIP switches are numbered and defaulted for your convenience.*

### SW1/1 — Cxxx/Dxxx Cache Disable

The *ZipGS* default is **ON** (option disabled). If a program flips a 65C816 bank between "shadow" and "non-shadow" in this address area, it is possible to confuse the cache memory. Simply set this switch to the **OFF** position if you wish to power up with this option. **THERE IS NO KNOWN SOFTWARE REQUIRING THIS SWITCH CHANGE.**

### SW1/2 — Joystick Delay

The *ZipGS* default is **OFF** (option enabled). If a program continually accesses the paddle registers (even when it's not being used) and you don't use the paddle, you can set this switch to the **ON** position to defeat the unneeded delay at power-up.

### SW1/3 — AppleTalk Delay

The *ZipGS* default is **ON** (option disabled). The AppleTalk Delay causes a delay during interrupts required for compatibility with the AppleTalk network. If you wish compatibility with that network on power-up, simply switch it to the **OFF** position (and, depending on full system speed, adjust processor speed percentage).

### SW1/4 — Counter Delay

The *ZipGS* default is **OFF** (option enabled). This option, when enabled, allows the Apple IIGS internal test `05XXXXXX` to pass. It simply creates a delay whenever the horizontal counter register is accessed. To disable this delay, flip this switch to **ON**. But be aware that the Apple IIGS internal test *will* **FAIL Test `05XXXXXX`!**

### SW1/5 — CPS Follow

The *ZipGS* default is **OFF** (option enabled). This option controls whether the *ZipGS* will disable whenever the Apple IIGS goes to 1 MHz mode. When this switch is set in the ON position, from power-up the *ZipGS* will continue to function at system speed when the Apple IIGS is at the 1 MHz mode.

> **NOTE:** If this option is *disabled*, either at power-up through its DIP switch or through software, you will not have the use of the Open or Closed Apple keys at power-up or reset.

> **WARNING:** Floppy drives will not function properly when this option is <ins>disabled</ins>.

### SW1/6 — Disable

The *ZipGS* default is **ON** (option disabled). This option controls whether the *ZipGS* will power-up disabled. If you, for some arcane reason, wish to power-up in slow mode, simply flip this switch to the **OFF** position.

### SW1/7–8 — Cache Size

Here are the cache sizes and their respective SW1/7 and SW1/8 positions.

| Cache size | SW1/7 | SW1/8 |
|-----------|-------|-------|
| 8k\*      | ON    | ON    |
| 16k\*\*   | ON    | OFF   |
| 32k       | OFF   | ON    |
| 64k       | OFF   | OFF   |

\* ZipChipGS as shipped.
\*\* ZipChipGS Plus / ZipGSX as shipped.

> **Note:** Unless you actually increase the cache size, DO NOT change these switches.

### SW2/1–7 — Slot Delay

SW2/1–7 controls the delay disable/enable of the seven slots on your Apple IIGS. In our compatibility list (end of manual), mention will be made if a particular peripheral or program requires a "slow" slot. **SW2/2** and **SW2/6** are defaulted to the OFF position (delay enabled). All the rest are defaulted to the ON position (delay disabled).

### SW2/8 — Speaker Delay

The *ZipGS* default is OFF (delay enabled). Change if you wish.

---

## Diagnostic L.E.D.s

Both the ZipChipGS Plus and the ZipGSX (and the ZipChipGS with the DMA upgrade kit) include two diagnostic L.E.D.s.

- One is a **red power L.E.D.** It is lit when the ZipGS is getting power, simple as that.
- The other is what is sometimes called the **"anti-caching" L.E.D.** It glows brighter as more accesses come from your Apple IIGS and glows dimmer as more accesses come from the ZipGS cache memory. This yellow L.E.D. is a good visual guide as to how effectively the ZipGS is accelerating your software.

> *Fig. 10 — The ZipGSX includes two diagnostic L.E.D.s. Use them to verify access to power and program caching.*

---

## Supplied Software

> **Note:** No software is required for the ZipGS to function. The supplied software simply gives the user information on the ZipGS and control over its options.

As of the release of the manual version mentioned in the page number area, the supplied software consists of the visual instruction manual, installation scripts, and the ZipGS control programs (CDA / CDEV / App / INIT).

- **CDA** — Very straightforward. Once installed, the CDA reflects the current status of the ZipGS and can effect real-time changes to its internal registers.
- **CDEV** — A Control Panel version of the CDA software. All information and control provided by the CDA can also be had through the CDEV.
- **Application program (Sys16)** — Has the same control that the CDA and CDEV have PLUS it can alter the characteristics of an INIT supplied with your software. To load the status of the INIT, simply OPEN from the FILE pull-down window. The current settings of the INIT will now become the system's current settings. You can edit these settings and resave the parameters to the INIT through the SAVE command in the FILE pull-down menu.

> **REMEMBER:** The INIT will supersede the DIP switch settings automatically on power-up. Also, any ZipGS register adjustments (option changes to the layman) made during the current session will be brought to INIT defaults if you reset and the INIT is able to run. If you do not wish this feature, simply delete the INIT or deactivate its functioning.

An NDA is planned for the ZipGS series but not implemented at this time.

---

## Warranty Information

The ZipGS accelerator series carries a 30-day money-back guarantee and a 1-year warranty against manufacturing defects.

As Zip Technology is constantly working to improve its products, it may perform warranty replacement with a later version of the product.

All express and implied warranties for this product, including the warranties of merchantability and fitness for a particular purpose, are limited to product replacement only. No other warranties, whether express or implied, will apply.

If this product is not in good working order, your sole remedy is replacement as stated above. In no event shall Zip Technology be liable to you for any damages, including lost profits, lost savings or other incidental or consequential damages arising out of the use or inability to use this product.

Any alteration to the ZipGS (such as cache size or processor speed adjustments) without the use of Zip Technology supplied parts voids the above warranty.

---

## Compatibility List

> **Note:** All hardware and software tested has proved compatible. We, however, don't have the time nor resources to test EVERY hardware/software combination available to the Apple IIGS. Any special option settings will be mentioned in this area.

### Hardware

- Apple II 1 meg memory card
- Apple IIGS 1 meg memory card
- Apple II High-Speed DMA SCSI card
- Apple II Revision C SCSI card
- Apple Video Overlay card (GenLock)
- Apple Super Serial card
- Apple Disk II / Apple 3.5 / Apple Unidisk — *requires CPS Follow and/or specific slot slowdown*
- Apple AppleTalk network — *requires AppleTalk delay and 87% speed at 8 MHz*
- AE 1 meg RamFactor card
- AE RamKeeper card
- AE Sonic Blaster
- AE Audio Animator
- AE PC Transporter
- AE Vulcan harddrive/controller
- AE Parallel Pro
- AE TimeMaster HO clock
- AE GS RAM memory card series
- CV Tech RamFAST caching DMA SCSI card
- OKS MultiCache caching disk controller
- Ingenuity GS Juice+ 4 meg card
- Ingenuity InnerDrive/controller
- Corvus Omninet network
- Corvus standard harddrive/controller
- Microsoft CP/M card
- CPS MultiFunction card
- GreyMatter harddrive/controller
- Epic Classic II 2400 baud modem
- Vitesse Quickie scanner
- S&S 4 meg RAM card
- FCP Sider II
- ComputerEyes video scanner
- Chinook IIGS 4 meg RAM card
- AST Vision +
- ThirdWare Fingerprint GSi
- NicePrint Parallel card
- Orange Micro Grappler +
- Epson APL Parallel printer card

### Software

- All Apple IIGS System software thru 5.0.4
- All known CDAs / NDAs / CDEVs / INITs
- Apple America Online
- Apple HyperCard GS
- SynthLab
- Claris AppleWorks / AppleWorks GS
- Beagle Bros TimeOut series (all)
- RWP HyperStudio (plus digitizer)
- RWP Merlin 8/16+
- Vitesse Harmonie
- Vitesse Salvation series (all)
- Glen Bredon's ProSel / ProSel 16
- EA Deluxe Paint II
- Activision PaintWorks+ / PaintWorks Gold
- Broderbund PrintShop
- Graphic Writer III
- TimeWorks PublishIt! series
- Milliken Medley
- Springboard Publisher
- WordPerfect
- StoneEdge Tech DBMaster
- FutureSound (plus digitizer)
- Music Studio
- Orca C / Orca 1.1 Shell
- APW Shell / ECP 16
- ShrinkIt and ShrinkItGS
- America Online
- ZZCopy — **Requires slot 6 slow**

This list is by no means complete. This section will be updated as this manual is revised.

Enjoy your *ZipGS*. The time is right for *ZipGS* as, according to **Zip**, time is of the essence...

---

## Zip Technology

5601 West Slauson Avenue, Suite #190
Culver City, CA 90230

| | |
|---|---|
| **Main** | (213) 337-1313 |
| **Tech** | (213) 337-1734 |
| **FAX** | (213) 337-9337 |

*Version 1.04*
