// ============================================================================
// mmu_tb.cpp — standalone unit test for rtl/mmu.sv
//
// Sweeps the MMU decode (a pure combinational function) against an
// independently written golden model of the Apple IIgs memory map, derived
// from the IIgs Hardware Reference / IIe MMU semantics and cross-checked
// against gssquared and KEGS. Build and run with:
//
//     cd vsim && make mmutest
//
// The golden model is written region-first (like an emulator's memory map),
// deliberately NOT signal-first like the RTL, so a typo in one is unlikely
// to be reproduced in the other.
//
// Known-divergence toggles: three places where the historical RTL differed
// from real hardware. With the fixes applied to the RTL these are all true;
// set one to false to reproduce/document the old behavior.
// ============================================================================

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include "Vmmu.h"
#include "verilated.h"

// --- Known-divergence toggles (see doc in git history / PR description) ----
// D1: language-card ROM windows (RDROM reads of $D000-$FFFF) apply to bank 01
//     as well as bank 00. Old RTL returned RAM ($Dxxx) or floating bus ($Exxx+).
static const bool FIX_BANK01_LC_ROM = true;
// D2: banks E0/E1 $D000-$FFFF with RDROM=1 read from ROM (gssquared maps
//     SYS_ROM there). Old RTL read the LC RAM contents instead.
static const bool FIX_E0E1_RDROM_READS = true;
// D3: banks E0/E1 $Dxxx LC *writes* under RDROM=1 (write RAM while reading
//     ROM) must still fold A12 when LC bank 2 is selected, like banks 00/01.
//     Old RTL only folded when RDROM=0, putting such writes in the wrong bank.
static const bool FIX_E0E1_LC_WRITE_FOLD = true;

struct In {
    uint8_t  bank; uint16_t addr;
    bool we, vpb_n, rom_select;
    bool LCRAM2, RDROM, LC_WE;
    uint8_t shadow;
    bool ALTZP, RAMRD, RAMWRT, STORE80, PAGE2, HIRES;
    bool bank_latch, shadow_all;
    uint8_t SLTROMSEL;
};

struct Out {
    uint32_t addr_bus;
    bool aux, lcram2_sel, inhibit_cxxx, IO, EXTERNAL_IO;
    bool is_internal, is_internal_io;
    bool fastram_ce, slowram_ce, slowram_we;
    bool rom1_ce, rom2_ce, romc_ce, romd_ce;
    bool slot_ce, slot_internalrom_ce, rom_writethrough;
};

static const int RAMSIZE = 128;

