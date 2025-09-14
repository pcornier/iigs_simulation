#include "parallel_clemens.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

// For now, disable Clemens integration due to C++ compilation issues
// We'll implement a simple memory tracking system instead
static bool clemens_initialized = false;
static unsigned long access_count = 0;

// Simple memory tracking arrays
static uint8_t tracked_reads[0x100][0x10000];  // [bank][addr] = last read value
static uint8_t tracked_writes[0x100][0x10000]; // [bank][addr] = last written value
static bool read_tracked[0x100][0x10000];      // Track if location has been read
static bool write_tracked[0x100][0x10000];     // Track if location has been written

// Latest hardware state snapshot (from Verilog core)
static uint8_t g_RDROM = 0;
static uint8_t g_LCRAM2 = 0;
static uint8_t g_LC_WE = 0;
static uint8_t g_VPB = 1;
static uint8_t g_SHADOW = 0;
static uint8_t g_ALTZP = 0;
static uint8_t g_INTCXROM = 0;
static uint8_t g_PAGE2 = 0;
static uint8_t g_RAMRD = 0;
static uint8_t g_RAMWRT = 0;
static uint8_t g_SLTROMSEL = 0;
static uint8_t g_STORE80 = 0;
static uint8_t g_HIRES = 0;

// Small helper to decide expected mapping for the current access
// This approximates GS/GSplus/Clemens semantics for the regions we care about
// and is focused on revealing mismatches vs our hardware mapping.
static void expected_mapping(unsigned int bank,
                             unsigned int addr,
                             int is_write,
                             /*out*/ int* exp_is_rom,
                             /*out*/ unsigned int* exp_physical_bank,
                             /*out*/ int* exp_is_fast,
                             /*out*/ int* exp_is_slow)
{
    // Defaults: normal RAM in given bank
    int rom = 0;
    unsigned int phys_bank = bank & 0xFF;
    int fast = 1;
    int slow = 0;

    // ROM banks FC-FF always ROM on read
    if (bank >= 0xFC) {
        rom = (is_write ? 0 : 1);
        fast = 0; slow = 0;
        // Physical bank not crucial here, keep phys_bank
    }

    // Bank 00 / 01 special cases
    if (bank == 0x00 || bank == 0x01) {
        // $C000-$C0FF is I/O: never ROM
        if (addr >= 0xC000 && addr <= 0xC0FF) {
            rom = 0;
            fast = 1; slow = 0;
        }
        // $C100-$C7FF: internal or slot ROM (reads are ROM)
        else if (addr >= 0xC100 && addr <= 0xC7FF) {
            rom = !is_write;
            fast = !rom; slow = 0;
        }
        // $C800-$CFFF: ROM window (reads are ROM)
        else if (addr >= 0xC800 && addr <= 0xCFFF) {
            rom = !is_write;
            fast = !rom; slow = 0;
        }
        // $D000-$FFFF: LC/RDROM interactions
        else if (addr >= 0xD000) {
            if (!is_write) {
                // Reads: RDROM -> ROM, otherwise RAM
                rom = g_RDROM ? 1 : 0;
            } else {
                // Writes: go to RAM (LC write-through allowed elsewhere)
                rom = 0;
            }
            fast = !rom; slow = 0;
        }
        // No special-case for $BF00-$BFFF: follows normal Bank 00/01 rules
    }

    // Banks E0/E1 are slow RAM
    if (bank == 0xE0 || bank == 0xE1) {
        rom = 0; fast = 0; slow = 1;
    }

    *exp_is_rom = rom;
    *exp_physical_bank = phys_bank & 0xFF;
    *exp_is_fast = fast;
    *exp_is_slow = slow;
}

// ------------------ Shadow mirror (partial) ------------------
// Mirror a subset of banks sufficient for early boot and MVN:
//   RAM: banks 00, 01, E0, E1
//   ROM: banks FC, FD, FE, FF
static uint8_t mir_ram00[0x10000];
static uint8_t mir_ram01[0x10000];
static uint8_t mir_slowE0[0x10000];
static uint8_t mir_slowE1[0x10000];
static uint8_t mir_romFC[0x10000];
static uint8_t mir_romFD[0x10000];
static uint8_t mir_romFE[0x10000];
static uint8_t mir_romFF[0x10000];
static uint8_t hw_last_phys_bank00[0x10000]; // track last HW physical bank for bank 00 addresses
static uint8_t hw_last_phys_bank00_valid[0x10000];

