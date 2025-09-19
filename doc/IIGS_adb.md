[cite_start]The **Apple Desktop Bus** (ADB) is the system used by the Apple IIGS to connect input devices like keyboards and mice to the computer[cite: 2]. [cite_start]The ADB hardware consists of the ADB microcontroller, the ADB General Logic Unit (GLU), and the necessary cables[cite: 3]. [cite_start]The microcontroller is responsible for managing the devices on the bus by processing commands from the computer's main 65C816 microprocessor and communicating with the connected input devices[cite: 55].

[cite_start]For the purposes of this summary, the computer is referred to as the **host**, and the connected input devices (keyboard, mouse, etc.) are called **devices**[cite: 60].

---
## The Bus and Keyboard
[cite_start]All input devices share a 4-wire cable bus that uses 4-pin mini-DIN connectors[cite: 76]. [cite_start]Devices can draw power from the bus, but the total for all devices must not exceed 500 mA[cite: 78]. [cite_start]The total cable length should not exceed 5 meters[cite: 82].

[cite_start]The Apple IIGS keyboard communicates with the computer via the ADB[cite: 90]. [cite_start]It features automatic key repeat, and the delay and speed of this function can be adjusted in the Control Panel[cite: 93, 94]. [cite_start]The keyboard supports **n-key rollover** for modifier keys (like Shift, Control, etc.), meaning any number of them can be held down while another key is pressed[cite: 98]. [cite_start]However, it has **2-key lockout** for alphanumeric keys, so if two are pressed simultaneously, a third will not be recognized[cite: 100, 101].

### Reading the Keyboard
[cite_start]Application programs get keyboard input by reading the **Keyboard Data register** at memory location `$C000`[cite: 110, 113]. [cite_start]The lower seven bits of the byte at this location contain the ASCII code of the last key pressed, while the high bit (bit 7) is the **strobe bit**[cite: 116, 117].

* [cite_start]**Any-Key-Down Flag**: By reading from location `$C000`, a program can check bit 7 to see if any key (except for modifiers) is currently being held down[cite: 119, 120].
* [cite_start]**Strobe Bit**: This bit is set to 1 after any key is pressed and stays high until it's cleared[cite: 123, 124]. [cite_start]Clearing the strobe is done by reading or writing to location `$C010`[cite: 125]. [cite_start]After the strobe is cleared, the ASCII code for the last key can still be read from the data register, but bit 7 will be 0[cite: 132, 133].

[cite_start]The states of modifier keys like Shift and Control can be determined by reading the **Modifier Key register**[cite: 137].

---
## The ADB Microcontroller and GLU
[cite_start]The **ADB microcontroller** is an intelligent chip that manages the bus[cite: 144]. [cite_start]It runs on a superset of the 6502 instruction set and contains its own RAM and ROM[cite: 145]. [cite_start]The **ADB General Logic Unit (GLU)** is an interface chip that works with the microcontroller, using several internal registers to handle communication between the ADB system and the computer's main bus[cite: 150, 151, 152].

### GLU Registers
[cite_start]The ADB GLU uses five main registers to store data, commands, and status information[cite: 154].

* [cite_start]**ADB Command/Data register (`$C026`)**: Used to send commands to devices and read their status[cite: 166, 167, 168].
* [cite_start]**Keyboard Data register (`$C000`)**: Contains the ASCII value of the last key pressed[cite: 183].
* [cite_start]**Modifier Key register (`$C025`)**: Reflects the status of modifier keys like Shift, Control, and Caps Lock, as well as keys on the numeric keypad[cite: 206, 207].
* [cite_start]**Mouse Data register (`$C024`)**: Contains data about mouse movement and the status of the mouse button[cite: 213]. [cite_start]To get both X and Y coordinates, this register must be read twice in a row; the first read returns Y-coordinate data, and the second returns X-coordinate data[cite: 215, 216].
* [cite_start]**ADB Status register (`$C027`)**: Contains status flags for the other registers, such as whether they are full, and also contains bits to enable or disable interrupts for keyboard and mouse events[cite: 251, 161].

---
## Bus Communication
[cite_start]Communication on the bus occurs through **commands** sent from the host to a specific device and **global signals** that are broadcast to all devices[cite: 313, 314]. [cite_start]A complete communication sequence between the host and a device is called a **transaction**[cite: 300].

[cite_start]A transaction typically consists of a **command packet** from the host, which may be followed by a **data packet** from either the host or the device[cite: 331].

### Commands
[cite_start]Only the host can send commands[cite: 373]. [cite_start]A command is an 8-bit word containing a 4-bit device address and a 4-bit command code[cite: 377, 378, 380]. The four main commands are:
* [cite_start]**Talk**: Asks a device to send the contents of one of its internal registers[cite: 384].
* [cite_start]**Listen**: Tells a device to store the data that the host is sending into one of its internal registers[cite: 395].
* [cite_start]**Send Reset**: Instructs all devices on the bus to reset to their power-on state[cite: 400, 401].
* [cite_start]**Flush**: A device-specific command that clears any pending commands from that device[cite: 403].

### Broadcast Signals
[cite_start]These signals are sent by the host or a device to all other devices on the bus simultaneously[cite: 320, 406].
* [cite_start]**Attention and Sync**: The host sends a long "Attention" signal followed by a short "Sync" pulse to mark the beginning of every command[cite: 411, 412].
* [cite_start]**Global Reset**: When the host holds the bus line low for at least 2.8 milliseconds, all devices on the bus are forced to reset[cite: 421, 422].
* [cite_start]**Service Request**: A device can signal that it needs attention (e.g., it has data to send) by holding the bus line low during the stop bit of a command[cite: 426, 427]. [cite_start]The host then polls devices to find which one made the request[cite: 435].

---
## ADB Peripheral Devices
[cite_start]All devices on the ADB are **slaves**, meaning they only transmit data when requested by the host[cite: 446, 447]. [cite_start]Each device has four internal registers (0 through 3) for storing data and status information[cite: 452].

* [cite_start]**Register 0**: A data register[cite: 466]. [cite_start]For a keyboard, it holds the keycodes of the last two keys pressed[cite: 489]. [cite_start]For a mouse, it holds X and Y movement values and the button status[cite: 506].
* [cite_start]**Register 1**: A device-specific data register[cite: 511].
* [cite_start]**Register 2**: A device-specific data register[cite: 514].
* [cite_start]**Register 3**: A status register that holds the device's unique address and a handler code that defines its function[cite: 518]. [cite_start]The host can change a device's address and enable or disable its ability to send Service Requests by writing to this register[cite: 519, 585, 586].

[cite_start]Each device type has a preassigned default address (e.g., a mouse defaults to address 3), but the host can assign a new address to avoid conflicts if multiple devices of the same type are connected[cite: 549, 550, 551, 556].

---
## 1 MB Apple IIGS Features
[cite_start]The 1 MB version of the Apple IIGS features a redesigned ADB microcontroller with expanded RAM and ROM[cite: 591, 592]. [cite_start]The new ROM code supports additional features, including sticky keys and ADB mouse functions[cite: 593].

* [cite_start]**Sticky Keys**: This feature allows users to press modifier keys (Shift, Command, Option, Control) sequentially instead of simultaneously to achieve key combinations[cite: 597, 598]. [cite_start]It can be enabled or disabled by pressing the Shift key five times[cite: 601].
* [cite_start]**ADB Mouse**: This feature lets users control mouse functions, such as moving the cursor and clicking the button, using the numeric keypad on the keyboard[cite: 603, 604]. [cite_start]It is enabled with the Shift-Command-Clear key sequence[cite: 627].
