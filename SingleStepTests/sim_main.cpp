#include <verilated.h>
#include "Vsinglesteptests.h"
#include "Vsinglesteptests__Syms.h"

#include <cstdio>
#include "json.hpp"

using json = nlohmann::json;

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)

#if VERILATOR_MAJOR_VERSION >= 5
#define VERTOPINTERN top->rootp
#else
#define VERTOPINTERN top
#endif

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
#include <map>

// Simulation control
// ------------------
int initialReset = 48;
vluint64_t main_time = 0;	// Current simulation time.

double sc_time_stamp() {	// Called by $time in Verilog.
	return main_time;
}

namespace {
	// Verilog module
	// --------------
	Vsinglesteptests* top = NULL;
	std::vector<uint8_t> ram;
	std::vector<uint32_t> dirty;   // addresses touched since last test (for fast RAM reset)

	bool get_ef() {
		uint32_t pval = VERTOPINTERN->singlesteptests__DOT__cpu__DOT__P;
		return (pval >> 8) & 0x01;
	}

	bool get_xf() {
		uint32_t pval = VERTOPINTERN->singlesteptests__DOT__cpu__DOT__P;
		return (pval >> 4) & 0x01;
	}

	void finish() {
		top->final();
		delete top;
	}

	void update_ram() {
		top->cpu_din = ram[top->cpu_addr];
		if (!top->cpu_we_n) { ram[top->cpu_addr] = top->cpu_dout; dirty.push_back(top->cpu_addr); }
	}

	void run_cycle(bool updateram=true) {
		top->clk = 0;
		main_time++;
		if (updateram) update_ram();
		top->eval();
		if (updateram) update_ram();
		top->clk = 1;
		main_time++;
		top->eval();
		if (updateram) update_ram();
	}

	// Force the execution of a JMP
	void jmp(uint32_t addr) {
		const bool ef = get_ef();
		top->cpu_din = ef ? 0x4c : 0x5c; // JMP abs / JMP long opcodes
		run_cycle(false);
		top->cpu_din = addr & 0xff;
		run_cycle(false);
		top->cpu_din = (addr >> 8) & 0xff;
		run_cycle(false);

		if (!ef) {
			top->cpu_din = (addr >> 16) & 0xff;
			run_cycle(false);
		}
	}

	bool check_result(const std::string& testname, const std::string& fieldname, int actual, int expected) {
		bool pass = (expected == actual);
		if (!pass) {
			std::cerr << "Failed test " << testname
				  << ": Expected " << fieldname << " to be " << expected
				  << " but got " << actual << "\n";
		}
		return pass;
	}
}