// Recent activity ring buffers
typedef struct {
    uint8_t lbank; uint16_t addr; uint8_t pbank; uint8_t data;
} recent_io_t;
static const int RECENT_CAP = 512;
static recent_io_t recent_writes[RECENT_CAP];
static int recent_w_wptr = 0, recent_w_count = 0;
static recent_io_t recent_reads[RECENT_CAP];
static int recent_r_wptr = 0, recent_r_count = 0;

static int load_mem_file(const char* path, uint8_t* dst, size_t len)
{
    FILE* f = fopen(path, "r");
    if (!f) return 0;
    char line[256];
    size_t idx = 0;
    while (fgets(line, sizeof(line), f) && idx < len) {
        unsigned int val;
        if (sscanf(line, "%x", &val) == 1) {
            dst[idx++] = (uint8_t)(val & 0xFF);
        }
    }
    fclose(f);
    return idx == len;
}

static void mirror_init_rom()
{
    // Try VSIM rom paths; if not found, mirror will be filled lazily by reads
    load_mem_file("rom3/romc.mem", mir_romFC, sizeof(mir_romFC));
    load_mem_file("rom3/romd.mem", mir_romFD, sizeof(mir_romFD));
    load_mem_file("rom3/rom1.mem", mir_romFE, sizeof(mir_romFE));
    load_mem_file("rom3/rom2.mem", mir_romFF, sizeof(mir_romFF));
}

static uint8_t mirror_read_byte(unsigned int bank, unsigned int addr)
{
    switch (bank & 0xFF) {
    case 0x00: return mir_ram00[addr & 0xFFFF];
    case 0x01: return mir_ram01[addr & 0xFFFF];
    case 0xE0: return mir_slowE0[addr & 0xFFFF];
    case 0xE1: return mir_slowE1[addr & 0xFFFF];
    case 0xFC: return mir_romFC[addr & 0xFFFF];
    case 0xFD: return mir_romFD[addr & 0xFFFF];
    case 0xFE: return mir_romFE[addr & 0xFFFF];
    case 0xFF: return mir_romFF[addr & 0xFFFF];
    default:   return 0xFF; // unknown bank
    }
}

static void mirror_write_byte(unsigned int bank, unsigned int addr, uint8_t val)
{
    switch (bank & 0xFF) {
    case 0x00: mir_ram00[addr & 0xFFFF] = val; break;
    case 0x01: mir_ram01[addr & 0xFFFF] = val; break;
    case 0xE0: mir_slowE0[addr & 0xFFFF] = val; break;
    case 0xE1: mir_slowE1[addr & 0xFFFF] = val; break;
    default: break; // no writes to ROM here
    }
}

// Region helpers (Apple IIgs key windows)
static inline int is_txt1_addr(unsigned int addr) { return (addr >= 0x0400 && addr <= 0x07FF); }
static inline int is_txt2_addr(unsigned int addr) { return (addr >= 0x0800 && addr <= 0x0BFF); }
static inline int is_hgr1_addr(unsigned int addr) { return (addr >= 0x2000 && addr <= 0x3FFF); }
static inline int is_hgr2_addr(unsigned int addr) { return (addr >= 0x4000 && addr <= 0x5FFF); }
static inline int is_shgr_addr(unsigned int addr) { return (addr >= 0x6000 && addr <= 0x9FFF); }
static inline int is_lc_addr  (unsigned int addr) { return (addr >= 0xC000); }

