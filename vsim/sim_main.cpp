#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vemu.h"
#include "Vemu__Syms.h"

#include "imgui.h"
#include "implot.h"
#ifndef _MSC_VER
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>
#else
#define WIN32
#include <dinput.h>
#endif


#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)

#if VERILATOR_MAJOR_VERSION >= 5
#define VERTOPINTERN top->rootp
#else
#define VERTOPINTERN top
#endif

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_blkdevice.h"
#include "sim_video.h"
#include "sim_audio.h"
#include "sim_input.h"
#include "sim_clock.h"
// parallel_clemens.h removed

#define FMT_HEADER_ONLY
#include <fmt/core.h>

#include "../imgui/imgui_memory_editor.h"
#include "../imgui/ImGuiFileDialog.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <iterator>
#include <string>
#include <iomanip>
#include <thread>
#include <chrono>
#include <vector>
#include <cstring>
#include <algorithm>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "sim/stb_image_write.h"

#ifndef WIN32
#include <SDL_opengl.h>
#endif

enum class RunState {Stopped, Running, SingleClock, MultiClock, StepIn, NextIRQ};

// Simulation control
// ------------------
int initialReset = 48;
RunState run_state = RunState::Running;
bool adam_mode = 1;
int batchSize = 100000;
int multi_step_amount = 1024;

// Debug GUI 
// ---------
const char* windowTitle = "Verilator Sim: IIgs";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_DebugLog = "Debug log";
const char* windowTitle_Video = "VGA output";
const char* windowTitle_Audio = "Audio output";
bool showDebugLog = true;
DebugConsole console;
MemoryEditor mem_edit;
char pc_breakpoint[10] = "";
int pc_breakpoint_addr = 0;
bool pc_break_enabled;
bool break_pending = false;
bool old_vpb = false;
// Track MVN operands for better source/dest diagnostics
static unsigned char last_mvn_src_bank = 0xFF;
static unsigned char last_mvn_dst_bank = 0xFF;
static int mvn_expect_operands = 0; // 2 -> expect dst then src on next two VPA fetches
static int mvn_logged_data_reads = 0; // limit noisy logs
static unsigned short mvn_pc_at_opcode = 0xFFFF;

// STA abs,Y tracing
static int sta99_expect_operands = 0; // expect 2 bytes following IR=0x99
static unsigned char sta99_op_lo = 0xFF;
static unsigned char sta99_op_hi = 0xFF;
static unsigned short sta99_base = 0xFFFF;

// Monitor entry trap (first time we enter ROM monitor idle loop)
static bool monitor_trap_fired = false;
static bool loader_entry_trap_fired = false;
static int loader_ifetch_trace_budget = 0;

// Ring buffer of recent instruction fetches (for postmortem at monitor entry)
struct IfetchEntry { unsigned short pc; unsigned char pbr; unsigned char ir; };
static const int IFETCH_RING_CAP = 128;
static IfetchEntry ifetch_ring[IFETCH_RING_CAP];
static int ifetch_wptr = 0;

static inline void ifetch_ring_record(unsigned char pbr, unsigned short pc, unsigned char ir) {
    ifetch_ring[ifetch_wptr].pbr = pbr;
    ifetch_ring[ifetch_wptr].pc = pc;
    ifetch_ring[ifetch_wptr].ir = ir;
    ifetch_wptr = (ifetch_wptr + 1) & (IFETCH_RING_CAP - 1);
}

// HDD C0F0-C0FF event ring for protocol forensics at monitor entry
struct HddEvt { unsigned short pc; unsigned char pbr; unsigned short addr16; unsigned char bank; unsigned char rw; unsigned char data; };
static const int HDD_RING_CAP = 128;
static HddEvt hdd_ring[HDD_RING_CAP];
static int hdd_wptr = 0;
static FILE* hdd_csv = nullptr;
static bool hdd_csv_inited = false;
static inline void hdd_csv_maybe_init() {
    if (!hdd_csv_inited) {
        const char* path = getenv("HDD_CSV");
        if (path && *path) {
            hdd_csv = fopen(path, "w");
            if (hdd_csv) {
                fprintf(hdd_csv, "time,pc_bank,pc,bank,addr,rw,data\n");
                fflush(hdd_csv);
            }
        }
        hdd_csv_inited = true;
    }
}
static inline void hdd_ring_record(unsigned char pbr, unsigned short pc, unsigned char bank, unsigned short a16, bool is_write, unsigned char data) {
    hdd_ring[hdd_wptr].pbr = pbr;
    hdd_ring[hdd_wptr].pc = pc;
    hdd_ring[hdd_wptr].addr16 = a16;
    hdd_ring[hdd_wptr].bank = bank;
    hdd_ring[hdd_wptr].rw = is_write ? 'W' : 'R';
    hdd_ring[hdd_wptr].data = data;
    hdd_wptr = (hdd_wptr + 1) & (HDD_RING_CAP - 1);

    // Optional CSV logging for cross-emulator diffing
    hdd_csv_maybe_init();
    if (hdd_csv) {
        // main_time is in units of half-cycles (from Verilator sim harness); use it as a sortable timestamp
        extern vluint64_t main_time;
        fprintf(hdd_csv, "%llu,%02X,%04X,%02X,%04X,%c,%02X\n",
                (unsigned long long)main_time, pbr, pc, bank, a16, is_write ? 'W' : 'R', data);
        // Avoid excessive flushes; OS buffers are fine
    }
}


// Self-test mode support
bool selftest_mode = false;
bool selftest_override_active = false;
bool selftest_override_started = false;
vluint64_t selftest_start_time = 0;
const vluint64_t SELFTEST_OVERRIDE_DURATION = 10000000; // 10 seconds in simulation time (much longer)

// HPS emulator
// ------------
SimBus bus(console);
SimBlockDevice blockdevice(console);

// Input handling
// --------------
SimInput input(13, console);
const int input_right = 0;
const int input_left = 1;
const int input_down = 2;
const int input_up = 3;
const int input_a = 4;
const int input_b = 5;
const int input_x = 6;
const int input_y = 7;
const int input_l = 8;
const int input_r = 9;
const int input_select = 10;
const int input_start = 11;
const int input_menu = 12;

// Video
// -----
#define VGA_WIDTH 704
#define VGA_HEIGHT 262  // Full NTSC frame: 32 top + 200 active + 30 bottom = 262
#define VGA_ROTATE 0  // 90 degrees anti-clockwise
#define VGA_SCALE_X vga_scale
#define VGA_SCALE_Y vga_scale
SimVideo video(VGA_WIDTH, VGA_HEIGHT, VGA_ROTATE);
float vga_scale = 1.0;
// Headless mode flag (no SDL/ImGui rendering)
bool headless = false;

// Verilog module
// --------------
Vemu* top = NULL;

// CSV trace (Clemens-like) for per-access mapping and value comparison
static FILE* g_vsim_trace_csv = nullptr;
static unsigned long long g_vsim_seq = 0ULL;
static bool g_vsim_trace_active = false;
static bool g_csv_trace_enabled = false;  // Must be enabled via --enable-csv-trace
int dump_csv_after_frame = -1;
static void vsim_trace_open_fresh() {
    if (g_vsim_trace_csv) { fclose(g_vsim_trace_csv); g_vsim_trace_csv = nullptr; }
    g_vsim_trace_csv = fopen("vsim_trace.csv", "w");
    if (g_vsim_trace_csv) {
        fprintf(g_vsim_trace_csv,
                "seq,phase,type,pc,pbr,ir,a_bank,a_adr,data,mmap,phys,rom,slow,io\n");
        fflush(g_vsim_trace_csv);
    }
    g_vsim_seq = 0ULL;
}
static void vsim_trace_log(char phase, char type,
                           unsigned pc, unsigned pbr, unsigned ir,
                           unsigned a_bank, unsigned a_adr, unsigned data,
                           unsigned phys_bank, int is_rom, int is_slow, int is_io) {
    if (!g_vsim_trace_active) return;
    if (dump_csv_after_frame != -1 && video.count_frame < dump_csv_after_frame) return;
    if (!g_vsim_trace_csv) vsim_trace_open_fresh();
    // Build Clemens-like memory map (mmap) flags from current iigs signals
    // Bits map to clemens_iigs/clem_mmio_defs.h where feasible
    // 0x00000001 ALTZPLC, 0x00000002 RAMRD, 0x00000004 RAMWRT
    // 0x00000008 80COLSTORE (STORE80), 0x00000010 TXTPAGE2 (PAGE2), 0x00000020 HIRES
    // 0x00000100 RDLCRAM (RDROM==0), 0x00000200 WRLCRAM (LC_WE), 0x00000400 LCBANK2 (LCRAM2)
    // 0x00080000 CXROM (INTCXROM==0)
    uint32_t mmap = 0;
    // Protect against null top in early startup
    if (VERTOPINTERN) {
        // Access internal signals under emu->iigs
        // These names come from the Verilated model with public_flat annotations
        if (VERTOPINTERN->emu__DOT__iigs__DOT__ALTZP)       mmap |= 0x00000001;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__RAMRD)       mmap |= 0x00000002;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__RAMWRT)      mmap |= 0x00000004;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__STORE80)     mmap |= 0x00000008;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__PAGE2)       mmap |= 0x00000010;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__HIRES_MODE)  mmap |= 0x00000020;
        if (!VERTOPINTERN->emu__DOT__iigs__DOT__RDROM)      mmap |= 0x00000100;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE)       mmap |= 0x00000200;
        if (VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2)      mmap |= 0x00000400;
        if (!VERTOPINTERN->emu__DOT__iigs__DOT__INTCXROM)   mmap |= 0x00080000;

        // Shadow register bits (matching clemens CLEM_MEM_IO_MMAP_NSHADOW_* flags)
        // Note: shadow register uses inverted logic - bit=0 means shadowing enabled, bit=1 means disabled
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x01) mmap |= 0x00100000; // NSHADOW_TXT1
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x02) mmap |= 0x00400000; // NSHADOW_HGR1
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x04) mmap |= 0x00800000; // NSHADOW_HGR2
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x08) mmap |= 0x01000000; // NSHADOW_SHGR
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x10) mmap |= 0x02000000; // NSHADOW_AUX
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x20) mmap |= 0x00200000; // NSHADOW_TXT2
        if (VERTOPINTERN->emu__DOT__iigs__DOT__shadow & 0x40) mmap |= 0x04000000; // NIOLC
    }
    fprintf(g_vsim_trace_csv,
            "%llu,%c,%c,%04X,%02X,%02X,%02X,%04X,%02X,%08X,%02X,%d,%d,%d\n",
            (unsigned long long)g_vsim_seq++, phase, type,
            pc & 0xFFFF, pbr & 0xFF, ir & 0xFF,
            a_bank & 0xFF, a_adr & 0xFFFF, data & 0xFF,
            mmap, phys_bank & 0xFF, is_rom ? 1 : 0, is_slow ? 1 : 0, is_io ? 1 : 0);
    fflush(g_vsim_trace_csv);
}

// VCD trace dump support
VerilatedVcdC* tfp = NULL;
int dump_vcd_after_frame = -1;

vluint64_t main_time = 0;	// Current simulation time.
double sc_time_stamp() {	// Called by $time in Verilog.
	return main_time;
}

int CLK_14M_freq = 24000000;
SimClock CLK_14M(1);

int soft_reset = 0;
vluint64_t soft_reset_time = 0;

// Cold reset (power-on style reset vs warm reset)
int cold_reset = 0;           // 0 = warm reset, 1 = cold reset (full power-on initialization)
int reset_pending = 0;        // Reset is requested (from menu or keyboard)
int reset_pending_cold = 0;   // Type of pending reset (0=warm, 1=cold)
vluint64_t reset_time = 0;    // Counter for reset duration

//
// IWM emulation
//#include "defc.h"
#include <cstdint>
int g_c031_disk35;
uint32_t g_vbl_count;

// Audio
// -----
//#define DISABLE_AUDIO
#ifndef DISABLE_AUDIO
SimAudio audio(CLK_14M_freq, false);
#endif

// Reset simulation variables and clocks
void resetSim() {
	main_time = 0;
	top->reset = 1;
	break_pending = false;
	old_vpb = true;
    printf("resetSim!! main_time %llu top->reset %d\n", (unsigned long long)main_time, top->reset);
	CLK_14M.Reset();
	
	// parallel_clemens removed
}

//#define DEBUG

bool stop_on_log_mismatch = 1;
bool debug_6502 = 1;
bool quiet_mode = false;  // Suppress CPU trace to stdout
int cpu_sync;
long cpu_instruction_count;
int cpu_clock;
int cpu_clock_last;
const int ins_size = 48;
int ins_index = 0;
unsigned short ins_pc[ins_size];
unsigned char ins_in[ins_size];
unsigned long ins_ma[ins_size];
unsigned char ins_dbr[ins_size];
bool ins_formatted[ins_size];
std::string ins_str[ins_size];

// MAME debug log
const char* tracefilename = "traces/appleiigs.tr";
std::vector<std::string> log_mame;
std::vector<std::string> log_cpu;
long log_index;

bool writeLog(const char* line)
{
	// Print to stdout unless in quiet mode
	if (!quiet_mode) {
		printf("%s\n",line);
	}

	// Only do memory-intensive operations when debug_6502 is enabled
	if (debug_6502) {
		// Write to cpu log vector for GUI/debugging
		log_cpu.push_back(line);
		
		// Prevent unbounded memory growth - keep only last 10000 entries
		if (log_cpu.size() > 10000) {
			log_cpu.erase(log_cpu.begin(), log_cpu.begin() + 5000);
		}

		// Compare with MAME log
		bool match = true;

		std::string c_line = std::string(line);
		std::string c = "%6d  CPU > " + c_line;
		//printf("%s (%x)\n",line,ins_in[0]); // this has the instruction number

		if (log_index < log_mame.size()) {
			std::string m_line = log_mame.at(log_index);
			std::string m = "%6d MAME > " + m_line;
			if (stop_on_log_mismatch && m_line != c_line) {
                                console.AddLog("DIFF at %06ld - %06x", cpu_instruction_count, ins_pc[0]);
				console.AddLog(m.c_str(), cpu_instruction_count);
				console.AddLog(c.c_str(), cpu_instruction_count);
				match = false;
			}
			else {
				console.AddLog(c.c_str(), cpu_instruction_count);
			}
		}
		else {
			console.AddLog(c.c_str(), cpu_instruction_count);
		}

		log_index++;
		return match;
	}
	return true;
}

enum instruction_type {
	formatted,
	implied,
	immediate,
	absolute,
	absoluteX,
	absoluteY,
	zeroPage,
	zeroPageX,
	zeroPageY,
	relative,
	relativeLong,
	accumulator,
	direct24,
	direct24X,
	direct24Y,
	indirect,
	indirectX,
	indirectY,
	longValue,
	longX,
	longY,
	stackmode,
	srcdst
};

enum operand_type {
	none,
	byte2,
	byte3
};

struct dasm_data
{
	unsigned short addr;
	const char* name;
};

struct dasm_data32
{
	unsigned long addr;
	const char* name;
};

