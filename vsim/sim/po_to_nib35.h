// po_to_nib35.h - ProDOS Order to nibblized 3.5" disk image conversion
// Based on MAME's ap_dsk35.cpp and MacPlus_MiSTer's floppy_track_encoder.v
// This converts raw 800K PO/2MG images to pre-nibblized format for IWM

#ifndef PO_TO_NIB35_H
#define PO_TO_NIB35_H

#include <cstdint>
#include <cstring>
#include <vector>
#include <string>

// 3.5" disk format constants
#define PO35_TRACK_COUNT         80      // 80 tracks per side
#define PO35_SIDES               2       // Double-sided
#define PO35_SECTOR_SIZE         512     // 512 bytes per sector
#define PO35_FILE_SIZE           819200  // 800K = 1600 blocks × 512 bytes

// Sectors per track by zone (track / 16)
// Zone 0 (tracks 0-15):  12 sectors
// Zone 1 (tracks 16-31): 11 sectors
// Zone 2 (tracks 32-47): 10 sectors
// Zone 3 (tracks 48-63): 9 sectors
// Zone 4 (tracks 64-79): 8 sectors
static const int sectors_per_zone[5] = { 12, 11, 10, 9, 8 };

// Total sectors per side: 12*16 + 11*16 + 10*16 + 9*16 + 8*16 = 800
#define PO35_SECTORS_PER_SIDE    800

// Nibblized track size - each sector produces ~800 bytes encoded
// Max sectors per track = 12, so max track size ~10KB
// We use 10240 bytes (20 × 512) per track for padding
#define NIB35_TRACK_SIZE         10240
#define NIB35_FILE_SIZE          (PO35_TRACK_COUNT * PO35_SIDES * NIB35_TRACK_SIZE)

// GCR 6-bit encoding table (same as 5.25")
static const uint8_t gcr6_encode_table[64] = {
    0x96, 0x97, 0x9a, 0x9b, 0x9d, 0x9e, 0x9f, 0xa6,
    0xa7, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb2, 0xb3,
    0xb4, 0xb5, 0xb6, 0xb7, 0xb9, 0xba, 0xbb, 0xbc,
    0xbd, 0xbe, 0xbf, 0xcb, 0xcd, 0xce, 0xcf, 0xd3,
    0xd6, 0xd7, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde,
    0xdf, 0xe5, 0xe6, 0xe7, 0xe9, 0xea, 0xeb, 0xec,
    0xed, 0xee, 0xef, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6,
    0xf7, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
};

// NIB encoder for 3.5" disks
struct Nib35Encoder {
    uint8_t* buffer;
    size_t pos;
    size_t max_size;

    void init(uint8_t* buf, size_t size) {
        buffer = buf;
        pos = 0;
        max_size = size;
    }

    void write_byte(uint8_t b) {
        if (pos < max_size) {
            buffer[pos++] = b;
        }
    }

    void write_sync(int count) {
        for (int i = 0; i < count; i++) {
            write_byte(0xFF);
        }
    }

    void write_gcr6(uint8_t value) {
        write_byte(gcr6_encode_table[value & 0x3F]);
    }
};

// Get sector offset within the raw image for a given track/side/sector
// The PO format stores sectors sequentially: side 0 all tracks, then side 1 all tracks
// Actually for 800K disks, it's interleaved by track: track 0 side 0, track 0 side 1, etc.
inline int get_sector_offset_35(int track, int side, int sector) {
    // Calculate cumulative sectors before this track
    int cum_sectors = 0;
    for (int t = 0; t < track; t++) {
        int zone = t / 16;
        if (zone > 4) zone = 4;
        cum_sectors += sectors_per_zone[zone];
    }

    // For double-sided, multiply by 2 and add side offset
    int track_start = cum_sectors * 2;  // Both sides counted

    int zone = track / 16;
    if (zone > 4) zone = 4;
    int spt = sectors_per_zone[zone];

    // Side 1 sectors come after side 0 sectors for this track
    int sector_index = track_start + (side * spt) + sector;

    return sector_index * PO35_SECTOR_SIZE;
}

// Alternative: ProDOS block order (what .po files actually use)
// ProDOS stores blocks sequentially, and each track/side combo maps to blocks
inline int get_prodos_block_offset_35(int track, int side, int sector) {
    // For 800K ProDOS disks, blocks are stored linearly
    // The mapping is: block = (track * 2 + side) * sectors_per_track + sector
    // But sectors per track varies by zone...

    // Actually, .po files for 3.5" are stored as raw 512-byte blocks
    // in ProDOS block order. For 800K, that's blocks 0-1599.

    // The sector interleave for 3.5" is 2:1
    // Physical sector 0 = logical 0
    // Physical sector 1 = logical 2
    // Physical sector 2 = logical 4
    // etc., then wrap around

    int zone = track / 16;
    if (zone > 4) zone = 4;
    int spt = sectors_per_zone[zone];

    // Calculate block number using interleave
    // For now, assume direct mapping (we may need to adjust)
    int block = 0;

    // Sum sectors from all previous tracks (both sides)
    for (int t = 0; t < track; t++) {
        int z = t / 16;
        if (z > 4) z = 4;
        block += sectors_per_zone[z] * 2;  // Both sides
    }

    // Add sectors for side 0 if we're on side 1
    if (side == 1) {
        block += spt;
    }

    // Add sector number
    block += sector;

    return block * PO35_SECTOR_SIZE;
}