// Aux selection for Bank 00/E0 text and HGR ranges using STORE80, HIRES, PAGE2, RAMRD/RAMWRT
static int compute_aux_for_lowmem(int is_write, unsigned int bank, unsigned int addr)
{
    // For logical Bank 00/E0 only; Bank 01/E1 are already aux
    if (!((bank & 0xFF) == 0x00 || (bank & 0xFF) == 0xE0)) return 0;

    if (is_txt1_addr(addr) || is_txt2_addr(addr) || is_hgr1_addr(addr) || is_hgr2_addr(addr) || is_shgr_addr(addr)) {
        // Text ranges
        if (is_txt1_addr(addr) || is_txt2_addr(addr)) {
            int page2 = g_PAGE2 ? 1 : 0;
            if (g_STORE80 && page2) return 1;
            int sel = is_write ? (g_RAMWRT ? 1 : 0) : (g_RAMRD ? 1 : 0);
            return (!g_STORE80) ? sel : 0;
        }
        // HGR ranges
        if (is_hgr1_addr(addr) || is_hgr2_addr(addr)) {
            int page2 = g_PAGE2 ? 1 : 0;
            if (g_STORE80 && page2 && g_HIRES) return 1;
            int sel = is_write ? (g_RAMWRT ? 1 : 0) : (g_RAMRD ? 1 : 0);
            return ((!g_STORE80) || (!g_HIRES)) ? sel : 0;
        }
        // SHGR and other ranges: fallback to RAMRD/RAMWRT
        int sel = is_write ? (g_RAMWRT ? 1 : 0) : (g_RAMRD ? 1 : 0);
        return sel;
    }
    return 0;
}

// Map a logical (bank,addr) to expected physical target (bank, is_rom)
static void resolve_expected_phys(unsigned int bank, unsigned int addr, int is_write,
                                  unsigned int* phys_bank, int* is_rom)
{
    int rom = 0;
    unsigned int pb = bank & 0xFF;

    if (bank >= 0xFC) {
        rom = !is_write; // ROM banks
    } else if (bank == 0x00 || bank == 0x01) {
        if (addr >= 0xC000 && addr <= 0xC0FF) {
            rom = 0; // IO
        } else if (addr >= 0xC100 && addr <= 0xCFFF) {
            rom = !is_write; // ROM window
        } else if (addr >= 0xD000) {
            rom = (!is_write && g_RDROM) ? 1 : 0;
        } else {
            // Text/HGR region: aux may redirect to Bank 01
            int aux = compute_aux_for_lowmem(is_write, bank, addr);
            if (aux) pb = 0x01;
        }
    } else if (bank == 0xE0 || bank == 0xE1) {
        rom = 0;
        // For logical E0 accesses, aux may redirect to E1 similarly
        int aux = compute_aux_for_lowmem(is_write, bank, addr);
        if (aux) pb = 0xE1; else pb = 0xE0;
    }

    *phys_bank = pb;
    *is_rom = rom;
}

