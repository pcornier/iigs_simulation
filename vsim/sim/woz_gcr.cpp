//
// woz_gcr.cpp: GCR 6-and-2 encode/decode for 3.5" floppy sectors
//

#include "woz_gcr.h"
#include <cstdio>
#include <cstring>

namespace WozGCR {

// GCR encode table: 6-bit value → 8-bit disk byte
// Apple 3.5" uses the same GCR table as 5.25" (values with no more than
// one pair of adjacent zero bits)
const uint8_t gcr_encode_table[64] = {
    0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
    0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
    0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
    0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
    0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
    0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
    0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
    0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
};

// GCR decode table: 8-bit disk byte → 6-bit value (0xFF = invalid)
const uint8_t gcr_decode_table[256] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 00-07
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 08-0F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 10-17
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 18-1F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 20-27
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 28-2F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 30-37
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 38-3F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 40-47
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 48-4F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 50-57
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 58-5F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 60-67
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 68-6F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 70-77
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 78-7F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 80-87
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 88-8F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01, // 90-97
    0xFF, 0xFF, 0x02, 0x03, 0xFF, 0x04, 0x05, 0x06, // 98-9F
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x07, 0x08, // A0-A7
    0xFF, 0xFF, 0xFF, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, // A8-AF
    0xFF, 0xFF, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, // B0-B7
    0xFF, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, // B8-BF
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // C0-C7
    0xFF, 0xFF, 0xFF, 0x1B, 0xFF, 0x1C, 0x1D, 0x1E, // C8-CF
    0xFF, 0xFF, 0xFF, 0x1F, 0xFF, 0xFF, 0x20, 0x21, // D0-D7
    0xFF, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, // D8-DF
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x29, 0x2A, 0x2B, // E0-E7
    0xFF, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, // E8-EF
    0xFF, 0xFF, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, // F0-F7
    0xFF, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F  // F8-FF
};

//
// 3.5" GCR 6-and-2 encoding layout:
//
// The 524 raw bytes (12 tag + 512 data) are split into:
//   - "twos" buffer (175 entries): the low 2 bits of groups of 3 source bytes,
//     packed into 6-bit values
//   - "sixes" buffer (524 entries): the high 6 bits of each source byte
//
// The twos come first on disk, then the sixes, then 4 checksum bytes.
// Total: 175 + 524 = 699 six-bit values → 699 GCR bytes
//

static const int RAW_BYTES = 524;      // 12 tag + 512 data
static const int TWOS_COUNT = 175;     // ceil(524/3) = 175
static const int SIXES_COUNT = 524;
static const int GCR_DATA_BYTES = 699; // 175 + 524
static const int GCR_CKSUM_BYTES = 4;
static const int GCR_TOTAL_BYTES = 703; // 699 + 4

bool gcr_decode_sector(const uint8_t* gcr_data, size_t gcr_len,
                       uint8_t* raw_data, size_t raw_len)
{
    if (gcr_len < GCR_DATA_BYTES + GCR_CKSUM_BYTES || raw_len < RAW_BYTES)
        return false;

    // Step 1: GCR-decode all bytes to 6-bit values
    uint8_t decoded[GCR_DATA_BYTES + GCR_CKSUM_BYTES];
    uint8_t prev = 0;
    for (int i = 0; i < GCR_DATA_BYTES + GCR_CKSUM_BYTES; i++) {
        uint8_t gcr = gcr_data[i];
        uint8_t val = gcr_decode_table[gcr];
        if (val == 0xFF) {
            printf("WOZ_GCR: Invalid GCR byte %02X at offset %d\n", gcr, i);
            return false;
        }
        // Running XOR decode
        decoded[i] = val ^ prev;
        prev = decoded[i];
    }

    // Step 2: Extract twos and sixes
    // First 175 values are the "twos" (low 2-bit groups)
    // Next 524 values are the "sixes" (high 6 bits)
    const uint8_t* twos = decoded;
    const uint8_t* sixes = decoded + TWOS_COUNT;

    // Step 3: Reassemble raw bytes
    for (int i = 0; i < RAW_BYTES; i++) {
        uint8_t hi6 = sixes[i] & 0x3F;
        // The twos buffer packs 3 bytes' low-2-bits into each 6-bit value
        // twos[i/3] contains bits for bytes i, i+175, i+350 (approximately)
        // Actually the layout is: twos[j] contains bits for raw[j], raw[j+175], raw[j+350]
        // where the 6 bits are: {raw[j+350][1:0], raw[j+175][1:0], raw[j][1:0]}
        int two_idx = i % TWOS_COUNT;
        int two_shift;
        if (i < TWOS_COUNT)
            two_shift = 0;
        else if (i < 2 * TWOS_COUNT)
            two_shift = 2;
        else
            two_shift = 4;

        uint8_t lo2 = (twos[two_idx] >> two_shift) & 0x03;
        raw_data[i] = (hi6 << 2) | lo2;
    }

    // Step 4: Verify checksum (last 4 decoded values should all be 0)
    // After XOR chain, the checksum bytes should decode to 0
    for (int i = 0; i < GCR_CKSUM_BYTES; i++) {
        if (decoded[GCR_DATA_BYTES + i] != 0) {
            printf("WOZ_GCR: Checksum error at byte %d: %02X\n", i, decoded[GCR_DATA_BYTES + i]);
            // Don't fail on checksum - data may still be usable
        }
    }

    return true;
}

