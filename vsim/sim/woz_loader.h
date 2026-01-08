/**
 * @file woz_loader.h
 * @brief WOZ disk image loader for flux-based floppy emulation
 *
 * Parses WOZ 1.x and 2.x disk images, extracting track bit data
 * for use with hardware-accurate IWM emulation.
 *
 * Reference: https://applesaucefdc.com/woz/reference2/
 * Adapted from Clemens IIgs emulator (clem_woz.c)
 */

#ifndef WOZ_LOADER_H
#define WOZ_LOADER_H

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

// Disk type constants
#define WOZ_DISK_TYPE_525   1
#define WOZ_DISK_TYPE_35    2

// Max tracks: 160 quarter-tracks for 5.25" or 160 tracks (80 per side) for 3.5"
#define WOZ_MAX_TRACKS      160

// WOZ2 track data starts at offset 1536
#define WOZ_OFFSET_TRACK_DATA_V2  1536

// Error codes
#define WOZ_OK                    0
#define WOZ_ERR_INVALID_HEADER   -1
#define WOZ_ERR_UNSUPPORTED_VER  -2
#define WOZ_ERR_READ_ERROR       -3
#define WOZ_ERR_INVALID_CHUNK    -4

/**
 * @brief Single track data from WOZ image
 */
struct WOZTrack {
    uint32_t bit_count;              // Total bits in track
    uint32_t byte_count;             // Bytes needed to store bits
    std::vector<uint8_t> bits;       // Packed bits (8 per byte, MSB first)
    bool initialized;                // Track has data

    WOZTrack() : bit_count(0), byte_count(0), initialized(false) {}
};

/**
 * @brief Complete WOZ disk image
 */
struct WOZDisk {
    // From INFO chunk
    uint8_t version;                 // WOZ version (1 or 2)
    uint8_t disk_type;               // 1=5.25", 2=3.5"
    uint8_t bit_timing;              // Bit timing in 125ns units (32=4µs, 16=2µs)
    bool write_protected;
    bool double_sided;
    bool synchronized;
    bool cleaned;
    char creator[33];                // Creator string (32 chars + null)

    // Derived values
    uint32_t bit_timing_ns;          // Bit timing in nanoseconds
    uint32_t max_track_size_bytes;   // Maximum track size

    // Track map (quarter-track index -> track data index, 0xFF = empty)
    uint8_t tmap[WOZ_MAX_TRACKS];

    // Track data
    WOZTrack tracks[WOZ_MAX_TRACKS];
    uint8_t track_count;             // Number of valid tracks

    // Status
    bool loaded;

    WOZDisk() : version(0), disk_type(0), bit_timing(0),
                write_protected(false), double_sided(false),
                synchronized(false), cleaned(false),
                bit_timing_ns(0), max_track_size_bytes(0),
                track_count(0), loaded(false) {
        memset(creator, 0, sizeof(creator));
        memset(tmap, 0xFF, sizeof(tmap));
    }
};

/**
 * @brief Buffer iterator for reading WOZ data
 */
class WOZReader {
private:
    const uint8_t* cur;
    const uint8_t* end;

public:
    WOZReader(const uint8_t* data, size_t size)
        : cur(data), end(data + size) {}

    bool has_bytes(size_t n) const { return cur + n <= end; }
    size_t remaining() const { return end - cur; }

    uint8_t read_u8() {
        if (cur >= end) return 0xFF;
        return *cur++;
    }

    uint16_t read_u16() {
        if (cur + 2 > end) return 0xFFFF;
        uint16_t v = cur[0] | (cur[1] << 8);  // Little-endian
        cur += 2;
        return v;
    }

    uint32_t read_u32() {
        if (cur + 4 > end) return 0xFFFFFFFF;
        uint32_t v = cur[0] | (cur[1] << 8) | (cur[2] << 16) | (cur[3] << 24);
        cur += 4;
        return v;
    }

    void read_bytes(uint8_t* buf, size_t len) {
        size_t avail = (cur + len <= end) ? len : (end - cur);
        memcpy(buf, cur, avail);
        cur += avail;
    }

    void skip(size_t n) {
        cur += n;
        if (cur > end) cur = end;
    }

    const uint8_t* ptr() const { return cur; }
};

/**
 * @brief Load a WOZ file from disk
 *
 * @param filename Path to WOZ file
 * @param disk Output disk structure
 * @return Error code (WOZ_OK on success)
 */