// ---------------------------------------------------------------------------
// Golden model
// ---------------------------------------------------------------------------
static Out ref_mmu(const In& s)
{
    Out o{};
    const uint8_t  b  = s.bank;
    const uint16_t a  = s.addr;
    const bool     we = s.we;
    const bool sh0 = s.shadow & 0x01, sh1 = s.shadow & 0x02, sh2 = s.shadow & 0x04;
    const bool sh3 = s.shadow & 0x08, sh4 = s.shadow & 0x10, sh5 = s.shadow & 0x20;
    const bool sh6 = s.shadow & 0x40;

    // --- main/aux select (IIe soft switches, IIgs bank rules) --------------
    // "main-flavored" banks obey the IIe switches; bank 01 (and E1 when the
    // bank latch is on) is the aux side itself and always selects aux.
    const bool mainGrp = (b == 0x00 || b == 0xE0 || (b == 0xE1 && !s.bank_latch));
    const bool auxGrp  = (b == 0x01 || (b == 0xE1 && s.bank_latch));
    const bool rw      = we ? s.RAMWRT : s.RAMRD;   // RAMWRT for writes, RAMRD for reads

    bool aux;
    if (mainGrp && (a < 0x0200 || a >= 0xC000))
        aux = s.ALTZP;                              // ZP/stack + $C000-$FFFF follow ALTZP
    else if ((mainGrp || auxGrp) && a >= 0x0400 && a < 0x0800)
        aux = auxGrp || (s.STORE80 ? s.PAGE2 : rw); // text page 1: 80STORE overrides
    else if (a >= 0x2000 && a < 0x4000)
        aux = auxGrp || (mainGrp && ((s.STORE80 && s.HIRES) ? s.PAGE2 : rw)); // HGR page 1
    else if (s.shadow_all && b >= 0x02 && b <= 0x7E && !(b & 1))
        aux = rw;                                   // all-bank shadow: even->odd redirect
    else
        aux = auxGrp || (mainGrp && rw);
    o.aux = aux;

    // --- logical -> physical translation -----------------------------------
    // LC $Dxxx bank-2 window: fold A12. On the 00/01 (FPI) side the fold also
    // applies to LC writes under RDROM; the E0/E1 (Mega II) side historically
    // did not (FIX_E0E1_LC_WRITE_FOLD adds it).
    const bool lc_wr_exc = !s.RDROM || (s.LC_WE && we);
    const bool fold =
        (a >> 12) == 0xD && s.LCRAM2 &&
        ( ((b == 0xE0 || b == 0xE1) && (FIX_E0E1_LC_WRITE_FOLD ? lc_wr_exc : !s.RDROM)) ||
          ((b == 0x00 || b == 0x01) && !sh6 && lc_wr_exc) );

    const bool lc_exxx =
        a >= 0xE000 && !s.RDROM &&
        ( b == 0xE0 || b == 0xE1 || ((b == 0x00 || b == 0x01) && !sh6) );

    o.lcram2_sel = fold || lc_exxx;

    const uint8_t  beff  = (b == 0xE1 && !s.bank_latch) ? 0xE0 : b;   // bank latch off: E1 == E0
    const uint8_t  bphys = (beff & 0xFE) | ((beff & 1) | (aux ? 1 : 0));
    const uint16_t aphys = fold ? (a & ~0x1000) : a;
    o.addr_bus = ((uint32_t)bphys << 16) | aphys;

    // --- write gating -------------------------------------------------------
    o.slowram_we = we && (((b == 0xE0 || b == 0xE1) && a >= 0xD000) ? s.LC_WE : true);
    o.rom_writethrough = (b == 0x00 || b == 0x01) && a >= 0xD000 && s.LC_WE && we;

    // --- I/O and slot decode ------------------------------------------------
    o.is_internal_io = !((s.SLTROMSEL >> ((aphys >> 4) & 7)) & 1);
    o.is_internal    = !((s.SLTROMSEL >> ((aphys >> 8) & 7)) & 1);

    o.EXTERNAL_IO = ((((b == 0x00 || b == 0x01) && !sh6) || b == 0xE0 || b == 0xE1)
                     && a >= 0xC090 && a < 0xC100 && !o.is_internal_io);

    o.inhibit_cxxx = o.lcram2_sel || ((b == 0x00 || b == 0x01) && sh6);

    const bool all_bank_io = s.shadow_all && b >= 0x02 && b <= 0x7F;
    o.IO = !o.EXTERNAL_IO && (a >> 8) == 0xC0 &&
           (((b == 0x00 || b == 0x01) && !sh6) || b == 0xE0 || b == 0xE1 || all_bank_io);

    const bool slot_window =
        (bphys == 0x00 || bphys == 0x01 || bphys == 0xE0 || bphys == 0xE1) &&
        aphys >= 0xC100 && aphys < 0xC800 && !o.inhibit_cxxx;
    o.slot_ce             = slot_window && !o.is_internal;
    o.slot_internalrom_ce = slot_window &&  o.is_internal;

    // --- ROM chip enables ---------------------------------------------------
    o.romc_ce = (b == 0xFC);
    o.romd_ce = (b == 0xFD);
    o.rom1_ce = (b == 0xFE);

    const bool vec = !s.vpb_n && b == 0x00 &&
                     (a == 0xFFEE || a == 0xFFEF || a == 0xFFFE || a == 0xFFFF);
    const bool rd_or_vec = s.RDROM || !s.vpb_n;
    const bool lc_rom_bank = (b == 0x00) || (FIX_BANK01_LC_ROM && b == 0x01);

    o.rom2_ce = (b == 0xFF) || vec
        || (lc_rom_bank && a >= 0xD000 && a <= 0xDFFF && rd_or_vec && !sh6)
        || (b == 0x00 && a >= 0xC000 && a <  0xC100 && rd_or_vec && !sh6)
        || (b == 0x00 && a >= 0xC800 && a <= 0xCFFF && !sh6)
        || (lc_rom_bank && a >= 0xE000 && rd_or_vec && !sh6)
        || (b == 0x00 && a >= 0xC070 && a <= 0xC07F && !sh6)
        || (FIX_E0E1_RDROM_READS && (b == 0xE0 || b == 0xE1) && a >= 0xD000 && s.RDROM);

    // --- fast/slow RAM chip enables (memory controller) ---------------------
    // Shadow regions (shadow register bits are inhibit flags: 0 = shadowing on)
    const bool txt1 = !sh0 && a >= 0x0400 && a <= 0x07FF;
    const bool txt2 = !s.rom_select && !sh5 && a >= 0x0800 && a <= 0x0BFF;   // ROM3 only
    const bool hgr1 = !sh1 && a >= 0x2000 && a <= 0x3FFF;
    const bool hgr2 = !sh2 && a >= 0x4000 && a <= 0x5FFF;
    const bool shr  = !sh3 && bphys == 0x01 && a >= 0x2000 && a <= 0x9FFF;

    bool fast = false, slow = false;
    if (!o.IO) {
        if (b == 0x00) {
            if (s.RDROM && a >= 0xE000 && !o.rom_writethrough && !sh6) {
                // ROM window: no RAM
            } else if (txt1 || txt2 || shr || hgr1 || hgr2) {
                fast = slow = true;             // dual write into the shadow bank
            } else {
                fast = true;
            }
        } else if (b == 0x01) {
            if (s.RDROM && a >= 0xE000 && !o.rom_writethrough && !sh6) {
                // ROM window: no RAM
            } else if (shr) {
                fast = slow = true;
            } else if (txt1 || txt2) {
                fast = true; slow = we;         // text pages always shadow in bank 01
            } else if (!sh4 && (hgr1 || hgr2)) {
                fast = true; slow = we;         // HGR shadows unless inhibited by bit 4
            } else {
                fast = true;
            }
        } else if (b == 0xE0 || b == 0xE1) {
            slow = true;
        } else if (b >= 0xFC) {
            // ROM banks: reads via rom CEs, writes discarded
        } else if (b < RAMSIZE && !o.rom1_ce && !o.rom2_ce) {
            fast = true;
            if (s.shadow_all && we && (txt1 || txt2 || hgr1 || hgr2 || shr))
                slow = true;                    // all-bank shadow write to E0/E1
        }
    }
    o.fastram_ce = fast;
    o.slowram_ce = slow;
    return o;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------
static Vmmu* dut;
static long  n_tests = 0, n_fail = 0;

static void apply(const In& s, Out& d)
{
    dut->bank_log   = s.bank;
    dut->addr_log   = s.addr;
    dut->we         = s.we;
    dut->vpb_n      = s.vpb_n;
    dut->rom_select = s.rom_select;
    dut->LCRAM2     = s.LCRAM2;
    dut->RDROM      = s.RDROM;
    dut->LC_WE      = s.LC_WE;
    dut->shadow     = s.shadow;
    dut->ALTZP      = s.ALTZP;
    dut->RAMRD      = s.RAMRD;
    dut->RAMWRT     = s.RAMWRT;
    dut->STORE80    = s.STORE80;
    dut->PAGE2      = s.PAGE2;
    dut->HIRES_MODE = s.HIRES;
    dut->bank_latch = s.bank_latch;
    dut->shadow_all = s.shadow_all;
    dut->SLTROMSEL  = s.SLTROMSEL;
    dut->dbg_wdata  = 0;
    dut->dbg_cpu_addr = 0;
    dut->eval();

    d.addr_bus   = dut->addr_bus & 0xFFFFFF;
    d.aux        = dut->aux;
    d.lcram2_sel = dut->lcram2_sel;
    d.inhibit_cxxx = dut->inhibit_cxxx;
    d.IO         = dut->IO;
    d.EXTERNAL_IO = dut->EXTERNAL_IO;
    d.is_internal = dut->is_internal;
    d.is_internal_io = dut->is_internal_io;
    d.fastram_ce = dut->fastram_ce;
    d.slowram_ce = dut->slowram_ce;
    d.slowram_we = dut->slowram_we;
    d.rom1_ce    = dut->rom1_ce;
    d.rom2_ce    = dut->rom2_ce;
    d.romc_ce    = dut->romc_ce;
    d.romd_ce    = dut->romd_ce;
    d.slot_ce    = dut->slot_ce;
    d.slot_internalrom_ce = dut->slot_internalrom_ce;
    d.rom_writethrough    = dut->rom_writethrough;
}

#define CHECK(field, fmt) \
    if (d.field != r.field) { \
        if (mism == 0) printf("  MISMATCH bank=%02X addr=%04X we=%d vpb_n=%d rsel=%d " \
            "LCRAM2=%d RDROM=%d LC_WE=%d sh=%02X ALTZP=%d RAMRD=%d RAMWRT=%d ST80=%d PG2=%d HIRES=%d " \
            "latch=%d shall=%d SLT=%02X\n", \
            s.bank, s.addr, s.we, s.vpb_n, s.rom_select, s.LCRAM2, s.RDROM, s.LC_WE, s.shadow, \
            s.ALTZP, s.RAMRD, s.RAMWRT, s.STORE80, s.PAGE2, s.HIRES, s.bank_latch, s.shadow_all, s.SLTROMSEL); \
        printf("    %-18s dut=" fmt " ref=" fmt "\n", #field, (unsigned)d.field, (unsigned)r.field); \
        mism++; \
    }

static void run_one(const In& s)
{
    Out d, r;
    apply(s, d);
    r = ref_mmu(s);
    n_tests++;

    int mism = 0;
    if (n_fail < 40) {
        CHECK(addr_bus, "%06x")
        CHECK(aux, "%u")
        CHECK(lcram2_sel, "%u")
        CHECK(inhibit_cxxx, "%u")
        CHECK(IO, "%u")
        CHECK(EXTERNAL_IO, "%u")
        CHECK(is_internal, "%u")
        CHECK(is_internal_io, "%u")
        CHECK(fastram_ce, "%u")
        CHECK(slowram_ce, "%u")
        CHECK(slowram_we, "%u")
        CHECK(rom1_ce, "%u")
        CHECK(rom2_ce, "%u")
        CHECK(romc_ce, "%u")
        CHECK(romd_ce, "%u")
        CHECK(slot_ce, "%u")
        CHECK(slot_internalrom_ce, "%u")
        CHECK(rom_writethrough, "%u")
    } else {
        // fast path once we've printed enough detail
        if (d.addr_bus != r.addr_bus || d.aux != r.aux || d.lcram2_sel != r.lcram2_sel ||
            d.inhibit_cxxx != r.inhibit_cxxx || d.IO != r.IO || d.EXTERNAL_IO != r.EXTERNAL_IO ||
            d.is_internal != r.is_internal || d.is_internal_io != r.is_internal_io ||
            d.fastram_ce != r.fastram_ce || d.slowram_ce != r.slowram_ce ||
            d.slowram_we != r.slowram_we || d.rom1_ce != r.rom1_ce || d.rom2_ce != r.rom2_ce ||
            d.romc_ce != r.romc_ce || d.romd_ce != r.romd_ce || d.slot_ce != r.slot_ce ||
            d.slot_internalrom_ce != r.slot_internalrom_ce ||
            d.rom_writethrough != r.rom_writethrough)
            mism = 1;
    }
    if (mism) n_fail++;
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    dut = new Vmmu;

    static const uint8_t banks[] = {
        0x00, 0x01, 0x02, 0x03, 0x7E, 0x7F, 0x80, 0xE0, 0xE1, 0xFC, 0xFD, 0xFE, 0xFF
    };
    static const uint16_t addrs[] = {
        0x0000, 0x01FF, 0x0200, 0x03FF, 0x0400, 0x05FF, 0x07FF, 0x0800, 0x0BFF, 0x0C00,
        0x1FFF, 0x2000, 0x3FFF, 0x4000, 0x5FFF, 0x6000, 0x9FFF, 0xA000, 0xBFFF,
        0xC000, 0xC010, 0xC02D, 0xC034, 0xC035, 0xC036, 0xC068, 0xC070, 0xC07F,
        0xC080, 0xC08F, 0xC090, 0xC0FF, 0xC100, 0xC2FF, 0xC300, 0xC6FF, 0xC700, 0xC7FF,
        0xC800, 0xCFFF, 0xD000, 0xD0FF, 0xD100, 0xDFFF, 0xE000, 0xEFFF, 0xF7FF,
        0xFFEE, 0xFFEF, 0xFFFC, 0xFFFE, 0xFFFF
    };
    static const uint8_t shpats[] = {0x00, 0x3F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20};

    // ---- Phase 1: focused exhaustive sweep --------------------------------
    // All 2^10 combinations of the primary switches x shadow patterns x
    // bank latch x boundary addresses x banks x read/write x vector pull.
    printf("mmu_tb: phase 1 (focused exhaustive sweep)...\n");
    In s{};
    s.SLTROMSEL = 0x80;      // slot 7 external, rest internal (typical)
    for (int rsel = 0; rsel < 2; rsel++) {
        s.rom_select = rsel;
        for (int sw = 0; sw < 1024; sw++) {
            s.LCRAM2  = sw & 1;   s.RDROM  = sw & 2;    s.LC_WE   = sw & 4;
            bool sh6  = sw & 8;   s.ALTZP  = sw & 16;   s.RAMRD   = sw & 32;
            s.RAMWRT  = sw & 64;  s.STORE80 = sw & 128; s.PAGE2   = sw & 256;
            s.HIRES   = sw & 512;
            for (uint8_t shp : shpats) {
                s.shadow = shp | (sh6 ? 0x40 : 0);
                for (int lt = 0; lt < 2; lt++) {
                    s.bank_latch = lt;
                    s.shadow_all = (sw ^ lt) & 1;   // sampled, full coverage in phase 2
                    for (uint8_t b : banks) {
                        s.bank = b;
                        for (uint16_t a : addrs) {
                            s.addr = a;
                            for (int we = 0; we < 2; we++) {
                                s.we = we;
                                s.vpb_n = !(a >= 0xFFEE && !we); // exercise vectors on reads
                                run_one(s);
                            }
                        }
                    }
                }
            }
        }
    }
    printf("mmu_tb: phase 1 done: %ld tests, %ld failures\n", n_tests, n_fail);

    // ---- Phase 2: randomized sweep -----------------------------------------
    printf("mmu_tb: phase 2 (randomized)...\n");
    srand(0xA2C816);            // fixed seed: reproducible
    long p1 = n_tests;
    for (long i = 0; i < 4000000; i++) {
        uint32_t r1 = ((uint32_t)rand() << 16) ^ rand();
        uint32_t r2 = ((uint32_t)rand() << 16) ^ rand();
        In t{};
        t.bank      = (i & 1) ? banks[r1 % (sizeof(banks))] : (uint8_t)(r1 >> 8);
        t.addr      = (i & 2) ? addrs[r2 % (sizeof(addrs)/2)] : (uint16_t)(r2 >> 8);
        t.we        = r1 & 1;
        t.vpb_n     = !(r1 & 2) || ((r1 & 12) != 0);   // mostly 1, sometimes 0
        t.rom_select = r2 & 1;
        t.LCRAM2    = r1 & 4;    t.RDROM = r1 & 8;     t.LC_WE = r1 & 16;
        t.shadow    = (r2 >> 8) & 0x7F;
        t.ALTZP     = r1 & 32;   t.RAMRD = r1 & 64;    t.RAMWRT = r1 & 128;
        t.STORE80   = r2 & 2;    t.PAGE2 = r2 & 4;     t.HIRES = r2 & 8;
        t.bank_latch = r2 & 16;  t.shadow_all = r2 & 32;
        t.SLTROMSEL = (uint8_t)(r1 >> 16);
        run_one(t);
    }
    printf("mmu_tb: phase 2 done: %ld tests, %ld failures\n", n_tests - p1, n_fail);

    printf("mmu_tb: TOTAL %ld tests, %ld failures -> %s\n",
           n_tests, n_fail, n_fail ? "FAIL" : "PASS");
    delete dut;
    return n_fail ? 1 : 0;
}