// Encode sector data using 3.5" GCR (3 bytes -> 4 GCR bytes)
// Based on MAME's gcr6_encode and MacPlus nibbler
// Returns the running checksum
inline void encode_sector_data_35(Nib35Encoder& enc, const uint8_t* sector_data,
                                   uint8_t& c1, uint8_t& c2, uint8_t& c3) {
    // 3.5" encoding: 512 bytes + 12 tag bytes = 524 bytes
    // Encoded as 175 groups of 3 bytes -> 4 GCR bytes = 700 bytes
    // (Actually 174 full groups + 1 partial = 524 bytes -> 699 GCR + checksum)

    // We don't use tag bytes, so treat as 12 zero bytes + 512 data bytes
    uint8_t full_data[524];
    memset(full_data, 0, 12);  // 12 zero tag bytes
    memcpy(full_data + 12, sector_data, 512);  // 512 data bytes

    // Reset checksums
    c1 = 0;
    c2 = 0;
    c3 = 0;

    // Encode 175 groups (174 complete + 1 with zero padding)
    for (int i = 0; i < 175; i++) {
        uint8_t d0 = full_data[i * 3];
        uint8_t d1 = full_data[i * 3 + 1];
        uint8_t d2 = (i < 174) ? full_data[i * 3 + 2] : 0;  // Last group has only 2 bytes

        // Rotate c3 left by 1
        c3 = (c3 << 1) | (c3 >> 7);

        // Update checksums with carry chain
        uint16_t sum1 = (uint16_t)c1 + d0 + (c3 & 1);
        c1 = (uint8_t)sum1;
        uint8_t carry1 = (sum1 >> 8) & 1;

        uint16_t sum2 = (uint16_t)c2 + d1 + carry1;
        c2 = (uint8_t)sum2;
        uint8_t carry2 = (sum2 >> 8) & 1;

        if (i < 174) {
            c3 = c3 + d2 + carry2;
        }

        // XOR data with previous checksum for encoding
        uint8_t e0 = d0 ^ ((c3 << 1) | (c3 >> 7));  // XOR with rotated c3
        uint8_t e1 = d1 ^ c1;
        uint8_t e2 = d2 ^ c2;

        // Encode 3 bytes into 4 GCR bytes
        // First byte: high 2 bits of each data byte
        enc.write_gcr6(((e0 >> 2) & 0x30) | ((e1 >> 4) & 0x0C) | ((e2 >> 6) & 0x03));
        enc.write_gcr6(e0 & 0x3F);
        enc.write_gcr6(e1 & 0x3F);
        if (i < 174) {
            enc.write_gcr6(e2 & 0x3F);
        }
    }
}

// Encode a single sector for 3.5" disk
inline void encode_sector_35(Nib35Encoder& enc, int track, int side, int sector,
                              int format, const uint8_t* sector_data) {
    // Sync bytes before address field
    // Reduced from 56 to 8 bytes to ensure ROM finds D5 during quick probe.
    // The IIgs ROM has a tight timeout and may not wait for 56 bytes of rotation.
    enc.write_sync(8);

    // Address field prologue
    enc.write_byte(0xD5);
    enc.write_byte(0xAA);
    enc.write_byte(0x96);

    // Address field data (GCR encoded)
    uint8_t track_low = track & 0x3F;
    uint8_t sector_num = sector & 0x3F;
    uint8_t side_track_hi = (side ? 0x20 : 0x00) | ((track >> 6) & 0x01);
    uint8_t format_byte = format & 0x3F;
    uint8_t checksum = track_low ^ sector_num ^ side_track_hi ^ format_byte;

    enc.write_gcr6(track_low);
    enc.write_gcr6(sector_num);
    enc.write_gcr6(side_track_hi);
    enc.write_gcr6(format_byte);
    enc.write_gcr6(checksum);

    // Address field epilogue
    enc.write_byte(0xDE);
    enc.write_byte(0xAA);

    // Sync bytes before data field (5 bytes)
    enc.write_sync(5);

    // Data field prologue
    enc.write_byte(0xD5);
    enc.write_byte(0xAA);
    enc.write_byte(0xAD);

    // Sector number (again, GCR encoded)
    enc.write_gcr6(sector_num);

    // Encoded data (699 GCR bytes for 524 data bytes)
    uint8_t c1, c2, c3;
    encode_sector_data_35(enc, sector_data, c1, c2, c3);

    // Checksum (4 GCR bytes)
    enc.write_gcr6(((c1 >> 2) & 0x30) | ((c2 >> 4) & 0x0C) | ((c3 >> 6) & 0x03));
    enc.write_gcr6(c1 & 0x3F);
    enc.write_gcr6(c2 & 0x3F);
    enc.write_gcr6(c3 & 0x3F);

    // Data field epilogue
    enc.write_byte(0xDE);
    enc.write_byte(0xAA);
    enc.write_byte(0xFF);
}