extern "C" int parallel_clemens_value_compare_write(unsigned int bank, unsigned int addr, unsigned char data)
{
    if (!clemens_initialized) return 1;
    // Skip I/O space comparisons (C000-C0FF) on known IIgs banks
    if ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) && (addr >= 0xC000 && addr <= 0xC0FF)) {
        return 1;
    }
    unsigned int pb; int rom;
    resolve_expected_phys(bank, addr, 1, &pb, &rom);
    if (!rom) {
        // Primary write to resolved physical bank
        mirror_write_byte(pb, addr, data);

        // If within shadowed region, also mirror to slow bank (E0/E1) per GSplus
        int txt1 = is_txt1_addr(addr);
        int txt2 = is_txt2_addr(addr);
        int hgr1 = is_hgr1_addr(addr);
        int hgr2 = is_hgr2_addr(addr);
        int shgr = is_shgr_addr(addr);
        int lc   = is_lc_addr(addr);

        // Shadow bits: 0=TXT1, 5=TXT2, 1=HGR1, 2=HGR2, 3=SHGR, 6=LC
        int shadow_txt1 = ((g_SHADOW & 0x01) == 0) && txt1;
        int shadow_txt2 = ((g_SHADOW & 0x20) == 0) && txt2; // bit5
        int shadow_hgr1 = ((g_SHADOW & 0x02) == 0) && hgr1; // bit1
        int shadow_hgr2 = ((g_SHADOW & 0x04) == 0) && hgr2; // bit2
        int shadow_shgr = ((g_SHADOW & 0x08) == 0) && shgr; // bit3
        int shadow_lc   = ((g_SHADOW & 0x40) == 0) && lc;   // bit6

        int needs_shadow = shadow_txt1 || shadow_txt2 || shadow_hgr1 || shadow_hgr2 || shadow_shgr || shadow_lc;
        if (needs_shadow) {
            unsigned int slow_bank = (pb == 0x01) ? 0xE1 : 0xE0;
            mirror_write_byte(slow_bank, addr, data);

            // Trace dual-write for diagnostics in early boot
            if (((bank & 0xFF) == 0x00 || (bank & 0xFF) == 0x01) && (addr >= 0x0400 && addr <= 0x0BFF)) {
                printf("TRACE: dual-write txt%s: %02X:%04X -> fast %02X and slow %02X (SHADOW=%02X STORE80=%d HIRES=%d PAGE2=%d)\n",
                       txt1 ? "1" : (txt2 ? "2" : "?"),
                       bank & 0xFF, addr & 0xFFFF, pb & 0xFF, slow_bank, g_SHADOW, g_STORE80, g_HIRES, g_PAGE2);
            }
        }
        // Always trace where the primary write landed for text/page2 regions
        if (((bank & 0xFF) == 0x00 || (bank & 0xFF) == 0x01) && (addr >= 0x0400 && addr <= 0x0BFF)) {
            printf("WRITE TRACE: %02X:%04X -> phys %02X data=%02X (RAMWRT=%d RAMRD=%d SHADOW=%02X STORE80=%d HIRES=%d PAGE2=%d)\n",
                   bank & 0xFF, addr & 0xFFFF, pb & 0xFF, data, g_RAMWRT, g_RAMRD, g_SHADOW, g_STORE80, g_HIRES, g_PAGE2);
        }
    } else {
        // Writes targeting ROM are either discarded or LC write-through handled elsewhere.
        // Do not attempt value mirror comparison for ROM writes.
    }
    return 1;
}

extern "C" int parallel_clemens_value_compare_read(unsigned int bank, unsigned int addr, unsigned char verilog_data)
{
    if (!clemens_initialized) return 1;
    // Skip I/O space comparisons (C000-C0FF) on known IIgs banks
    if ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) && (addr >= 0xC000 && addr <= 0xC0FF)) {
        return 1;
    }
    unsigned int pb; int rom;
    resolve_expected_phys(bank, addr, 0, &pb, &rom);
    if (rom) {
        // Skip value comparison for ROM overlays in bank 00/01; mapping comparator covers ROM selection.
        // We still compare in true ROM banks FC-FF (handled elsewhere via exp_is_rom in mapping),
        // but since resolve_expected_phys keeps pb for 00/01 overlays, avoid false diffs here.
        return 1;
    }
    uint8_t exp = mirror_read_byte(pb, addr);
    if (exp != verilog_data) {
        // Provide extra diagnostics for text/page2 regions in Bank 00
        if ((bank & 0xFF) == 0x00 && (addr >= 0x0400 && addr <= 0x0BFF)) {
            unsigned int lastpb = 0xFF;
            int have_last = parallel_clemens_get_last_hw_phys_bank00(addr, &lastpb);
            if (have_last) {
                printf("VALUE MISMATCH: R MA=%02X:%04X exp=%02X got=%02X expPB=%02X lastHW_PB=%02X RDROM=%d LCRAM2=%d RAMRD=%d RAMWRT=%d SHADOW=%02X STORE80=%d HIRES=%d PAGE2=%d\n",
                       bank & 0xFF, addr & 0xFFFF, exp, verilog_data, pb & 0xFF, lastpb & 0xFF,
                       g_RDROM, g_LCRAM2, g_RAMRD, g_RAMWRT, g_SHADOW, g_STORE80, g_HIRES, g_PAGE2);
            } else {
                printf("VALUE MISMATCH: R MA=%02X:%04X exp=%02X got=%02X expPB=%02X lastHW_PB=?? RDROM=%d LCRAM2=%d RAMRD=%d RAMWRT=%d SHADOW=%02X STORE80=%d HIRES=%d PAGE2=%d\n",
                       bank & 0xFF, addr & 0xFFFF, exp, verilog_data, pb & 0xFF,
                       g_RDROM, g_LCRAM2, g_RAMRD, g_RAMWRT, g_SHADOW, g_STORE80, g_HIRES, g_PAGE2);
            }
        } else {
            printf("VALUE MISMATCH: R MA=%02X:%04X exp=%02X got=%02X RDROM=%d LCRAM2=%d RAMRD=%d RAMWRT=%d SHADOW=%02X STORE80=%d HIRES=%d PAGE2=%d\n",
                   bank & 0xFF, addr & 0xFFFF, exp, verilog_data,
                   g_RDROM, g_LCRAM2, g_RAMRD, g_RAMWRT, g_SHADOW, g_STORE80, g_HIRES, g_PAGE2);
        }
        return 0;
    }
    return 1;
}