int a2_name_count;
static const struct dasm_data a2_stuff[] =
{
	{ 0x0020, "WNDLFT" }, { 0x0021, "WNDWDTH" }, { 0x0022, "WNDTOP" }, { 0x0023, "WNDBTM" },
	{ 0x0024, "CH" }, { 0x0025, "CV" }, { 0x0026, "GBASL" }, { 0x0027, "GBASH" },
	{ 0x0028, "BASL" }, { 0x0029, "BASH" }, { 0x002b, "BOOTSLOT" }, { 0x002c, "H2" },
	{ 0x002d, "V2" }, { 0x002e, "MASK" }, { 0x0030, "COLOR" }, { 0x0031, "MODE" },
	{ 0x0032, "INVFLG" }, { 0x0033, "PROMPT" }, { 0x0036, "CSWL" }, { 0x0037, "CSWH" },
	{ 0x0038, "KSWL" }, { 0x0039, "KSWH" }, { 0x0045, "ACC" }, { 0x0046, "XREG" },
	{ 0x0047, "YREG" }, { 0x0048, "STATUS" }, { 0x004E, "RNDL" }, { 0x004F, "RNDH" },
	{ 0x0067, "TXTTAB" }, { 0x0069, "VARTAB" }, { 0x006b, "ARYTAB" }, { 0x6d, "STREND" },
	{ 0x006f, "FRETOP" }, { 0x0071, "FRESPC" }, { 0x0073, "MEMSIZ" }, { 0x0075, "CURLIN" },
	{ 0x0077, "OLDLIN" }, { 0x0079, "OLDTEXT" }, { 0x007b, "DATLIN" }, { 0x007d, "DATPTR" },
	{ 0x007f, "INPTR" }, { 0x0081, "VARNAM" }, { 0x0083, "VARPNT" }, { 0x0085, "FORPNT" },
	{ 0x009A, "EXPON" }, { 0x009C, "EXPSGN" }, { 0x009d, "FAC" }, { 0x00A2, "FAC.SIGN" },
	{ 0x00a5, "ARG" }, { 0x00AA, "ARG.SIGN" }, { 0x00af, "PRGEND" }, { 0x00B8, "TXTPTR" },
	{ 0x00C9, "RNDSEED" }, { 0x00D6, "LOCK" }, { 0x00D8, "ERRFLG" }, { 0x00DA, "ERRLIN" },
	{ 0x00DE, "ERRNUM" }, { 0x00E4, "HGR.COLOR" }, { 0x00E6, "HGR.PAGE" }, { 0x00F1, "SPEEDZ" },

	{ 0xc000, "KBD / 80STOREOFF" }, { 0xc001, "80STOREON" }, { 0xc002, "RDMAINRAM" }, {0xc003, "RDCARDRAM" }, {0xc004, "WRMAINRAM" },
	{ 0xc005, "WRCARDRAM" }, { 0xc006, "SETSLOTCXROM" }, { 0xc007, "SETINTCXROM" }, { 0xc008, "SETSTDZP" },
	{ 0xc009, "SETALTZP "}, { 0xc00a, "SETINTC3ROM" }, { 0xc00b, "SETSLOTC3ROM" }, { 0xc00c, "CLR80VID" },
	{ 0xc00d, "SET80VID" }, { 0xc00e, "CLRALTCHAR" }, { 0xc00f, "SETALTCHAR" }, { 0xc010, "KBDSTRB" },
	{ 0xc011, "RDLCBNK2" }, { 0xc012, "RDLCRAM" }, { 0xc013, "RDRAMRD" }, { 0xc014, "RDRAMWRT" },
	{ 0xc015, "RDCXROM" }, { 0xc016, "RDALTZP" }, { 0xc017, "RDC3ROM" }, { 0xc018, "RD80STORE" },
	{ 0xc019, "RDVBL" }, { 0xc01a, "RDTEXT" }, { 0xc01b, "RDMIXED" }, { 0xc01c, "RDPAGE2" },
	{ 0xc01d, "RDHIRES" }, { 0xc01e, "RDALTCHAR" }, { 0xc01f, "RD80VID" }, { 0xc020, "TAPEOUT" },
	{ 0xc021, "MONOCOLOR" }, { 0xc022, "TBCOLOR" }, { 0xc023, "VGCINT" }, { 0xc024, "MOUSEDATA" },
	{ 0xc025, "KEYMODREG" }, { 0xc026, "DATAREG" }, { 0xc027, "KMSTATUS" }, { 0xc028, "ROMBANK" },
	{ 0xc029, "NEWVIDEO"}, { 0xc02b, "LANGSEL" }, { 0xc02c, "CHARROM" }, { 0xc02d, "SLOTROMSEL" },
	{ 0xc02e, "VERTCNT" }, { 0xc02f, "HORIZCNT" }, { 0xc030, "SPKR" }, { 0xc031, "DISKREG" },
	{ 0xc032, "SCANINT" }, { 0xc033, "CLOCKDATA" }, { 0xc034, "CLOCKCTL" }, { 0xc035, "SHADOW" },
	{ 0xc036, "FPIREG/CYAREG" }, { 0xc037, "BMAREG" }, { 0xc038, "SCCBREG" }, { 0xc039, "SCCAREG" },
	{ 0xc03a, "SCCBDATA" }, { 0xc03b, "SCCADATA" }, { 0xc03c, "SOUNDCTL" }, { 0xc03d, "SOUNDDATA" },
	{ 0xc03e, "SOUNDADRL" }, { 0xc03f, "SOUNDADRH" }, { 0xc040, "STROBE/RDXYMSK" }, { 0xc041, "RDVBLMSK" },
	{ 0xc042, "RDX0EDGE" }, { 0xc043, "RDY0EDGE" }, { 0xc044, "MMDELTAX" }, { 0xc045, "MMDELTAY" },
	{ 0xc046, "DIAGTYPE" }, { 0xc047, "CLRVBLINT" }, { 0xc048, "CLRXYINT" }, { 0xc04f, "EMUBYTE" },
	{ 0xc050, "TXTCLR" }, { 0xc051, "TXTSET" },
	{ 0xc052, "MIXCLR" }, { 0xc053, "MIXSET" }, { 0xc054, "TXTPAGE1" }, { 0xc055, "TXTPAGE2" },
	{ 0xc056, "LORES" }, { 0xc057, "HIRES" }, { 0xc058, "CLRAN0" }, { 0xc059, "SETAN0" },
	{ 0xc05a, "CLRAN1" }, { 0xc05b, "SETAN1" }, { 0xc05c, "CLRAN2" }, { 0xc05d, "SETAN2" },
	{ 0xc05e, "DHIRESON" }, { 0xc05f, "DHIRESOFF" }, { 0xc060, "TAPEIN" }, { 0xc061, "RDBTN0" },
	{ 0xc062, "BUTN1" }, { 0xc063, "RD63" }, { 0xc064, "PADDL0" }, { 0xc065, "PADDL1" },
	{ 0xc066, "PADDL2" }, { 0xc067, "PADDL3" }, { 0xc068, "STATEREG" }, { 0xc070, "PTRIG" }, { 0xc073, "BANKSEL" },
	{ 0xc07e, "IOUDISON" }, { 0xc07f, "IOUDISOFF" }, { 0xc081, "ROMIN" }, { 0xc083, "LCBANK2" },
	{ 0xc085, "ROMIN" }, { 0xc087, "LCBANK2" }, { 0xcfff, "DISCC8ROM" },

	{ 0xF800, "F8ROM:PLOT" }, { 0xF80E, "F8ROM:PLOT1" } , { 0xF819, "F8ROM:HLINE" }, { 0xF828, "F8ROM:VLINE" },
	{ 0xF832, "F8ROM:CLRSCR" }, { 0xF836, "F8ROM:CLRTOP" }, { 0xF838, "F8ROM:CLRSC2" }, { 0xF847, "F8ROM:GBASCALC" },
	{ 0xF856, "F8ROM:GBCALC" }, { 0xF85F, "F8ROM:NXTCOL" }, { 0xF864, "F8ROM:SETCOL" }, { 0xF871, "F8ROM:SCRN" },
	{ 0xF882, "F8ROM:INSDS1" }, { 0xF88E, "F8ROM:INSDS2" }, { 0xF8A5, "F8ROM:ERR" }, { 0xF8A9, "F8ROM:GETFMT" },
	{ 0xF8D0, "F8ROM:INSTDSP" }, { 0xF940, "F8ROM:PRNTYX" }, { 0xF941, "F8ROM:PRNTAX" }, { 0xF944, "F8ROM:PRNTX" },
	{ 0xF948, "F8ROM:PRBLNK" }, { 0xF94A, "F8ROM:PRBL2" },  { 0xF84C, "F8ROM:PRBL3" }, { 0xF953, "F8ROM:PCADJ" },
	{ 0xF854, "F8ROM:PCADJ2" }, { 0xF856, "F8ROM:PCADJ3" }, { 0xF85C, "F8ROM:PCADJ4" }, { 0xF962, "F8ROM:FMT1" },
	{ 0xF9A6, "F8ROM:FMT2" }, { 0xF9B4, "F8ROM:CHAR1" }, { 0xF9BA, "F8ROM:CHAR2" }, { 0xF9C0, "F8ROM:MNEML" },
	{ 0xFA00, "F8ROM:MNEMR" }, { 0xFA40, "F8ROM:OLDIRQ" }, { 0xFA4C, "F8ROM:BREAK" }, { 0xFA59, "F8ROM:OLDBRK" },
	{ 0xFA62, "F8ROM:RESET" }, { 0xFAA6, "F8ROM:PWRUP" }, { 0xFABA, "F8ROM:SLOOP" }, { 0xFAD7, "F8ROM:REGDSP" },
	{ 0xFADA, "F8ROM:RGDSP1" }, { 0xFAE4, "F8ROM:RDSP1" }, { 0xFB19, "F8ROM:RTBL" }, { 0xFB1E, "F8ROM:PREAD" },
	{ 0xFB21, "F8ROM:PREAD4" }, { 0xFB25, "F8ROM:PREAD2" }, { 0xFB2F, "F8ROM:INIT" }, { 0xFB39, "F8ROM:SETTXT" },
	{ 0xFB40, "F8ROM:SETGR" }, { 0xFB4B, "F8ROM:SETWND" }, { 0xFB51, "F8ROM:SETWND2" }, { 0xFB5B, "F8ROM:TABV" },
	{ 0xFB60, "F8ROM:APPLEII" }, { 0xFB6F, "F8ROM:SETPWRC" }, { 0xFB78, "F8ROM:VIDWAIT" }, { 0xFB88, "F8ROM:KBDWAIT" },
	{ 0xFBB3, "F8ROM:VERSION" }, { 0xFBBF, "F8ROM:ZIDBYTE2" }, { 0xFBC0, "F8ROM:ZIDBYTE" }, { 0xFBC1, "F8ROM:BASCALC" },
	{ 0xFBD0, "F8ROM:BSCLC2" }, { 0xFBDD, "F8ROM:BELL1" }, { 0xFBE2, "F8ROM:BELL1.2" }, { 0xFBE4, "F8ROM:BELL2" },
	{ 0xFBF0, "F8ROM:STORADV" }, { 0xFBF4, "F8ROM:ADVANCE" }, { 0xFBFD, "F8ROM:VIDOUT" }, { 0xFC10, "F8ROM:BS" },
	{ 0xFC1A, "F8ROM:UP" }, { 0xFC22, "F8ROM:VTAB" }, { 0xFC24, "F8ROM:VTABZ" }, { 0xFC42, "F8ROM:CLREOP" },
	{ 0xFC46, "F8ROM:CLEOP1" }, { 0xFC58, "F8ROM:HOME" }, { 0xFC62, "F8ROM:CR" }, { 0xFC66, "F8ROM:LF" },
	{ 0xFC70, "F8ROM:SCROLL" }, { 0xFC95, "F8ROM:SCRL3" }, { 0xFC9C, "F8ROM:CLREOL" }, { 0xFC9E, "F8ROM:CLREOLZ" },
	{ 0xFCA8, "F8ROM:WAIT" }, { 0xFCB4, "F8ROM:NXTA4" }, { 0xFCBA, "F8ROM:NXTA1" }, { 0xFCC9, "F8ROM:HEADR" },
	{ 0xFCEC, "F8ROM:RDBYTE" }, { 0xFCEE, "F8ROM:RDBYT2" }, { 0xFCFA, "F8ROM:RD2BIT" }, { 0xFD0C, "F8ROM:RDKEY" },
	{ 0xFD18, "F8ROM:RDKEY1" }, { 0xFD1B, "F8ROM:KEYIN" }, { 0xFD2F, "F8ROM:ESC" }, { 0xFD35, "F8ROM:RDCHAR" },
	{ 0xFD3D, "F8ROM:NOTCR" }, { 0xFD62, "F8ROM:CANCEL" }, { 0xFD67, "F8ROM:GETLNZ" }, { 0xFD6A, "F8ROM:GETLN" },
	{ 0xFD6C, "F8ROM:GETLN0" }, { 0xFD6F, "F8ROM:GETLN1" }, { 0xFD8B, "F8ROM:CROUT1" }, { 0xFD8E, "F8ROM:CROUT" },
	{ 0xFD92, "F8ROM:PRA1" }, { 0xFDA3, "F8ROM:XAM8" }, { 0xFDDA, "F8ROM:PRBYTE" }, { 0xFDE3, "F8ROM:PRHEX" },
	{ 0xFDE5, "F8ROM:PRHEXZ" }, { 0xFDED, "F8ROM:COUT" }, { 0xFDF0, "F8ROM:COUT1" }, { 0xFDF6, "F8ROM:COUTZ" },
	{ 0xFE18, "F8ROM:SETMODE" }, { 0xFE1F, "F8ROM:IDROUTINE" }, { 0xFE20, "F8ROM:LT" }, { 0xFE22, "F8ROM:LT2" },
	{ 0xFE2C, "F8ROM:MOVE" }, { 0xFE36, "F8ROM:VFY" }, { 0xFE5E, "F8ROM:LIST" }, { 0xFE63, "F8ROM:LIST2" },
	{ 0xFE75, "F8ROM:A1PC" }, { 0xFE80, "F8ROM:SETINV" }, { 0xFE84, "F8ROM:SETNORM" }, { 0xFE89, "F8ROM:SETKBD" },
	{ 0xFE8B, "F8ROM:INPORT" }, { 0xFE8D, "F8ROM:INPRT" }, { 0xFE93, "F8ROM:SETVID" }, { 0xFE95, "F8ROM:OUTPORT" },
	{ 0xFE97, "F8ROM:OUTPRT" }, { 0xFEB0, "F8ROM:XBASIC" }, { 0xFEB3, "F8ROM:BASCONT" }, { 0xFEB6, "F8ROM:GO" },
	{ 0xFECA, "F8ROM:USR" }, { 0xFECD, "F8ROM:WRITE" }, { 0xFEFD, "F8ROM:READ" }, { 0xFF2D, "F8ROM:PRERR" },
	{ 0xFF3A, "F8ROM:BELL" }, { 0xFF3F, "F8ROM:RESTORE" }, { 0xFF4A, "F8ROM:SAVE" }, { 0xFF58, "F8ROM:IORTS" },
	{ 0xFF59, "F8ROM:OLDRST" }, { 0xFF65, "F8ROM:MON" }, { 0xFF69, "F8ROM:MONZ" }, { 0xFF6C, "F8ROM:MONZ2" },
	{ 0xFF70, "F8ROM:MONZ4" }, { 0xFF8A, "F8ROM:DIG" }, { 0xFFA7, "F8ROM:GETNUM" }, { 0xFFAD, "F8ROM:NXTCHR" },
	{ 0xFFBE, "F8ROM:TOSUB" }, { 0xFFC7, "F8ROM:ZMODE" }, { 0xFFCC, "F8ROM:CHRTBL" }, { 0xFFE3, "F8ROM:SUBTBL" },

	{ 0xffff, "" }
};

static const struct dasm_data32 gs_vectors[] =
{
	{ 0xE10000, "System Tool dispatcher" }, { 0xE10004, "System Tool dispatcher, glue entry" }, { 0xE10008, "User Tool dispatcher" }, { 0xE1000C, "User Tool dispatcher, glue entry" },
	{ 0xE10010, "Interrupt mgr" }, { 0xE10014, "COP mgr" }, { 0xE10018, "Abort mgr" }, { 0xE1001C, "System Death mgr" }, { 0xE10020, "AppleTalk interrupt" },
	{ 0xE10024, "Serial interrupt" }, { 0xE10028, "Scanline interrupt" }, { 0xE1002C, "Sound interrupt" }, { 0xE10030, "VertBlank interrupt" }, { 0xE10034, "Mouse interrupt" },
	{ 0xE10038, "1/4 sec interrupt" }, { 0xE1003C, "Keyboard interrupt" }, { 0xE10040, "ADB Response byte int" }, { 0xE10044, "ADB SRQ int" }, { 0xE10048, "Desk Acc mgr" },
	{ 0xE1004C, "FlushBuffer handler" }, { 0xE10050, "KbdMicro interrupt" }, { 0xE10054, "1 sec interrupt" }, { 0xE10058, "External VGC int" }, { 0xE1005C, "other interrupt" },
	{ 0xE10060, "Cursor update" }, { 0xE10064, "IncBusy" }, { 0xE10068, "DecBusy" }, { 0xE1006C, "Bell vector" }, { 0xE10070, "Break vector" }, { 0xE10074, "Trace vector" },
	{ 0xE10078, "Step vector" }, { 0xE1007C, "[install ROMdisk]" }, { 0xE10080, "ToWriteBram" }, { 0xE10084, "ToReadBram" }, { 0xE10088, "ToWriteTime" },
	{ 0xE1008C, "ToReadTime" }, { 0xE10090, "ToCtrlPanel" }, { 0xE10094, "ToBramSetup" }, { 0xE10098, "ToPrintMsg8" }, { 0xE1009C, "ToPrintMsg16" }, { 0xE100A0, "Native Ctrl-Y" },
	{ 0xE100A4, "ToAltDispCDA" }, { 0xE100A8, "ProDOS 16 [inline parms]" }, { 0xE100AC, "OS vector" }, { 0xE100B0, "GS/OS(@parms,call) [stackmode parms]" },
	{ 0xE100B4, "OS_P8_Switch" }, { 0xE100B8, "OS_Public_Flags" }, { 0xE100BC, "OS_KIND (byte: 0=P8,1=P16)" }, { 0xE100BD, "OS_BOOT (byte)" }, { 0xE100BE, "OS_BUSY (bit 15=busy)" },
	{ 0xE100C0, "MsgPtr" }, { 0xe10135, "CURSOR" }, { 0xe10136, "NXTCUR" },
	{ 0xE10180, "ToBusyStrip" }, { 0xE10184, "ToStrip" }, { 0xe10198, "MDISPATCH" }, { 0xe1019c, "MAINSIDEPATCH" },
	{ 0xE101B2, "MidiInputPoll" }, { 0xE10200, "Memory Mover" }, { 0xE10204, "Set System Speed" },
	{ 0xE10208, "Slot Arbiter" }, { 0xE10220, "HyperCard IIgs callback" }, { 0xE10224, "WordForRTL" }, { 0xE11004, "ATLK: BASIC" }, { 0xE11008, "ATLK: Pascal" },
	{ 0xE1100C, "ATLK: RamGoComp" }, { 0xE11010, "ATLK: SoftReset" }, { 0xE11014, "ATLK: RamDispatch" }, { 0xE11018, "ATLK: RamForbid" }, { 0xE1101C, "ATLK: RamPermit" },
	{ 0xE11020, "ATLK: ProEntry" }, { 0xE11022, "ATLK: ProDOS" }, { 0xE11026, "ATLK: SerStatus" }, { 0xE1102A, "ATLK: SerWrite" }, { 0xE1102E, "ATLK: SerRead" },
	{ 0xE1103A, "ATLK: InitFileHook" }, { 0xE1103E, "ATLK: PFI Vector" }, { 0xE1D600, "ATLK: CmdTable" }, { 0xE1DA00, "ATLK: TickCount" },
	{ 0xE01D00, "BRegSave" }, { 0xE01D02, "IntStatus" }, { 0xE01D03, "SVStateReg" }, { 0xE01D04, "80ColSave" }, { 0xE01D05, "LoXClampSave" },
	{ 0xE01D07, "LoYClampSave" }, { 0xE01D09, "HiXClampSave" }, { 0xE01D0B, "HiYClampSave" }, { 0xE01D0D, "OutGlobals" }, { 0xE01D14, "Want40" },
	{ 0xE01D16, "CursorSave" }, { 0xE01D18, "NEWVIDSave" }, { 0xE01D1A, "TXTSave" }, { 0xE01D1B, "MIXSave" }, { 0xE01D1C, "PAGE2Save" },
	{ 0xE01D1D, "HIRESSave" }, { 0xE01D1E, "ALTCHARSave" }, { 0xE01D1F, "VID80Save" }, { 0xE01D20, "Int1AY" }, { 0xE01D2D, "Int1BY" },
	{ 0xE01D39, "Int2AY" }, { 0xE01D4C, "Int2BY" }, { 0xE01D61, "MOUSVBLSave" }, { 0xE01D63, "DirPgSave" }, { 0xE01D65, "C3ROMSave" },
	{ 0xE01D66, "Save4080" }, { 0xE01D67, "NumInts" }, { 0xE01D68, "MMode" }, { 0xE01D6A, "MyMSLOT" }, { 0xE01D6C, "Slot" },
	{ 0xE01D6E, "EntryCount" }, { 0xE01D70, "BottomLine" }, { 0xE01D72, "HPos" }, { 0xE01D74, "VPos" }, { 0xE01D76, "CurScreenLoc" },
	{ 0xE01D7C, "NumDAs" }, { 0xE01D7E, "LeftBorder" }, { 0xE01D80, "FirstMenuItem" }, { 0xE01D82, "IDNum" }, { 0xE01D84, "CDATabHndl" },
	{ 0xE01D88, "RoomLeft" }, { 0xE01D8A, "KeyInput" }, { 0xE01D8C, "EvntRec" }, { 0xE01D8E, "Message" }, { 0xE01D92, "When" },
	{ 0xE01D96, "Where" }, { 0xE01D9A, "Mods" }, { 0xE01D9C, "StackSave" }, { 0xE01D9E, "OldOutGlobals" }, { 0xE01DA2, "OldOutDevice" },
	{ 0xE01DA8, "CDataBPtr" }, { 0xE01DAC, "DAStrPtr" }, { 0xE01DB0, "CurCDA" }, { 0xE01DB2, "OldOutHook" }, { 0xE01DB4, "OldInDev" },
	{ 0xE01DBA, "OldInGlob" }, { 0xE01DBE, "RealDeskStat" }, { 0xE01DC0, "Next" }, { 0xE01DDE, "SchActive" }, { 0xE01DDF, "TaskQueue" },
	{ 0xE01DDF, "FirstTask" }, { 0xE01DE3, "SecondTask" }, { 0xE01DED, "Scheduler" }, { 0xE01DEF, "Offset" }, { 0xE01DFF, "Lastbyte" },
	{ 0xE01E04, "QD:StdText" }, { 0xE01E08, "QD:StdLine" }, { 0xE01E0C, "QD:StdRect" }, { 0xE01E10, "QD:StdRRect" }, { 0xE01E14, "QD:StdOval" }, { 0xE01E18, "QD:StdArc" }, { 0xE01E1C, "QD:StdPoly" },
	{ 0xE01E20, "QD:StdRgn" }, { 0xE01E24, "QD:StdPixels" }, { 0xE01E28, "QD:StdComment" }, { 0xE01E2C, "QD:StdTxMeas" }, { 0xE01E30, "QD:StdTxBnds" }, { 0xE01E34, "QD:StdGetPic" },
	{ 0xE01E38, "QD:StdPutPic" }, { 0xE01E98, "QD:ShieldCursor" }, { 0xE01E9C, "QD:UnShieldCursor" },
	{ 0x010100, "MNEMSTKPTR" }, { 0x010101, "ALEMSTKPTR" }, { 0x01FC00, "SysSrv:DEV_DISPATCHER" }, { 0x01FC04, "SysSrv:CACHE_FIND_BLK" }, { 0x01FC08, "SysSrv:CACHE_ADD_BLK" },
	{ 0x01FC0C, "SysSrv:CACHE_INIT" }, { 0x01FC10, "SysSrv:CACHE_SHUTDN" }, { 0x01FC14, "SysSrv:CACHE_DEL_BLK" }, { 0x01FC18, "SysSrv:CACHE_DEL_VOL" },
	{ 0x01FC1C, "SysSrv:ALLOC_SEG" }, { 0x01FC20, "SysSrv:RELEASE_SEG" }, { 0x01FC24, "SysSrv:ALLOC_VCR" }, { 0x01FC28, "SysSrv:RELEASE_VCR" },
	{ 0x01FC2C, "SysSrv:ALLOC_FCR" }, { 0x01FC30, "SysSrv:RELEASE_FCR" }, { 0x01FC34, "SysSrv:SWAP_OUT" }, { 0x01FC38, "SysSrv:DEREF" },
	{ 0x01FC3C, "SysSrv:GET_SYS_GBUF" }, { 0x01FC40, "SysSrv:SYS_EXIT" }, { 0x01FC44, "SysSrv:SYS_DEATH" }, { 0x01FC48, "SysSrv:FIND_VCR" },
	{ 0x01FC4C, "SysSrv:FIND_FCR" }, { 0x01FC50, "SysSrv:SET_SYS_SPEED" }, { 0x01FC54, "SysSrv:CACHE_FLSH_DEF" }, { 0x01FC58, "SysSrv:RENAME_VCR" },
	{ 0x01FC5C, "SysSrv:RENAME_FCR" }, { 0x01FC60, "SysSrv:GET_VCR" }, { 0x01FC64, "SysSrv:GET_FCR" }, { 0x01FC68, "SysSrv:LOCK_MEM" },
	{ 0x01FC6C, "SysSrv:UNLOCK_MEM" }, { 0x01FC70, "SysSrv:MOVE_INFO" }, { 0x01FC74, "SysSrv:CVT_0TO1" }, { 0x01FC78, "SysSrv:CVT_1TO0" },
	{ 0x01FC7C, "SysSrv:REPLACE80" }, { 0x01FC80, "SysSrv:TO_B0_CORE" }, { 0x01FC84, "SysSrv:G_DISPATCH" }, { 0x01FC88, "SysSrv:SIGNAL" },
	{ 0x01FC8C, "SysSrv:GET_SYS_BUFF" }, { 0x01FC90, "SysSrv:SET_DISK_SW" }, { 0x01FC94, "SysSrv:REPORT_ERROR" }, { 0x01FC98, "SysSrv:MOUNT_MESSAGE" },
	{ 0x01FC9C, "SysSrv:FULL_ERROR" }, { 0x01FCA0, "SysSrv:RESERVED_07" }, { 0x01FCA4, "SysSrv:SUP_DRVR_DISP" }, { 0x01FCA8, "SysSrv:INSTALL_DRIVER" },
	{ 0x01FCAC, "SysSrv:S_GET_BOOT_PFX" },  { 0x01FCB0, "SysSrv:S_SET_BOOT_PFX" }, { 0x01FCB4, "SysSrv:LOW_ALLOCATE" },
	{ 0x01FCB8, "SysSrv:GET_STACKED_ID" }, { 0x01FCBC, "SysSrv:DYN_SLOT_ARBITER" }, { 0x01FCC0, "SysSrv:PARSE_PATH" },
	{ 0x01FCC4, "SysSrv:OS_EVENT" }, { 0x01FCC8, "SysSrv:INSERT_DRIVER" }, { 0x01FCCC, "SysSrv:(device manager?)" },
	{ 0x01FCD0, "SysSrv:Old Device Dispatcher" }, { 0x01FCD4, "SysSrv:INIT_PARSE_PATH" }, { 0x01FCD8, "SysSrv:UNBIND_INT_VEC" },
	{ 0x01FCDC, "SysSrv:DO_INSERT_SCAN" }, { 0x01FCE0, "SysSrv:TOOLBOX_MSG" },

	{ 0xffff, "" }
};


