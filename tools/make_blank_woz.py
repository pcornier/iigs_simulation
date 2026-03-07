#!/usr/bin/env python3
"""Create a blank WOZ2 3.5" floppy disk image with all tracks pre-allocated.

All 160 tracks (80 tracks × 2 sides) are allocated with empty data (0xFF),
so the woz_floppy_controller can write back to them without needing block
allocation. Use GS/OS to initialize/format the disk.

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
BLOCKS_PER_TRACK = 13       # 13 × 512 = 6656 bytes per track
BYTES_PER_TRACK = BLOCKS_PER_TRACK * 512
BITS_PER_TRACK = 51200      # Standard 3.5" Apple track bit count

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


def make_info_chunk():
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
    data += struct.pack('<H', BLOCKS_PER_TRACK)
    # Pad to 60 bytes
    data = data.ljust(60, b'\x00')
    return data


def make_tmap_chunk():
    """Build the 160-byte TMAP chunk. Each entry maps to a TRKS index."""
    # Simple 1:1 mapping: TMAP[i] = i for all 160 tracks
    return bytes(range(NUM_TRACKS))


def make_trks_metadata(first_data_block):
    """Build the 1280-byte TRKS metadata (160 × 8-byte entries)."""
    data = b''
    for i in range(NUM_TRACKS):
        start_block = first_data_block + i * BLOCKS_PER_TRACK
        data += struct.pack('<HHI',
                            start_block,        # StartBlock
                            BLOCKS_PER_TRACK,   # BlockCount
                            BITS_PER_TRACK)     # BitCount
    return data


def make_chunk(chunk_id, chunk_data):
    """Wrap data in a WOZ chunk (4-byte id + 4-byte LE size + data)."""
    return chunk_id + struct.pack('<I', len(chunk_data)) + chunk_data


def make_blank_woz(filename):
    """Generate a complete blank WOZ2 3.5" disk image."""
    # Build chunks
    info_data = make_info_chunk()
    tmap_data = make_tmap_chunk()

    # Calculate where track data starts
    # Header: 12 bytes
    # INFO chunk: 8 + 60 = 68 bytes → ends at byte 80
    # TMAP chunk: 8 + 160 = 168 bytes → ends at byte 248
    # TRKS chunk header: 8 bytes → at byte 248, data at byte 256
    # TRKS metadata: 1280 bytes → at byte 256, ends at byte 1536
    # Track data starts at byte 1536 = block 3
    first_data_block = 3

    trks_meta = make_trks_metadata(first_data_block)
    # Track data: all 0xFF (unformatted/blank)
    track_data = b'\xFF' * (NUM_TRACKS * BYTES_PER_TRACK)
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
    print(f"  Blocks per track: {BLOCKS_PER_TRACK} ({BYTES_PER_TRACK} bytes)")
    print(f"  Bits per track: {BITS_PER_TRACK}")
    print(f"  Track data starts at block {first_data_block}")
    print(f"  File size: {file_size} bytes ({file_size / 1024:.1f} KB)")
    print(f"  CRC32: 0x{crc:08X}")


if __name__ == '__main__':
    output = sys.argv[1] if len(sys.argv) > 1 else 'blank_35.woz'
    make_blank_woz(output)