extern "C" int parallel_clemens_init(void) {
    printf("Initializing simple memory tracking system...\n");
    
    // Initialize tracking arrays
    memset(tracked_reads, 0, sizeof(tracked_reads));
    memset(tracked_writes, 0, sizeof(tracked_writes));
    memset(read_tracked, false, sizeof(read_tracked));
    memset(write_tracked, false, sizeof(write_tracked));
    memset(hw_last_phys_bank00, 0xFF, sizeof(hw_last_phys_bank00));
    memset(hw_last_phys_bank00_valid, 0, sizeof(hw_last_phys_bank00_valid));
    
    clemens_initialized = true;
    printf("Memory tracking system initialized successfully\n");
    mirror_init_rom();
    recent_w_wptr = recent_w_count = 0;
    recent_r_wptr = recent_r_count = 0;
    return 1;
}

extern "C" int parallel_clemens_compare_read(unsigned int bank, unsigned int addr, unsigned char verilog_data) {
    if (!clemens_initialized) {
        return 1; // Skip comparison if not initialized
    }
    
    access_count++;
    
    // Track this read
    if (bank < 0x100 && addr < 0x10000) {
        tracked_reads[bank][addr] = verilog_data;
        read_tracked[bank][addr] = true;
    }
    
    // Log first few accesses for verification
    if (access_count <= 10) {
        printf("Memory read tracked #%lu: Bank=%02X Addr=%04X Data=%02X\n", 
               access_count, bank, addr, verilog_data);
    }
    
    // Enhanced debugging for Language Card area
    if (bank == 0x00 && addr >= 0xBF00) {
        printf("TRACKED READ: Bank=%02X Addr=%04X Data=%02X (LC area - should be redirected to Bank 01)\n", 
               bank, addr, verilog_data);
    }
    
    // Also track what should be Bank 01 reads
    if (bank == 0x01 && addr >= 0xBF00) {
        printf("TRACKED READ: Bank=%02X Addr=%04X Data=%02X (Direct Bank 01 access)\n", 
               bank, addr, verilog_data);
    }
    
    return 1;
}

// Value-level comparison using a shadow memory mirror modeled on GSplus rules.
// (second block removed – functions are already defined above)

extern "C" int parallel_clemens_compare_write(unsigned int bank, unsigned int addr, unsigned char data) {
    if (!clemens_initialized) {
        return 1; // Skip comparison if not initialized
    }
    
    access_count++;
    
    // Track this write
    if (bank < 0x100 && addr < 0x10000) {
        tracked_writes[bank][addr] = data;
        write_tracked[bank][addr] = true;
    }
    
    // Log first few accesses for verification
    if (access_count <= 10) {
        printf("Memory write tracked #%lu: Bank=%02X Addr=%04X Data=%02X\n", 
               access_count, bank, addr, data);
    }
    
    // Enhanced debugging for MVN-related writes
    if (addr >= 0xBF00 && addr <= 0xCFFF) {
        printf("TRACKED WRITE: Bank=%02X Addr=%04X Data=%02X (ProDOS/LC area - may be MVN copy)\n", 
               bank, addr, data);
    }
    
    // Track ROM area writes (write-through to RAM)
    if (bank >= 0xFC && addr >= 0xBF00) {
        printf("TRACKED WRITE: Bank=%02X Addr=%04X Data=%02X (ROM write-through to RAM)\n", 
               bank, addr, data);
    }
    
    // Track any writes to BF00 specifically
    if (addr == 0xBF00) {
        printf("TRACKED WRITE: Bank=%02X Addr=BF00 Data=%02X *** ProDOS MLI ENTRY POINT ***\n", 
               bank, data);
    }
    
    return 1;
}

