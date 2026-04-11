#!/usr/bin/env python3
"""Create blank WOZ2 floppy disk images with all tracks pre-allocated.

Supports both 3.5" and 5.25" disk types. All tracks are allocated with
empty data (0xFF), so the woz_floppy_controller can write back to them
without needing block allocation. Use GS/OS or DOS 3.3/ProDOS to
initialize/format the disk.

Apple 3.5" disks use 5 speed groups with different motor speeds, resulting
in different bit counts per track:
  Group 0 (tracks  0-15): 12 sectors, ~394 RPM → 75976 bits
  Group 1 (tracks 16-31): 11 sectors, ~429 RPM → 69640 bits
  Group 2 (tracks 32-47): 10 sectors, ~472 RPM → 63312 bits
  Group 3 (tracks 48-63):  9 sectors, ~525 RPM → 56992 bits
  Group 4 (tracks 64-79):  8 sectors, ~590 RPM → 50660 bits

Apple 5.25" disks spin at a constant ~300 RPM with a fixed 4µs bit cell,
giving ~51200 bits per track across all 35 tracks.

Usage:
    python3 make_blank_woz.py                      # Create both types
    python3 make_blank_woz.py --type 35             # 3.5" only
    python3 make_blank_woz.py --type 525            # 5.25" only
    python3 make_blank_woz.py --type 35 -o out.woz  # Custom output name
"""

import argparse
import struct
import sys
import zlib

# WOZ2 format constants
WOZ2_SIGNATURE = b'WOZ2'
WOZ2_HEADER_MAGIC = b'\xFF\x0A\x0D\x0A'

# --- 3.5" disk parameters ---

# 80 tracks × 2 sides = 160 TMAP entries
NUM_TRACKS_35 = 160

# Apple 3.5" speed groups: physical_track → (bit_count, blocks_per_track)
SPEED_GROUPS_35 = [
    # (first_track, last_track, sectors, bit_count, blocks_per_track)
    (0,  15, 12, 75976, 19),   # Group 0: 75976 bits = 9497 bytes → 19 blocks
    (16, 31, 11, 69640, 18),   # Group 1: 69640 bits = 8705 bytes → 18 blocks
    (32, 47, 10, 63312, 16),   # Group 2: 63312 bits = 7914 bytes → 16 blocks
    (48, 63,  9, 56992, 14),   # Group 3: 56992 bits = 7124 bytes → 14 blocks
    (64, 79,  8, 50660, 13),   # Group 4: 50660 bits = 6333 bytes → 13 blocks
]

# --- 5.25" disk parameters ---

# 35 whole tracks, quarter-track TMAP has 160 entries
NUM_WHOLE_TRACKS_525 = 35
NUM_TMAP_ENTRIES = 160

# Constant speed: 300 RPM, 4µs bit cell → 51200 bits per track
BITS_PER_TRACK_525 = 51200
BLOCKS_PER_TRACK_525 = 13   # ceil(51200 / 8 / 512) = 13


def get_track_params_35(track_index):
    """Return (bit_count, blocks_per_track) for a 3.5" TMAP track index."""
    physical_track = track_index // 2
    for first, last, _sectors, bit_count, blocks in SPEED_GROUPS_35:
        if first <= physical_track <= last:
            return bit_count, blocks
    return 51200, 13


def make_chunk(chunk_id, chunk_data):
    """Wrap data in a WOZ chunk (4-byte id + 4-byte LE size + data)."""
    return chunk_id + struct.pack('<I', len(chunk_data)) + chunk_data


def make_info_chunk(disk_type, max_blocks):
    """Build the 60-byte INFO chunk data.

    disk_type: 1 = 5.25", 2 = 3.5"
    """
    if disk_type == 2:
        sides = 2
        bit_timing = 16      # 16 × 8ns = 128ns ≈ 125ns per bit cell
        creator = b'MiSTer IIgs Blank 3.5   '
    else:
        sides = 1
        bit_timing = 32      # 32 × 125ns = 4µs per bit cell
        creator = b'MiSTer IIgs Blank 5.25  '

    creator = creator.ljust(32, b' ')[:32]

    data = struct.pack('<BB', 2, disk_type)       # version, disk_type
    data += struct.pack('<B', 0)                   # write_protect
    data += struct.pack('<B', 0)                   # synchronized
    data += struct.pack('<B', 0)                   # cleaned
    data += creator
    data += struct.pack('<B', sides)
    data += struct.pack('<B', 0)                   # boot_sector_format
    data += struct.pack('<B', bit_timing)
    data += struct.pack('<H', 0)                   # compatible_hardware
    data += struct.pack('<H', 0)                   # required_ram
    data += struct.pack('<H', max_blocks)          # largest_track
    data = data.ljust(60, b'\x00')
    return data


# --- 3.5" disk creation ---

def make_tmap_35():
    """Build 160-byte TMAP for 3.5" disk. 1:1 mapping for all 160 tracks."""
    return bytes(range(NUM_TRACKS_35))


def make_trks_35(first_data_block):
    """Build TRKS metadata and track data for 3.5" disk."""
    meta = b''
    track_data = b''
    current_block = first_data_block

    for i in range(NUM_TRACKS_35):
        bit_count, blocks = get_track_params_35(i)
        meta += struct.pack('<HHI', current_block, blocks, bit_count)
        track_data += b'\xFF' * (blocks * 512)
        current_block += blocks

    return meta, track_data


