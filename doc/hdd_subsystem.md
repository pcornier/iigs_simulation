NOTE: THIS IS CLAUDE GENERATED, IT MAY NOT BE CORRECT

# HDD Subsystem Documentation

This document describes the Hard Disk Drive (HDD) subsystem implementation for the Apple IIgs Verilog simulation. The subsystem consists of two main files:

- `rtl/hdd.v` - The hardware controller visible to the CPU
- `vsim/sim.v` - The simulation top-level that connects the controller to block device images

## Overview

The HDD subsystem implements a ProDOS-compatible block device interface based on the AppleWin emulator's design. It supports 2 HDD units (the ProDOS limit per slot) on slot 7.

```
┌────────────────────────────────────────────────────────────────────┐
│                        sim.v (Top Level)                           │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐ │
│  │ Block Device│    │ Block Device│    │   State Machine         │ │
│  │  Index [1]  │    │  Index [3]  │    │   (hdd_active_unit)     │ │
│  │  (Unit 0)   │    │  (Unit 1)   │    │                         │ │
│  └──────┬──────┘    └──────┬──────┘    │  state=0: Idle          │ │
│         │                  │           │  state=1: Waiting ACK   │ │
│         └────────┬─────────┘           └───────────┬─────────────┘ │
│                  │                                 │               │
│                  │                     ┌───────────┴───────────┐   │
│                  │                     │   Routing Logic       │   │
│                  │                     │   (sd_rd/sd_wr/ack)   │   │
│                  │                     └───────────┬───────────┘   │
└──────────────────┼─────────────────────────────────┼───────────────┘
                   │                                 │
                   ▼                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                        hdd.v (Controller)                          │
│  ┌────────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
│  │ I/O Registers  │   │  512-byte Sector │   │   HDD ROM        │  │
│  │ $C0F0 - $C0F8  │   │     Buffer       │   │ $C700 - $C7FF    │  │
│  │                │   │  (dual-port RAM) │   │                  │  │
│  │ Status  $C0F0  │   │                  │   │ ProDOS driver    │  │
│  │ Error   $C0F1  │   │ Port A: DMA      │   │ SmartPort entry  │  │
│  │ Command $C0F2  │   │ Port B: CPU      │   │                  │  │
│  │ Unit    $C0F3  │   │                  │   │                  │  │
│  │ MemL    $C0F4  │   └──────────────────┘   └──────────────────┘  │
│  │ MemH    $C0F5  │                                                │
│  │ BlkL    $C0F6  │   hdd_unit = reg_unit[7]                       │
│  │ BlkH    $C0F7  │   (ProDOS bit 7 = drive select)                │
│  │ Next    $C0F8  │                                                │
│  └────────────────┘                                                │
└────────────────────────────────────────────────────────────────────┘
```

## File: rtl/hdd.v

### I/O Register Map ($C0F0 - $C0F8)

| Address | Name      | R/W | Description |
|---------|-----------|-----|-------------|
| $C0F0   | EXECUTE   | R   | Execute command and return status |
| $C0F1   | STATUS    | R   | Status/error code |
| $C0F2   | COMMAND   | R/W | Command to execute |
| $C0F3   | UNIT      | R/W | Unit number (slot+drive encoding) |
| $C0F4   | MEMBLOCK_L| R/W | Low byte of memory buffer address |
| $C0F5   | MEMBLOCK_H| R/W | High byte of memory buffer address |
| $C0F6   | DISKBLOCK_L| R/W| Low byte of disk block number |
| $C0F7   | DISKBLOCK_H| R/W| High byte of disk block number |
| $C0F8   | NEXT_BYTE | R/W | Sequential sector buffer access |

### Commands (Written to $C0F2)

| Value | Command | Description |
|-------|---------|-------------|
| $00   | STATUS  | Check if unit is mounted |
| $01   | READ    | Read 512-byte block from disk to memory |
| $02   | WRITE   | Write 512-byte block from memory to disk |
| $03   | FORMAT  | Format disk (not implemented) |

### Unit Number Encoding (ProDOS Standard)

The unit number at $C0F3 uses the **ProDOS block device convention**:

```
Bit 7: Drive select (0 = drive 1, 1 = drive 2)
Bits 6-4: Slot number
Bits 3-0: Reserved (should be 0)
```

For slot 7 with 2 units:

| Unit | Value at $C0F3 | Binary |
|------|----------------|--------|
| 0    | $70            | 0111 0000 (bit7=0, slot=7) |
| 1    | $F0            | 1111 0000 (bit7=1, slot=7) |

**Critical Code** (`hdd.v:107`):
```verilog
assign hdd_unit = reg_unit[7];  // ProDOS format: bit 7 = drive select
```

**Reference**: AppleWin `source/Harddisk.cpp`:
```cpp
BYTE HarddiskInterfaceCard::GetProDOSBlockDeviceUnit(void)
{
    const BYTE slotFromUnitNum = (m_unitNum >> 4) & 7;
    const BYTE offset = (slotFromUnitNum == m_slot) ? 0 : 2;
    return offset + (m_unitNum >> 7);   // bit7 = drive select
}
```

### Sector Buffer

The controller uses a **single shared 512-byte dual-port RAM** for both units:

```verilog
dpram #(.widthad_a(9)) sector_ram (
    // Port A: DMA access (from sim.v)
    .clock_a(CLK_14M),
    .wren_a(ram_we),
    .address_a(ram_addr),      // Address from sim.v (0-511)
    .data_a(ram_di),           // Data from block device
    .q_a(sector_dma_q),        // Data to block device

    // Port B: CPU access via $C0F8
    .clock_b(CLK_14M),
    .wren_b(cpu_c0f8_we),
    .address_b(sec_addr),      // Internal counter (0-511)
    .data_b(cpu_c0f8_din),     // Data from CPU
    .q_b(sector_cpu_q)         // Data to CPU
);
```

**Why a shared buffer works**: Only one unit can be actively transferring at a time. The CPU issues a command, waits for completion, then reads/writes the buffer sequentially. The `hdd_active_unit` register in sim.v ensures DMA goes to the correct block device.

### Data Flow: READ Command

1. **CPU Setup Phase**:
   - CPU writes unit to $C0F3 (e.g., $F0 for unit 1)
   - CPU writes memory address to $C0F4/$C0F5
   - CPU writes block number to $C0F6/$C0F7
   - CPU writes command $01 to $C0F2
     - This sets `reg_status = $80` (busy)
     - Resets `sec_addr = 0`
     - Arms prefetch mechanism

2. **CPU Triggers Execute**:
   - CPU reads $C0F0
   - Controller asserts `hdd_read` pulse for 1 cycle
   - Controller outputs `hdd_unit = reg_unit[7]`

3. **DMA Phase** (handled by sim.v):
   - sim.v latches `hdd_active_unit`
   - sim.v asserts `sd_rd` for the correct block device index
   - Block device fills sector buffer via Port A (ram_we, ram_addr, ram_di)
   - sim.v signals completion via `hdd_ack`

4. **CPU Read Phase**:
   - CPU reads $C0F8 repeatedly (512 times)
   - Each read returns `sector_cpu_q` (via `next_byte_q` staging)
   - Each read increments `sec_addr`
   - After byte 511, `reg_status` clears to $00

### Data Flow: WRITE Command

1. **CPU Setup Phase**: Same as READ

2. **CPU Write Phase** (before execute):
   - CPU writes command $02 to $C0F2
   - This sets `sec_addr = $1FF` (wraps to 0 on first write)
   - CPU writes $C0F8 repeatedly (512 times)
   - Each write stores to buffer via Port B

3. **CPU Triggers Execute**:
   - CPU reads $C0F0
   - Controller asserts `hdd_write` pulse

4. **DMA Phase**:
   - sim.v reads sector buffer via Port A
   - Writes to block device

### Prefetch Mechanism

BRAM has 1-cycle read latency. To avoid the CPU reading stale data on the first $C0F8 access after a READ command:

```verilog
// When command $01 is written to $C0F2:
prefetch_armed <= (D_IN == PRODOS_COMMAND_READ);

// On next clock cycle:
if (prefetch_armed) begin
    prefetch_data  <= sector_cpu_q;  // Capture first byte
    prefetch_valid <= 1'b1;
    prefetch_armed <= 1'b0;
end

// When CPU reads $C0F8:
if (prefetch_valid) begin
    D_OUT <= prefetch_data;          // Return prefetched byte
    prefetch_valid <= 1'b0;
end else begin
    D_OUT <= next_byte_q;            // Return staged byte
end
```

### HDD ROM

The HDD ROM at $C700-$C7FF contains ProDOS driver code based on AppleWin's `hddrvr.a65`:

- **$C700**: Boot signature (checked by autoboot ROM)
- **$C70A**: ProDOS block device entry point
- **$C70D**: SmartPort entry point
- **$C7FC-$C7FD**: Device size (word, little-endian) = $7FFF (32767 blocks)
- **$C7FE**: Status byte indicating capabilities
- **$C7FF**: Entry point offset (must be $0A)

**Status byte $C7FE = $D7** means:
- Bit 7 (1): Removable media
- Bit 6 (1): Interruptable
- Bits 5-4 (01): Number of volumes - 1 (binary 01 = 2 volumes)
- Bit 3 (0): Does NOT support FORMAT
- Bit 2 (1): Supports WRITE
- Bit 1 (1): Supports READ
- Bit 0 (1): Supports STATUS

**Reference**: Apple IIgs Technical Note #20 - Block Device Driver Call
```
Status Byte ($CnFE):
  Bit 7: Medium is removable
  Bit 6: Device is interruptable
  Bits 5-4: Number of volumes on device (0-3 means 1-4)
  Bit 3: Device supports Format call
  Bit 2: Device can be written to
  Bit 1: Device can be read from (must be 1)
  Bit 0: Device status can be read (must be 1)
```

---

## File: vsim/sim.v

### Block Device Index Mapping

The simulation uses an array of block device interfaces. HDD units are mapped as follows:

| Index | Device |
|-------|--------|
| [0]   | Floppy drive 1 |
| [1]   | **HDD Unit 0** ($70) |
| [2]   | Floppy drive 2 |
| [3]   | **HDD Unit 1** ($F0) |
| [4]   | Unused |
| [5]   | Unused |

### Key Signals

```verilog
wire [15:0] hdd_sector;           // Block number from controller
wire        hdd_unit;             // Unit (0-1) from controller (bit 7)
wire        hdd_read;             // READ pulse from controller
wire        hdd_write;            // WRITE pulse from controller
reg  [1:0]  hdd_mounted;          // Per-unit mounted status
reg  [1:0]  hdd_protect;          // Per-unit write protect
reg         hdd_active_unit;      // Unit being served (latched)
reg         cpu_wait_hdd;         // CPU wait signal during DMA
```

### State Machine

```
         ┌────────────┐
         │  state=0   │◄──────────────────────────┐
         │   IDLE     │                           │
         └─────┬──────┘                           │
               │                                  │
               │ (hdd_read_pending |              │ (old_ack & ~hdd_ack)
               │  hdd_write_pending)              │  DMA complete
               ▼                                  │
         ┌────────────┐                           │
         │  state=1   │───────────────────────────┘
         │ WAIT_ACK   │
         └────────────┘
```

**State 0 (IDLE)**:
- Monitors `hdd_read_pending` and `hdd_write_pending`
- When either goes high:
  - Latches `hdd_active_unit` from `hdd_unit`
  - Asserts `sd_rd_hd` or `sd_wr_hd`
  - Asserts `cpu_wait_hdd` to stall CPU
  - Transitions to state 1

**State 1 (WAIT_ACK)**:
- Waits for `hdd_ack` rising edge: clears `sd_rd_hd`/`sd_wr_hd`
- Waits for `hdd_ack` falling edge: DMA complete
  - Clears `cpu_wait_hdd`
  - Clears pending flags
  - Returns to state 0

### Request Routing

Both units share the same sector number and buffer, but requests are routed to different block devices based on `hdd_active_unit`:

```verilog
// LBA (sector number) - same for both units
assign sd_lba[1] = {16'b0, hdd_sector};  // Unit 0
assign sd_lba[3] = {16'b0, hdd_sector};  // Unit 1

// READ request routing
assign sd_rd[1] = sd_rd_hd & (hdd_active_unit == 1'b0);
assign sd_rd[3] = sd_rd_hd & (hdd_active_unit == 1'b1);

// WRITE request routing
assign sd_wr[1] = sd_wr_hd & (hdd_active_unit == 1'b0);
assign sd_wr[3] = sd_wr_hd & (hdd_active_unit == 1'b1);

// ACK mux - select correct ack for active unit
wire hdd_ack = (hdd_active_unit == 1'b0) ? sd_ack[1] : sd_ack[3];
```

### Unit Latching

**Critical Code** (`sim.v`):
```verilog
// Latch hdd_unit when a new request arrives
if ((hdd_read | hdd_write) & !state & !(hdd_read_pending | hdd_write_pending)) begin
    hdd_active_unit <= hdd_unit;
end
```

This captures which unit the request is for **at the moment the request arrives**, before the state machine picks it up.

### Mounting Logic

```verilog
// img_mounted pulses high when a disk image is mounted
if (img_mounted[1]) begin
    hdd_mounted[0] <= img_size != 0;
    hdd_protect[0] <= img_readonly;
end
if (img_mounted[3]) begin
    hdd_mounted[1] <= img_size != 0;
    hdd_protect[1] <= img_readonly;
end
```

---

## Timing Diagram: READ Operation

```
Clock     ─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─
           │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
hdd_read   │ ╔═╗ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
           │ ║ ║ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
hdd_unit   │ ╠═╬═╣ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
           │  1 │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
           │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
hdd_active │ │ │ ╔═════════════════════════════════════════════════════
_unit      │ │ │ ║ 1
           │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
sd_rd[3]   │ │ │ │ ╔═════════════════╗ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
           │ │ │ │ │                 │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
sd_ack[3]  │ │ │ │ │ │ │ │ ╔═════════════════════════╗ │ │ │ │ │ │ │
           │ │ │ │ │ │ │ │ │                         │ │ │ │ │ │ │ │
cpu_wait   │ │ │ │ ╔═════════════════════════════════════╗ │ │ │ │ │
           │ │ │ │ │                                     │ │ │ │ │ │
state      │ │ │ │ ╔═══════════════════════════════════════╗ │ │ │ │
           │ 0 │ │ 1                                       │0│ │ │ │
```

---

## Debug Macros

Enable `SIMULATION` define to get detailed trace output:

```verilog
`define SIMULATION
```

Key debug messages:
- `HDD WR C0F3: unit <= XX` - Unit register written
- `HDD RD C0F0: STATUS/READ` - Command execution
- `HDD_SIM: Latching unit` - Active unit capture
- `HDD: DMA ack rising/falling` - DMA transfer events

---

## CLI Usage

```bash
# Mount single HDD image (unit 0)
./obj_dir/Vemu --disk myimage.hdv

