[cite_start]The Apple IIGS has seven 50-pin peripheral-card connectors, or slots, on its main logic board that allow for hardware expansion. [cite: 2507, 2508, 2509] [cite_start]A circuit card plugged into one of these slots can access all the signals needed to perform I/O and execute programs. [cite: 2576] [cite_start]The computer also has a separate **memory expansion slot**, which is not an I/O slot and should only be used for memory cards designed specifically for it. [cite: 2567, 2568, 2569, 2570]

---
## Apple II Compatibility and Slot I/O
[cite_start]The I/O slots are nearly identical to those in the Apple IIe, ensuring a high degree of compatibility. [cite: 2645] [cite_start]However, because the Apple IIGS can run at a faster speed (2.8 MHz) and has a 24-bit address space, peripheral cards need to handle addressing differently than on older Apple II models. [cite: 2649] [cite_start]The `/M2SEL` signal on pin 39 indicates when a valid 1.024 MHz memory cycle is occurring, which is crucial for cards that need to decode addresses. [cite: 2507, 2650]

[cite_start]Most I/O cards that use the `/IOSEL` and `/DEVSEL` bus signals will work correctly because these signals handle the larger address range. [cite: 2670] [cite_start]However, some older multifunction and RAM cards that perform their own 16-bit address decoding may not function properly. [cite: 2672, 2673]

### DMA (Direct Memory Access)
[cite_start]DMA cards that work in previous Apple II models will often work in the Apple IIGS, though they may require software updates to use the **DMA bank register** properly. [cite: 2682] [cite_start]This register, located at address `$C037`, must be loaded with the upper 8 bits of the address before a DMA transfer. [cite: 2655]

[cite_start]Generally, DMA should be performed when the system is running at the standard 1.024 MHz speed, as DMA to I/O or video areas will not work correctly at the faster 2.8 MHz speed. [cite: 2687, 2688] [cite_start]DMA to high-speed RAM or ROM can be done at the faster speed, but it may cause issues if the main processor is accessing an I/O location at the same time. [cite: 2689, 2690, 2691, 2692, 2693]

---
## Slot Signals and Buses
[cite_start]The expansion slots provide access to several key signal groups, including the address bus, the data bus, and signals for DMA and interrupts. [cite: 2696, 2697, 2698, 2699]

* [cite_start]**Address Bus**: The 16-bit address bus (A0-A15) and the Read/Write line are buffered and can be disabled by a peripheral card for DMA operations. [cite: 2593, 2703]
* [cite_start]**Data Bus**: The system has three data buses: an internal bus (DBUS), a Mega II bus (MDBUS), and the slot data bus (SDBUS). [cite: 2717] [cite_start]The slot data bus is buffered to handle the electrical load of up to seven peripheral cards. [cite: 2719, 2720, 2742]
* [cite_start]**Interrupt and DMA Daisy Chains**: To prevent conflicts when multiple cards request an interrupt or DMA transfer simultaneously, the slots use a priority **daisy chain**. [cite: 2748, 2749] [cite_start]The output of one slot connects to the input of the next higher-numbered slot, giving priority to cards in higher-numbered slots (slot 7 has the highest priority). [cite: 2751, 3039]

---
## Peripheral Programming and Memory Spaces
[cite_start]Each expansion slot is allocated specific memory areas for I/O and for on-card firmware (ROM). [cite: 2816]

### I/O and ROM Spaces
* [cite_start]**I/O Space**: Each slot has exclusive use of 16 memory locations for I/O, starting from `$C090` for slot 1. [cite: 2825] [cite_start]When the system addresses one of these locations, the `/DEVSEL` signal for that slot becomes active. [cite: 2828]
* [cite_start]**Card ROM Space**: Each slot is also allocated a 256-byte page of memory for on-card ROM, starting at `$C100` for slot 1. [cite: 2834, 2835] [cite_start]The `/IOSEL` signal for that slot becomes active when this space is addressed. [cite: 2839]
* [cite_start]**Expansion ROM Space**: A larger 2K memory space from `$C800` to `$CFFE` is available for any peripheral card to use for larger programs. [cite: 2845, 2846, 2847] [cite_start]A card must have special circuitry to enable and disable its use of this shared space. [cite: 2849]
* [cite_start]**Card RAM Space**: 56 bytes of main memory, known as "screen holes," are allocated for peripheral cards to use for temporary data storage (8 bytes per card). [cite: 2888, 2889]

### The Slot Register
[cite_start]The **Slot register**, located at `$C02D`, is used to select whether the system uses a built-in device or a peripheral card for a given slot. [cite: 2778, 2779] [cite_start]For example, slot 2 can be used for either the internal serial port or a card plugged into that slot. [cite: 2776] [cite_start]This selection is typically made through the Control Panel. [cite: 2784]

### Interrupts
[cite_start]An interrupt is a hardware signal that tells the computer to pause its current task to handle a more urgent one. [cite: 3032] [cite_start]The Apple IIGS provides improved firmware support for interrupts compared to older Apple II models. [cite: 3026] [cite_start]When a peripheral card requests an interrupt, the microprocessor transfers control to the **interrupt handler** in the system's Monitor firmware, which then determines the source of the interrupt and takes appropriate action. [cite: 3041, 3042]