inline int woz_load(const char* filename, WOZDisk* disk) {
    // Read entire file into memory
    FILE* f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "WOZ: Failed to open %s\n", filename);
        return WOZ_ERR_READ_ERROR;
    }

    fseek(f, 0, SEEK_END);
    size_t file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    std::vector<uint8_t> data(file_size);
    if (fread(data.data(), 1, file_size, f) != file_size) {
        fclose(f);
        fprintf(stderr, "WOZ: Failed to read %s\n", filename);
        return WOZ_ERR_READ_ERROR;
    }
    fclose(f);

    // Parse WOZ header
    WOZReader reader(data.data(), data.size());

    // Check signature: "WOZ1" or "WOZ2"
    if (!reader.has_bytes(12)) return WOZ_ERR_INVALID_HEADER;

    uint8_t sig[4];
    reader.read_bytes(sig, 4);
    if (memcmp(sig, "WOZ", 3) != 0) {
        fprintf(stderr, "WOZ: Invalid signature\n");
        return WOZ_ERR_INVALID_HEADER;
    }

    uint8_t woz_version = sig[3] - '0';
    if (woz_version < 1 || woz_version > 2) {
        fprintf(stderr, "WOZ: Unsupported version %d\n", woz_version);
        return WOZ_ERR_UNSUPPORTED_VER;
    }

    // Check high-bit, LF, CR, LF sequence
    if (reader.read_u8() != 0xFF) return WOZ_ERR_INVALID_HEADER;
    if (reader.read_u8() != 0x0A) return WOZ_ERR_INVALID_HEADER;
    if (reader.read_u8() != 0x0D) return WOZ_ERR_INVALID_HEADER;
    if (reader.read_u8() != 0x0A) return WOZ_ERR_INVALID_HEADER;

    // CRC32 (skip for now)
    reader.skip(4);

    // Parse chunks
    bool have_info = false;
    bool have_tmap = false;
    bool have_trks = false;

    while (reader.has_bytes(8)) {
        uint8_t chunk_id[4];
        reader.read_bytes(chunk_id, 4);
        uint32_t chunk_size = reader.read_u32();

        if (!reader.has_bytes(chunk_size)) {
            fprintf(stderr, "WOZ: Truncated chunk\n");
            break;
        }

        const uint8_t* chunk_start = reader.ptr();

        // INFO chunk
        if (memcmp(chunk_id, "INFO", 4) == 0) {
            disk->version = reader.read_u8();
            disk->disk_type = reader.read_u8();
            disk->write_protected = reader.read_u8() != 0;
            disk->synchronized = reader.read_u8() != 0;
            disk->cleaned = reader.read_u8() != 0;
            reader.read_bytes((uint8_t*)disk->creator, 32);
            disk->creator[32] = '\0';

            if (disk->version >= 2) {
                disk->double_sided = (reader.read_u8() == 2);
                reader.skip(1);  // boot_type
                disk->bit_timing = reader.read_u8();
                reader.skip(2);  // compatibility flags
                reader.skip(2);  // required_ram_kb
                disk->max_track_size_bytes = reader.read_u16() * 512;
            } else {
                // WOZ 1 defaults
                if (disk->disk_type == WOZ_DISK_TYPE_525) {
                    disk->bit_timing = 32;  // 4µs
                    disk->max_track_size_bytes = 6646;
                } else {
                    disk->bit_timing = 16;  // 2µs
                    disk->max_track_size_bytes = 9830;
                }
            }

            disk->bit_timing_ns = disk->bit_timing * 125;
            have_info = true;

            printf("WOZ: INFO - version=%d disk_type=%d bit_timing=%d (%dns) creator=\"%s\"\n",
                   disk->version, disk->disk_type, disk->bit_timing,
                   disk->bit_timing_ns, disk->creator);
        }
        // TMAP chunk
        else if (memcmp(chunk_id, "TMAP", 4) == 0) {
            for (int i = 0; i < WOZ_MAX_TRACKS && reader.ptr() < chunk_start + chunk_size; i++) {
                disk->tmap[i] = reader.read_u8();
            }
            have_tmap = true;

            // Count valid tracks
            disk->track_count = 0;
            for (int i = 0; i < WOZ_MAX_TRACKS; i++) {
                if (disk->tmap[i] != 0xFF && disk->tmap[i] >= disk->track_count) {
                    disk->track_count = disk->tmap[i] + 1;
                }
            }
            printf("WOZ: TMAP - track_count=%d\n", disk->track_count);
        }
        // TRKS chunk
        else if (memcmp(chunk_id, "TRKS", 4) == 0) {
            if (woz_version == 1) {
                // WOZ 1: track data is inline after TRK entries
                for (int i = 0; i < disk->track_count; i++) {
                    WOZTrack& track = disk->tracks[i];

                    // Read track bits directly
                    track.bits.resize(disk->max_track_size_bytes);
                    reader.read_bytes(track.bits.data(), disk->max_track_size_bytes);
                    track.byte_count = reader.read_u16();
                    track.bit_count = reader.read_u16();
                    reader.skip(6);  // Skip write hints

                    track.bits.resize(track.byte_count);
                    track.initialized = true;
                }
            } else {
                // WOZ 2: TRK entries first, then BITS data at block offsets
                struct TRKEntry {
                    uint16_t starting_block;
                    uint16_t block_count;
                    uint32_t bit_count;
                };

                std::vector<TRKEntry> entries(WOZ_MAX_TRACKS);
                for (int i = 0; i < WOZ_MAX_TRACKS; i++) {
                    entries[i].starting_block = reader.read_u16();
                    entries[i].block_count = reader.read_u16();
                    entries[i].bit_count = reader.read_u32();
                }

                // Now read track bits from their block offsets
                for (int i = 0; i < WOZ_MAX_TRACKS; i++) {
                    if (entries[i].starting_block == 0) continue;

                    WOZTrack& track = disk->tracks[i];
                    track.bit_count = entries[i].bit_count;
                    track.byte_count = entries[i].block_count * 512;

                    // Calculate offset into file
                    size_t offset = entries[i].starting_block * 512;
                    if (offset + track.byte_count <= data.size()) {
                        track.bits.resize(track.byte_count);
                        memcpy(track.bits.data(), data.data() + offset, track.byte_count);
                        track.initialized = true;
                    }
                }
            }
            have_trks = true;

            // Count initialized tracks and display stats
            int init_count = 0;
            for (int i = 0; i < WOZ_MAX_TRACKS; i++) {
                if (disk->tracks[i].initialized) init_count++;
            }
            printf("WOZ: TRKS - %d tracks with data\n", init_count);

            // Print first few track sizes
            printf("WOZ: Track bit counts: ");
            for (int i = 0; i < 5 && i < WOZ_MAX_TRACKS; i++) {
                if (disk->tracks[i].initialized) {
                    printf("T%d=%u ", i, disk->tracks[i].bit_count);
                }
            }
            printf("...\n");
        }
        // Skip unknown chunks
        else {
            printf("WOZ: Skipping chunk '%.4s' (%u bytes)\n", chunk_id, chunk_size);
        }

        // Advance to next chunk
        reader = WOZReader(chunk_start + chunk_size, data.data() + data.size() - (chunk_start + chunk_size));
    }

    if (!have_info || !have_tmap || !have_trks) {
        fprintf(stderr, "WOZ: Missing required chunks (INFO=%d TMAP=%d TRKS=%d)\n",
                have_info, have_tmap, have_trks);
        return WOZ_ERR_INVALID_CHUNK;
    }

    disk->loaded = true;

    printf("WOZ: Successfully loaded %s\n", filename);
    printf("WOZ: Disk type: %s, %s\n",
           disk->disk_type == WOZ_DISK_TYPE_525 ? "5.25\"" : "3.5\"",
           disk->double_sided ? "double-sided" : "single-sided");
    printf("WOZ: Bit timing: %d ns (%s)\n",
           disk->bit_timing_ns,
           disk->bit_timing_ns == 4000 ? "slow/5.25\"" :
           disk->bit_timing_ns == 2000 ? "fast/3.5\"" : "custom");

    return WOZ_OK;
}