int main(int argc, char** argv, char** env) {
	// Create core and initialise
	top = new Vsinglesteptests();
	Verilated::commandArgs(argc, argv);
	Verilated::traceEverOn(true);

	ram.resize(0x1000000, 0x00);

	top->reset = 1;
	for (int i = 0; i < 16; ++i) {
		run_cycle();
	}
	top->reset = 0;

	// VPA = VDA = 1 immediately after reset is released; need to wait a bit
	while (VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VPA &&
	       VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VDA) {
		run_cycle();
	}
	// Parse command line arguments
	if (argc != 2) {
		std::cerr << "Usage: Vsinglesteptests [filename]\n\n";
		return 0;
	}
	const std::string fname(argv[1]);

	std::ifstream f(fname);
	//std::ifstream f("v1/ea.n.json"); // NOP
	//std::ifstream f("v1/8d.n.json"); // STA a

	json data = json::parse(f);

	int passcount = 0;

	// --- cycle-accuracy accumulators (per file) ---
	long ntests = 0, state_ok = 0;
	std::map<int,long> delta_hist;   // (actual_cycles - expected_cycles) -> count

	for (auto& t : data ) {
		const std::string testname = t["name"];

		// Synchronize to CPU opcode fetch (guarded: STP/WAI may have halted the CPU)
		for (int sg = 0; sg < 300 &&
		     (!VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VPA ||
		      !VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VDA); ++sg) {
			run_cycle();
		}

        // Initialize CPU pre-execution state
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__PC = t["initial"]["pc"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__SP = t["initial"]["s"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__P   = t["initial"]["p"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__A = t["initial"]["a"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__X = t["initial"]["x"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__Y = t["initial"]["y"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__DBR = t["initial"]["dbr"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__D = t["initial"]["d"];
		VERTOPINTERN->singlesteptests__DOT__cpu__DOT__PBR  = t["initial"]["pbr"];

		if (t["initial"]["e"] != 0) {
			VERTOPINTERN->singlesteptests__DOT__cpu__DOT__P |= (1 << 8);
		}

		// Initialize RAM: clear only the addresses touched by the previous test
		// (and its writes), then load this test's initial bytes -- avoids a full
		// 16 MB memset per test.
		for (auto a : dirty) ram[a] = 0x00;
		dirty.clear();
		for (auto& r : t["initial"]["ram"]) {
			ram[r[0]] = r[1];
			dirty.push_back(r[0]);
		}

		// JMP to the opcode location
		const uint32_t pc = t["initial"]["pc"];
		const uint32_t pbr = t["initial"]["pbr"];
		jmp((pbr << 16) | pc);

		// --- Measure actual cycle count ---
		// Cycle 1 is the test opcode fetch (after the forced JMP). Count cycles
		// until the NEXT opcode fetch (VPA & VDA both high), which belongs to the
		// following instruction and is NOT counted. Expected = len(cycles) from JSON.
		const int expected = (int)t["cycles"].size();
		// Make sure the bus is at the test instruction's opcode fetch (VPA & VDA).
		for (int ag = 0; ag < 300 &&
		     !(VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VPA &&
		       VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VDA); ++ag)
			run_cycle();
		// Count cycles from this opcode fetch up to (and including the detection of)
		// the NEXT opcode fetch == this instruction's cycle count.
		int actual = 0, guard = 0;
		do {
			run_cycle(); actual++;
		} while (!(VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VPA &&
		           VERTOPINTERN->singlesteptests__DOT__cpu__DOT__VDA) && guard++ < 64);
		delta_hist[actual - expected]++;

		/* Check the final state (at instruction completion = next opcode fetch) */
		bool pass = true;
		const bool ef = get_ef();
		const bool xf = get_xf();
		const uint16_t spval = VERTOPINTERN->singlesteptests__DOT__cpu__DOT__SP;
		const uint16_t xval = VERTOPINTERN->singlesteptests__DOT__cpu__DOT__X;
		const uint16_t yval = VERTOPINTERN->singlesteptests__DOT__cpu__DOT__Y;
		const uint16_t spval8 = (spval & 0xff) | 0x100;
		const uint8_t xval8 = xval & 0xff;
		const uint8_t yval8 = yval & 0xff;

		pass &= check_result(testname, "PC", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__PC, t["final"]["pc"]);
		pass &= check_result(testname, "SP", (ef ? spval8 : spval), t["final"]["s"]);
		pass &= check_result(testname, "P", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__P & 0xff, t["final"]["p"]);
		pass &= check_result(testname, "A", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__A, t["final"]["a"]);
		pass &= check_result(testname, "X", (xf ? xval8 : xval), t["final"]["x"]);
		pass &= check_result(testname, "Y", (xf ? yval8 : yval), t["final"]["y"]);
		pass &= check_result(testname, "DBR", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__DBR,  t["final"]["dbr"]);
		pass &= check_result(testname, "D", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__D, t["final"]["d"]);
		pass &= check_result(testname, "PBR", VERTOPINTERN->singlesteptests__DOT__cpu__DOT__PBR, t["final"]["pbr"]);
		pass &= check_result(testname, "E", ef, t["final"]["e"]);

        for (auto& r : t["final"]["ram"]) {
            std::ostringstream ram_field;
            ram_field << "RAM[0x" << std::hex << std::setw(6) << std::setfill('0') << (unsigned int)r[0] << "]";
            pass &= check_result(testname, ram_field.str(), ram[r[0]], r[1]);
        }

		if (pass) { passcount++; state_ok++; }
		ntests++;
	}

	// --- Per-file summary line (parseable: one line per opcode/mode) ---
	std::cout << "SUMMARY " << fname
	          << " ntests=" << ntests
	          << " stateOK=" << state_ok
	          << " deltas=";
	bool first = true;
	for (auto& kv : delta_hist) {
		if (!first) std::cout << ",";
		std::cout << (kv.first >= 0 ? "+" : "") << kv.first << "x" << kv.second;
		first = false;
	}
	std::cout << "\n";
	finish();
	return 0;
}
