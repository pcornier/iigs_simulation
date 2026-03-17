#!/usr/bin/env python3
"""Create a blank WOZ2 3.5" floppy disk image with all tracks pre-allocated.

All 160 tracks (80 tracks × 2 sides) are allocated with empty data (0xFF),
so the woz_floppy_controller can write back to them without needing block
allocation. Use GS/OS to initialize/format the disk.

Apple 3.5" disks use 5 speed groups with different motor speeds, resulting
in different bit counts per track:
  Group 0 (tracks  0-15): 12 sectors, ~394 RPM → 75976 bits
  Group 1 (tracks 16-31): 11 sectors, ~429 RPM → 69640 bits
  Group 2 (tracks 32-47): 10 sectors, ~472 RPM → 63312 bits
  Group 3 (tracks 48-63):  9 sectors, ~525 RPM → 56992 bits
  Group 4 (tracks 64-79):  8 sectors, ~590 RPM → 50660 bits

In the simulation, the rotation period = bit_count × 2µs (fixed bit cell time).
Larger bit_count = slower rotation = more data capacity, matching real hardware.

Usage:
    python3 make_blank_woz.py [output.woz]
"""

import struct
import sys
import zlib

# WOZ2 format constants
WOZ2_SIGNATURE = b'WOZ2'
WOZ2_HEADER_MAGIC = b'\xFF\x0A\x0D\x0A'

# 3.5" disk: 80 tracks × 2 sides = 160 TMAP entries
NUM_TRACKS = 160

# Apple 3.5" speed groups: physical_track → (bit_count, blocks_per_track)
# bit_count chosen to provide enough room for the required sectors plus
# inter-sector gaps (~3% margin over minimum).
# blocks_per_track = ceil(bit_count / 8 / 512) to hold all bits.
SPEED_GROUPS = [
    # (first_track, last_track, sectors, bit_count, blocks_per_track)
    # Bit counts derived from real Apple 3.5" disk images (AppleWorks5d1.woz)
    (0,  15, 12, 75976, 19),   # Group 0: 75976 bits = 9497 bytes → 19 blocks
    (16, 31, 11, 69640, 18),   # Group 1: 69640 bits = 8705 bytes → 18 blocks
    (32, 47, 10, 63312, 16),   # Group 2: 63312 bits = 7914 bytes → 16 blocks
    (48, 63,  9, 56992, 14),   # Group 3: 56992 bits = 7124 bytes → 14 blocks
    (64, 79,  8, 50660, 13),   # Group 4: 50660 bits = 6333 bytes → 13 blocks
]


def get_track_params(track_index):
    """Return (bit_count, blocks_per_track) for a given TMAP track index.

    TMAP indices 0-159 map to physical tracks:
      Even indices = side 0 (track_index / 2 = physical track)
      Odd indices = side 1 (track_index / 2 = physical track)
    """
    physical_track = track_index // 2
    for first, last, _sectors, bit_count, blocks in SPEED_GROUPS:
        if first <= physical_track <= last:
            return bit_count, blocks
    # Fallback (shouldn't happen for 0-79)
    return 51200, 13


# INFO chunk (60 bytes)
INFO_VERSION = 2            # WOZ v2
INFO_DISK_TYPE = 2          # 3.5" disk
INFO_WRITE_PROTECT = 0      # Not write protected
INFO_SYNCHRONIZED = 0
INFO_CLEANED = 0
INFO_CREATOR = b'MiSTer IIgs Blank Disk  '  # 32 bytes padded
INFO_SIDES = 2
INFO_BOOT_SECTOR = 0       # Unknown
INFO_BIT_TIMING = 16       # Standard 3.5" (125ns per bit cell → 16 × 8ns)
INFO_COMPATIBLE_HW = 0
INFO_REQUIRED_RAM = 0