/**
 * @brief Get a specific bit from a track
 *
 * @param disk WOZ disk image
 * @param track_idx Track index (from TMAP or direct)
 * @param bit_idx Bit index within track
 * @return Bit value (0 or 1), or -1 if invalid
 */
inline int woz_get_bit(const WOZDisk* disk, int track_idx, uint32_t bit_idx) {
    if (track_idx < 0 || track_idx >= WOZ_MAX_TRACKS) return -1;

    const WOZTrack& track = disk->tracks[track_idx];
    if (!track.initialized) return -1;
    if (bit_idx >= track.bit_count) return -1;

    uint32_t byte_idx = bit_idx >> 3;
    uint8_t bit_mask = 0x80 >> (bit_idx & 7);  // MSB first

    return (track.bits[byte_idx] & bit_mask) ? 1 : 0;
}

/**
 * @brief Get track data for a quarter-track position (5.25") or track (3.5")
 *
 * @param disk WOZ disk image
 * @param qtr_track Quarter-track index (0-159)
 * @return Pointer to track data, or nullptr if no track
 */
inline const WOZTrack* woz_get_track(const WOZDisk* disk, int qtr_track) {
    if (qtr_track < 0 || qtr_track >= WOZ_MAX_TRACKS) return nullptr;

    uint8_t track_idx = disk->tmap[qtr_track];
    if (track_idx == 0xFF) return nullptr;
    if (track_idx >= WOZ_MAX_TRACKS) return nullptr;

    const WOZTrack& track = disk->tracks[track_idx];
    if (!track.initialized) return nullptr;

    return &track;
}

/**
 * @brief Debug: dump track bit pattern
 */
inline void woz_dump_track_bits(const WOZDisk* disk, int track_idx, int start_bit, int num_bits) {
    const WOZTrack* track = woz_get_track(disk, track_idx);
    if (!track) {
        printf("Track %d not found\n", track_idx);
        return;
    }

    printf("Track %d: %u bits, dumping from bit %d:\n", track_idx, track->bit_count, start_bit);
    for (int i = 0; i < num_bits && start_bit + i < (int)track->bit_count; i++) {
        if (i > 0 && (i % 64) == 0) printf("\n");
        else if (i > 0 && (i % 8) == 0) printf(" ");
        printf("%d", woz_get_bit(disk, track_idx, start_bit + i));
    }
    printf("\n");
}

#endif // WOZ_LOADER_H
