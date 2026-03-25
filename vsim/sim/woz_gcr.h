#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>

//
// woz_gcr.h: GCR 6-and-2 encode/decode for 3.5" floppy sectors
//
// 3.5" GCR format:
//   Address field: D5 AA 96 <track> <sector> <side> <format> <checksum> DE AA
//   Data field:    D5 AA AD <sector_id> <699 GCR bytes> <4 checksum bytes> DE AA
//
// The 699 GCR bytes encode 524 raw bytes (12 tag + 512 data) using 6-and-2 encoding.
//

namespace WozGCR {

// GCR decode table: maps 8-bit disk byte to 6-bit value (0-63)
// Invalid entries return 0xFF
extern const uint8_t gcr_decode_table[256];

// GCR encode table: maps 6-bit value (0-63) to 8-bit disk byte
extern const uint8_t gcr_encode_table[64];

// Decode a 3.5" GCR data field (699 GCR bytes) into 524 raw bytes (12 tag + 512 data)
// Returns true on success, false on checksum error
// Input: gcr_data points to the 699 GCR bytes AFTER the D5 AA AD <sector_id> prologue
// Output: raw_data receives 524 bytes (12 tag + 512 data)
bool gcr_decode_sector(const uint8_t* gcr_data, size_t gcr_len,
                       uint8_t* raw_data, size_t raw_len);

// Encode 524 raw bytes (12 tag + 512 data) into 699 GCR bytes
// Input: raw_data is 524 bytes (12 tag + 512 data)
// Output: gcr_data receives 699 GCR bytes (NOT including D5 AA AD prologue or DE AA epilogue)
// Also computes and appends the 4 checksum bytes (encoded as 4 GCR bytes)
// Total output: 703 bytes (699 data + 4 checksum)
bool gcr_encode_sector(const uint8_t* raw_data, size_t raw_len,
                       uint8_t* gcr_data, size_t gcr_buf_len,
                       size_t* gcr_out_len);

// Block-to-track/side/sector mapping for 3.5" 800K disks
// Speed groups: tracks 0-15=12spt, 16-31=11spt, 32-47=10spt, 48-63=9spt, 64-79=8spt
void block_to_tss(int block, int* track, int* side, int* sector);

// Total blocks on an 800K 3.5" disk
static const int TOTAL_BLOCKS_800K = 1600;

// Find a sector's data field in a WOZ bitstream track
// Scans for D5 AA 96 address mark with matching sector number,
// then finds the following D5 AA AD data mark.
// Returns bit offset to first byte after D5 AA AD <sector_id>, or -1 if not found
int find_sector_data(const uint8_t* track_bits, uint32_t bit_count,
                     int target_sector, int target_track, int target_side);

// Write GCR-encoded sector data into a WOZ bitstream at the given bit offset
// The offset should point to the first GCR data byte (after D5 AA AD <sector_id>)
// Writes 703 bytes (699 data + 4 checksum GCR bytes)
bool write_sector_data(uint8_t* track_bits, uint32_t bit_count,
                       int bit_offset, const uint8_t* gcr_data, size_t gcr_len);

// Read GCR-encoded sector data from a WOZ bitstream at the given bit offset
// The offset should point to the first GCR data byte (after D5 AA AD <sector_id>)
// Reads 699 GCR data bytes (not including checksum)
bool read_sector_data(const uint8_t* track_bits, uint32_t bit_count,
                      int bit_offset, uint8_t* gcr_data, size_t gcr_buf_len);

} // namespace WozGCR