def make_blank_woz_35(filename):
    """Generate a complete blank WOZ2 3.5" disk image."""
    max_blocks = max(blocks for _, _, _, _, blocks in SPEED_GROUPS_35)

    info_data = make_info_chunk(2, max_blocks)
    tmap_data = make_tmap_35()

    # Header(12) + INFO(68) + TMAP(168) + TRKS header(8) + metadata(1280) = 1536
    # 1536 / 512 = block 3
    first_data_block = 3
    trks_meta, track_data = make_trks_35(first_data_block)
    trks_data = trks_meta + track_data

    info_chunk = make_chunk(b'INFO', info_data)
    tmap_chunk = make_chunk(b'TMAP', tmap_data)
    trks_chunk = make_chunk(b'TRKS', trks_data)

    body = info_chunk + tmap_chunk + trks_chunk
    crc = zlib.crc32(body) & 0xFFFFFFFF
    header = WOZ2_SIGNATURE + WOZ2_HEADER_MAGIC + struct.pack('<I', crc)

    with open(filename, 'wb') as f:
        f.write(header)
        f.write(body)

    file_size = 12 + len(body)
    print(f"Created {filename}")
    print(f"  Format: WOZ2 3.5\" double-sided")
    print(f"  Tracks: {NUM_TRACKS_35} (80 x 2 sides)")
    print(f"  Speed groups:")
    for first, last, sectors, bit_count, blocks in SPEED_GROUPS_35:
        print(f"    Tracks {first:2d}-{last:2d}: {sectors:2d} sectors, "
              f"{bit_count} bits, {blocks} blocks ({blocks * 512} bytes)")
    print(f"  Track data starts at block {first_data_block}")
    print(f"  File size: {file_size} bytes ({file_size / 1024:.1f} KB)")
    print(f"  CRC32: 0x{crc:08X}")


# --- 5.25" disk creation ---

def make_tmap_525():
    """Build 160-byte TMAP for 5.25" disk.

    Standard 35 tracks at whole-track positions (every 4th TMAP entry).
    Quarter-track entries adjacent to a whole track point to the same
    TRKS entry (±1 quarter track).  All other entries are 0xFF (no track).
    """
    tmap = bytearray([0xFF] * NUM_TMAP_ENTRIES)
    for t in range(NUM_WHOLE_TRACKS_525):
        trks_index = t
        center = t * 4
        # Map the whole track and its immediate neighbors (±1 quarter track)
        for offset in (-1, 0, 1):
            idx = center + offset
            if 0 <= idx < NUM_TMAP_ENTRIES:
                tmap[idx] = trks_index
    return bytes(tmap)


def make_trks_525(first_data_block):
    """Build TRKS metadata and track data for 5.25" disk."""
    # TRKS metadata is always 160 entries × 8 bytes = 1280 bytes,
    # even though only 35 are used. Unused entries are zeroed.
    meta = b''
    track_data = b''
    current_block = first_data_block

    for t in range(NUM_WHOLE_TRACKS_525):
        meta += struct.pack('<HHI', current_block, BLOCKS_PER_TRACK_525,
                            BITS_PER_TRACK_525)
        track_data += b'\xFF' * (BLOCKS_PER_TRACK_525 * 512)
        current_block += BLOCKS_PER_TRACK_525

    # Pad remaining TRKS entries (35..159) with zeros
    meta += b'\x00' * ((NUM_TMAP_ENTRIES - NUM_WHOLE_TRACKS_525) * 8)

    return meta, track_data


def make_blank_woz_525(filename):
    """Generate a complete blank WOZ2 5.25" disk image."""
    info_data = make_info_chunk(1, BLOCKS_PER_TRACK_525)
    tmap_data = make_tmap_525()

    # Same layout: block 3 for first track data
    first_data_block = 3
    trks_meta, track_data = make_trks_525(first_data_block)
    trks_data = trks_meta + track_data

    info_chunk = make_chunk(b'INFO', info_data)
    tmap_chunk = make_chunk(b'TMAP', tmap_data)
    trks_chunk = make_chunk(b'TRKS', trks_data)

    body = info_chunk + tmap_chunk + trks_chunk
    crc = zlib.crc32(body) & 0xFFFFFFFF
    header = WOZ2_SIGNATURE + WOZ2_HEADER_MAGIC + struct.pack('<I', crc)

    with open(filename, 'wb') as f:
        f.write(header)
        f.write(body)

    file_size = 12 + len(body)
    total_bytes = NUM_WHOLE_TRACKS_525 * BLOCKS_PER_TRACK_525 * 512
    print(f"Created {filename}")
    print(f"  Format: WOZ2 5.25\" single-sided")
    print(f"  Tracks: {NUM_WHOLE_TRACKS_525} (whole tracks, quarter-track TMAP)")
    print(f"  Bits per track: {BITS_PER_TRACK_525} ({BLOCKS_PER_TRACK_525} blocks)")
    print(f"  Track data: {total_bytes} bytes ({total_bytes / 1024:.1f} KB)")
    print(f"  Track data starts at block {first_data_block}")
    print(f"  File size: {file_size} bytes ({file_size / 1024:.1f} KB)")
    print(f"  CRC32: 0x{crc:08X}")


# --- Main ---

def main():
    parser = argparse.ArgumentParser(
        description='Create blank WOZ2 floppy disk images')
    parser.add_argument('--type', choices=['35', '525', 'both'], default='both',
                        help='Disk type: 35 (3.5"), 525 (5.25"), or both (default)')
    parser.add_argument('-o', '--output',
                        help='Output filename (only valid with --type 35 or 525)')
    args = parser.parse_args()

    if args.output and args.type == 'both':
        parser.error('-o/--output cannot be used with --type both')

    if args.type in ('35', 'both'):
        filename = args.output or 'blank_35.woz'
        make_blank_woz_35(filename)

    if args.type in ('525', 'both'):
        if args.type == 'both':
            print()
        filename = args.output or 'blank_525.woz'
        make_blank_woz_525(filename)


if __name__ == '__main__':
    main()