// Encode a full track for 3.5" disk
inline void encode_track_35(Nib35Encoder& enc, int track, int side,
                             int format, const uint8_t* disk_data, size_t disk_size) {
    int zone = track / 16;
    if (zone > 4) zone = 4;
    int spt = sectors_per_zone[zone];

    // Sector interleave: 2:1 (0, 2, 4, 6, 8, 10, 1, 3, 5, 7, 9, 11 for 12 sectors)
    for (int i = 0; i < spt; i++) {
        // Calculate physical sector from interleave
        int phys_sector = (i * 2) % spt;
        if (i >= (spt + 1) / 2) {
            phys_sector = ((i - (spt + 1) / 2) * 2 + 1) % spt;
        }

        // Actually, let's use simpler interleave for now: just use logical order
        // The interleave is handled by the disk format, not the encoding
        int logical_sector = i;

        // Get sector data from raw image
        int offset = get_prodos_block_offset_35(track, side, logical_sector);
        const uint8_t* sector_data;

        if (offset + PO35_SECTOR_SIZE <= (int)disk_size) {
            sector_data = disk_data + offset;
        } else {
            // Sector beyond disk image - use zeros
            static uint8_t zero_sector[PO35_SECTOR_SIZE] = {0};
            sector_data = zero_sector;
        }

        encode_sector_35(enc, track, side, logical_sector, format, sector_data);
    }
}

// Convert entire PO image to nibblized format
// Returns true on success, false on failure
inline bool convert_po_to_nib35(const uint8_t* po_data, size_t po_size,
                                 std::vector<uint8_t>& nib_output) {
    // Validate PO size
    if (po_size != PO35_FILE_SIZE) {
        printf("PO_TO_NIB35: Invalid PO size %zu, expected %d\n", po_size, PO35_FILE_SIZE);
        return false;
    }

    // Allocate NIB output buffer
    nib_output.resize(NIB35_FILE_SIZE);
    memset(nib_output.data(), 0xFF, NIB35_FILE_SIZE);  // Fill with sync bytes

    // Format byte: 0x22 for double-sided, 0x02 for single-sided
    int format = 0x22;

    printf("PO_TO_NIB35: Converting %zu bytes PO to %d bytes NIB35\n",
           po_size, NIB35_FILE_SIZE);

    // Encode each track on each side
    for (int side = 0; side < PO35_SIDES; side++) {
        for (int track = 0; track < PO35_TRACK_COUNT; track++) {
            // Calculate output position: side 0 first, then side 1
            // Or interleaved by track...
            // For now, use: track_index = side * 80 + track
            int track_index = side * PO35_TRACK_COUNT + track;
            uint8_t* nib_track = nib_output.data() + track_index * NIB35_TRACK_SIZE;

            Nib35Encoder enc;
            enc.init(nib_track, NIB35_TRACK_SIZE);

            encode_track_35(enc, track, side, format, po_data, po_size);

            // Fill remainder with sync bytes
            while (enc.pos < NIB35_TRACK_SIZE) {
                enc.write_byte(0xFF);
            }
        }
    }

    printf("PO_TO_NIB35: Conversion complete\n");
    return true;
}

// Check if filename has .po extension (case insensitive)
inline bool is_po_extension(const std::string& filename) {
    size_t len = filename.length();
    if (len < 3) return false;

    std::string ext = filename.substr(len - 3);
    for (auto& c : ext) {
        c = tolower(c);
    }

    return (ext == ".po");
}

// Check if filename has .2mg extension (case insensitive)
inline bool is_2mg_extension(const std::string& filename) {
    size_t len = filename.length();
    if (len < 4) return false;

    std::string ext = filename.substr(len - 4);
    for (auto& c : ext) {
        c = tolower(c);
    }

    return (ext == ".2mg");
}

// Check if file size matches 800K PO format
inline bool is_po35_size(size_t size) {
    return size == PO35_FILE_SIZE;
}

#endif // PO_TO_NIB35_H