void DumpInstruction() {

	std::string log = "{0:02X}:{1:04X}: ";
	const char* f = "";
	const char* sta;

	instruction_type type = implied;
	operand_type opType = none;

	std::string arg1 = "";
	std::string arg2 = "";

	switch (ins_in[0])
	{
	case 0x00: sta = "brk"; break;
	case 0x98: sta = "tya"; break;
	case 0xA8: sta = "tay"; break;
	case 0xAA: sta = "tax"; break;
	case 0x8A: sta = "txa"; break;
	case 0x9B: sta = "txy"; break;
	case 0x40: sta = "rti"; break;
	case 0x60: sta = "rts"; break;
	case 0x9A: sta = "txs"; break;
	case 0xBA: sta = "tsx"; break;
	case 0xBB: sta = "tyx"; break;
	case 0x0C: sta = "tsb"; type = absolute; opType = byte3; break;
	case 0x1B: sta = "tcs"; break;
	case 0x5B: sta = "tcd"; break;

	case 0x08: sta = "php"; break;
	case 0x0B: sta = "phd"; break;
	case 0x2B: sta = "pld"; break;
	case 0xAB: sta = "plb"; break;
	case 0x8B: sta = "phb"; break;
	case 0x4B: sta = "phk"; break;
	case 0x28: sta = "plp"; break;
	case 0xfb: sta = "xce"; break;

	case 0x18: sta = "clc"; break;
	case 0x58: sta = "cli"; break;
	case 0xB8: sta = "clv"; break;
	case 0xD8: sta = "cld"; break;

	case 0xE8: sta = "inx"; break;
	case 0xC8: sta = "iny"; break;
	case 0x1A: sta = "ina"; break;

	case 0x70: sta = "bvs"; type = relativeLong; break;
	case 0x80: sta = "bra"; type = relativeLong; break;

	case 0x38: sta = "sec"; break;
	case 0xe2: sta = "sep"; type = immediate;  break;
	case 0x78: sta = "sei"; break;
	case 0xF8: sta = "sed"; break;

	case 0x48: sta = "pha"; break;
	case 0xDA: sta = "phx"; break;
	case 0x5A: sta = "phy"; break;
	case 0x68: sta = "pla"; break;
	case 0xFA: sta = "plx"; break;
	case 0x7A: sta = "ply"; break;

	case 0xF4: sta = "pea"; type = absolute; break;
	case 0x62: sta = "per"; type = relativeLong; break;
	case 0xD4: sta = "pei"; type = zeroPage; break;

	case 0x0A: sta = "asl"; type = accumulator; break;
	case 0x06: sta = "asl"; type = zeroPage; break;
	case 0x16: sta = "asl"; type = zeroPageX; break;
	case 0x0E: sta = "asl"; type = absolute; break;
	case 0x1E: sta = "asl"; type = absoluteX; break;

	case 0x01: sta = "ora"; type = indirectX; break;
	case 0x03: sta = "ora"; type = stackmode; break;
	case 0x05: sta = "ora"; type = zeroPage; break;
	case 0x07: sta = "ora"; type = direct24; break;
	case 0x09: sta = "ora"; type = immediate; break;
	case 0x0D: sta = "ora"; type = absolute; opType = byte2; break;
	case 0x0F: sta = "ora"; type = longValue; opType = byte3; break;
	case 0x11: sta = "ora"; type = indirectY; break;
	case 0x15: sta = "ora"; type = zeroPageX; break;
	case 0x17: sta = "ora"; type = direct24Y; break;
	case 0x19: sta = "ora"; type = absoluteY; break;
	case 0x1D: sta = "ora"; type = absoluteX; break;
	case 0x1F: sta = "ora"; type = longX; break;

	case 0x43: sta = "eor"; type = stackmode; break;
	case 0x47: sta = "eor"; type = direct24; break;
	case 0x49: sta = "eor"; type = immediate; break;
	case 0x4d: sta = "eor"; type = absolute; break;
	case 0x45: sta = "eor"; type = zeroPage; break;
	case 0x55: sta = "eor"; type = zeroPageX; break;
	case 0x57: sta = "eor"; type = direct24Y; break;
	case 0x5d: sta = "eor"; type = absoluteX; break;
	case 0x59: sta = "eor"; type = absoluteY; break;
	case 0x41: sta = "eor"; type = indirectX; break;
	case 0x51: sta = "eor"; type = indirectY; break;

	case 0x23: sta = "and"; type = stackmode; break;
	case 0x25: sta = "and"; type = zeroPage; break;
	case 0x27: sta = "and"; type = direct24; break;
	case 0x29: sta = "and"; type = immediate; break;
	case 0x2D: sta = "and"; type = absolute; break;
	case 0x35: sta = "and"; type = zeroPageX; break;
	case 0x37: sta = "and"; type = direct24Y; break;
	case 0x39: sta = "and"; type = absoluteY; break;
	case 0x3D: sta = "and"; type = absoluteX; break;


	case 0xE1: sta = "sbc"; type = indirectX; break;
	case 0xE3: sta = "sbc"; type = stackmode; break;
	case 0xE5: sta = "sbc"; type = zeroPage; break;
	case 0xE7: sta = "sbc"; type = direct24; break;
	case 0xE9: sta = "sbc"; type = immediate; break;
	case 0xED: sta = "sbc"; type = absolute; break;
	case 0xF1: sta = "sbc"; type = indirectY; break;
	case 0xF5: sta = "sbc"; type = zeroPageX; break;
	case 0xF7: sta = "sbc"; type = direct24Y; break;
	case 0xF9: sta = "sbc"; type = absoluteY; break;
	case 0xFD: sta = "sbc"; type = absoluteX; break;

	case 0xC3: sta = "cmp"; type = stackmode; break;
	case 0xC5: sta = "cmp"; type = zeroPage; break;
	case 0xC7: sta = "cmp"; type = direct24; break;
	case 0xC9: sta = "cmp"; type = immediate; break;
	case 0xCD: sta = "cmp"; type = absolute; break;
	case 0xCF: sta = "cmp"; type = longValue; opType=byte3; break;
	case 0xD1: sta = "cmp"; type = indirectY; break;
	case 0xD5: sta = "cmp"; type = zeroPageX; break;
	case 0xD7: sta = "cmp"; type = direct24Y; break;
	case 0xD9: sta = "cmp"; type = absoluteY; break;
	case 0xDD: sta = "cmp"; type = absoluteX; break;
	case 0xDF: sta = "cmp"; type = longX; break;


	case 0xE0: sta = "cpx"; type = immediate; break;
	case 0xE4: sta = "cpx"; type = zeroPage; break;
	case 0xEC: sta = "cpx"; type = absolute; break;

	case 0xC0: sta = "cpy"; type = immediate; break;
	case 0xC4: sta = "cpy"; type = zeroPage; break;
	case 0xCC: sta = "cpy"; type = absolute; break;

	case 0xC2: sta = "rep"; type = immediate; break;

	case 0xA2: sta = "ldx"; type = immediate; break;
	case 0xA6: sta = "ldx"; type = zeroPage; break;
	case 0xB6: sta = "ldx"; type = zeroPageY; break;
	case 0xAE: sta = "ldx"; type = absolute; break;
	case 0xBE: sta = "ldx"; type = absoluteY; break;

	case 0xA0: sta = "ldy"; type = immediate; break;
	case 0xA4: sta = "ldy"; type = zeroPage; break;
	case 0xB4: sta = "ldy"; type = zeroPageX; break;
	case 0xAC: sta = "ldy"; type = absolute; break;
	case 0xBC: sta = "ldy"; type = absoluteX; break;

	case 0xA1: sta = "lda"; type = indirectX; break;
	case 0xA3: sta = "lda"; type = stackmode; break;
	case 0xA5: sta = "lda"; type = zeroPage; break;
	case 0xA7: sta = "lda"; type = direct24; break;
	case 0xA9: sta = "lda"; type = immediate; break;
	case 0xAD: sta = "lda"; type = absolute; opType = byte3; break;
	case 0xAF: sta = "lda"; type = longValue; opType=byte3; break;
	case 0xB1: sta = "lda"; type = indirectY; break;
	case 0xB2: sta = "lda"; type = indirect; break;
	case 0xB5: sta = "lda"; type = zeroPageX; break;
	case 0xB7: sta = "lda"; type = direct24Y; break;
	case 0xB9: sta = "lda"; type = absoluteY; break;
	case 0xBD: sta = "lda"; type = absoluteX; break;
	case 0xBF: sta = "lda"; type = longX; break;


	case 0x1C: sta = "trb"; type = absolute; break;

	case 0x81: sta = "sta"; type = indirectX; break;
	case 0x83: sta = "sta"; type = stackmode; break;
	case 0x85: sta = "sta"; type = zeroPage; break;
	case 0x87: sta = "sta"; type = direct24; break;
	case 0x8D: sta = "sta"; type = absolute; opType = byte3; break;
	case 0x8F: sta = "sta"; type = longValue; opType = byte3; break;
	case 0x91: sta = "sta"; type = indirectY; break;
	case 0x95: sta = "sta"; type = zeroPageX; break;
	case 0x97: sta = "sta"; type = direct24Y; break;
	case 0x99: sta = "sta"; type = absoluteY; break;
	case 0x9D: sta = "sta"; type = absoluteX; break;
	case 0x9F: sta = "sta"; type = longX; break;


	case 0x86: sta = "stx"; type = zeroPage; break;
	case 0x96: sta = "stx"; type = zeroPageY; break;
	case 0x8E: sta = "stx"; type = absolute; break;
	case 0x84: sta = "sty"; type = zeroPage; break;
	case 0x94: sta = "sty"; type = zeroPageX; break;
	case 0x8C: sta = "sty"; type = absolute; break;
	case 0x64: sta = "stz"; type = zeroPage;  break;
	case 0x9C: sta = "stz"; type = absolute;  opType = byte3; break;
	case 0x9E: sta = "stz"; type = absoluteX; break;

	case 0x63: sta = "adc"; type = stackmode; break;
	case 0x65: sta = "adc"; type = zeroPage; break;
	case 0x67: sta = "adc"; type = direct24; break;
	case 0x69: sta = "adc"; type = immediate; break;
	case 0x6D: sta = "adc"; type = absolute; break;
	case 0x71: sta = "adc"; type = indirectY; break;
	case 0x75: sta = "adc"; type = zeroPageX; break;
	case 0x77: sta = "adc"; type = direct24Y; break;
	case 0x79: sta = "adc"; type = absoluteY; break;
	case 0x7D: sta = "adc"; type = absoluteX; break;

	case 0x3b: sta = "tsc"; break;
	case 0x7b: sta = "tdc"; break;

	case 0xC6: sta = "dec"; type = zeroPage;  break;
	case 0xD6: sta = "dec"; type = zeroPageX;  break;
	case 0xCE: sta = "dec"; type = absolute;  break;
	case 0xDE: sta = "dec"; type = absoluteX;  break;

	case 0x3A: sta = "dea"; break;
	case 0xCA: sta = "dex"; break;
	case 0x88: sta = "dey"; break;

	case 0xEB: sta = "xba"; break;

	case 0x24: sta = "bit"; type = zeroPage; break;
	case 0x2C: sta = "bit"; type = absolute; break;
	case 0x3C: sta = "bit"; type = absoluteX; break;
	case 0x89: sta = "bit"; type = immediate; break;

	case 0x30: sta = "bmi"; type = relativeLong; break;
	case 0x90: sta = "bcc"; type = relative; break;
	case 0xB0: sta = "bcs"; type = relative; break;
	case 0xD0: sta = "bne"; type = relative; break;
	case 0xF0: sta = "beq"; type = relative; break;
	case 0x50: sta = "bvc"; type = relative; break;
	case 0x10: sta = "bpl"; type = relative; break;

	case 0x26: sta = "rol"; type = zeroPage; break;
	case 0x2a: sta = "rol"; type = accumulator; break;
	case 0x2e: sta = "rol"; type = absolute ; break;
	case 0x3e: sta = "rol"; type = absoluteX; break;

	case 0x66: sta = "ror"; type = zeroPage; break;
	case 0x6a: sta = "ror"; type = accumulator; break;
	case 0x6e: sta = "ror"; type = absolute ; break;
	case 0x7e: sta = "ror"; type = absoluteX; break;

	case 0x46: sta = "lsr"; type = zeroPage; break;
	case 0x4A: sta = "lsr"; type = accumulator; break;
	case 0x4e: sta = "lsr"; type = absolute ; break;
	case 0x5e: sta = "lsr"; type = absoluteX; break;

	case 0x54: sta = "mvn"; type = srcdst; break;
	case 0x44: sta = "mvp"; type = srcdst; break;

	case 0xE6: sta = "inc"; type = zeroPage; break;
	case 0xF6: sta = "inc"; type = zeroPageX; break;
	case 0xEE: sta = "inc"; type = absolute; break;
	case 0xFE: sta = "inc"; type = absoluteX; break;

	case 0x20: sta = "jsr"; type = absolute; opType = byte3; break;
	case 0xFC: sta = "jsr"; type = absoluteX; break;

	case 0x22: sta = "jsl"; type = longValue; opType = byte3; break;

	case 0x4C: sta = "jmp"; type = absolute; break;
	case 0x5C: sta = "jmp"; type = longValue; opType=byte3; break;
	case 0x6C: sta = "jmp"; type = indirect; break;
	case 0x7C: sta = "jmp"; type = absoluteX; break;

	case 0x6B: sta = "rtl";  break;

	case 0xEA: sta = "nop";  break;

	default: sta = "???";  f = "\t\tPC={0:X} arg1={1:X} arg2={2:X} IN0={3:X} IN1={4:X} IN2={5:X} IN3={6:X} IN4={7:X} MA0={8:X} MA1={9:X} MA2={10:X} MA3={11:X} MA4={12:X}";
	}

	// replace out named values?

	if (ins_index > 1) {

		if (opType == byte3) {
			unsigned long operand = ins_in[1];
			operand |= (ins_in[2] << 8);
			operand |= (ins_in[3] << 16);

			if (ins_index <= 3) {
				operand = ins_in[1];
				operand |= (ins_in[2] << 8);
				operand |= (ins_dbr[1] << 16);
			}
			//console.AddLog("%d %x", ins_index, operand);

			int item = 0;
			while (gs_vectors[item].addr != 0xffff)
			{
				if (gs_vectors[item].addr == operand)
				{
					ins_str[1] = type == longValue ? ">" : "";
					ins_str[1].append(gs_vectors[item].name);
					type = formatted;
					break;
				}
				item++;
			}
		}

		if (type != formatted && (opType == byte2 || (opType == byte3 && ins_index == 3))) {

			unsigned short operand = ins_in[1];
			if (ins_index > 2) {
				operand |= (ins_in[2] << 8);
			}

			int item = 0;
			while (a2_stuff[item].addr != 0xffff)
			{
				if (a2_stuff[item].addr == operand)
				{
					ins_str[1] = a2_stuff[item].name;
					type = formatted;
					break;
				}
				item++;
			}
		}
	}


	f = "{2:s}";
	unsigned long relativeAddress = ins_ma[0] + ((signed char)ins_in[1]) + 2;
	if (sta == "per") {
		relativeAddress++; // I HATE THIS
	}
	unsigned char maHigh0 = (unsigned char)(ins_ma[0] >> 16) & 0xff;
	unsigned char maHigh1 = (unsigned char)(ins_ma[1] >> 16) & 0xff;

	signed char signedIn1 = ins_in[1];
	std::string signedIn1Formatted = signedIn1 < 0 ? fmt::format("-${0:x}", signedIn1 * -1) : fmt::format("${0:x}", signedIn1);

	switch (type) {
	case implied: f = ""; break;
	case formatted: arg1 = ins_str[1]; f = " {2:s}"; break;
	case immediate:
		if (ins_index == 3) {
			arg1 = fmt::format(" #${0:02x}{1:02x}", ins_in[2], ins_in[1]);
		}
		else {
			arg1 = fmt::format(" #${0:02x}", ins_in[1]);
		}
		break;
	case srcdst: arg1 = fmt::format(" ${0:02x}, ${1:02x}", ins_in[2], ins_in[1]); break;
	case absolute: arg1 = fmt::format(" ${0:02x}{1:02x}", ins_in[2], ins_in[1]); break;
	case absoluteX: arg1 = fmt::format(" ${0:02x}{1:02x},x", ins_in[2], ins_in[1]); break;
	case absoluteY: arg1 = fmt::format(" ${0:02x}{1:02x},y", ins_in[2], ins_in[1]); break;
	case zeroPage: arg1 = fmt::format(" ${0:02x}", ins_in[1]); break;
	case direct24: arg1 = fmt::format(" [${0:02x}]", ins_in[1]); break;
	case direct24X: arg1 = fmt::format(" [${0:02x}],x", ins_in[1]); break;
	case direct24Y: arg1 = fmt::format(" [${0:02x}],y", ins_in[1]); break;
	case zeroPageX: arg1 = fmt::format(" ${0:02x},x", ins_in[1]); break;
	case zeroPageY: arg1 = fmt::format(" ${0:02x},y", ins_in[1]); break;
	case indirect: arg1 = fmt::format(" (${0:04x})", ins_in[1]); break;
	case indirectX: arg1 = fmt::format(" (${0:02x}),x", ins_in[1]); break;
	case indirectY: arg1 = fmt::format(" (${0:02x}),y", ins_in[1]); break;
	case stackmode: arg1 = fmt::format(" ${0:x},s", ins_in[1]); break;
	case longValue: arg1 = fmt::format(" ${0:02x}{1:02x}{2:02x}", ins_in[3], ins_in[2], ins_in[1]); break;
	case longX: arg1 = fmt::format(" ${0:02x}{1:02x}{2:02x},x", ins_in[3], ins_in[2], ins_in[1]); break;
	case longY: arg1 = fmt::format(" ${0:02x}{1:02x}{2:02x},y", ins_in[3], ins_in[2], ins_in[1]); break;
		//case longX: arg1 = fmt::format(" ${0:02x}{1:02x}{2:02x},x", maHigh1, ins_in[2], ins_in[1]); break;
		//case longY: arg1 = fmt::format(" ${0:02x}{1:02x}{2:02x},y", maHigh1, ins_in[2], ins_in[1]); break;
	case accumulator: arg1 = "a"; break;
	case relative: arg1 = fmt::format(" {0:06x} ({1})", relativeAddress, signedIn1Formatted);		break;
	case relativeLong: arg1 = fmt::format(" {0:06x} ({1})", relativeAddress, signedIn1Formatted);		break;
	default: arg1 = "UNSUPPORTED TYPE!";
	}

	log.append(sta);
	log.append(f);
	log = fmt::format(log, maHigh0, (unsigned short)ins_pc[0], arg1);

	if (!writeLog(log.c_str())) {
		run_state = RunState::Stopped;
	}
	cpu_instruction_count++;
	//if (sta == "???") {
	//	console.AddLog(log.c_str());
	//	run_enable = 0;
	//}

}