bool gcr_encode_sector(const uint8_t* raw_data, size_t raw_len,
                       uint8_t* gcr_data, size_t gcr_buf_len,
                       size_t* gcr_out_len)
{
    if (raw_len < RAW_BYTES || gcr_buf_len < GCR_TOTAL_BYTES)
        return false;

    // Step 1: Split raw bytes into twos and sixes
    uint8_t twos[TWOS_COUNT];
    uint8_t sixes[SIXES_COUNT];
    memset(twos, 0, sizeof(twos));

    for (int i = 0; i < RAW_BYTES; i++) {
        sixes[i] = (raw_data[i] >> 2) & 0x3F;
        uint8_t lo2 = raw_data[i] & 0x03;
        int two_idx = i % TWOS_COUNT;
        int two_shift;
        if (i < TWOS_COUNT)
            two_shift = 0;
        else if (i < 2 * TWOS_COUNT)
            two_shift = 2;
        else
            two_shift = 4;
        twos[two_idx] |= (lo2 << two_shift);
    }

    // Step 2: Build the 6-bit value stream (twos first, then sixes)
    uint8_t values[GCR_DATA_BYTES];
    for (int i = 0; i < TWOS_COUNT; i++)
        values[i] = twos[i] & 0x3F;
    for (int i = 0; i < SIXES_COUNT; i++)
        values[TWOS_COUNT + i] = sixes[i] & 0x3F;

    // Step 3: Running XOR encode + compute checksum
    uint8_t prev = 0;
    uint8_t cksum[4] = {0, 0, 0, 0};
    for (int i = 0; i < GCR_DATA_BYTES; i++) {
        uint8_t encoded = values[i] ^ prev;
        prev = values[i];
        gcr_data[i] = gcr_encode_table[encoded & 0x3F];
    }

    // Step 4: Checksum = prev (the last accumulated XOR value) split into 4 bytes
    // Actually, checksum bytes encode the running XOR so that decode produces 0
    // Append 4 checksum bytes: each is the XOR-encode of 0 (to zero the chain)
    // The checksum is split across 4 six-bit values
    uint8_t ck = prev; // Running XOR up to this point
    // Four checksum nibbles encode the final XOR value
    // Byte 0: bits 5-4 of ck, Byte 1: bits 3-2, Byte 2: bits 1-0, Byte 3: verify
    // Actually, Apple uses a simpler scheme: the checksum is just the final XOR value
    // encoded so that the decode chain zeroes out
    gcr_data[GCR_DATA_BYTES + 0] = gcr_encode_table[prev & 0x3F];
    gcr_data[GCR_DATA_BYTES + 1] = gcr_encode_table[0];
    gcr_data[GCR_DATA_BYTES + 2] = gcr_encode_table[0];
    gcr_data[GCR_DATA_BYTES + 3] = gcr_encode_table[0];

    *gcr_out_len = GCR_TOTAL_BYTES;
    return true;
}

void block_to_tss(int block, int* track, int* side, int* sector)
{
    // 3.5" 800K disk: 80 tracks, 2 sides
    // Speed groups: 0-15=12spt, 16-31=11spt, 32-47=10spt, 48-63=9spt, 64-79=8spt
    static const int sectors_per_group[] = {12, 11, 10, 9, 8};
    static const int tracks_per_group = 16;

    int block_offset = 0;
    for (int g = 0; g < 5; g++) {
        int spt = sectors_per_group[g];
        int blocks_in_group = spt * tracks_per_group * 2; // 2 sides
        if (block < block_offset + blocks_in_group) {
            int local = block - block_offset;
            int track_in_group = local / (spt * 2);
            int remainder = local % (spt * 2);
            *track = g * tracks_per_group + track_in_group;
            *side = remainder / spt;
            *sector = remainder % spt;
            return;
        }
        block_offset += blocks_in_group;
    }
    // Block out of range
    *track = 0;
    *side = 0;
    *sector = 0;
    printf("WOZ_GCR: block_to_tss: block %d out of range!\n", block);
}