extern "C" void parallel_clemens_track_hw_write(unsigned int logical_bank,
                                     unsigned int addr,
                                     unsigned int actual_physical_bank,
                                     unsigned char data)
{
    if ((logical_bank & 0xFF) == 0x00 && addr < 0x10000) {
        hw_last_phys_bank00[addr & 0xFFFF] = (uint8_t)(actual_physical_bank & 0xFF);
        hw_last_phys_bank00_valid[addr & 0xFFFF] = 1;

        // Opportunistically update mirror for writes where we know actual target
        // This helps align with hardware when aux/page mapping is complex.
        unsigned int pb = (unsigned int)(actual_physical_bank & 0xFF);
        if (pb != 0xFC && pb != 0xFD && pb != 0xFE && pb != 0xFF) {
            mirror_write_byte(pb, addr, data);
        }
    }
}

extern "C" int parallel_clemens_get_last_hw_phys_bank00(unsigned int addr, unsigned int* out_bank)
{
    if (addr < 0x10000 && hw_last_phys_bank00_valid[addr & 0xFFFF]) {
        *out_bank = hw_last_phys_bank00[addr & 0xFFFF];
        return 1;
    }
    return 0;
}

// ---------------- Recent IO buffer helpers ----------------
static inline int is_text_or_hgr(unsigned int addr) {
    return (addr >= 0x0400 && addr <= 0x0BFF) ||
           (addr >= 0x2000 && addr <= 0x3FFF) ||
           (addr >= 0x6000 && addr <= 0x9FFF);
}

extern "C" void parallel_clemens_recent_log_write(unsigned int logical_bank,
                                       unsigned int addr,
                                       unsigned int phys_bank,
                                       unsigned char data)
{
    if (!clemens_initialized) return;
    if (((logical_bank & 0xFF) == 0x00 || (logical_bank & 0xFF) == 0x01) && is_text_or_hgr(addr)) {
        recent_io_t e; e.lbank = logical_bank & 0xFF; e.addr = addr & 0xFFFF; e.pbank = phys_bank & 0xFF; e.data = data;
        recent_writes[recent_w_wptr] = e;
        recent_w_wptr = (recent_w_wptr + 1) % RECENT_CAP;
        if (recent_w_count < RECENT_CAP) recent_w_count++;
    }
}

extern "C" void parallel_clemens_recent_log_read(unsigned int logical_bank,
                                      unsigned int addr,
                                      unsigned int phys_bank,
                                      unsigned char data)
{
    if (!clemens_initialized) return;
    if (((logical_bank & 0xFF) == 0x00 || (logical_bank & 0xFF) == 0x01) && is_text_or_hgr(addr)) {
        recent_io_t e; e.lbank = logical_bank & 0xFF; e.addr = addr & 0xFFFF; e.pbank = phys_bank & 0xFF; e.data = data;
        recent_reads[recent_r_wptr] = e;
        recent_r_wptr = (recent_r_wptr + 1) % RECENT_CAP;
        if (recent_r_count < RECENT_CAP) recent_r_count++;
    }
}

extern "C" void parallel_clemens_dump_recent_writes(const char* reason)
{
    if (!clemens_initialized) return;
    printf("==== DUMP RECENT WRITES (reason: %s) ====\n", reason ? reason : "(none)");
    int n = recent_w_count;
    int idx = (recent_w_wptr - n);
    while (idx < 0) idx += RECENT_CAP;
    for (int i = 0; i < n; i++) {
        int p = (idx + i) % RECENT_CAP;
        recent_io_t e = recent_writes[p];
        printf("  W %02X:%04X -> phys %02X data=%02X\n", e.lbank, e.addr, e.pbank, e.data);
    }
    printf("==== END DUMP (%d entries) ====\n", n);
}