# Mount two HDD images (units 0 and 1)
./obj_dir/Vemu --disk gsos.hdv --disk2 apps.hdv
```

---

## Future Enhancement: 4-Drive Support via SmartPort

### Background

The current ProDOS block device protocol is limited to **2 drives per slot** because it uses only bit 7 of the unit number for drive selection. To support more than 2 drives, the **SmartPort** protocol must be used.

### SmartPort Overview

SmartPort is an enhanced block device protocol that supports up to 127 devices. It uses a different calling convention with an inline parameter block.

**Entry Point**: $Cn0D (for slot n)

**Calling Convention**:
```
JSR $Cn0D
.byte cmd           ; Command code
.word param_ptr     ; Pointer to parameter block
; Returns here with carry set on error, A = error code
```

**Parameter Block for READ/WRITE**:
```
+0: param_count     ; Number of parameters (usually 3)
+1: unit_number     ; SmartPort device number (1-127)
+2-3: buffer_ptr    ; Pointer to data buffer
+4-5: block_number  ; Block number (low word)
+6-7: block_number  ; Block number (high word, for large devices)
```

### Implementation Plan for 4 Drives

#### Phase 1: Firmware Changes (`rtl/roms/hdd.a65`)

1. **Update SmartPort Entry Point** ($C70D):
   - Parse inline parameter block
   - Extract unit number from param block (supports 1-4)
   - Map SmartPort unit to internal unit (1→0, 2→1, 3→2, 4→3)
   - Call existing cmdproc with mapped unit

2. **Update Status Byte** ($C7FE):
   - Change from $D7 to $BF (4 volumes)
   - Or use $D7 and rely on SmartPort STATUS call to report device count

3. **Add SmartPort STATUS Handler**:
   - Command $00: Return device count and characteristics
   - Report 4 devices available

#### Phase 2: Hardware Changes (`rtl/hdd.v`)

1. **Expand Unit Selection**:
   ```verilog
   // Option A: Use bits 1:0 for SmartPort unit
   output [1:0] hdd_unit;
   assign hdd_unit = smartport_mode ? reg_unit[1:0] : {1'b0, reg_unit[7]};

   // Option B: Separate SmartPort unit register
   reg [1:0] smartport_unit;
   ```

2. **Expand Mounted/Protect Arrays**:
   ```verilog
   input [3:0] hdd_mounted;
   input [3:0] hdd_protect;
   ```

3. **Add SmartPort Mode Detection**:
   - Track when SmartPort entry point is used vs ProDOS entry point
   - Could use a soft-switch or detect based on calling pattern

#### Phase 3: Simulation Changes (`vsim/sim.v`)

1. **Expand Routing to 4 Units**:
   ```verilog
   reg [1:0] hdd_active_unit;

   assign sd_rd[1] = sd_rd_hd & (hdd_active_unit == 2'd0);
   assign sd_rd[3] = sd_rd_hd & (hdd_active_unit == 2'd1);
   assign sd_rd[4] = sd_rd_hd & (hdd_active_unit == 2'd2);
   assign sd_rd[5] = sd_rd_hd & (hdd_active_unit == 2'd3);
   ```

2. **Add CLI Options**:
   ```bash
   --disk3 <file>   # SmartPort unit 3
   --disk4 <file>   # SmartPort unit 4
   ```

#### Phase 4: MiSTer Changes (`IIgs.sv`)

1. **Update CONF_STR** for 4 HDD slots
2. **Expand VDNUM** and sd_* arrays
3. **Mirror sim.v routing logic

### References

- **Apple IIgs Firmware Reference**: SmartPort protocol specification
- **AppleWin Source**: `firmware/HDD-SmartPort/HDC-SmartPort.a65`
- **Apple II Technical Note #20**: SmartPort
- **Apple II Technical Note #21**: SmartPort Dispatch

### SmartPort Command Reference

| Cmd | Name | Description |
|-----|------|-------------|
| $00 | STATUS | Return device status |
| $01 | READ BLOCK | Read 512-byte block |
| $02 | WRITE BLOCK | Write 512-byte block |
| $03 | FORMAT | Format device |
| $04 | CONTROL | Device-specific control |
| $05 | INIT | Initialize device |
| $06 | OPEN | Open device (char devices) |
| $07 | CLOSE | Close device (char devices) |
| $08 | READ | Read bytes (char devices) |
| $09 | WRITE | Write bytes (char devices) |

### AppleWin SmartPort Firmware Reference

AppleWin includes a SmartPort-capable firmware in `firmware/HDD-SmartPort/HDC-SmartPort.a65`. Key differences from the standard ProDOS firmware:

1. **$Cn07 = $00**: Indicates SmartPort interface (vs $3C for ProDOS-only)
2. **Supports extended unit numbers**: Via SmartPort parameter block
3. **DIB (Device Information Block)** support for STATUS command

The firmware handles both legacy ProDOS calls (via $Cn0A) and SmartPort calls (via $Cn0D), making it backward compatible.

---

## Version History

- **v1.0**: Initial 4-unit implementation (using bits 2:1 - incorrect)
- **v2.0**: Fixed to 2-unit support using ProDOS bit 7 convention
- **v3.0** (planned): SmartPort support for 4+ units