void send_clock() {
	//printf("Update RTC %ld %d\n",main_time,send_clock_done);
	uint8_t rtc[8];
	
//	printf("Update RTC %ld %d\n",main_time,send_clock_done);
	
	time_t t;

	tzset();
	time(&t);

	struct tm tm;
        localtime_r(&t,&tm);

	
	rtc[0] = (tm.tm_sec % 10) | ((tm.tm_sec / 10) << 4);
	rtc[1] = (tm.tm_min % 10) | ((tm.tm_min / 10) << 4);
	rtc[2] = (tm.tm_hour % 10) | ((tm.tm_hour / 10) << 4);
	rtc[3] = (tm.tm_mday % 10) | ((tm.tm_mday / 10) << 4);

	rtc[4] = ((tm.tm_mon + 1) % 10) | (((tm.tm_mon + 1) / 10) << 4);
	rtc[5] = (tm.tm_year % 10) | (((tm.tm_year / 10) % 10) << 4);
	rtc[6] = tm.tm_wday;
	rtc[7] = 0x40;

	// 64:0
	 
	//top->RTC_l = 0;
/*
	top->RTC_l = rtc[0] | rtc[1] << 8 | rtc[2] << 16 | rtc[3] << 24 ;
	printf("RTC: %x 0: %x",top->RTC_l,rtc[0]);
	top->RTC_h = rtc[4] | rtc[5] << 8 | rtc[6] << 16 | rtc[7] << 24 ;
	//t += t - mktime(gmtime(&t));
	top->RTC_toggle=~top->RTC_toggle;
*/
	// 32:0
	top->TIMESTAMP=t;//|0x01<<32;


}