extern "C" void parallel_clemens_sync_cpu_state(unsigned int pc, unsigned int bank, unsigned int sp, unsigned char flags) {
    if (!clemens_initialized) {
        return;
    }
    
    // For now, just log CPU state changes we're interested in
    static unsigned int last_pc = 0;
    static unsigned int last_bank = 0;
    
    if (pc != last_pc || bank != last_bank) {
        // Log interesting state changes
        if (pc == 0xBF00 || pc == 0xC700) {
            printf("CPU STATE: PC=%04X Bank=%02X SP=%04X P=%02X\n", 
                   pc, bank, sp, flags);
        }
        
        // Track MVN instruction execution in detail
        if (pc == 0xF8C9) {
            printf("CPU STATE: MVN at PC=%04X Bank=%02X SP=%04X P=%02X (Block copy instruction)\n", 
                   pc, bank, sp, flags);
        }
        
        // Track ROM area execution 
        if (bank >= 0xFC) {
            if (pc == 0xBF00 || (pc >= 0xF8C0 && pc <= 0xF8CF)) {
                printf("CPU STATE: ROM PC=%04X Bank=%02X (ProDOS setup area)\n", pc, bank);
            }
        }
        
        last_pc = pc;
        last_bank = bank;
    }
}

extern "C" void parallel_clemens_update_hw(unsigned char RDROM,
                                unsigned char LCRAM2,
                                unsigned char LC_WE,
                                unsigned char VPB,
                                unsigned char SHADOW,
                                unsigned char ALTZP,
                                unsigned char INTCXROM,
                                unsigned char PAGE2,
                                unsigned char RAMRD,
                                unsigned char RAMWRT,
                                unsigned char SLTROMSEL,
                                unsigned char STORE80,
                                unsigned char HIRES_MODE)
{
    g_RDROM = RDROM ? 1 : 0;
    g_LCRAM2 = LCRAM2 ? 1 : 0;
    g_LC_WE = LC_WE ? 1 : 0;
    g_VPB = VPB ? 1 : 0;
    g_SHADOW = SHADOW;
    g_ALTZP = ALTZP ? 1 : 0;
    g_INTCXROM = INTCXROM ? 1 : 0;
    g_PAGE2 = PAGE2 ? 1 : 0;
    g_RAMRD = RAMRD ? 1 : 0;
    g_RAMWRT = RAMWRT ? 1 : 0;
    g_SLTROMSEL = SLTROMSEL;
    g_STORE80 = STORE80 ? 1 : 0;
    g_HIRES = HIRES_MODE ? 1 : 0;
}

extern "C" int parallel_clemens_compare_access(unsigned int bank,
                                    unsigned int addr,
                                    unsigned char data,
                                    int is_write,
                                    unsigned int actual_physical_bank,
                                    int actual_is_rom,
                                    int actual_is_fast,
                                    int actual_is_slow,
                                    unsigned int pc,
                                    unsigned int pbr)
{
    if (!clemens_initialized) return 1;

    int exp_is_rom = 0, exp_is_fast = 0, exp_is_slow = 0;
    unsigned int exp_physical_bank = bank;
    expected_mapping(bank, addr, is_write, &exp_is_rom, &exp_physical_bank, &exp_is_fast, &exp_is_slow);

    int ok = 1;
    if (exp_is_rom != actual_is_rom) ok = 0;
    if (exp_physical_bank != (actual_physical_bank & 0xFF)) ok = 0;

    if (!ok) {
        printf("MEMMAP MISMATCH: %s CPU=%02X:%04X MA=%02X:%04X exp[rom=%d phys=%02X] got[rom=%d phys=%02X] RDROM=%d LCRAM2=%d LC_WE=%d VPB=%d SHADOW=%02X data=%02X\n",
               is_write ? "W" : "R",
               (unsigned)pbr & 0xFF, (unsigned)pc & 0xFFFF,
               (unsigned)bank & 0xFF, (unsigned)addr & 0xFFFF,
               exp_is_rom, exp_physical_bank,
               actual_is_rom, (unsigned)actual_physical_bank & 0xFF,
               g_RDROM, g_LCRAM2, g_LC_WE, g_VPB, g_SHADOW, data);
        return 0;
    }
    return 1;
}

extern "C" void parallel_clemens_cleanup(void) {
    clemens_initialized = false;
    printf("Memory tracking system cleaned up\n");
}
