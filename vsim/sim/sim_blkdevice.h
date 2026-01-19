#pragma once
#include <iostream>
#include <fstream>
#include <vector>
#include "verilated.h"
#include "sim_console.h"
#include "woz_loader.h"


#ifndef _MSC_VER
#else
#define WIN32
#endif

#define kVDNUM 10
#define kBLKSZ 512

// WOZ drive indices
#define WOZ_DRIVE_35_1  4   // 3.5" drive 1 (WOZ mode)
#define WOZ_DRIVE_35_2  5   // 3.5" drive 2 (WOZ mode)
#define WOZ_DRIVE_525_1 6   // 5.25" drive 1 (WOZ mode)
#define WOZ_DRIVE_525_2 7   // 5.25" drive 2 (WOZ mode)

struct SimBlockDevice {
public:

	IData* sd_lba[kVDNUM];
	SData* sd_rd;
	SData* sd_wr;
	SData* sd_ack;
	SData* sd_buff_addr;
	CData* sd_buff_dout;
	CData* sd_buff_din[kVDNUM];
	CData* sd_buff_wr;
	SData* img_mounted;
	CData* img_readonly;
	QData* img_size;

	// WOZ bit interface pointers (direct access from Verilog)
	// 3.5" drive 1
	CData* woz3_track;          // Input: track being accessed
	SData* woz3_bit_addr;       // Input: byte address in track bit buffer
	CData* woz3_bit_data;       // Output: byte from track bit buffer
	IData* woz3_bit_count;      // Output: total bits in track
	// 5.25" drive 1
	CData* woz1_track;          // Input: track being accessed
	SData* woz1_bit_addr;       // Input: byte address in track bit buffer
	CData* woz1_bit_data;       // Output: byte from track bit buffer
	IData* woz1_bit_count;      // Output: total bits in track
	// WOZ disk ready signals
	CData* woz3_ready;          // Output: 3.5" WOZ drive 1 ready
	CData* woz1_ready;          // Output: 5.25" WOZ drive 1 ready

	int bytecnt;
        long int disk_size[kVDNUM];
	long int header_size[kVDNUM];
	bool reading;
	bool writing;
	int ack_delay;
	int current_disk;
	int current_lba[kVDNUM];  // LBA currently being transferred for each drive
	bool mountQueue[kVDNUM];
	std::fstream disk[kVDNUM];

	// WOZ disk support
	WOZDisk woz_disk[4];     // Up to 4 WOZ drives (2x 3.5", 2x 5.25")
	bool woz_mounted[4];     // WOZ drive mounted status
	int woz_current_track[4]; // Current track being transferred
	int woz_block_offset[4]; // Current block offset in track transfer

	void BeforeEval(int cycles);
	void AfterEval(void);
	void MountDisk( std::string file, int index);

	// WOZ-specific mounting
	bool MountWOZ(const std::string& file, int woz_index);

	// Get WOZ track data for a specific drive and track
	// Returns pointer to track, or nullptr if not available
	const WOZTrack* GetWOZTrack(int woz_index, int track);

	// Get WOZ disk info
	const WOZDisk* GetWOZDisk(int woz_index) const;

	SimBlockDevice(DebugConsole c);
	~SimBlockDevice();


private:
	// Handle WOZ track data requests (sd_lba encodes track number)
	void HandleWOZRequest(int woz_index, int cycles);
};