static int last_cpu_addr=-1;
static int already_saw_this = 0;
int verilate() {

	if (!Verilated::gotFinish()) {
		if (soft_reset) {
			fprintf(stderr, "soft_reset.. in gotFinish\n");
			top->soft_reset = 1;
			soft_reset = 0;
			soft_reset_time = 0;
			fprintf(stderr, "turning on %x\n", top->soft_reset);
		}
		if (CLK_14M.IsRising()) {
			soft_reset_time++;
		}
		if (soft_reset_time == initialReset) {
			top->soft_reset = 0;
			fprintf(stderr, "turning off %x\n", top->soft_reset);
			fprintf(stderr, "soft_reset_time %ld initialReset %x\n", soft_reset_time, initialReset);
		}

		// Handle reset from menu or keyboard
		if (reset_pending) {
			fprintf(stderr, "Reset triggered: cold=%d main_time=%lu\n", reset_pending_cold, main_time);
			top->reset = 1;
			top->cold_reset = reset_pending_cold;
			reset_pending = 0;
			reset_time = 0;
			fprintf(stderr, "USER_RESET: Asserted reset=%d cold_reset=%d\n", top->reset, top->cold_reset);
		}
		if (top->reset && main_time >= initialReset) {
			// Count reset duration
			if (CLK_14M.IsRising()) {
				reset_time++;
				if (reset_time <= 5 || reset_time % 10000 == 0) {
					fprintf(stderr, "USER_RESET: Reset held: reset_time=%lu/%u (rising edge)\n", reset_time, initialReset);
				}
			}
			// Hold reset for same duration as initial reset
			if (reset_time >= initialReset) {
				fprintf(stderr, "USER_RESET: Releasing reset after %ld cycles, main_time=%lu\n", reset_time, main_time);
				top->reset = 0;
				top->cold_reset = 0;
				reset_time = 0;
			}
		}

		// Check keyboard-triggered resets (Ctrl+F11 or Ctrl+OpenApple+F11)
		if (top->keyboard_reset && !top->reset) {
			// Keyboard triggered a reset
			reset_pending = 1;
			reset_pending_cold = top->keyboard_cold_reset ? 1 : 0;
			fprintf(stderr, "Keyboard reset: Ctrl+F11 pressed (cold=%d)\n", reset_pending_cold);
		}

		// Assert reset during startup (always cold reset on power-on)
		if (main_time < initialReset) { top->reset = 1; top->cold_reset = 1; }
		// Deassert reset after startup
		if (main_time == initialReset) { top->reset = 0; top->cold_reset = 0; }
		
		// Handle self-test mode override timing
		if (selftest_mode) {
			if (!selftest_override_started && main_time >= 10) {
				// Start self-test override BEFORE reset is released (keys must be held during reset)
				selftest_override_active = true;
				selftest_override_started = true;
				selftest_start_time = main_time;
				printf("Self-test mode: Activating Command+Option+Control override during reset\n");
			}
			
			if (selftest_override_active && (main_time - selftest_start_time) >= SELFTEST_OVERRIDE_DURATION) {
				// Release override after long duration
				selftest_override_active = false;
				printf("Self-test mode: Releasing key override after %d time units\n", (int)SELFTEST_OVERRIDE_DURATION);
			}
		}
		
		// Set self-test override signal to hardware
		top->selftest_override = selftest_override_active ? 1 : 0;

		// Clock dividers
		CLK_14M.Tick();

		// Set system clock in core
		top->CLK_14M = CLK_14M.clk;
		top->adam = adam_mode;
		g_vbl_count=video.count_frame;

		// Simulate both edges of system clock
		if (CLK_14M.clk != CLK_14M.old) {
			if (CLK_14M.IsRising() && *bus.ioctl_download != 1) blockdevice.BeforeEval(main_time);
			if (CLK_14M.clk) {
				input.BeforeEval();
				bus.BeforeEval();
			}
			top->eval();

			if (tfp && video.count_frame >= dump_vcd_after_frame)
				tfp->dump(main_time);

			// Log 6502 instructions
			cpu_clock = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__CLK;
			bool cpu_reset = top->reset;
			// Only log on rising edge of CPU clock to avoid duplicates
			if (cpu_clock && !cpu_clock_last && cpu_reset == 0) {


				unsigned char en = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__EN;
				if (en) {

					unsigned char vpa = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPA;
					unsigned char vda = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VDA;
					unsigned char vpb = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPB;
                    unsigned char din = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D_IN;
					unsigned char dout = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D_OUT;
					// CPU WE signal is ACTIVE LOW: 0=write, 1=read
					// This is opposite of iigs.sv internal 'we' signal which is active HIGH
					unsigned char we_n = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__WE;
					unsigned char we = !we_n;  // Convert to active HIGH for consistency
					unsigned long addr = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
					unsigned char nextstate = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__NextState;
					
                    // Extract bank and address for memory tracking
                    unsigned char bank = (addr >> 16) & 0xFF;
                    unsigned short addr16 = addr & 0xFFFF;

                    // Read memory control state from hardware and feed into Clemens shadow mapper
                    unsigned char hw_RDROM   = VERTOPINTERN->emu__DOT__iigs__DOT__RDROM;
                    unsigned char hw_LCRAM2  = VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2;
                    unsigned char hw_LC_WE   = VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE;
                    // Use CPU VPB for mapping semantics
                    unsigned char hw_VPB     = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPB;
                    unsigned char hw_SHADOW  = VERTOPINTERN->emu__DOT__iigs__DOT__shadow;
                    unsigned char hw_ALTZP   = VERTOPINTERN->emu__DOT__iigs__DOT__ALTZP;
                    unsigned char hw_INTCXROM= VERTOPINTERN->emu__DOT__iigs__DOT__INTCXROM;
                    unsigned char hw_PAGE2   = VERTOPINTERN->emu__DOT__iigs__DOT__PAGE2;
                    unsigned char hw_RAMRD   = VERTOPINTERN->emu__DOT__iigs__DOT__RAMRD;
                    unsigned char hw_RAMWRT  = VERTOPINTERN->emu__DOT__iigs__DOT__RAMWRT;
                    unsigned char hw_SLTROMSEL=VERTOPINTERN->emu__DOT__iigs__DOT__SLTROMSEL;
                    unsigned char hw_STORE80 = VERTOPINTERN->emu__DOT__iigs__DOT__STORE80;
                    unsigned char hw_HIRES   = VERTOPINTERN->emu__DOT__iigs__DOT__HIRES_MODE;
                    // parallel_clemens_update_hw removed
					
					// Enhanced debug info for timing analysis
					static unsigned long last_addr = 0;
					static unsigned char last_bank = 0xFF;
					static unsigned char last_din = 0xFF;
					static bool debug_bf00_timing = false;
					static bool debug_mvn_area = false;
					
					// Get memory controller signals for debugging
					// The issue is likely that CPU A_OUT shows logical address (Bank 00)
					// but memory controller redirects to physical address (Bank 01)
					
                    // Track memory accesses 
                    if (vda && we) {
                        // Memory write - add MVN debug for Language Card area
                        if ((bank >= 0xFC || bank == 0x00) && addr16 >= 0xBF00) {
							debug_mvn_area = true;
							printf("TIMING DEBUG MVN WRITE: VDA=%d WE=%d LOGICAL_BANK=%02X ADDR=%04X DOUT=%02X\n", 
								   vda, we, bank, addr16, dout);
							printf("  CPU_A_OUT=%06lX PBR=%02X PC=%04X (CPU view)\n", 
								   addr, VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR, 
								   VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC);
							printf("  LC_WE=%d RDROM=%d LCRAM2=%d (should enable write-through)\n",
								   VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE,
								   VERTOPINTERN->emu__DOT__iigs__DOT__RDROM,
								   VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2);
						}
						
                        // Actual mapping sampling from hardware: use address bus and ROM selects
                        unsigned int phys_addr_bus = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                        unsigned int actual_phys_bank = (phys_addr_bus >> 16) & 0xFF;
                        int romc = VERTOPINTERN->emu__DOT__iigs__DOT__romc_ce;
                        int romd = VERTOPINTERN->emu__DOT__iigs__DOT__romd_ce;
                        int rom1 = VERTOPINTERN->emu__DOT__iigs__DOT__rom1_ce;
                        int rom2 = VERTOPINTERN->emu__DOT__iigs__DOT__rom2_ce;
                        int actual_is_rom = (int)(romc | romd | rom1 | rom2);
                        if (actual_is_rom) {
                            if (romc) actual_phys_bank = 0xFC;
                            else if (romd) actual_phys_bank = 0xFD;
                            else if (rom1) actual_phys_bank = 0xFE;
                            else if (rom2) actual_phys_bank = 0xFF;
                        }
                        if (we) actual_is_rom = 0; // writes never go to ROM
                        // Use actual slowMem signal from hardware instead of incorrect inference
                        int actual_is_slow = VERTOPINTERN->emu__DOT__iigs__DOT__clk_div_inst__DOT__slowMem ? 1 : 0;
                        int actual_is_fast = (!actual_is_rom && !actual_is_slow) ? 1 : 0;

                        // Shadow compare access mapping with Clemens-derived expectation
                        unsigned short pc_local = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        // parallel_clemens_compare_access removed

                        // parallel_clemens_compare_write removed
                        // parallel_clemens_value_compare_write removed
                        // parallel_clemens_track_hw_write removed
                        // Ring-log this write for later dump on failure
                        // parallel_clemens_recent_log_write removed

                        // CSV trace for write
                        unsigned short pc_local_write = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local_write = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        unsigned char  ir_local_write  = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR;
                        int is_io = ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) &&
                                     (addr16 >= 0xC000 && addr16 <= 0xC0FF)) ? 1 : 0;
                        if (is_io) {
                            // Approximate Clemens IO slow/fast classification:
                            // - Many early boot accesses in $C000-$C02F are slow
                            // - Known fast exceptions: $C036 (CYAREG/SPEED), $C035 (SHADOW reg read mirror), $C039 (SCCAREG), $C068 (STATEREG)
                            bool io_is_slow = (addr16 >= 0xC000 && addr16 <= 0xC02F) && (addr16 != 0xC036) && (addr16 != 0xC035) && (addr16 != 0xC039) && (addr16 != 0xC068);
                            if (io_is_slow) actual_is_slow = 1; else {/*leave as inferred*/}
                            // Normalize phys bank reporting for IO to match Clemens
                            // Clemens logs phys equal to the logical bank for IO ($00 or $E1)
                            actual_phys_bank = bank;
                            actual_is_rom = 0;
                        }
                        // For non-ROM, non-IO accesses, log phys as logical bank to match Clemens
                        if (!actual_is_rom && !is_io) {
                            actual_phys_bank = bank;
                        }
                        // Suppress spurious ROM reporting for non-ROM regions
                        if (actual_is_rom && !(actual_phys_bank >= 0xFC)) {
                            actual_is_rom = 0;
                        }
                        // For ROM reads Clemens logs a_bank=phys. For writes keep logical bank.
                        vsim_trace_log(/*phase*/ vpa ? 'I' : 'D', /*type*/ 'W',
                                       pc_local_write, pbr_local_write, ir_local_write,
                                       bank, addr16, dout,
                                       actual_phys_bank, actual_is_rom, actual_is_slow, is_io);
                        // Additional write-time diagnostics for STA abs,Y and BFxx
                        if (ir_local_write == 0x99 && sta99_base != 0xFFFF) {
                            unsigned short eff = (unsigned short)(sta99_base + VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                            printf("STA abs,Y WRITE: eff=%02X:%04X actual=%02X:%04X data=%02X\n",
                                   VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR,
                                   eff, bank, addr16, dout);
                        }
                        if (bank == 0x00 && addr16 >= 0xBF00 && addr16 <= 0xBFFF) {
                            printf("BFxx WRITE: %02X:%04X <= %02X (PC=%04X PBR=%02X)\n",
                                   bank, addr16, dout,
                                   VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC,
                                   VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR);
                        }
						
						if (debug_mvn_area) {
							debug_mvn_area = false;
							printf("TIMING DEBUG MVN WRITE COMPLETE: Data %02X written to Bank %02X Addr %04X\n", 
								   dout, bank, addr16);
						}
                    } else if (vda && !we) {
                        // Memory read - add timing debug for $BF00
                        if (bank == 0x00 && addr16 == 0xBF00) {
							debug_bf00_timing = true;
							printf("TIMING DEBUG $BF00: VDA=%d WE=%d LOGICAL_BANK=%02X ADDR=%04X DIN=%02X\n", 
								   vda, we, bank, addr16, din);
							printf("  CPU_A_OUT=%06lX PBR=%02X PC=%04X (CPU view)\n", 
								   addr, VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR, 
								   VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC);
							
							// Check Language Card state
							printf("  LC_WE=%d RDROM=%d LC_WE_PRE=%d LCRAM2=%d\n",
								   VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE,
								   VERTOPINTERN->emu__DOT__iigs__DOT__RDROM,
								   VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE_PRE,
								   VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2);
                        }

                        // CSV logging for VDA reads (including operand fetches that come through as data reads)
                        unsigned int phys_addr_bus = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                        unsigned int actual_phys_bank = (phys_addr_bus >> 16) & 0xFF;
                        int romc = VERTOPINTERN->emu__DOT__iigs__DOT__romc_ce;
                        int romd = VERTOPINTERN->emu__DOT__iigs__DOT__romd_ce;
                        int rom1 = VERTOPINTERN->emu__DOT__iigs__DOT__rom1_ce;
                        int rom2 = VERTOPINTERN->emu__DOT__iigs__DOT__rom2_ce;
                        int actual_is_rom = (int)(romc | romd | rom1 | rom2);
                        if (actual_is_rom) {
                            if (romc) actual_phys_bank = 0xFC;
                            else if (romd) actual_phys_bank = 0xFD;
                            else if (rom1) actual_phys_bank = 0xFE;
                            else if (rom2) actual_phys_bank = 0xFF;
                        }
                        int actual_is_slow = VERTOPINTERN->emu__DOT__iigs__DOT__clk_div_inst__DOT__slowMem ? 1 : 0;
                        int is_io = ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) &&
                                     (addr16 >= 0xC000 && addr16 <= 0xC0FF)) ? 1 : 0;
                        if (is_io) {
                            bool io_is_slow = (addr16 >= 0xC000 && addr16 <= 0xC02F) && (addr16 != 0xC036);
                            if (addr16 == 0xC035 || addr16 == 0xC039 || addr16 == 0xC068) io_is_slow = false;
                            if (io_is_slow) actual_is_slow = 1;
                            actual_phys_bank = bank;
                            actual_is_rom = 0;
                        }
                        if (!actual_is_rom && !is_io) {
                            actual_phys_bank = bank;
                        }
                        if (actual_is_rom && !(actual_phys_bank >= 0xFC)) {
                            actual_is_rom = 0;
                        }

                        unsigned short pc_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        unsigned char  ir_local_read  = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR;

                        vsim_trace_log(/*phase*/ 'D', /*type*/ 'R',
                                       pc_local_read, pbr_local_read, ir_local_read,
                                       bank, addr16, din,
                                       actual_phys_bank, actual_is_rom, actual_is_slow, is_io);
                    } else if (vpa && !we) {
                        // Instruction fetch only (VPA=1, VDA=0): log mapping and CSV
                        unsigned int phys_addr_bus = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                        unsigned int actual_phys_bank = (phys_addr_bus >> 16) & 0xFF;
                        int romc2 = VERTOPINTERN->emu__DOT__iigs__DOT__romc_ce;
                        int romd2 = VERTOPINTERN->emu__DOT__iigs__DOT__romd_ce;
                        int rom12 = VERTOPINTERN->emu__DOT__iigs__DOT__rom1_ce;
                        int rom22 = VERTOPINTERN->emu__DOT__iigs__DOT__rom2_ce;
                        int actual_is_rom = (int)(romc2 | romd2 | rom12 | rom22);
                        if (actual_is_rom) {
                            if (romc2) actual_phys_bank = 0xFC;
                            else if (romd2) actual_phys_bank = 0xFD;
                            else if (rom12) actual_phys_bank = 0xFE;
                            else if (rom22) actual_phys_bank = 0xFF;
                        }
                        int actual_is_slow = VERTOPINTERN->emu__DOT__iigs__DOT__clk_div_inst__DOT__slowMem ? 1 : 0;
                        int is_io2 = ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) &&
                                      (addr16 >= 0xC000 && addr16 <= 0xC0FF)) ? 1 : 0;
                        if (is_io2) {
                            bool io_is_slow2 = (addr16 >= 0xC000 && addr16 <= 0xC02F) && (addr16 != 0xC036);
                            if (addr16 == 0xC035 || addr16 == 0xC039 || addr16 == 0xC068) io_is_slow2 = false;
                            if (io_is_slow2) actual_is_slow = 1;
                            // Normalize IO phys bank and ROM flag
                            actual_phys_bank = bank;
                            actual_is_rom = 0;
                        }
                        // For non-ROM, non-IO accesses, log phys as logical bank to match Clemens
                        if (!actual_is_rom && !is_io2) {
                            actual_phys_bank = bank;
                        }
                        // Suppress spurious ROM reporting for non-ROM regions
                        if (actual_is_rom && !(actual_phys_bank >= 0xFC)) {
                            actual_is_rom = 0;
                        }
                        // Gate CSV at reset vector (only if CSV tracing is enabled)
                        if (g_csv_trace_enabled && !g_vsim_trace_active && (actual_is_rom) && (actual_phys_bank == 0xFF) && addr16 == 0xFFFC) {
                            g_vsim_trace_active = true;
                            vsim_trace_open_fresh();
                        }
                        unsigned short pc_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        unsigned char  ir_local_read  = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR;
                        {
                            unsigned csv_bank_ifetch = (vpb ? actual_phys_bank : bank);
                            vsim_trace_log(/*phase*/ 'I', /*type*/ 'R',
                                           pc_local_read, pbr_local_read, ir_local_read,
                                           csv_bank_ifetch, addr16, din,
                                           actual_phys_bank, actual_is_rom, actual_is_slow, is_io2);
                        }
                    }
						
                        // Actual mapping sampling from hardware: use address bus and ROM selects
                        unsigned int phys_addr_bus = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                        unsigned int actual_phys_bank = (phys_addr_bus >> 16) & 0xFF;
                        int romc2 = VERTOPINTERN->emu__DOT__iigs__DOT__romc_ce;
                        int romd2 = VERTOPINTERN->emu__DOT__iigs__DOT__romd_ce;
                        int rom12 = VERTOPINTERN->emu__DOT__iigs__DOT__rom1_ce;
                        int rom22 = VERTOPINTERN->emu__DOT__iigs__DOT__rom2_ce;
                        int actual_is_rom = (int)(romc2 | romd2 | rom12 | rom22);
                        if (actual_is_rom) {
                            if (romc2) actual_phys_bank = 0xFC;
                            else if (romd2) actual_phys_bank = 0xFD;
                            else if (rom12) actual_phys_bank = 0xFE;
                            else if (rom22) actual_phys_bank = 0xFF;
                        }
                        // Use actual slowMem signal from hardware
                        int actual_is_slow = VERTOPINTERN->emu__DOT__iigs__DOT__clk_div_inst__DOT__slowMem ? 1 : 0;
                        int actual_is_fast = (!actual_is_rom && !actual_is_slow) ? 1 : 0;

                        // Shadow compare access mapping with Clemens-derived expectation
                        unsigned short pc_local = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        // parallel_clemens_compare_access removed

                        // parallel_clemens_compare_read removed
                        // parallel_clemens_value_compare_read removed
                        // Log reads in text/page regions for correlation
                        // parallel_clemens_recent_log_read removed

                        // Gate CSV tracing to start at first vector fetch (ROM overlay at FF:FFFC)
                        // Only if CSV tracing is enabled via --enable-csv-trace
                        if (g_csv_trace_enabled && !g_vsim_trace_active && (actual_is_rom) && (actual_phys_bank == 0xFF) && addr16 == 0xFFFC) {
                            g_vsim_trace_active = true;
                            vsim_trace_open_fresh();
                        }
                        // Gate CSV tracing to start at first vector fetch FF:FFFC
                        if (g_csv_trace_enabled && !g_vsim_trace_active && bank == 0xFF && addr16 == 0xFFFC) {
                            g_vsim_trace_active = true;
                            vsim_trace_open_fresh();
                        }
                        // CSV trace for read
                        unsigned short pc_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                        unsigned char  pbr_local_read = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                        unsigned char  ir_local_read  = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR;
                        int is_io2 = ((bank == 0x00 || bank == 0x01 || bank == 0xE0 || bank == 0xE1) &&
                                      (addr16 >= 0xC000 && addr16 <= 0xC0FF)) ? 1 : 0;
                        if (is_io2) actual_is_slow = 1; // IO page is slow
                        {
                            unsigned csv_bank_read = (vpb ? actual_phys_bank : bank);
                            vsim_trace_log(/*phase*/ vpa ? 'I' : 'D', /*type*/ 'R',
                                           pc_local_read, pbr_local_read, ir_local_read,
                                           csv_bank_read, addr16, din,
                                           actual_phys_bank, actual_is_rom, actual_is_slow, is_io2);
                        }

                        // MVN tracing: generic detection independent of hardcoded PC values
                        {
                            unsigned char ir_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR;
                            unsigned char vpa_sig = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPA;
                            static unsigned char last_ir = 0xFF;
                            if (vpa_sig) {
                                // Instruction/operand fetch phase
                                // Capture STA abs,Y operands
                                if (sta99_expect_operands > 0) {
                                    if (sta99_expect_operands == 2) sta99_op_lo = din; else sta99_op_hi = din;
                                    sta99_expect_operands--;
                                    if (sta99_expect_operands == 0) {
                                        unsigned short base = (unsigned short)(sta99_op_lo | (sta99_op_hi << 8));
                                        printf("STA abs,Y operands: base=%04X Y=%04X\n",
                                               base, VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    }
                                } else if (ir_now == 0x99 && last_ir != 0x99) {
                                    sta99_expect_operands = 2; sta99_op_lo = sta99_op_hi = 0xFF;
                                    printf("STA abs,Y opcode: PC=%04X PBR=%02X\n",
                                           VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC,
                                           VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR);
                                }
                                if (mvn_expect_operands > 0) {
                                    if (mvn_expect_operands == 2) {
                                        last_mvn_dst_bank = din;
                                    printf("MVN DEST BANK operand=%02X (DBR before=%02X X=%04X Y=%04X)\n",
                                               last_mvn_dst_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    } else if (mvn_expect_operands == 1) {
                                        last_mvn_src_bank = din;
                                    printf("MVN SRC BANK operand=%02X (DBR before=%02X X=%04X Y=%04X)\n",
                                               last_mvn_src_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    }
                                    mvn_expect_operands--;
                                    if (mvn_expect_operands == 0) {
                                        // After both operands fetched, dump DBR state
                                        printf("MVN OPERANDS latched: dst=%02X src=%02X, DBR now=%02X X=%04X Y=%04X\n",
                                               last_mvn_dst_bank, last_mvn_src_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    }
                                } else if (ir_now == 0x54 && last_ir != 0x54) {
                                    // MVN opcode fetch observed, expect next two bytes as dst,src banks
                                    mvn_expect_operands = 2;
                                    last_mvn_dst_bank = 0xFF; last_mvn_src_bank = 0xFF;
                                    mvn_logged_data_reads = 0;
                                    mvn_pc_at_opcode = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                                    printf("MVN OPCODE: PC=%04X PBR=%02X A_OUT=%06lX IR=54\n",
                                           VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC,
                                           VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR,
                                           addr);
                                } else if (ir_now == 0x54 && mvn_pc_at_opcode != 0xFFFF) {
                                    // PC-based operand detection fallback: if we see VPA at PC+1 or PC+2, treat as operands
                                    unsigned short pc_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                                    if ((unsigned short)(mvn_pc_at_opcode + 1) == pc_now && last_mvn_dst_bank == 0xFF) {
                                        last_mvn_dst_bank = din;
                                        printf("MVN DEST BANK operand=%02X (PC-based) DBR=%02X X=%04X Y=%04X\n",
                                               last_mvn_dst_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    } else if ((unsigned short)(mvn_pc_at_opcode + 2) == pc_now && last_mvn_src_bank == 0xFF) {
                                        last_mvn_src_bank = din;
                                        printf("MVN SRC BANK operand=%02X (PC-based) DBR=%02X X=%04X Y=%04X\n",
                                               last_mvn_src_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                        printf("MVN OPERANDS latched: dst=%02X src=%02X, DBR now=%02X X=%04X Y=%04X (PC-based)\n",
                                               last_mvn_dst_bank, last_mvn_src_bank,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X,
                                               VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
                                    }
                                }
                                last_ir = ir_now;
                            } else {
                                // Data phase: log first few MVN source reads if operands known
                                if (last_mvn_src_bank != 0xFF && mvn_logged_data_reads < 8) {
                                    unsigned char dbr_local = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR;
                                    printf("MVN SRC READ: A_OUT=%06lX bank=%02X addr=%04X DIN=%02X DBR=%02X MVN.src=%02X dst=%02X\n",
                                           addr, bank, addr16, din, dbr_local, last_mvn_src_bank, last_mvn_dst_bank);
                                    mvn_logged_data_reads++;
                                }
                                // Log STA abs,Y writes: when IR was 0x99 and we see a W, print effective address/components
                                if (ir_now == 0x99 && (!we)) {
                                    // no-op here for reads
                                }
                            }
                        }
						
                        if (debug_bf00_timing && bank == 0x00 && addr16 == 0xBF00) {
                            debug_bf00_timing = false;
                            printf("TIMING DEBUG $BF00 COMPLETE: Data returned = %02X (should be ProDOS MLI, not BRK!)\n", din);
                            // Dump recent writes to correlate with possible bad LC stub or misrouted early text writes
                            // parallel_clemens_dump_recent_writes removed
                        }

                        // Loader entry detection: first ifetch at 00:0801
                        if (!loader_entry_trap_fired) {
                            unsigned short pc_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                            unsigned char pbr_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                            if (pbr_now == 0x00 && pc_now == 0x0801 && vpa) {
                                loader_entry_trap_fired = true;
                                loader_ifetch_trace_budget = 64; // trace next 64 ifetches in 00:08xx
                                unsigned short sp = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP;
                                unsigned short d = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D;
                                unsigned char p = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__P;
                                unsigned short a = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__A;
                                unsigned short x = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X;
                                unsigned short y = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y;
                                unsigned char dbr = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR;
                                unsigned char RDROM = VERTOPINTERN->emu__DOT__iigs__DOT__RDROM;
                                unsigned char LCRAM2 = VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2;
                                unsigned char LC_WE = VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE;
                                unsigned char INTCXROM = VERTOPINTERN->emu__DOT__iigs__DOT__INTCXROM;
                                unsigned char ALTZP = VERTOPINTERN->emu__DOT__iigs__DOT__ALTZP;
                                unsigned char RAMRD = VERTOPINTERN->emu__DOT__iigs__DOT__RAMRD;
                                unsigned char RAMWRT = VERTOPINTERN->emu__DOT__iigs__DOT__RAMWRT;
                                unsigned char STORE80 = VERTOPINTERN->emu__DOT__iigs__DOT__STORE80;
                                unsigned char PAGE2 = VERTOPINTERN->emu__DOT__iigs__DOT__PAGE2;
                                printf("LOADER ENTRY TRAP: PC=%02X:%04X A=%04X X=%04X Y=%04X P=%02X SP=%04X D=%04X DBR=%02X\n",
                                       pbr_now, pc_now, a, x, y, p, sp, d, dbr);
                                printf("  MAP: RDROM=%d LCRAM2=%d LC_WE=%d INTCXROM=%d ALTZP=%d RAMRD=%d RAMWRT=%d STORE80=%d PAGE2=%d\n",
                                       RDROM, LCRAM2, LC_WE, INTCXROM, ALTZP, RAMRD, RAMWRT, STORE80, PAGE2);
                            }
                        }

                        // Monitor entry detection: trap when PC enters FF:9Axx–FF:9Bxx region
                        if (!monitor_trap_fired) {
                            unsigned short pc_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                            unsigned char pbr_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                            if (pbr_now == 0xFF && pc_now >= 0x9A00 && pc_now <= 0x9BFF) {
                                monitor_trap_fired = true;
                                unsigned short sp = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP;
                                unsigned short d = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D;
                                unsigned char p = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__P;
                                unsigned short a = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__A;
                                unsigned short x = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X;
                                unsigned short y = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y;
                                unsigned char dbr = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR;
                                // Mapping flags
                                unsigned char RDROM = VERTOPINTERN->emu__DOT__iigs__DOT__RDROM;
                                unsigned char LCRAM2 = VERTOPINTERN->emu__DOT__iigs__DOT__LCRAM2;
                                unsigned char LC_WE = VERTOPINTERN->emu__DOT__iigs__DOT__LC_WE;
                                unsigned char INTCXROM = VERTOPINTERN->emu__DOT__iigs__DOT__INTCXROM;
                                unsigned char ALTZP = VERTOPINTERN->emu__DOT__iigs__DOT__ALTZP;
                                unsigned char RAMRD = VERTOPINTERN->emu__DOT__iigs__DOT__RAMRD;
                                unsigned char RAMWRT = VERTOPINTERN->emu__DOT__iigs__DOT__RAMWRT;
                                unsigned char STORE80 = VERTOPINTERN->emu__DOT__iigs__DOT__STORE80;
                                unsigned char PAGE2 = VERTOPINTERN->emu__DOT__iigs__DOT__PAGE2;
                                printf("MONITOR ENTRY TRAP: PC=%02X:%04X A=%04X X=%04X Y=%04X P=%02X SP=%04X D=%04X DBR=%02X\n",
                                       pbr_now, pc_now, a, x, y, p, sp, d, dbr);
                                printf("  MAP: RDROM=%d LCRAM2=%d LC_WE=%d INTCXROM=%d ALTZP=%d RAMRD=%d RAMWRT=%d STORE80=%d PAGE2=%d\n",
                                       RDROM, LCRAM2, LC_WE, INTCXROM, ALTZP, RAMRD, RAMWRT, STORE80, PAGE2);
                                // Dump a few bytes at the top of stack (bank always 00 in native mode)
                                for (int i = 0; i < 8; i++) {
                                    unsigned short saddr = (sp + i) & 0xFFFF;
                                    printf("  STK[%02d] @00:%04X\n", i, saddr);
                                }
                                // Dump recent ifetch history
                                printf("RECENT IFETCHES (most recent last):\n");
                                int idx = ifetch_wptr;
                                for (int i = 0; i < 32; i++) {
                                    idx = (idx - 1) & (IFETCH_RING_CAP - 1);
                                    printf("  %02X:%04X IR=%02X\n", ifetch_ring[idx].pbr, ifetch_ring[idx].pc, ifetch_ring[idx].ir);
                                }
                                // Dump recent HDD C0F0-C0FF activity
                                printf("RECENT HDD IO (C0F0-C0FF, most recent last):\n");
                                int hidx = hdd_wptr;
                                for (int i = 0; i < 32; i++) {
                                    hidx = (hidx - 1) & (HDD_RING_CAP - 1);
                                    printf("  %02X:%04X %c 00:%04X = %02X\n", hdd_ring[hidx].pbr, hdd_ring[hidx].pc,
                                           hdd_ring[hidx].rw, hdd_ring[hidx].addr16, hdd_ring[hidx].data);
                                }
                            }
                        }

                        // While in loader area (00:0800-08FF), trace upcoming ifetches to see opcodes executed
                        if (loader_ifetch_trace_budget > 0 && vpa) {
                            unsigned long addr = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                            unsigned char bank = (addr >> 16) & 0xFF;
                            unsigned short addr16 = addr & 0xFFFF;
                            if (bank == 0x00 && (addr16 >= 0x0800 && addr16 <= 0x08FF)) {
                                printf("LOADER IFETCH: PC=%02X:%04X IR=%02X\n", bank, addr16,
                                       (unsigned int)din & 0xFF);
                                loader_ifetch_trace_budget--;
                            } else {
                                // Stop tracing if we leave the loader page
                                loader_ifetch_trace_budget = 0;
                            }
                        }
					
					
					// Track address/bank changes for timing analysis
					if (addr != last_addr || bank != last_bank || din != last_din) {
						if ((addr & 0xFFFF) >= 0xBF00 && (addr & 0xFFFF) <= 0xBFFF) {
							printf("ADDR CHANGE: %06lX->%06lX BANK: %02X->%02X DIN: %02X->%02X\n",
								   last_addr, addr, last_bank, bank, last_din, din);
						}
						last_addr = addr;
						last_bank = bank;
						last_din = din;
					}
					
					// Track CPU state
					unsigned short pc = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
					unsigned char pbr = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
					unsigned short sp = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP;
					unsigned char p = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__P;
					// parallel_clemens_sync_cpu_state removed

					//console.AddLog(fmt::format(">> PC={0:06x} IN={1:02x} MA={2:06x} VPA={3:x} VPB={4:x} VDA={5:x} NEXT={6:x}", ins_pc[ins_index], din, addr, vpa, vpb, vda, nextstate).c_str());

				        break_pending |= run_state == RunState::NextIRQ && vpb && !old_vpb;
					old_vpb = vpb;

					if (vpa && nextstate == 1) {
						const long break_addr = strtol(pc_breakpoint, NULL, 16);
						break_pending |= pc_break_enabled && break_addr == ins_pc[0];
						break_pending |= run_state == RunState::StepIn;
						//console.AddLog(fmt::format("LOG? ins_index ={0:x} ins_pc[0]={1:06x} ", ins_index, ins_pc[0]).c_str());
													// JSR/JSL
						if (ins_index > 0 && ins_pc[0] > 0) {
							DumpInstruction();
						}
						// Clear instruction cache
						ins_index = 0;
						for (int i = 0; i < ins_size; i++) {
							ins_in[i] = 0;
							ins_ma[i] = 0;
							ins_formatted[i] = false;
						}

						std::string log = fmt::format("{0:06d} > ", cpu_instruction_count);
						log.append(fmt::format("A={0:04x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__A));
						log.append(fmt::format("X={0:04x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X));
						log.append(fmt::format("Y={0:04x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y));

						log.append(fmt::format("M={0:x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__MF));
						log.append(fmt::format("E={0:x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__EF));
						log.append(fmt::format("D={0:04x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D));
						//ImGui::Text("D       0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D);
						//ImGui::Text("SP      0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP);
						//ImGui::Text("DBR     0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR);
						//ImGui::Text("PBR     0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR);
						//ImGui::Text("PC      0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC);
						if (0x011B==VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC)
						   log.append(fmt::format("D={0:04x} ", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP));
							
						// Only add to console log when debug_6502 is enabled (saves memory)
						if (debug_6502) {
							console.AddLog(log.c_str());
						}
					}

                        if ((vpa || vda) && !(vpa == 0 && vda == 1)) {
                            ins_pc[ins_index] = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                            if (ins_pc[ins_index] > 0) {
                                ins_in[ins_index] = din;
                                ins_ma[ins_index] = addr;
                                ins_dbr[ins_index] = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR;
                                //console.AddLog(fmt::format("! PC={0:06x} IN={1:02x} MA={2:06x} VPA={3:x} VPB={4:x} VDA={5:x} I={6:x}", ins_pc[ins_index], ins_in[ins_index], ins_ma[ins_index], vpa, vpb, vda, ins_index).c_str());

                                ins_index++;
                                if (ins_index > ins_size - 1) { ins_index = 0; }

                            }
                        }

                        // Record ifetch ring on start-of-instruction fetch
                        if (vpa && nextstate == 1) {
                            unsigned short pc_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                            unsigned char pbr_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                            ifetch_ring_record(pbr_now, pc_now, (unsigned char)din);
                        }

                        // HDD event ring for C0F0-C0FF accesses (bank 00 only)
                        if (vda) {
                            unsigned long addr = VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;
                            unsigned char bank = (addr >> 16) & 0xFF;
                            unsigned short addr16 = addr & 0xFFFF;
                            if (bank == 0x00 && (addr16 >= 0xC0F0 && addr16 <= 0xC0FF)) {
                                unsigned short pc_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC;
                                unsigned char pbr_now = VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR;
                                // Prefer top-level bus write-enable computed in iigs.sv (we = ~cpu_we_n)
                                bool is_write = VERTOPINTERN->emu__DOT__iigs__DOT__we;
                                unsigned char data = is_write ? (unsigned char)VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D_OUT : (unsigned char)din;
                                hdd_ring_record(pbr_now, pc_now, bank, addr16, is_write, data);
                            }
                        }
				}

			}

			// Update cpu_clock_last to properly track clock edge transitions
			cpu_clock_last = cpu_clock;

			if (CLK_14M.clk) { bus.AfterEval(); blockdevice.AfterEval(); }
		}

#ifndef DISABLE_AUDIO
        if (!headless) {
            if (CLK_14M.IsRising())
            {
                audio.Clock(top->AUDIO_L, top->AUDIO_R);
            }
        }
#endif

		// Output pixels on rising edge of pixel clock
        if (!headless) {
            if (CLK_14M.IsRising() && top->CE_PIXEL) {
                uint32_t colour = 0xFF000000 | top->VGA_B << 16 | top->VGA_G << 8 | top->VGA_R;
                video.Clock(top->VGA_HB, top->VGA_VB, top->VGA_HS, top->VGA_VS, colour);
            }
        }

		if (CLK_14M.IsRising()) {



            // IWM emulation now handled in Verilog (rtl/iwm.v using iwmref core).
            // Preserve a mirror of DISK35 for any UI or status use.
	    /*
            if (VERTOPINTERN->emu__DOT__iigs__DOT__iwm__DOT__strobe) {
                g_c031_disk35 = VERTOPINTERN->emu__DOT__iigs__DOT__iwm__DOT__DISK35;
            }
	    */
last_cpu_addr=VERTOPINTERN->emu__DOT__iigs__DOT__addr_bus;




			main_time++;
		}
		return 1;
	}

	// Stop verilating and cleanup
	top->final();

	if (tfp) {
		tfp->close();
		delete tfp;
	}

	delete top;
	exit(0);
	return 0;
}

void RunBatch(int steps)
{
	for (int step = 0; step < steps; step++) {
		verilate();
		if (break_pending) {
			run_state = RunState::Stopped;
			break_pending = false;
			break;
		}
	}
}

unsigned char mouse_clock = 0;
unsigned char mouse_clock_reduce = 0;
unsigned char mouse_buttons = 0;
signed char mouse_x = 0;
signed char mouse_y = 0;

// Real mouse tracking for Apple IIgs
int prev_mouse_x = 0;
int prev_mouse_y = 0;
int prev_mouse_buttons = 0;  // Track previous button state to detect changes
bool mouse_captured = false;  // True when mouse is captured for IIgs control

char spinner_toggle = 0;

// Screenshot functionality
// ------------------------
std::vector<int> screenshot_frames;
bool screenshot_mode = false;

// Stop at frame functionality
// ---------------------------
int stop_at_frame = -1;
bool stop_at_frame_enabled = false;

// Reset at frame functionality (for testing reset)
// ------------------------------------------------
int reset_at_frame = -1;
bool reset_at_frame_enabled = false;
bool reset_at_frame_cold = false;  // true = cold reset, false = warm reset

// Memory dump functionality
// -------------------------
std::vector<int> memory_dump_frames;
bool memory_dump_mode = false;

// Disk image support (supports 2 HDD units - ProDOS limit)
// ---------------------------
std::string disk_image = "";   // HDD unit 0 (--disk)
std::string disk_image2 = "";  // HDD unit 1 (--disk2)
std::string floppy_image = "";  // Floppy disk image (NIB format, 5.25" 140K)

// Key injection functionality
// ---------------------------
struct KeyInjection {
    int frame;
    std::string keys;
};
std::vector<KeyInjection> key_injections;

// Mouse injection functionality
// ---------------------------
struct MouseInjection {
    int frame;
    int dx;        // X delta (-127 to 127)
    int dy;        // Y delta (-127 to 127)
    int buttons;   // Button state: bit 0 = left button
    int duration;  // Number of frames to apply this movement
};
std::vector<MouseInjection> mouse_injections;
int mouse_injection_frames_remaining = 0;  // Countdown for current injection

// Joystick/Paddle injection functionality
// ---------------------------------------
struct JoystickInjection {
    int frame;
    int paddle0;   // Paddle 0 value (0-255), -1 means don't change
    int paddle1;   // Paddle 1 value (0-255), -1 means don't change
    int paddle2;   // Paddle 2 value (0-255), -1 means don't change
    int paddle3;   // Paddle 3 value (0-255), -1 means don't change
    int buttons;   // Button state: bit 0 = button 0, bit 1 = button 1, -1 means don't change
    int duration;  // Number of frames to apply these values
};
std::vector<JoystickInjection> joystick_injections;
int joystick_injection_frames_remaining = 0;

// ASCII to PS/2 scancode mapping (for SDL/non-Windows platforms)
// Returns: scancode in bits 7:0, EXT flag in bit 19, SHIFT required in bit 9
struct AsciiToPS2 {
    unsigned int scancode;
    bool needs_shift;
};

// Map printable ASCII characters to PS/2 scancodes
// Based on US keyboard layout
static AsciiToPS2 ascii_to_ps2(char c) {
    AsciiToPS2 result = {0xFF, false};  // Default: unmapped

    // Lowercase letters (a-z) -> no shift needed
    if (c >= 'a' && c <= 'z') {
        static const unsigned int letter_scancodes[] = {
            0x1c, 0x32, 0x21, 0x23, 0x24, 0x2b, 0x34, 0x33,  // a-h
            0x43, 0x3b, 0x42, 0x4b, 0x3a, 0x31, 0x44, 0x4d,  // i-p
            0x15, 0x2d, 0x1b, 0x2c, 0x3c, 0x2a, 0x1d, 0x22,  // q-x
            0x35, 0x1a                                        // y-z
        };
        result.scancode = letter_scancodes[c - 'a'];
        result.needs_shift = false;
        return result;
    }

    // Uppercase letters (A-Z) -> shift + letter
    if (c >= 'A' && c <= 'Z') {
        static const unsigned int letter_scancodes[] = {
            0x1c, 0x32, 0x21, 0x23, 0x24, 0x2b, 0x34, 0x33,  // A-H
            0x43, 0x3b, 0x42, 0x4b, 0x3a, 0x31, 0x44, 0x4d,  // I-P
            0x15, 0x2d, 0x1b, 0x2c, 0x3c, 0x2a, 0x1d, 0x22,  // Q-X
            0x35, 0x1a                                        // Y-Z
        };
        result.scancode = letter_scancodes[c - 'A'];
        result.needs_shift = true;
        return result;
    }

    // Numbers 0-9
    if (c >= '0' && c <= '9') {
        static const unsigned int num_scancodes[] = {
            0x45, 0x16, 0x1e, 0x26, 0x25, 0x2e, 0x36, 0x3d, 0x3e, 0x46  // 0-9
        };
        result.scancode = num_scancodes[c - '0'];
        result.needs_shift = false;
        return result;
    }

    // Special characters
    switch (c) {
        case ' ':  result.scancode = 0x29; result.needs_shift = false; break;  // Space
        case '\n': result.scancode = 0x5a; result.needs_shift = false; break;  // Enter
        case '\r': result.scancode = 0x5a; result.needs_shift = false; break;  // Enter
        case '\t': result.scancode = 0x0d; result.needs_shift = false; break;  // Tab
        case '\b': result.scancode = 0x66; result.needs_shift = false; break;  // Backspace
        case 0x1b: result.scancode = 0x76; result.needs_shift = false; break;  // Escape

        // Punctuation without shift
        case '-':  result.scancode = 0x4e; result.needs_shift = false; break;
        case '=':  result.scancode = 0x55; result.needs_shift = false; break;
        case '[':  result.scancode = 0x54; result.needs_shift = false; break;
        case ']':  result.scancode = 0x5b; result.needs_shift = false; break;
        case '\\': result.scancode = 0x5d; result.needs_shift = false; break;
        case ';':  result.scancode = 0x4c; result.needs_shift = false; break;
        case '\'': result.scancode = 0x52; result.needs_shift = false; break;
        case '`':  result.scancode = 0x0e; result.needs_shift = false; break;
        case ',':  result.scancode = 0x41; result.needs_shift = false; break;
        case '.':  result.scancode = 0x49; result.needs_shift = false; break;
        case '/':  result.scancode = 0x4a; result.needs_shift = false; break;

        // Punctuation with shift
        case '!':  result.scancode = 0x16; result.needs_shift = true; break;  // Shift+1
        case '@':  result.scancode = 0x1e; result.needs_shift = true; break;  // Shift+2
        case '#':  result.scancode = 0x26; result.needs_shift = true; break;  // Shift+3
        case '$':  result.scancode = 0x25; result.needs_shift = true; break;  // Shift+4
        case '%':  result.scancode = 0x2e; result.needs_shift = true; break;  // Shift+5
        case '^':  result.scancode = 0x36; result.needs_shift = true; break;  // Shift+6
        case '&':  result.scancode = 0x3d; result.needs_shift = true; break;  // Shift+7
        case '*':  result.scancode = 0x3e; result.needs_shift = true; break;  // Shift+8
        case '(':  result.scancode = 0x46; result.needs_shift = true; break;  // Shift+9
        case ')':  result.scancode = 0x45; result.needs_shift = true; break;  // Shift+0
        case '_':  result.scancode = 0x4e; result.needs_shift = true; break;  // Shift+-
        case '+':  result.scancode = 0x55; result.needs_shift = true; break;  // Shift+=
        case '{':  result.scancode = 0x54; result.needs_shift = true; break;  // Shift+[
        case '}':  result.scancode = 0x5b; result.needs_shift = true; break;  // Shift+]
        case '|':  result.scancode = 0x5d; result.needs_shift = true; break;  // Shift+backslash
        case ':':  result.scancode = 0x4c; result.needs_shift = true; break;  // Shift+;
        case '"':  result.scancode = 0x52; result.needs_shift = true; break;  // Shift+'
        case '~':  result.scancode = 0x0e; result.needs_shift = true; break;  // Shift+`
        case '<':  result.scancode = 0x41; result.needs_shift = true; break;  // Shift+,
        case '>':  result.scancode = 0x49; result.needs_shift = true; break;  // Shift+.
        case '?':  result.scancode = 0x4a; result.needs_shift = true; break;  // Shift+/
    }

    return result;
}

// Queue key events for a string of characters
void queue_key_string(const std::string& keys) {
    const unsigned int SHIFT_SCANCODE = 0x12;  // Left shift PS/2 scancode

    for (char c : keys) {
        AsciiToPS2 mapping = ascii_to_ps2(c);
        if (mapping.scancode == 0xFF) {
            fprintf(stderr, "Warning: unmapped character '%c' (0x%02x) in key injection\n", c, (unsigned char)c);
            continue;
        }

        // If shift is needed, press shift first
        if (mapping.needs_shift) {
            SimInput_PS2KeyEvent shift_down(SHIFT_SCANCODE, true, false, SHIFT_SCANCODE);
            input.keyEvents.push(shift_down);
        }

        // Press key
        SimInput_PS2KeyEvent key_down(mapping.scancode, true, false, mapping.scancode);
        input.keyEvents.push(key_down);

        // Release key
        SimInput_PS2KeyEvent key_up(mapping.scancode, false, false, mapping.scancode);
        input.keyEvents.push(key_up);

        // If shift was pressed, release it
        if (mapping.needs_shift) {
            SimInput_PS2KeyEvent shift_up(SHIFT_SCANCODE, false, false, SHIFT_SCANCODE);
            input.keyEvents.push(shift_up);
        }
    }

    printf("Queued %zu key events for string: %s\n", keys.length() * 2, keys.c_str());
}

// Process key injections for the current frame
void process_key_injections(int current_frame) {
    auto it = key_injections.begin();
    while (it != key_injections.end()) {
        if (it->frame == current_frame) {
            printf("Injecting keys at frame %d: %s\n", current_frame, it->keys.c_str());
            queue_key_string(it->keys);
            it = key_injections.erase(it);
        } else {
            ++it;
        }
    }
}

// Active mouse injection state
static signed char injected_mouse_x = 0;
static signed char injected_mouse_y = 0;
static int injected_mouse_buttons = 0;
static bool mouse_injection_active = false;

// Process mouse injections for the current frame
// Returns true if a NEW injection started this frame (for toggle signaling)
bool process_mouse_injections(int current_frame) {
    static int last_processed_frame = -1;
    bool new_injection_started = false;

    // Check if there's a new injection starting this frame
    auto it = mouse_injections.begin();
    while (it != mouse_injections.end()) {
        if (it->frame == current_frame) {
            injected_mouse_x = (signed char)it->dx;
            injected_mouse_y = (signed char)it->dy;
            injected_mouse_buttons = it->buttons;
            mouse_injection_frames_remaining = it->duration;
            mouse_injection_active = true;
            new_injection_started = true;
            it = mouse_injections.erase(it);
        } else {
            ++it;
        }
    }

    // Decrement duration counter only once per frame (not when a new injection just started)
    if (mouse_injection_active && !new_injection_started && current_frame != last_processed_frame) {
        mouse_injection_frames_remaining--;
        if (mouse_injection_frames_remaining <= 0) {
            // Injection complete - clear state
            injected_mouse_x = 0;
            injected_mouse_y = 0;
            injected_mouse_buttons = 0;
            mouse_injection_active = false;
        }
    }

    last_processed_frame = current_frame;
    return new_injection_started;
}

// Active joystick injection state
static int injected_paddle0 = 128;  // Center position
static int injected_paddle1 = 128;
static int injected_paddle2 = 128;
static int injected_paddle3 = 128;
static int injected_joy_buttons = 0;
static bool joystick_injection_active = false;

// Convert unsigned paddle value (0-255) to signed analog value for joystick_l_analog
// The FPGA converts back with: paddle = {~sign_bit, lower_7_bits}
// So paddle 0 = signed -128, paddle 128 = signed 0, paddle 255 = signed +127
static inline int8_t paddle_to_analog(int paddle_value) {
    return (int8_t)(paddle_value - 128);
}

// Pack two paddle values into a 16-bit analog value (X in [7:0], Y in [15:8])
static inline uint16_t pack_analog(int paddle_x, int paddle_y) {
    return ((uint8_t)paddle_to_analog(paddle_y) << 8) | (uint8_t)paddle_to_analog(paddle_x);
}

// Process joystick injections for the current frame
// Returns true if joystick is being injected (overrides normal joystick input)
bool process_joystick_injections(int current_frame) {
    // Check if there's a new injection starting this frame
    auto it = joystick_injections.begin();
    while (it != joystick_injections.end()) {
        if (it->frame == current_frame) {
            printf("Injecting joystick at frame %d: p0=%d p1=%d p2=%d p3=%d btn=%d dur=%d\n",
                   current_frame, it->paddle0, it->paddle1, it->paddle2, it->paddle3,
                   it->buttons, it->duration);
            if (it->paddle0 >= 0) injected_paddle0 = it->paddle0;
            if (it->paddle1 >= 0) injected_paddle1 = it->paddle1;
            if (it->paddle2 >= 0) injected_paddle2 = it->paddle2;
            if (it->paddle3 >= 0) injected_paddle3 = it->paddle3;
            if (it->buttons >= 0) injected_joy_buttons = it->buttons;
            joystick_injection_frames_remaining = it->duration;
            joystick_injection_active = true;
            it = joystick_injections.erase(it);
        } else {
            ++it;
        }
    }

    // Process active injection
    if (joystick_injection_active && joystick_injection_frames_remaining > 0) {
        joystick_injection_frames_remaining--;
        if (joystick_injection_frames_remaining == 0) {
            // Injection complete - reset to center
            injected_paddle0 = 128;
            injected_paddle1 = 128;
            injected_paddle2 = 128;
            injected_paddle3 = 128;
            injected_joy_buttons = 0;
            joystick_injection_active = false;
        }
        return true;  // Joystick is being injected
    }
    return false;
}

void show_help() {
	printf("Apple IIgs Hardware Simulator\n");
	printf("Usage: ./Vemu [options]\n\n");
	printf("Options:\n");
	printf("  -h, --help                    Show this help message\n");
	printf("  --headless, --no-gui          Run without SDL/ImGui (CI/headless)\n");
	printf("  --screenshot <frames>         Take screenshots at specified frame numbers\n");
	printf("                                (comma-separated list, e.g., 100,200,300)\n");
	printf("  -screenshot <frames>          Legacy form of --screenshot (deprecated)\n");
	printf("  --memory-dump <frames>        Dump memory at specified frame numbers\n");
	printf("                                (comma-separated list, e.g., 100,200,300)\n");
	printf("  --stop-at-frame <frame>       Exit simulation after specified frame\n");
	printf("  --reset-at-frame <frame>      Trigger warm reset at specified frame\n");
	printf("  --cold-reset-at-frame <frame> Trigger cold reset at specified frame\n");
	printf("  --selftest                    Enable self-test mode\n");
	printf("  --no-cpu-log                  Disable CPU log storage in memory (saves memory)\n");
	printf("  --quiet                       Suppress CPU instruction trace to stdout (faster)\n");
	printf("  --disk <filename>             Use specified HDD image (slot 7 unit 0, no disk mounted by default)\n");
	printf("  --disk2 <filename>            Use specified HDD image for slot 7 unit 1\n");
	printf("  --floppy <filename>           Use specified floppy image (5.25\" NIB format, drive 1)\n");
	printf("  --enable-csv-trace            Enable CSV memory trace logging (vsim_trace.csv)\n");
	printf("  --dump-csv-after <frame>      Start dumping vsim_trace.csv after a frame number\n");
	printf("  --dump-vcd-after <frame>      Start dumping vsim.vcd after a frame number\n");
	printf("  --send-keys <frame>:<keys>    Send keyboard input at specified frame\n");
	printf("                                Can be specified multiple times\n");
	printf("                                Use \\n for Enter, \\t for Tab, \\e for ESC,\n");
	printf("                                \\xNN for hex codes, \\\\ for backslash\n");
	printf("  --send-mouse <frame>:<dx>,<dy>[,<btn>[,<dur>]]\n");
	printf("                                Send mouse input at specified frame\n");
	printf("                                dx,dy: movement deltas (-127 to 127)\n");
	printf("                                btn: button state (0=none, 1=left click)\n");
	printf("                                dur: duration in frames (default 1)\n");
	printf("                                Can be specified multiple times\n");
	printf("  --send-joystick <frame>:<p0>,<p1>[,<p2>,<p3>][,<btn>[,<dur>]]\n");
	printf("                                Send joystick/paddle input at specified frame\n");
	printf("                                p0-p3: paddle values (0-255, 128=center, -1=unchanged)\n");
	printf("                                btn: button state (bit 0=btn0, bit 1=btn1, -1=unchanged)\n");
	printf("                                dur: duration in frames (default 1)\n");
	printf("                                Can be specified multiple times\n\n");
	printf("Examples:\n");
	printf("  ./Vemu                        Run simulator in windowed mode\n");
	printf("  ./Vemu --screenshot 245       Take screenshot at frame 245\n");
	printf("  ./Vemu --stop-at-frame 300    Stop simulation after frame 300\n");
	printf("  ./Vemu --disk totalreplay.hdv Use totalreplay.hdv as disk image\n");
	printf("  ./Vemu --disk pd.hdv --screenshot 50 --stop-at-frame 100\n");
	printf("                                Use pd.hdv, take screenshot at frame 50, stop at 100\n");
	printf("  ./Vemu --memory-dump 200      Dump memory at frame 200\n");
	printf("  ./Vemu --selftest --no-cpu-log    Run selftest without CPU logging\n");
	printf("  ./Vemu --disk totalreplay.hdv --send-keys 200:lode\\n\n");
	printf("                                Boot Total Replay and type 'lode' + Enter at frame 200\n");
	printf("  ./Vemu --disk app.hdv --send-mouse 100:10,0 --send-mouse 110:0,0,1\n");
	printf("                                Move mouse right 10 at frame 100, click at frame 110\n");
	printf("  ./Vemu --disk game.hdv --send-joystick 100:0,128\n");
	printf("                                Move joystick full left at frame 100\n");
}

void save_screenshot(int frame_number) {
	if (!output_ptr) {
		printf("Error: output_ptr is null, cannot save screenshot\n");
		return;
	}
	
	char filename[256];
	snprintf(filename, sizeof(filename), "screenshot_frame_%04d.png", frame_number);
	
	// Read directly from the IIgs video output buffer that video.Clock() writes to
	// The colour format is: 0xFF000000 | B << 16 | G << 8 | R (ABGR)
	// IIgs screen is 700x240, use the actual video dimensions not the texture buffer size
	
	int iigs_width = video.output_width;   // 700 (actual IIgs width)
	int iigs_height = video.output_height; // 240 (actual IIgs height)
	
	
	
	uint8_t* rgb_data = (uint8_t*)malloc(iigs_width * iigs_height * 3);
	if (!rgb_data) {
		printf("Error: Could not allocate memory for screenshot\n");
		return;
	}
	
	for (int y = 0; y < iigs_height; y++) {
		for (int x = 0; x < iigs_width; x++) {
			uint32_t pixel = output_ptr[y * iigs_width + x];    // Use iigs_width as stride too!
			int dst_index = (y * iigs_width + x) * 3;           // And iigs_width for destination
			
			// Format: 0xFF000000 | B << 16 | G << 8 | R (ABGR)
			uint8_t a = (pixel >> 24) & 0xFF;  // Alpha in bits 31-24
			uint8_t b = (pixel >> 16) & 0xFF;  // Blue in bits 23-16  
			uint8_t g = (pixel >> 8) & 0xFF;   // Green in bits 15-8  
			uint8_t r = (pixel >> 0) & 0xFF;   // Red in bits 7-0
			
			rgb_data[dst_index + 0] = r;
			rgb_data[dst_index + 1] = g;
			rgb_data[dst_index + 2] = b;
		}
	}
	
	// Save as PNG using stb_image_write
	int result = stbi_write_png(filename, iigs_width, iigs_height, 3, rgb_data, iigs_width * 3);
	
	free(rgb_data);
	
	if (result) {
		printf("Screenshot saved: %s\n", filename);
	} else {
		printf("Error: Failed to save screenshot %s\n", filename);
	}
}

void save_memory_dump(int frame_number) {
	printf("Saving memory dump at frame %d...\n", frame_number);
	
	char filename[256];
	
	// Dump Fast RAM (8MB) - Banks 00-3F
	snprintf(filename, sizeof(filename), "memdump_frame_%04d_fastram.bin", frame_number);
	FILE* f = fopen(filename, "wb");
	if (f) {
		fwrite(&VERTOPINTERN->emu__DOT__fastram__DOT__ram, 1, 8388608, f);
		fclose(f);
		printf("Fast RAM dump saved: %s (8MB)\n", filename);
	} else {
		printf("Error: Could not save fast RAM dump %s\n", filename);
	}
	
	// Dump Slow RAM (128KB) - Banks E0-E1 
	snprintf(filename, sizeof(filename), "memdump_frame_%04d_slowram.bin", frame_number);
	f = fopen(filename, "wb");
	if (f) {
		fwrite(&VERTOPINTERN->emu__DOT__iigs__DOT__slowram__DOT__ram, 1, 131072, f);
		fclose(f);
		printf("Slow RAM dump saved: %s (128KB)\n", filename);
	} else {
		printf("Error: Could not save slow RAM dump %s\n", filename);
	}
	
	// Also create a text dump of key memory regions for easy comparison
	snprintf(filename, sizeof(filename), "memdump_frame_%04d_summary.txt", frame_number);
	f = fopen(filename, "w");
	if (f) {
		fprintf(f, "Memory dump at frame %d\n", frame_number);
		fprintf(f, "========================================\n\n");
		
		// Dump Bank E1 page 0600 (text screen area where errors occur)
		fprintf(f, "Bank E1 $0600-$06FF (text screen area):\n");
		uint8_t* slowram = (uint8_t*)&VERTOPINTERN->emu__DOT__iigs__DOT__slowram__DOT__ram;
		for (int i = 0; i < 256; i += 16) {
			fprintf(f, "E1:%04X: ", 0x0600 + i);
			for (int j = 0; j < 16 && (i + j) < 256; j++) {
				// Bank E1 is at offset 65536 in slowram, page 06 is at offset 0x600
				fprintf(f, "%02X ", slowram[65536 + 0x600 + i + j]);
			}
			fprintf(f, "\n");
		}
		
		fprintf(f, "\nBank 00 $0600-$06FF (main text screen):\n");
		uint8_t* fastram = (uint8_t*)&VERTOPINTERN->emu__DOT__fastram__DOT__ram;
		for (int i = 0; i < 256; i += 16) {
			fprintf(f, "00:%04X: ", 0x0600 + i);
			for (int j = 0; j < 16 && (i + j) < 256; j++) {
				// Bank 00 page 06 is at offset 0x600
				fprintf(f, "%02X ", fastram[0x600 + i + j]);
			}
			fprintf(f, "\n");
		}
		
		fclose(f);
		printf("Memory summary saved: %s\n", filename);
	} else {
		printf("Error: Could not save memory summary %s\n", filename);
	}
}

int main(int argc, char** argv, char** env) {
    // Detect headless from env
    const char* env_headless = getenv("HEADLESS");
    if (env_headless && env_headless[0] && env_headless[0] != '0') headless = true;

	// Parse command line arguments
	for (int i = 1; i < argc; i++) {
		if ((strcmp(argv[i], "-h") == 0) || (strcmp(argv[i], "--help") == 0)) {
			show_help();
			return 0;
        } else if ((strcmp(argv[i], "--headless") == 0) || (strcmp(argv[i], "--no-gui") == 0)) {
            headless = true;
	   debug_6502 = false;
		} else if ((strcmp(argv[i], "-screenshot") == 0 || strcmp(argv[i], "--screenshot") == 0) && i + 1 < argc) {
			screenshot_mode = true;
			std::string frames_str = argv[i + 1];
			std::stringstream ss(frames_str);
			std::string frame_num;
			while (std::getline(ss, frame_num, ',')) {
				screenshot_frames.push_back(std::stoi(frame_num));
			}
			printf("Screenshot mode enabled for frames: %s\n", frames_str.c_str());
			i++; // Skip the next argument since it's the frame list
		} else if (strcmp(argv[i], "--memory-dump") == 0 && i + 1 < argc) {
			memory_dump_mode = true;
			std::string frames_str = argv[i + 1];
			std::stringstream ss(frames_str);
			std::string frame_num;
			while (std::getline(ss, frame_num, ',')) {
				memory_dump_frames.push_back(std::stoi(frame_num));
			}
			printf("Memory dump mode enabled for frames: %s\n", frames_str.c_str());
			i++; // Skip the next argument since it's the frame list
		} else if (strcmp(argv[i], "--stop-at-frame") == 0 && i + 1 < argc) {
			stop_at_frame_enabled = true;
			stop_at_frame = std::stoi(argv[i + 1]);
			printf("Will stop simulation at frame %d\n", stop_at_frame);
			i++; // Skip the next argument since it's the frame number
		} else if (strcmp(argv[i], "--reset-at-frame") == 0 && i + 1 < argc) {
			reset_at_frame_enabled = true;
			reset_at_frame = std::stoi(argv[i + 1]);
			reset_at_frame_cold = false;
			printf("Will trigger WARM reset at frame %d\n", reset_at_frame);
			i++;
		} else if (strcmp(argv[i], "--cold-reset-at-frame") == 0 && i + 1 < argc) {
			reset_at_frame_enabled = true;
			reset_at_frame = std::stoi(argv[i + 1]);
			reset_at_frame_cold = true;
			printf("Will trigger COLD reset at frame %d\n", reset_at_frame);
			i++;
		} else if (strcmp(argv[i], "--enable-csv-trace") == 0) {
			g_csv_trace_enabled = true;
			printf("CSV memory trace logging enabled (vsim_trace.csv)\n");
		} else if (strcmp(argv[i], "--dump-csv-after") == 0 && i + 1 < argc) {
			g_csv_trace_enabled = true;  // Implicitly enable CSV tracing
			dump_csv_after_frame = std::stoi(argv[i + 1]);
			printf("CSV trace enabled, will start dumping at frame %d\n", dump_csv_after_frame);
			i++; // Skip the next argument since it's the frame number
		} else if (strcmp(argv[i], "--dump-vcd-after") == 0 && i + 1 < argc) {
			dump_vcd_after_frame = std::stoi(argv[i + 1]);
			printf("Will start dumping VCD at frame %d\n", dump_vcd_after_frame);
			i++; // Skip the next argument since it's the frame number
		} else if (strcmp(argv[i], "--selftest") == 0) {
			selftest_mode = true;
			printf("Self-test mode enabled - will simulate Command+Option+Control+Reset\n");
		} else if (strcmp(argv[i], "--no-cpu-log") == 0) {
			debug_6502 = false;
			printf("CPU log memory storage disabled to save memory (stdout traces still enabled)\n");
		} else if (strcmp(argv[i], "--quiet") == 0) {
			quiet_mode = true;
			printf("Quiet mode enabled - CPU instruction trace suppressed\n");
        } else if (strcmp(argv[i], "--headless") == 0) {
            headless = true;
        } else if (strcmp(argv[i], "--disk") == 0 && i + 1 < argc) {
            disk_image = argv[i + 1];
            printf("Using HDD unit 0 image: %s\n", disk_image.c_str());
            i++; // Skip the next argument since it's the filename
        } else if (strcmp(argv[i], "--disk2") == 0 && i + 1 < argc) {
            disk_image2 = argv[i + 1];
            printf("Using HDD unit 1 image: %s\n", disk_image2.c_str());
            i++; // Skip the next argument since it's the filename
        } else if (strcmp(argv[i], "--floppy") == 0 && i + 1 < argc) {
            floppy_image = argv[i + 1];
            printf("Using floppy image: %s (will mount to drive 1, 5.25\" 140K)\n", floppy_image.c_str());
            i++; // Skip the next argument since it's the filename
        } else if (strcmp(argv[i], "--send-keys") == 0 && i + 1 < argc) {
            // Parse frame:keys format
            std::string arg = argv[i + 1];
            size_t colon_pos = arg.find(':');
            if (colon_pos == std::string::npos) {
                fprintf(stderr, "Error: --send-keys requires format <frame>:<keys>\n");
                return 1;
            }
            int frame = std::stoi(arg.substr(0, colon_pos));
            std::string keys = arg.substr(colon_pos + 1);

            // Process escape sequences in the keys string
            std::string processed_keys;
            for (size_t j = 0; j < keys.length(); j++) {
                if (keys[j] == '\\' && j + 1 < keys.length()) {
                    char next = keys[j + 1];
                    if (next == 'n') { processed_keys += '\n'; j++; }
                    else if (next == 'r') { processed_keys += '\r'; j++; }
                    else if (next == 't') { processed_keys += '\t'; j++; }
                    else if (next == 'e') { processed_keys += '\x1b'; j++; }  // ESC key
                    else if (next == '\\') { processed_keys += '\\'; j++; }
                    else if (next == 'x' && j + 3 < keys.length()) {
                        // Handle \xNN hex escape sequences
                        char hex[3] = {keys[j + 2], keys[j + 3], 0};
                        processed_keys += (char)strtol(hex, nullptr, 16);
                        j += 3;
                    }
                    else { processed_keys += keys[j]; }
                } else {
                    processed_keys += keys[j];
                }
            }

            KeyInjection ki = {frame, processed_keys};
            key_injections.push_back(ki);
            printf("Will send keys at frame %d: %s\n", frame, processed_keys.c_str());
            i++; // Skip the next argument since it's the frame:keys
        } else if (strcmp(argv[i], "--send-mouse") == 0 && i + 1 < argc) {
            // Parse frame:dx,dy[,btn[,dur]] format
            std::string arg = argv[i + 1];
            size_t colon_pos = arg.find(':');
            if (colon_pos == std::string::npos) {
                fprintf(stderr, "Error: --send-mouse requires format <frame>:<dx>,<dy>[,<btn>[,<dur>]]\n");
                return 1;
            }
            int frame = std::stoi(arg.substr(0, colon_pos));
            std::string params = arg.substr(colon_pos + 1);

            // Parse dx,dy[,btn[,dur]]
            int dx = 0, dy = 0, btn = 0, dur = 1;
            int parsed = sscanf(params.c_str(), "%d,%d,%d,%d", &dx, &dy, &btn, &dur);
            if (parsed < 2) {
                fprintf(stderr, "Error: --send-mouse requires at least dx,dy values\n");
                return 1;
            }

            // Clamp values
            if (dx > 127) dx = 127;
            if (dx < -127) dx = -127;
            if (dy > 127) dy = 127;
            if (dy < -127) dy = -127;
            if (dur < 1) dur = 1;

            MouseInjection mi = {frame, dx, dy, btn, dur};
            mouse_injections.push_back(mi);
            printf("Will send mouse at frame %d: dx=%d dy=%d btn=%d dur=%d\n",
                   frame, dx, dy, btn, dur);
            i++; // Skip the next argument
        } else if (strcmp(argv[i], "--send-joystick") == 0 && i + 1 < argc) {
            // Parse frame:p0,p1[,p2,p3][,btn[,dur]] format
            std::string arg = argv[i + 1];
            size_t colon_pos = arg.find(':');
            if (colon_pos == std::string::npos) {
                fprintf(stderr, "Error: --send-joystick requires format <frame>:<p0>,<p1>[,<p2>,<p3>][,<btn>[,<dur>]]\n");
                return 1;
            }
            int frame = std::stoi(arg.substr(0, colon_pos));
            std::string params = arg.substr(colon_pos + 1);

            // Parse p0,p1[,p2,p3[,btn[,dur]]]
            int p0 = -1, p1 = -1, p2 = -1, p3 = -1, btn = -1, dur = 1;
            int parsed = sscanf(params.c_str(), "%d,%d,%d,%d,%d,%d", &p0, &p1, &p2, &p3, &btn, &dur);
            if (parsed < 2) {
                fprintf(stderr, "Error: --send-joystick requires at least p0,p1 values\n");
                return 1;
            }
            // Handle case where only 4 values given (p0,p1,btn,dur) vs (p0,p1,p2,p3)
            if (parsed == 4 && p2 >= 0 && p2 <= 3 && p3 >= 1) {
                // Looks like p0,p1,btn,dur format
                dur = p3;
                btn = p2;
                p2 = -1;
                p3 = -1;
            }

            // Clamp paddle values to 0-255
            if (p0 > 255) p0 = 255;
            if (p1 > 255) p1 = 255;
            if (p2 > 255) p2 = 255;
            if (p3 > 255) p3 = 255;
            if (dur < 1) dur = 1;

            JoystickInjection ji = {frame, p0, p1, p2, p3, btn, dur};
            joystick_injections.push_back(ji);
            printf("Will send joystick at frame %d: p0=%d p1=%d p2=%d p3=%d btn=%d dur=%d\n",
                   frame, p0, p1, p2, p3, btn, dur);
            i++; // Skip the next argument
        }
    }

	// Create core and initialise
	top = new Vemu();
	Verilated::commandArgs(argc, argv);

	if (dump_vcd_after_frame > -1) {
		Verilated::traceEverOn(true);
		tfp = new VerilatedVcdC;
		top->trace(tfp, 99);
		tfp->open("vsim.vcd");
	}

	// parallel_clemens removed

#ifdef WIN32
	// Attach debug console to the verilated code
	Verilated::setDebug(console);
#endif


	// Load debug trace
	std::string line;
	std::ifstream fin(tracefilename);
	while (getline(fin, line)) {
		log_mame.push_back(line);
	}
	//a2_name_count = size(a2_stuff);
	a2_name_count = sizeof(a2_stuff)/sizeof(a2_stuff[0]);

	// Attach bus
	bus.ioctl_addr = &top->ioctl_addr;
	bus.ioctl_index = &top->ioctl_index;
	bus.ioctl_wait = &top->ioctl_wait;
	bus.ioctl_download = &top->ioctl_download;
	//bus.ioctl_upload = &top->ioctl_upload;
	bus.ioctl_wr = &top->ioctl_wr;
	bus.ioctl_dout = &top->ioctl_dout;
	//bus.ioctl_din = &top->ioctl_din;
	input.ps2_key = &top->ps2_key;

	// hookup blk device
	blockdevice.sd_lba[0] = &top->sd_lba[0];
	blockdevice.sd_lba[1] = &top->sd_lba[1];
	blockdevice.sd_lba[2] = &top->sd_lba[2];
	blockdevice.sd_lba[3] = &top->sd_lba[3];  // HDD unit 1
	blockdevice.sd_lba[4] = &top->sd_lba[4];  // HDD unit 2
	blockdevice.sd_lba[5] = &top->sd_lba[5];  // HDD unit 3
	blockdevice.sd_rd = &top->sd_rd;
	blockdevice.sd_wr = &top->sd_wr;
	blockdevice.sd_ack = &top->sd_ack;
	blockdevice.sd_buff_addr = &top->sd_buff_addr;
	blockdevice.sd_buff_dout = &top->sd_buff_dout;
	blockdevice.sd_buff_din[0] = &top->sd_buff_din[0];
	blockdevice.sd_buff_din[1] = &top->sd_buff_din[1];
	blockdevice.sd_buff_din[2] = &top->sd_buff_din[2];
	blockdevice.sd_buff_din[3] = &top->sd_buff_din[3];  // HDD unit 1
	blockdevice.sd_buff_din[4] = &top->sd_buff_din[4];  // HDD unit 2
	blockdevice.sd_buff_din[5] = &top->sd_buff_din[5];  // HDD unit 3
	blockdevice.sd_buff_wr = &top->sd_buff_wr;
	blockdevice.img_mounted = &top->img_mounted;
	blockdevice.img_readonly = &top->img_readonly;
	blockdevice.img_size = &top->img_size;

	send_clock();

#ifndef DISABLE_AUDIO
    if (!headless) {
	    audio.Initialise();
    }
#endif

    // Set up input module (skip in headless)
    if (!headless) {
        input.Initialise();
    }
#ifdef WIN32
	input.SetMapping(input_up, DIK_UP);
	input.SetMapping(input_right, DIK_RIGHT);
	input.SetMapping(input_down, DIK_DOWN);
	input.SetMapping(input_left, DIK_LEFT);
	input.SetMapping(input_a, DIK_Z); // A
	input.SetMapping(input_b, DIK_X); // B
	input.SetMapping(input_x, DIK_A); // X
	input.SetMapping(input_y, DIK_S); // Y
	input.SetMapping(input_l, DIK_Q); // L
	input.SetMapping(input_r, DIK_W); // R
	input.SetMapping(input_select, DIK_1); // Select
	input.SetMapping(input_start, DIK_2); // Start
	input.SetMapping(input_menu, DIK_M); // System menu trigger

#else
	input.SetMapping(input_up, SDL_SCANCODE_UP);
	input.SetMapping(input_right, SDL_SCANCODE_RIGHT);
	input.SetMapping(input_down, SDL_SCANCODE_DOWN);
	input.SetMapping(input_left, SDL_SCANCODE_LEFT);
	input.SetMapping(input_a, SDL_SCANCODE_A);
	input.SetMapping(input_b, SDL_SCANCODE_B);
	input.SetMapping(input_x, SDL_SCANCODE_X);
	input.SetMapping(input_y, SDL_SCANCODE_Y);
	input.SetMapping(input_l, SDL_SCANCODE_L);
	input.SetMapping(input_r, SDL_SCANCODE_E);
	input.SetMapping(input_start, SDL_SCANCODE_1);
	input.SetMapping(input_select, SDL_SCANCODE_2);
	input.SetMapping(input_menu, SDL_SCANCODE_M);
#endif
    // Setup video output (in headless, SimVideo will be initialized lazily)
    if (!headless) {
        if (video.Initialise(windowTitle) == 1) { return 1; }
    }

    // Mount floppy image to index 0 (5.25" drive 1) if specified via --floppy
    if (!floppy_image.empty()) {
        printf("Mounting floppy image: %s to index 0 (5.25\" drive 1)\n", floppy_image.c_str());
        blockdevice.MountDisk(floppy_image.c_str(), 0);
    }

    // Mount HDD images into slot 7 backend (only if specified via --disk/--disk2)
    if (!disk_image.empty()) {
        printf("Mounting disk image: %s to index 1 (HDD slot 7 unit 0)\n", disk_image.c_str());
        blockdevice.MountDisk(disk_image.c_str(), 1);
    }
    if (!disk_image2.empty()) {
        printf("Mounting disk image: %s to index 3 (HDD slot 7 unit 1)\n", disk_image2.c_str());
        blockdevice.MountDisk(disk_image2.c_str(), 3);
    }

    if (disk_image.empty() && disk_image2.empty() && floppy_image.empty()) {
        printf("No disk images specified - booting without disk\n");
    }

   // In headless mode, run a continuous simulation honoring stop/screenshot flags
   if (headless) {
       printf("Headless mode enabled.\n");
       // Ensure output buffer is allocated for screenshots
       if (output_ptr == nullptr) {
           output_width = VGA_WIDTH;
           output_height = VGA_HEIGHT;
           size_t fb_bytes = (size_t)output_width * (size_t)output_height * 4u;
           output_ptr = (uint32_t*)malloc(fb_bytes);
           if (!output_ptr) {
               fprintf(stderr, "Failed to allocate framebuffer for headless mode.\n");
               return 2;
           }
           memset(output_ptr, 0, fb_bytes);
       }
       run_state = RunState::Running;
       int last_logged_frame = -1;
       while (1) {
           RunBatch(4096);
           if (video.count_frame != last_logged_frame) {
               printf("Frame: %d\n", video.count_frame);
               last_logged_frame = video.count_frame;
               // Handle key injections
               if (!key_injections.empty()) {
                   process_key_injections(video.count_frame);
               }
               // Handle mouse injections (headless mode)
               // Similar to joystick: process injections, then ALWAYS apply mouse values
               if (!mouse_injections.empty() || mouse_injection_active) {
                   bool new_injection = process_mouse_injections(video.count_frame);
                   if (new_injection) {
                       // Toggle clock ONLY when new data arrives - this signals new data to Verilog
                       mouse_clock = !mouse_clock;
                   }
               }
               // ALWAYS set ps2_mouse value (like joystick) - the toggle bit tells Verilog when there's new data
               if (mouse_injection_active) {
                   // Build PS/2 mouse packet from injected values
                   // Negate Y to match real mouse behavior: positive dy from user = move down
                   signed char packet_y = -injected_mouse_y;
                   unsigned char status_byte = (injected_mouse_buttons & 0x07) | 0x08;
                   if (injected_mouse_x < 0) status_byte |= 0x10;
                   if (packet_y < 0) status_byte |= 0x20;
                   unsigned long mouse_temp = status_byte;
                   mouse_temp |= ((unsigned char)injected_mouse_x << 8);
                   mouse_temp |= ((unsigned char)packet_y << 16);
                   // Set bit 24 to current mouse_clock state
                   if (mouse_clock) { mouse_temp |= (1UL << 24); }
                   top->ps2_mouse = mouse_temp;
                   top->ps2_mouse_ext = injected_mouse_x + (injected_mouse_buttons << 8);
               }
               // Handle joystick injections (headless mode)
               if (!joystick_injections.empty() || joystick_injection_active) {
                   process_joystick_injections(video.count_frame);
               }
               // Apply joystick values via direct paddle inputs (0-255 unsigned)
               if (joystick_injection_active) {
                   top->paddle_0 = injected_paddle0;
                   top->paddle_1 = injected_paddle1;
                   top->paddle_2 = injected_paddle2;
                   top->paddle_3 = injected_paddle3;
                   // Also set analog for compatibility
                   top->joystick_l_analog_0 = pack_analog(injected_paddle0, injected_paddle1);
                   top->joystick_l_analog_1 = pack_analog(injected_paddle2, injected_paddle3);
                   // Buttons are active high in joystick_0
                   top->joystick_0 = (injected_joy_buttons & 1) ? (1 << 4) : 0;  // Button 0
                   top->joystick_0 |= (injected_joy_buttons & 2) ? (1 << 5) : 0; // Button 1
               } else {
                   // Default centered position (128)
                   top->paddle_0 = 128;
                   top->paddle_1 = 128;
                   top->paddle_2 = 128;
                   top->paddle_3 = 128;
                   top->joystick_l_analog_0 = pack_analog(128, 128);
                   top->joystick_l_analog_1 = pack_analog(128, 128);
               }
               // Handle screenshots
               if (screenshot_mode) {
                   auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(), video.count_frame);
                   if (it != screenshot_frames.end()) {
                       save_screenshot(video.count_frame);
                       screenshot_frames.erase(it);
                   }
               }
               // Handle memory dumps
               if (memory_dump_mode) {
                   auto it2 = std::find(memory_dump_frames.begin(), memory_dump_frames.end(), video.count_frame);
                   if (it2 != memory_dump_frames.end()) {
                       save_memory_dump(video.count_frame);
                       memory_dump_frames.erase(it2);
                   }
               }
               // Trigger reset at frame (for testing reset functionality)
               if (reset_at_frame_enabled && video.count_frame == reset_at_frame) {
                   fprintf(stderr, "Triggering %s reset at frame %d\n",
                           reset_at_frame_cold ? "COLD" : "WARM", reset_at_frame);
                   reset_pending = 1;
                   reset_pending_cold = reset_at_frame_cold ? 1 : 0;
                   reset_at_frame_enabled = false;  // Only trigger once
               }
               // Stop at frame
               if (stop_at_frame_enabled && video.count_frame >= stop_at_frame) {
                   printf("Reached stop frame %d, exiting...\n", stop_at_frame);
                   return 0;
               }
           }
       }
   }

       // iwm_init();
       // iwm_reset();

#ifdef WIN32
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}
#else
	bool done = false;
	while (!done)
	{
		SDL_Event event;
		// Reset mouse deltas each frame before accumulating events
		mouse_x = 0;
		mouse_y = 0;
		while (SDL_PollEvent(&event))
		{
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT)
				done = true;
			// Handle mouse motion when captured
			if (event.type == SDL_MOUSEMOTION && mouse_captured) {
				mouse_x += event.motion.xrel;
				mouse_y -= event.motion.yrel;  // RTL negates Y, so don't negate here
			}
			// Handle mouse buttons when captured
			if (mouse_captured) {
				if (event.type == SDL_MOUSEBUTTONDOWN) {
					if (event.button.button == SDL_BUTTON_LEFT)
						mouse_buttons |= 0x01;
				}
				if (event.type == SDL_MOUSEBUTTONUP) {
					if (event.button.button == SDL_BUTTON_LEFT)
						mouse_buttons &= ~0x01;
				}
			}
			// Escape key releases mouse capture
			if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE && mouse_captured) {
				mouse_captured = false;
				SDL_SetRelativeMouseMode(SDL_FALSE);
				ImGui::GetIO().ConfigFlags &= ~ImGuiConfigFlags_NoMouse;
			}
		}
		// Clamp mouse deltas to signed 8-bit range
		if (mouse_x > 127) mouse_x = 127;
		if (mouse_x < -127) mouse_x = -127;
		if (mouse_y > 127) mouse_y = 127;
		if (mouse_y < -127) mouse_y = -127;
#endif
		video.StartFrame();

		input.Read();


		// Draw GUI
		// --------
		ImGui::NewFrame();

		// Simulation control window
		ImGui::Begin(windowTitle_Control);
		ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 150), ImGuiCond_Once);
		if (ImGui::Button("Reset simulation")) { resetSim(); } ImGui::SameLine();
		ImGui::Checkbox("STOPONDIFF", &stop_on_log_mismatch);
		if (ImGui::Button("Start running")) { run_state = RunState::Running; } ImGui::SameLine();
		if (ImGui::Button("Stop running")) { run_state = RunState::Stopped; } ImGui::SameLine();
		ImGui::PushItemWidth(100);
		ImGui::InputInt("Run batch size", &batchSize, 1000, 10000);
		ImGui::PopItemWidth();
		if (run_state == RunState::SingleClock || run_state == RunState::MultiClock) { run_state = RunState::Stopped;}
		ImGui::Text("Clock step:"); ImGui::SameLine();
		if (ImGui::Button("Single")) { run_state = RunState::SingleClock; }
		ImGui::SameLine();
		if (ImGui::Button("Multi")) { run_state = RunState::MultiClock; }
		ImGui::SameLine();
		ImGui::PushItemWidth(100);
		ImGui::InputInt("Multi clock amount", &multi_step_amount, 1, 10);
		ImGui::PopItemWidth();
		ImGui::Text("CPU:"); ImGui::SameLine();
		if (ImGui::Button("Step")) { run_state = RunState::StepIn; }
		ImGui::SameLine();
		if (ImGui::Button("Next IRQ")) { run_state = RunState::NextIRQ; }

		//ImGui::SameLine();
		//		if (ImGui::Button("Load ROM"))
			//ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose File", ".rom", ".");

		// Reset buttons
		ImGui::Separator();
		ImGui::Text("System Reset:");
		if (ImGui::Button("Warm Reset (Ctrl+F11)")) {
			fprintf(stderr, "Warm Reset requested from ImGui menu\n");
			reset_pending = 1;
			reset_pending_cold = 0;
		}
		ImGui::SameLine();
		if (ImGui::Button("Cold Reset (Ctrl+OA+F11)")) {
			fprintf(stderr, "Cold Reset requested from ImGui menu\n");
			reset_pending = 1;
			reset_pending_cold = 1;
		}
		ImGui::SameLine();
		ImGui::TextDisabled("(?)");
		if (ImGui::IsItemHovered()) {
			ImGui::BeginTooltip();
			ImGui::Text("Warm Reset: CPU reset, preserves power-on flag (CYAREG bit 6=0)");
			ImGui::Text("Cold Reset: Full power-on reset, sets CYAREG=$C0 (bit 6=1 triggers ROM init)");
			ImGui::Text("Keyboard: F11 = Reset key, Ctrl+F11 = Warm, Ctrl+OpenApple+F11 = Cold");
			ImGui::EndTooltip();
		}

		ImGui::End();

		// Debug log window
		console.Draw(windowTitle_DebugLog, &showDebugLog, ImVec2(500, 700));
		ImGui::SetWindowPos(windowTitle_DebugLog, ImVec2(0, 160), ImGuiCond_Once);

		// Memory debug
		ImGui::Begin("Fast RAM Editor");
		mem_edit.DrawContents(&VERTOPINTERN->emu__DOT__fastram__DOT__ram, 8388608, 0);
		ImGui::End();
		ImGui::Begin("Slow RAM Editor");
		mem_edit.DrawContents(&VERTOPINTERN->emu__DOT__iigs__DOT__slowram__DOT__ram, 131072, 0);
		ImGui::End();
		ImGui::Begin("ROM 1 Editor");
		mem_edit.DrawContents(&VERTOPINTERN->emu__DOT__iigs__DOT__rom1__DOT__d, 65536, 0);
		ImGui::End();
		ImGui::Begin("ROM 2 Editor");
		mem_edit.DrawContents(&VERTOPINTERN->emu__DOT__iigs__DOT__rom2__DOT__d, 65536, 0);
		ImGui::End();

		ImGui::Begin("CPU Registers");
		ImGui::Checkbox("Break", &pc_break_enabled); ImGui::SameLine();
		ImGui::InputTextWithHint("Address", "0000", pc_breakpoint, IM_ARRAYSIZE(pc_breakpoint), ImGuiInputTextFlags_CharsHexadecimal);
		ImGui::Spacing();
		ImGui::Text("A       0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__A);
		ImGui::Text("X       0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__X);
		ImGui::Text("Y       0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__Y);
		ImGui::Text("D       0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D);
		ImGui::Text("SP      0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__SP);
		ImGui::Text("DBR     0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__DBR);
		ImGui::Text("PBR     0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PBR);
		ImGui::Text("PC      0x%04X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__PC);
		ImGui::Spacing();
		ImGui::Text("ADDR:    0x%06X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__A_OUT);
		ImGui::Text("DIN:     0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D_IN);
		ImGui::Text("DOUT:    0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__D_OUT);
		ImGui::Text("WE:      0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__WE);
		ImGui::Text("VDA:     0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VDA);
		ImGui::Text("VPA:     0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPA);
		ImGui::Text("VPB:     0x%01X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__VPB);
		ImGui::Text("IR:      0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IR);
		ImGui::Text("IRQ_n:   0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__cpu__DOT__IRQ_N);
		ImGui::Spacing();
		ImGui::Text("PAGE2:   %s", VERTOPINTERN->emu__DOT__iigs__DOT__PAGE2 ? "PAGE2" : "PAGE1");
		ImGui::Text("TEXTG:   %s", VERTOPINTERN->emu__DOT__iigs__DOT__TEXTG ? "TEXT" : "*GRAPHICS");
		ImGui::Text("HIRES:   %s", VERTOPINTERN->emu__DOT__iigs__DOT__HIRES_MODE ? "HIGH RES": "LOW RES");
		ImGui::Text("EIGHTY:   %s", VERTOPINTERN->emu__DOT__iigs__DOT__EIGHTYCOL? "80COL": "40COL");
		ImGui::Text("MIXG:      0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__MIXG);
		ImGui::Text("NEWVIDEO:      0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__NEWVIDEO);
		ImGui::Text("SHADOW:      0x%02X", VERTOPINTERN->emu__DOT__iigs__DOT__shadow);
		ImGui::Text(VERTOPINTERN->emu__DOT__iigs__DOT__shadow&0x08 ? "DON'T SHADOW SHRG" : "SHADOW SHRG");
		ImGui::Text(VERTOPINTERN->emu__DOT__iigs__DOT__NEWVIDEO&0x80 ? " SHRG VIDEO " : " " );
		ImGui::Text(VERTOPINTERN->emu__DOT__iigs__DOT__NEWVIDEO&0x20 ? " IIGS monochrome VIDEO " : " " );
		ImGui::Spacing();
		ImGui::End();
		//ImGui::Spacing();


		int windowX = 550;
		int windowWidth = (VGA_WIDTH * VGA_SCALE_X) + 24;
		int windowHeight = (VGA_HEIGHT * VGA_SCALE_Y) + 90;

		// Video window
		ImGui::Begin(windowTitle_Video);
		ImGui::SetWindowPos(windowTitle_Video, ImVec2(windowX, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Video, ImVec2(windowWidth, windowHeight), ImGuiCond_Once);

		ImGui::SliderFloat("Zoom", &vga_scale, 1, 8); ImGui::SameLine();
		ImGui::SliderInt("Rotate", &video.output_rotate, -1, 1); ImGui::SameLine();
		ImGui::Checkbox("Flip V", &video.output_vflip);
		ImGui::Text("main_time: %ld frame_count: %d sim FPS: %f", main_time, video.count_frame, video.stats_fps);
		//ImGui::Text("pixel: %06d line: %03d", video.count_pixel, video.count_line);
		
		// Log frame number to stdout for user reference
		static int last_logged_frame = -1;
		if (video.count_frame != last_logged_frame) {
			printf("Frame: %d\n", video.count_frame);
			last_logged_frame = video.count_frame;
			// Handle key injections in GUI mode too
			if (!key_injections.empty()) {
				process_key_injections(video.count_frame);
			}
			// Handle mouse injections in GUI mode too
			if (!mouse_injections.empty() || mouse_injection_active) {
				process_mouse_injections(video.count_frame);
			}
			// Handle joystick injections in GUI mode too
			if (!joystick_injections.empty() || joystick_injection_active) {
				process_joystick_injections(video.count_frame);
			}
		}

		// Draw VGA output
		ImGui::Image(video.texture_id, ImVec2(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y));

		// Mouse capture for Apple IIgs: capture when clicking on VGA output, release with Escape
		if (ImGui::IsItemHovered() && ImGui::IsMouseClicked(0)) {
			mouse_captured = true;
			SDL_SetRelativeMouseMode(SDL_TRUE);
			ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_NoMouse;
		}
		if (mouse_captured) {
			ImGui::Text("Mouse captured - Press ESC to release");
		} else {
			ImGui::Text("Click on display to capture mouse");
		}

		// Check if this frame should be screenshotted (after texture is displayed)
		bool took_screenshot_this_frame = false;
		if (screenshot_mode) {
			auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(), video.count_frame);
			if (it != screenshot_frames.end()) {
				save_screenshot(video.count_frame);
				screenshot_frames.erase(it);  // Remove frame from list after capturing
				took_screenshot_this_frame = true;
			}
		}
		
		// Check if this frame should have memory dumped
		if (memory_dump_mode) {
			auto it = std::find(memory_dump_frames.begin(), memory_dump_frames.end(), video.count_frame);
			if (it != memory_dump_frames.end()) {
				save_memory_dump(video.count_frame);
				memory_dump_frames.erase(it);  // Remove frame from list after dumping
			}
		}
		
		// Check if we should trigger reset at this frame
		if (reset_at_frame_enabled && video.count_frame == reset_at_frame) {
			fprintf(stderr, "GUI: Triggering %s reset at frame %d\n",
					reset_at_frame_cold ? "COLD" : "WARM", reset_at_frame);
			reset_pending = 1;
			reset_pending_cold = reset_at_frame_cold ? 1 : 0;
			reset_at_frame_enabled = false;  // Only trigger once
		}

		// Check if we should stop at this frame
		if (stop_at_frame_enabled && video.count_frame == stop_at_frame) {
			if (took_screenshot_this_frame) {
				printf("Reached stop frame %d after taking screenshot, exiting...\n", stop_at_frame);
			} else {
				printf("Reached stop frame %d, exiting...\n", stop_at_frame);
			}
			exit(0);
		}
		
		ImGui::End();

		if (ImGuiFileDialog::Instance()->Display("ChooseFileDlgKey"))
		{
			// action if OK
			if (ImGuiFileDialog::Instance()->IsOk())
			{
				std::string filePathName = ImGuiFileDialog::Instance()->GetFilePathName();
				std::string filePath = ImGuiFileDialog::Instance()->GetCurrentPath();
				// action
				fprintf(stderr, "filePathName: %s\n", filePathName.c_str());
				fprintf(stderr, "filePath: %s\n", filePath.c_str());
				bus.QueueDownload(filePathName, 1, 1);
			}

			// close
			ImGuiFileDialog::Instance()->Close();
		}


#ifndef DISABLE_AUDIO

		ImGui::Begin(windowTitle_Audio);
		ImGui::SetWindowPos(windowTitle_Audio, ImVec2(windowX, windowHeight), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Audio, ImVec2(windowWidth, 250), ImGuiCond_Once);


		//float vol_l = ((signed short)(top->AUDIO_L) / 256.0f) / 256.0f;
		//float vol_r = ((signed short)(top->AUDIO_R) / 256.0f) / 256.0f;
		//ImGui::ProgressBar(vol_l + 0.5f, ImVec2(200, 16), 0); ImGui::SameLine();
		//ImGui::ProgressBar(vol_r + 0.5f, ImVec2(200, 16), 0);

		int ticksPerSec = (24000000 / 60);
		if (run_state == RunState::Running) {
			audio.CollectDebug((signed short)top->AUDIO_L, (signed short)top->AUDIO_R);
		}
		int channelWidth = (windowWidth / 2) - 16;
		ImPlot::CreateContext();
		if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImGui::SameLine();
		if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImPlot::DestroyContext();
		ImGui::End();
#endif

		video.UpdateTexture();


		// Pass inputs to sim

		top->menu = input.inputs[input_menu];

		top->joystick_0 = 0;
		for (int i = 0; i < input.inputCount; i++)
		{
			if (input.inputs[i]) { top->joystick_0 |= (1 << i); }
		}
		top->joystick_1 = top->joystick_0;

		// Apply joystick/paddle values via analog inputs
		if (joystick_injection_active) {
			top->joystick_l_analog_0 = pack_analog(injected_paddle0, injected_paddle1);
			top->joystick_l_analog_1 = pack_analog(injected_paddle2, injected_paddle3);
			// Override button bits for injected buttons
			if (injected_joy_buttons & 1) top->joystick_0 |= (1 << 4);  // Button 0
			if (injected_joy_buttons & 2) top->joystick_0 |= (1 << 5);  // Button 1
		} else {
			// Default centered position (128 = signed 0)
			top->joystick_l_analog_0 = pack_analog(128, 128);
			top->joystick_l_analog_1 = pack_analog(128, 128);
		}

		/*top->joystick_analog_0 += 1;
		top->joystick_analog_0 -= 256;*/
		//top->paddle_0 += 1;
		//if (input.inputs[0] || input.inputs[1]) {
		//	spinner_toggle = !spinner_toggle;
		//	top->spinner_0 = (input.inputs[0]) ? 16 : -16;
		//	for (char b = 8; b < 16; b++) {
		//		top->spinner_0 &= ~(1UL << b);
		//	}
		//	if (spinner_toggle) { top->spinner_0 |= 1UL << 8; }
		//}

		// Mouse input: check for injection first, then captured mouse or arrow keys as fallback
		if (mouse_injection_active) {
			// Use injected mouse values
			// Negate Y: user's positive dy = move down, but internal convention is negative Y = down
			mouse_x = injected_mouse_x;
			mouse_y = -injected_mouse_y;
			mouse_buttons = injected_mouse_buttons;
		} else if (!mouse_captured) {
			// Fallback to arrow keys when mouse not captured
			mouse_buttons = 0;
			mouse_x = 0;
			mouse_y = 0;
			if (input.inputs[input_left]) { mouse_x = -2; }
			if (input.inputs[input_right]) { mouse_x = 2; }
			if (input.inputs[input_up]) { mouse_y = 2; }
			if (input.inputs[input_down]) { mouse_y = -2; }
			if (input.inputs[input_a]) { mouse_buttons |= 0x01; }
		}
		// mouse_x, mouse_y, mouse_buttons already set from SDL events when captured

		// Build PS/2 mouse packet (matching MiSTer hps_io format):
		// Byte 0 [7:0]: YOvfl[7], XOvfl[6], Ysign[5], Xsign[4], 1[3], Mbtn[2], Rbtn[1], Lbtn[0]
		// Byte 1 [15:8]: X delta (signed 8-bit)
		// Byte 2 [23:16]: Y delta (signed 8-bit, already negated by MiSTer)
		// Bit 24: Toggle bit for event detection
		unsigned char status_byte = (mouse_buttons & 0x07) | 0x08;  // Bit 3 always 1 per PS/2 spec
		if (mouse_x < 0) status_byte |= 0x10;  // X sign bit
		if (mouse_y < 0) status_byte |= 0x20;  // Y sign bit

		unsigned long mouse_temp = status_byte;
		mouse_temp |= ((unsigned char)mouse_x << 8);
		mouse_temp |= ((unsigned char)mouse_y << 16);

		// Toggle clock when there's mouse movement OR button state changed
		// Critical: must detect button releases (when mouse_buttons becomes 0)
		if (mouse_x != 0 || mouse_y != 0 || mouse_buttons != prev_mouse_buttons) {
			mouse_clock = !mouse_clock;
		}
		prev_mouse_buttons = mouse_buttons;
		if (mouse_clock) { mouse_temp |= (1UL << 24); }

		top->ps2_mouse = mouse_temp;
		top->ps2_mouse_ext = mouse_x + (mouse_buttons << 8);

		// Run simulation
		switch (run_state) {
		case RunState::StepIn:
		case RunState::NextIRQ:
		case RunState::Running: RunBatch(batchSize); break;
		case RunState::SingleClock: verilate(); break;
		case RunState::MultiClock: RunBatch(multi_step_amount); break;
		default: std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
	}

	// Clean up before exit
	// --------------------

#ifndef DISABLE_AUDIO
	audio.CleanUp();
#endif 
	video.CleanUp();
	input.CleanUp();

	return 0;
}