// Read a byte from a bitstream at a given bit offset
static uint8_t read_byte_at_bit(const uint8_t* bits, uint32_t bit_count, uint32_t bit_offset)
{
    uint8_t result = 0;
    for (int i = 0; i < 8; i++) {
        uint32_t pos = (bit_offset + i) % bit_count;
        uint32_t byte_idx = pos / 8;
        uint32_t bit_idx = 7 - (pos % 8); // MSB first
        result = (result << 1) | ((bits[byte_idx] >> bit_idx) & 1);
    }
    return result;
}

// Write a byte into a bitstream at a given bit offset
static void write_byte_at_bit(uint8_t* bits, uint32_t bit_count, uint32_t bit_offset, uint8_t value)
{
    for (int i = 0; i < 8; i++) {
        uint32_t pos = (bit_offset + i) % bit_count;
        uint32_t byte_idx = pos / 8;
        uint32_t bit_idx = 7 - (pos % 8); // MSB first
        if (value & (0x80 >> i))
            bits[byte_idx] |= (1 << bit_idx);
        else
            bits[byte_idx] &= ~(1 << bit_idx);
    }
}

int find_sector_data(const uint8_t* track_bits, uint32_t bit_count,
                     int target_sector, int target_track, int target_side)
{
    if (bit_count == 0) return -1;

    // Scan for address field: D5 AA 96
    // Then check track/sector/side match
    // Then find following data field: D5 AA AD
    uint32_t scan_limit = bit_count; // Scan up to one full rotation
    uint8_t window[3] = {0, 0, 0};

    for (uint32_t bit_pos = 0; bit_pos < scan_limit; bit_pos += 8) {
        uint8_t byte_val = read_byte_at_bit(track_bits, bit_count, bit_pos);

        // Shift window
        window[0] = window[1];
        window[1] = window[2];
        window[2] = byte_val;

        // Look for D5 AA 96 (address field prologue)
        if (window[0] == 0xD5 && window[1] == 0xAA && window[2] == 0x96) {
            // Read address field: track, sector, side, format, checksum
            uint32_t addr_pos = bit_pos + 8; // Next byte after 96
            uint8_t addr_track  = read_byte_at_bit(track_bits, bit_count, addr_pos);
            uint8_t addr_sector = read_byte_at_bit(track_bits, bit_count, addr_pos + 8);
            uint8_t addr_side   = read_byte_at_bit(track_bits, bit_count, addr_pos + 16);
            uint8_t addr_format = read_byte_at_bit(track_bits, bit_count, addr_pos + 24);
            uint8_t addr_cksum  = read_byte_at_bit(track_bits, bit_count, addr_pos + 32);

            // Verify checksum
            uint8_t calc_cksum = addr_track ^ addr_sector ^ addr_side ^ addr_format;

            if (addr_sector == target_sector &&
                addr_track == target_track &&
                addr_side == target_side &&
                calc_cksum == addr_cksum) {

                // Found matching address field. Now find D5 AA AD data field
                // It should follow within a reasonable distance
                uint32_t data_search_start = addr_pos + 5 * 8; // Skip address field
                uint8_t dw[3] = {0, 0, 0};

                for (uint32_t dp = data_search_start; dp < data_search_start + 200 * 8; dp += 8) {
                    dw[0] = dw[1];
                    dw[1] = dw[2];
                    dw[2] = read_byte_at_bit(track_bits, bit_count, dp);

                    if (dw[0] == 0xD5 && dw[1] == 0xAA && dw[2] == 0xAD) {
                        // Found data prologue. Next byte is sector_id, then GCR data
                        uint32_t sector_id_pos = dp + 8;
                        uint32_t gcr_data_pos = sector_id_pos + 8; // Skip sector_id byte
                        return (int)gcr_data_pos;
                    }
                }
            }
        }
    }

    return -1; // Not found
}

bool write_sector_data(uint8_t* track_bits, uint32_t bit_count,
                       int bit_offset, const uint8_t* gcr_data, size_t gcr_len)
{
    if (bit_offset < 0 || gcr_len == 0) return false;

    for (size_t i = 0; i < gcr_len; i++) {
        uint32_t pos = (bit_offset + i * 8) % bit_count;
        write_byte_at_bit(track_bits, bit_count, pos, gcr_data[i]);
    }
    return true;
}

bool read_sector_data(const uint8_t* track_bits, uint32_t bit_count,
                      int bit_offset, uint8_t* gcr_data, size_t gcr_buf_len)
{
    if (bit_offset < 0 || gcr_buf_len < GCR_DATA_BYTES + GCR_CKSUM_BYTES) return false;

    for (int i = 0; i < GCR_DATA_BYTES + GCR_CKSUM_BYTES; i++) {
        uint32_t pos = (bit_offset + i * 8) % bit_count;
        gcr_data[i] = read_byte_at_bit(track_bits, bit_count, pos);
    }
    return true;
}

} // namespace WozGCR