def make_info_chunk(max_blocks):
    """Build the 60-byte INFO chunk data."""
    creator = INFO_CREATOR.ljust(32, b' ')[:32]
    data = struct.pack('<BB', INFO_VERSION, INFO_DISK_TYPE)
    data += struct.pack('<B', INFO_WRITE_PROTECT)
    data += struct.pack('<B', INFO_SYNCHRONIZED)
    data += struct.pack('<B', INFO_CLEANED)
    data += creator
    data += struct.pack('<B', INFO_SIDES)
    data += struct.pack('<B', INFO_BOOT_SECTOR)
    data += struct.pack('<B', INFO_BIT_TIMING)
    data += struct.pack('<H', INFO_COMPATIBLE_HW)
    data += struct.pack('<H', INFO_REQUIRED_RAM)
    # WOZ2 has 2 extra bytes (largest_track) at offset 44
    data += struct.pack('<H', max_blocks)
    # Pad to 60 bytes
    data = data.ljust(60, b'\x00')
    return data


def make_tmap_chunk():
    """Build the 160-byte TMAP chunk. Each entry maps to a TRKS index."""
    # Simple 1:1 mapping: TMAP[i] = i for all 160 tracks
    return bytes(range(NUM_TRACKS))


def make_trks_metadata_and_data(first_data_block):
    """Build TRKS metadata and track data with per-group bit counts."""
    meta = b''
    track_data = b''
    current_block = first_data_block

    for i in range(NUM_TRACKS):
        bit_count, blocks = get_track_params(i)
        bytes_per_track = blocks * 512

        meta += struct.pack('<HHI',
                            current_block,      # StartBlock
                            blocks,             # BlockCount
                            bit_count)          # BitCount

        # Track data: all 0xFF (unformatted/blank)
        track_data += b'\xFF' * bytes_per_track
        current_block += blocks

    return meta, track_data


def make_chunk(chunk_id, chunk_data):
    """Wrap data in a WOZ chunk (4-byte id + 4-byte LE size + data)."""
    return chunk_id + struct.pack('<I', len(chunk_data)) + chunk_data


def make_blank_woz(filename):
    """Generate a complete blank WOZ2 3.5" disk image."""
    # Calculate max blocks across all groups for INFO chunk
    max_blocks = max(blocks for _, _, _, _, blocks in SPEED_GROUPS)

    # Build chunks
    info_data = make_info_chunk(max_blocks)
    tmap_data = make_tmap_chunk()

    # Calculate where track data starts
    # Header: 12 bytes
    # INFO chunk: 8 + 60 = 68 bytes → ends at byte 80
    # TMAP chunk: 8 + 160 = 168 bytes → ends at byte 248
    # TRKS chunk header: 8 bytes → at byte 248, data at byte 256
    # TRKS metadata: 1280 bytes → at byte 256, ends at byte 1536
    # Track data starts at byte 1536 = block 3
    first_data_block = 3

    trks_meta, track_data = make_trks_metadata_and_data(first_data_block)
    trks_data = trks_meta + track_data

    # Assemble chunks
    info_chunk = make_chunk(b'INFO', info_data)
    tmap_chunk = make_chunk(b'TMAP', tmap_data)
    trks_chunk = make_chunk(b'TRKS', trks_data)

    # File body (after header)
    body = info_chunk + tmap_chunk + trks_chunk

    # CRC32 of everything after the 12-byte header
    crc = zlib.crc32(body) & 0xFFFFFFFF

    # Build header
    header = WOZ2_SIGNATURE + WOZ2_HEADER_MAGIC + struct.pack('<I', crc)

    # Write file
    with open(filename, 'wb') as f:
        f.write(header)
        f.write(body)

    file_size = 12 + len(body)
    print(f"Created {filename}")
    print(f"  Format: WOZ2 3.5\" double-sided")
    print(f"  Tracks: {NUM_TRACKS} (80 × 2 sides)")
    print(f"  Speed groups:")
    for first, last, sectors, bit_count, blocks in SPEED_GROUPS:
        print(f"    Tracks {first:2d}-{last:2d}: {sectors:2d} sectors, "
              f"{bit_count} bits, {blocks} blocks ({blocks * 512} bytes)")
    print(f"  Track data starts at block {first_data_block}")
    print(f"  File size: {file_size} bytes ({file_size / 1024:.1f} KB)")
    print(f"  CRC32: 0x{crc:08X}")


if __name__ == '__main__':
    output = sys.argv[1] if len(sys.argv) > 1 else 'blank_35.woz'
    make_blank_woz(output)
