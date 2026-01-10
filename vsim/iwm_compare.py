#!/usr/bin/env python3
"""
IWM Log Comparison Tool

Compares IWM (Integrated Woz Machine) debugging info between MAME and vsim logs.

Usage:
    python iwm_compare.py mame.log vsim.log [options]

Options:
    --data-only      Show only data reads (not status)
    --limit N        Limit output to first N events
    --start N        Start from event N
    --show-bytes     Show byte-by-byte comparison only
    --motor-on       Only show events after motor is on
    --cpu            Compare CPU instruction sequences at IWM accesses
    --cpu-bytes      Show CPU data reads ($C0EC) with returned byte values
    --status         Compare IWM status/sense line reads
    --flux           Compare bit-level flux decoding (SHIFT operations)
"""

import re
import sys
import argparse
from dataclasses import dataclass
from typing import List, Optional, Tuple

@dataclass
class FluxEvent:
    """Represents a flux decoding event (SHIFT or BYTE_COMPLETE)"""
    source: str  # 'mame' or 'vsim'
    event_type: str  # 'SHIFT', 'BYTE_COMPLETE', 'EDGE', 'START_READ'
    bit: Optional[int] = None  # 0 or 1 for SHIFT events
    rsh_before: Optional[int] = None  # Shift register before
    rsh_after: Optional[int] = None  # Shift register after
    state: Optional[str] = None  # 'EDGE_0' or 'EDGE_1'
    endw: Optional[int] = None  # End of window time
    data: Optional[int] = None  # Completed byte value
    position: Optional[int] = None  # Disk position
    line_num: int = 0

@dataclass
class IWMEvent:
    """Represents an IWM event from either log format"""
    source: str  # 'mame' or 'vsim'
    event_type: str  # 'DATA', 'STATUS', 'MOTOR_ON', 'MOTOR_OFF', 'DEVSEL', 'DISKREG', 'PHASES'
    timestamp: str  # Raw timestamp string
    result: int  # Result/data byte (0-255)
    active: Optional[int] = None  # Motor active flag
    status: Optional[int] = None  # Status register
    mode: Optional[int] = None  # Mode register
    motor: Optional[int] = None  # Motor state
    q6: Optional[int] = None
    q7: Optional[int] = None
    shift_reg: Optional[int] = None  # Shift register value
    extra: Optional[str] = None  # Extra info (floppy type, etc.)
    line_num: int = 0
    # New fields for sense register debugging
    phases: Optional[int] = None  # Phase register value (4 bits)
    m_reg: Optional[int] = None   # Sense register index {sel, phases[2:0]}
    latched: Optional[int] = None # Latched sense register (phases & 7)
    sel: Optional[int] = None     # SEL bit from $C031
    position: Optional[int] = None  # Disk position for flux debugging

def parse_mame_log(filename: str) -> List[IWMEvent]:
    """Parse MAME IWM log entries"""
    events = []

    # Patterns for MAME log lines
    # New format with position: IWM_DATA @<time> pos=<pos>: result=...
    # Old format without position: IWM_DATA @<time>: result=...
    iwm_data_pattern_with_pos = re.compile(
        r'\[:fdc\] IWM_DATA @([^ ]+) pos=(\d+): result=([0-9a-f]{2}) active=(\d) data=([0-9a-f]{2}) status=([0-9a-f]{2}) mode=([0-9a-f]{2}) floppy=(.+)'
    )
    iwm_data_pattern = re.compile(
        r'\[:fdc\] IWM_DATA @([^:]+): result=([0-9a-f]{2}) active=(\d) data=([0-9a-f]{2}) status=([0-9a-f]{2}) mode=([0-9a-f]{2}) floppy=(.+)'
    )
    iwm_status_pattern = re.compile(
        r'\[:fdc\] IWM_STATUS @([^:]+): result=([0-9a-f]{2}) \(bit7_wp=\d bit5_motor=(\d) mode=([0-9a-f]{2}) phases=([0-9a-f]+)\) floppy=(.+)'
    )
    iwm_motor_on_pattern = re.compile(
        r'\[:fdc\] IWM_MOTOR_ON @([^:]+): control=([0-9a-f]{2}) floppy=(.+)'
    )
    iwm_motor_off_pattern = re.compile(
        r'\[:fdc\] IWM_MOTOR_OFF @([^:]+)'
    )
    devsel_pattern = re.compile(
        r'\[:\] DEVSEL (\d): (.+) @(.+)'
    )
    diskreg_pattern = re.compile(
        r'\[:\] DISKREG WR ([0-9a-f]{2})->([0-9a-f]{2}) \((.+)\) @(.+)'
    )

    try:
        with open(filename, 'r', errors='replace') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()

                # IWM_DATA - try new format with position first
                m = iwm_data_pattern_with_pos.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='DATA',
                        timestamp=m.group(1),
                        position=int(m.group(2)),
                        result=int(m.group(3), 16),
                        active=int(m.group(4)),
                        status=int(m.group(6), 16),
                        mode=int(m.group(7), 16),
                        extra=m.group(8),
                        line_num=line_num
                    ))
                    continue

                # IWM_DATA - old format without position
                m = iwm_data_pattern.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='DATA',
                        timestamp=m.group(1),
                        result=int(m.group(2), 16),
                        active=int(m.group(3)),
                        status=int(m.group(5), 16),
                        mode=int(m.group(6), 16),
                        extra=m.group(7),
                        line_num=line_num
                    ))
                    continue

                # IWM_STATUS
                m = iwm_status_pattern.search(line)
                if m:
                    phases_val = int(m.group(5), 16)
                    # Compute m_reg as (phases & 7) - SEL bit not available in MAME log
                    # MAME uses m_reg = (phases & 7) | (sel ? 8 : 0), but we only have phases
                    events.append(IWMEvent(
                        source='mame',
                        event_type='STATUS',
                        timestamp=m.group(1),
                        result=int(m.group(2), 16),
                        motor=int(m.group(3)),
                        mode=int(m.group(4), 16),
                        phases=phases_val,
                        latched=phases_val & 7,  # Lower 3 bits
                        extra=m.group(6),
                        line_num=line_num
                    ))
                    continue

                # IWM_MOTOR_ON
                m = iwm_motor_on_pattern.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='MOTOR_ON',
                        timestamp=m.group(1),
                        result=int(m.group(2), 16),
                        extra=m.group(3),
                        line_num=line_num
                    ))
                    continue

                # IWM_MOTOR_OFF
                m = iwm_motor_off_pattern.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='MOTOR_OFF',
                        timestamp=m.group(1),
                        result=0,
                        line_num=line_num
                    ))
                    continue

                # DEVSEL
                m = devsel_pattern.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='DEVSEL',
                        timestamp=m.group(3),
                        result=int(m.group(1)),
                        extra=m.group(2),
                        line_num=line_num
                    ))
                    continue

                # DISKREG
                m = diskreg_pattern.search(line)
                if m:
                    events.append(IWMEvent(
                        source='mame',
                        event_type='DISKREG',
                        timestamp=m.group(4),
                        result=int(m.group(2), 16),
                        extra=f"{m.group(1)}->{m.group(2)} ({m.group(3)})",
                        line_num=line_num
                    ))
                    continue

    except FileNotFoundError:
        print(f"Error: Could not open {filename}", file=sys.stderr)
        sys.exit(1)

    return events

def parse_vsim_log(filename: str) -> List[IWMEvent]:
    """Parse vsim IWM log entries"""
    events = []

    # Patterns for vsim log lines
    # New format with position: IWM_FLUX: READ DATA @1 -> ff pos=12345 (motor=0 rsh=00 data=00 bc=0 dr=1 q6=0 q7=0)
    # Old format: IWM_FLUX: READ DATA @1 -> ff (motor=0 rsh=00 data=00 bc=0 dr=1 q6=0 q7=0)
    iwm_flux_pattern_with_pos = re.compile(
        r'IWM_FLUX: READ DATA @([0-9a-f]+) -> ([0-9a-f]{2}) pos=(\d+) \(motor=(\d) rsh=([0-9a-f]{2}) data=([0-9a-f]{2}) bc=(\d+) dr=(\d) q6=(\d) q7=(\d)\)'
    )
    iwm_flux_pattern = re.compile(
        r'IWM_FLUX: READ DATA @([0-9a-f]+) -> ([0-9a-f]{2}) \(motor=(\d) rsh=([0-9a-f]{2}) data=([0-9a-f]{2}) bc=(\d+) dr=(\d) q6=(\d) q7=(\d)\)'
    )
    # IWM_WOZ: phases 0000 -> 0001 (is_35=0)
    iwm_phases_pattern = re.compile(
        r'IWM_WOZ: phases ([0-9a-f]+) -> ([0-9a-f]+) \(is_35=(\d)\)'
    )
    # FLUX_DRIVE[0]: Status: motor=0 track_loaded=0 bit_pos=0/0 rotate=0 stopped=0 ratio=0%
    flux_status_pattern = re.compile(
        r'FLUX_DRIVE\[(\d)\]: Status: motor=(\d) track_loaded=(\d) bit_pos=(\d+)/(\d+)'
    )

    try:
        # Handle potential binary content
        with open(filename, 'rb') as f:
            content = f.read()

        # Try to decode, replacing errors
        text = content.decode('utf-8', errors='replace')

        for line_num, line in enumerate(text.split('\n'), 1):
            line = line.strip()

            # IWM_FLUX READ STATUS - three possible formats
            # Newest: IWM_FLUX: READ STATUS @d -> 00 (sense=0 m_reg=0 latched=0 sel=0 phases=0000 is_35=1 motor_active=0 mounted=1)
            # Old: IWM_FLUX: READ STATUS @d -> 00 (sense=0 phases=0000 is_35=1 motor_active=0 mounted=1)
            # Oldest: IWM_FLUX: READ STATUS @e -> af (data_rdy=1 m_data_read=0 phases=0000 is_35=1 motor_active=1 mounted=1)
            status_pattern_newest = re.compile(
                r'IWM_FLUX: READ STATUS @([0-9a-f]+) -> ([0-9a-f]{2}) \(sense=(\d) m_reg=([0-9a-f]+) latched=([0-9a-f]+) sel=(\d) phases=([0-9a-f]+) is_35=(\d) motor_active=(\d) mounted=(\d)\)'
            )
            status_pattern_new = re.compile(
                r'IWM_FLUX: READ STATUS @([0-9a-f]+) -> ([0-9a-f]{2}) \(sense=(\d) phases=([0-9a-f]+) is_35=(\d) motor_active=(\d) mounted=(\d)\)'
            )
            status_pattern_old = re.compile(
                r'IWM_FLUX: READ STATUS @([0-9a-f]+) -> ([0-9a-f]{2}) \(data_rdy=(\d) m_data_read=(\d) phases=([0-9a-f]+) is_35=(\d) motor_active=(\d) mounted=(\d)\)'
            )
            # Try newest format first (with m_reg, latched, sel)
            m = status_pattern_newest.search(line)
            if m:
                phases_val = int(m.group(7), 16)
                events.append(IWMEvent(
                    source='vsim',
                    event_type='STATUS',
                    timestamp=m.group(1),  # register offset (d or e)
                    result=int(m.group(2), 16),  # status value returned
                    active=int(m.group(9)),  # motor_active
                    motor=int(m.group(9)),  # motor_active
                    phases=phases_val,
                    m_reg=int(m.group(4), 16),
                    latched=int(m.group(5), 16),
                    sel=int(m.group(6)),
                    extra=f"sense={m.group(3)} m_reg={m.group(4)} latched={m.group(5)} sel={m.group(6)} phases={m.group(7)} is_35={m.group(8)} mounted={m.group(10)}",
                    line_num=line_num
                ))
                continue
            m = status_pattern_new.search(line)
            if m:
                phases_val = int(m.group(4), 16)
                events.append(IWMEvent(
                    source='vsim',
                    event_type='STATUS',
                    timestamp=m.group(1),  # register offset (d or e)
                    result=int(m.group(2), 16),  # status value returned
                    active=int(m.group(6)),  # motor_active
                    motor=int(m.group(6)),  # motor_active
                    phases=phases_val,
                    latched=phases_val & 7,
                    extra=f"sense={m.group(3)} phases={m.group(4)} is_35={m.group(5)} mounted={m.group(7)}",
                    line_num=line_num
                ))
                continue
            m = status_pattern_old.search(line)
            if m:
                phases_val = int(m.group(5), 16)
                events.append(IWMEvent(
                    source='vsim',
                    event_type='STATUS',
                    timestamp=m.group(1),  # register offset (d or e)
                    result=int(m.group(2), 16),  # status value returned
                    active=int(m.group(7)),  # motor_active
                    motor=int(m.group(7)),  # motor_active
                    phases=phases_val,
                    latched=phases_val & 7,
                    extra=f"data_rdy={m.group(3)} phases={m.group(5)} is_35={m.group(6)} mounted={m.group(8)}",
                    line_num=line_num
                ))
                continue

            # IWM_FLUX READ DATA - try new format with position first
            m = iwm_flux_pattern_with_pos.search(line)
            if m:
                # m.group(6) is the 'data' field - the assembled byte
                assembled_data = int(m.group(6), 16)
                events.append(IWMEvent(
                    source='vsim',
                    event_type='DATA',
                    timestamp=m.group(1),  # phase number
                    result=int(m.group(2), 16),  # what's actually returned
                    position=int(m.group(3)),  # disk position
                    motor=int(m.group(4)),
                    shift_reg=int(m.group(5), 16),
                    status=assembled_data,  # store assembled data in status field
                    q6=int(m.group(9)),
                    q7=int(m.group(10)),
                    line_num=line_num
                ))
                continue

            # IWM_FLUX READ DATA - old format without position
            m = iwm_flux_pattern.search(line)
            if m:
                # m.group(5) is the 'data' field - the assembled byte
                assembled_data = int(m.group(5), 16)
                events.append(IWMEvent(
                    source='vsim',
                    event_type='DATA',
                    timestamp=m.group(1),  # phase number
                    result=int(m.group(2), 16),  # what's actually returned
                    motor=int(m.group(3)),
                    shift_reg=int(m.group(4), 16),
                    status=assembled_data,  # store assembled data in status field
                    q6=int(m.group(8)),
                    q7=int(m.group(9)),
                    line_num=line_num
                ))
                continue

            # IWM_WOZ phases
            m = iwm_phases_pattern.search(line)
            if m:
                events.append(IWMEvent(
                    source='vsim',
                    event_type='PHASES',
                    timestamp='',
                    result=0,
                    extra=f"{m.group(1)}->{m.group(2)} (35={m.group(3)})",
                    line_num=line_num
                ))
                continue

            # FLUX_DRIVE status
            m = flux_status_pattern.search(line)
            if m:
                events.append(IWMEvent(
                    source='vsim',
                    event_type='FLUX_STATUS',
                    timestamp=m.group(1),  # drive number
                    result=0,
                    motor=int(m.group(2)),
                    extra=f"drive{m.group(1)} motor={m.group(2)} loaded={m.group(3)} pos={m.group(4)}/{m.group(5)}",
                    line_num=line_num
                ))
                continue

    except FileNotFoundError:
        print(f"Error: Could not open {filename}", file=sys.stderr)
        sys.exit(1)

    return events

def extract_data_bytes(events: List[IWMEvent], motor_on_only: bool = False) -> List[Tuple[int, int, Optional[int]]]:
    """Extract just the data byte reads (result values with bit 7 set)
    Returns list of (byte_value, line_num, position)"""
    bytes_read = []
    motor_on = not motor_on_only  # Start active if not filtering

    for i, event in enumerate(events):
        if event.event_type == 'MOTOR_ON':
            motor_on = True
        elif event.event_type == 'MOTOR_OFF':
            motor_on = False
        elif event.event_type == 'DATA' and motor_on:
            # For vsim, check motor flag directly
            if event.source == 'vsim' and motor_on_only and event.motor == 0:
                continue
            # Only count valid data bytes (bit 7 set means valid data)
            if event.result & 0x80:
                bytes_read.append((event.result, event.line_num, event.position))

    return bytes_read

def compare_data_streams(mame_events: List[IWMEvent], vsim_events: List[IWMEvent],
                         start: int = 0, limit: int = 0, motor_on_only: bool = False,
                         show_positions: bool = False):
    """Compare the data byte streams between MAME and vsim"""

    mame_bytes = extract_data_bytes(mame_events, motor_on_only)
    vsim_bytes = extract_data_bytes(vsim_events, motor_on_only)

    print(f"\n=== Data Byte Comparison ===")
    print(f"MAME: {len(mame_bytes)} valid data bytes (bit7=1)")
    print(f"vsim: {len(vsim_bytes)} valid data bytes (bit7=1)")
    print()

    if not mame_bytes and not vsim_bytes:
        print("No valid data bytes found in either log.")
        return

    # Show the bytes side by side
    max_len = max(len(mame_bytes), len(vsim_bytes))
    if limit > 0:
        max_len = min(max_len, start + limit)

    if show_positions:
        # Show positions - MAME uses 0-200M, vsim uses bit position
        print(f"{'Idx':>6}  {'MAME':>6} {'MAMEpos':>12} {'Line':>8}  {'vsim':>6} {'vsimPos':>8} {'Line':>8}  {'Match':>6}")
        print("-" * 90)
    else:
        print(f"{'Idx':>6}  {'MAME':>6} {'Line':>8}  {'vsim':>6} {'Line':>8}  {'Match':>6}")
        print("-" * 60)

    mismatches = 0
    for i in range(start, max_len):
        mame_val = mame_bytes[i] if i < len(mame_bytes) else (None, 0, None)
        vsim_val = vsim_bytes[i] if i < len(vsim_bytes) else (None, 0, None)

        mame_str = f"0x{mame_val[0]:02X}" if mame_val[0] is not None else "----"
        vsim_str = f"0x{vsim_val[0]:02X}" if vsim_val[0] is not None else "----"

        match = ""
        if mame_val[0] is not None and vsim_val[0] is not None:
            if mame_val[0] == vsim_val[0]:
                match = "OK"
            else:
                match = "DIFF"
                mismatches += 1
        elif mame_val[0] is None:
            match = "mame-"
        elif vsim_val[0] is None:
            match = "vsim-"

        if show_positions:
            mame_pos = f"{mame_val[2]:>12}" if mame_val[2] is not None else "----"
            vsim_pos = f"{vsim_val[2]:>8}" if vsim_val[2] is not None else "----"
            print(f"{i:>6}  {mame_str:>6} {mame_pos} {mame_val[1]:>8}  {vsim_str:>6} {vsim_pos} {vsim_val[1]:>8}  {match:>6}")
        else:
            print(f"{i:>6}  {mame_str:>6} {mame_val[1]:>8}  {vsim_str:>6} {vsim_val[1]:>8}  {match:>6}")

    if show_positions:
        print("-" * 90)
    else:
        print("-" * 60)
    print(f"Total compared: {max_len - start}, Mismatches: {mismatches}")

    # If showing positions, also show position conversion info
    if show_positions and mame_bytes and vsim_bytes:
        print(f"\nPosition conversion: MAME uses 0-200M per revolution, vsim uses bit position")
        print(f"For a track with ~75000 bits: MAME_pos / 2666 ≈ vsim_bit_pos")

def show_event_stream(events: List[IWMEvent], source: str, data_only: bool = False,
                      start: int = 0, limit: int = 50):
    """Show a stream of events from one source"""

    print(f"\n=== {source.upper()} Event Stream ===")

    count = 0
    shown = 0

    for event in events:
        if data_only and event.event_type not in ('DATA',):
            continue

        if count < start:
            count += 1
            continue

        if limit > 0 and shown >= limit:
            break

        line = f"[{event.line_num:>7}] {event.event_type:>12}"

        if event.event_type == 'DATA':
            line += f" result=0x{event.result:02X}"
            if event.source == 'mame':
                line += f" active={event.active} status=0x{event.status:02X} mode=0x{event.mode:02X}"
            else:
                line += f" motor={event.motor} q6={event.q6} q7={event.q7} rsh=0x{event.shift_reg:02X}"
        elif event.event_type == 'STATUS':
            line += f" result=0x{event.result:02X} motor={event.motor} mode=0x{event.mode:02X}"
        elif event.event_type in ('MOTOR_ON', 'MOTOR_OFF', 'DEVSEL', 'DISKREG', 'PHASES'):
            if event.extra:
                line += f" {event.extra}"
        elif event.event_type == 'FLUX_STATUS':
            line += f" {event.extra}"

        print(line)
        count += 1
        shown += 1

    print(f"\nShowed {shown} events")

def find_first_valid_data(events: List[IWMEvent]) -> int:
    """Find index of first valid data read (bit 7 set)"""
    motor_on = False
    for i, event in enumerate(events):
        if event.event_type == 'MOTOR_ON':
            motor_on = True
        if event.event_type == 'DATA' and motor_on and (event.result & 0x80):
            return i
    return -1

def find_sector_headers(events: List[IWMEvent], source: str) -> List[Tuple[int, List[int]]]:
    """Find GCR sector headers (D5 AA 96) in the data stream"""
    headers = []
    bytes_list = extract_data_bytes(events)

    for i in range(len(bytes_list) - 2):
        if (bytes_list[i][0] == 0xD5 and
            bytes_list[i+1][0] == 0xAA and
            bytes_list[i+2][0] == 0x96):
            # Found address field header, get next few bytes (track, sector, checksum)
            header_bytes = [b[0] for b in bytes_list[i:min(i+10, len(bytes_list))]]
            headers.append((bytes_list[i][1], header_bytes))

    return headers

def show_sector_headers(mame_events: List[IWMEvent], vsim_events: List[IWMEvent]):
    """Show sector headers found in both logs"""
    mame_headers = find_sector_headers(mame_events, 'mame')
    vsim_headers = find_sector_headers(vsim_events, 'vsim')

    print(f"\n=== GCR Sector Headers (D5 AA 96) ===")
    print(f"MAME: {len(mame_headers)} headers found")
    print(f"vsim: {len(vsim_headers)} headers found")

    if mame_headers:
        print(f"\nFirst 10 MAME headers:")
        for i, (line, header) in enumerate(mame_headers[:10]):
            hex_str = ' '.join(f'{b:02X}' for b in header)
            print(f"  [{line:>7}] {hex_str}")

    if vsim_headers:
        print(f"\nFirst 10 vsim headers:")
        for i, (line, header) in enumerate(vsim_headers[:10]):
            hex_str = ' '.join(f'{b:02X}' for b in header)
            print(f"  [{line:>7}] {hex_str}")

def find_headers_with_context(events: List[IWMEvent], context_before: int = 5, context_after: int = 15) -> List[Tuple[int, int, List[int], List[int]]]:
    """Find D5 AA 96 headers with context bytes before and after.
    Returns list of (byte_index, line_num, bytes_before, header_and_after)"""
    headers = []
    bytes_list = extract_data_bytes(events)

    for i in range(len(bytes_list) - 2):
        if (bytes_list[i][0] == 0xD5 and
            bytes_list[i+1][0] == 0xAA and
            bytes_list[i+2][0] == 0x96):
            # Found address field header
            before_start = max(0, i - context_before)
            after_end = min(len(bytes_list), i + context_after)

            bytes_before = [b[0] for b in bytes_list[before_start:i]]
            header_and_after = [b[0] for b in bytes_list[i:after_end]]

            headers.append((i, bytes_list[i][1], bytes_before, header_and_after))

    return headers

def compare_headers_detailed(mame_events: List[IWMEvent], vsim_events: List[IWMEvent], limit: int = 10):
    """Detailed comparison of sector headers between MAME and vsim"""
    mame_headers = find_headers_with_context(mame_events)
    vsim_headers = find_headers_with_context(vsim_events)

    print(f"\n=== Detailed Sector Header Comparison (D5 AA 96) ===")
    print(f"MAME: {len(mame_headers)} headers found")
    print(f"vsim: {len(vsim_headers)} headers found")

    if not mame_headers:
        print("No headers found in MAME log!")
        return
    if not vsim_headers:
        print("No headers found in vsim log!")
        return

    # Compare headers side by side
    max_compare = min(limit, len(mame_headers), len(vsim_headers))
    print(f"\nComparing first {max_compare} headers:\n")

    for i in range(max_compare):
        m_idx, m_line, m_before, m_header = mame_headers[i]
        v_idx, v_line, v_before, v_header = vsim_headers[i]

        print(f"=== Header #{i} ===")
        print(f"  MAME: byte_idx={m_idx:>6}, line={m_line}")
        print(f"  vsim: byte_idx={v_idx:>6}, line={v_line}")

        # Show sync bytes before header
        m_sync = ' '.join(f'{b:02X}' for b in m_before[-5:] if m_before)
        v_sync = ' '.join(f'{b:02X}' for b in v_before[-5:] if v_before)
        print(f"  MAME sync (before): {m_sync}")
        print(f"  vsim sync (before): {v_sync}")

        # Show header + data (should be D5 AA 96 + encoded track/sector/checksum)
        m_data = ' '.join(f'{b:02X}' for b in m_header[:15])
        v_data = ' '.join(f'{b:02X}' for b in v_header[:15])
        print(f"  MAME data: {m_data}")
        print(f"  vsim data: {v_data}")

        # Check if header data matches
        match_len = min(len(m_header), len(v_header))
        if m_header[:match_len] == v_header[:match_len]:
            print(f"  Status: MATCH ✓")
        else:
            # Find first difference
            for j in range(match_len):
                if m_header[j] != v_header[j]:
                    print(f"  Status: DIFFER at position {j} (MAME=0x{m_header[j]:02X}, vsim=0x{v_header[j]:02X})")
                    break
        print()

    # Summary: do headers match overall?
    if len(mame_headers) != len(vsim_headers):
        print(f"\nWARNING: Different number of headers ({len(mame_headers)} vs {len(vsim_headers)})")

    # Look for first completely matching header sequence
    print("\nLooking for matching header sequence...")
    for i in range(min(20, len(mame_headers), len(vsim_headers))):
        m_header = mame_headers[i][3][:10]
        v_header = vsim_headers[i][3][:10]
        if m_header == v_header:
            print(f"  Header #{i}: MATCH")
        else:
            print(f"  Header #{i}: DIFFER")
            print(f"    MAME: {' '.join(f'{b:02X}' for b in m_header)}")
            print(f"    vsim: {' '.join(f'{b:02X}' for b in v_header)}")
            break

def parse_flux_events(filename: str, source: str) -> List[FluxEvent]:
    """Parse flux-level debug events (SHIFT, BYTE_COMPLETE) from log file"""
    events = []

    # Patterns for flux events (both MAME and vsim use similar format now)
    # MAME: IWM_FLUX: SHIFT bit=1 rsh=00->01 state=EDGE_1 endw=9311338
    # vsim: IWM_FLUX: SHIFT bit=1 rsh=00->01 state=EDGE_1 endw=12345
    shift_pattern = re.compile(
        r'IWM_FLUX: SHIFT bit=(\d) rsh=([0-9a-f]{2})->([0-9a-f]{2}) state=(EDGE_[01]) endw=(\d+)'
    )

    # MAME: IWM_FLUX: BYTE_COMPLETE_ASYNC data=de pos=50475987 @timestamp
    # vsim: IWM_FLUX: BYTE_COMPLETE_ASYNC data=de pos=12345 @cycle=12345
    byte_complete_pattern = re.compile(
        r'IWM_FLUX: BYTE_COMPLETE_(?:ASYNC|SYNC) data=([0-9a-f]{2}) pos=(\d+)'
    )

    # MAME: IWM_FLUX: EDGE_0->EDGE_1 flux_at=9311331 rsh=00 win=14 half=7
    # vsim: IWM_FLUX: EDGE_0->EDGE_1 flux_at=12345 rsh=00 win=14 half=7
    edge_pattern = re.compile(
        r'IWM_FLUX: EDGE_0->EDGE_1 flux_at=(\d+) rsh=([0-9a-f]{2})'
    )

    # START_READ events
    start_read_pattern = re.compile(
        r'IWM_FLUX: START_READ'
    )

    try:
        with open(filename, 'rb') as f:
            content = f.read().decode('utf-8', errors='replace')

        for line_num, line in enumerate(content.split('\n'), 1):
            # SHIFT events
            m = shift_pattern.search(line)
            if m:
                events.append(FluxEvent(
                    source=source,
                    event_type='SHIFT',
                    bit=int(m.group(1)),
                    rsh_before=int(m.group(2), 16),
                    rsh_after=int(m.group(3), 16),
                    state=m.group(4),
                    endw=int(m.group(5)),
                    line_num=line_num
                ))
                continue

            # BYTE_COMPLETE events
            m = byte_complete_pattern.search(line)
            if m:
                events.append(FluxEvent(
                    source=source,
                    event_type='BYTE_COMPLETE',
                    data=int(m.group(1), 16),
                    position=int(m.group(2)),
                    line_num=line_num
                ))
                continue

            # EDGE events (flux detected)
            m = edge_pattern.search(line)
            if m:
                events.append(FluxEvent(
                    source=source,
                    event_type='EDGE',
                    endw=int(m.group(1)),
                    rsh_before=int(m.group(2), 16),
                    line_num=line_num
                ))
                continue

            # START_READ events
            m = start_read_pattern.search(line)
            if m:
                events.append(FluxEvent(
                    source=source,
                    event_type='START_READ',
                    line_num=line_num
                ))
                continue

    except FileNotFoundError:
        print(f"Error: Could not open {filename}", file=sys.stderr)
        sys.exit(1)

    return events

def compare_flux_events(mame_file: str, vsim_file: str, start: int = 0, limit: int = 100,
                        show_all: bool = False, byte_context: int = 0):
    """Compare flux-level decoding between MAME and vsim"""

    print(f"Parsing MAME flux events from {mame_file}...")
    mame_events = parse_flux_events(mame_file, 'mame')
    print(f"  Found {len(mame_events)} flux events")

    print(f"Parsing vsim flux events from {vsim_file}...")
    vsim_events = parse_flux_events(vsim_file, 'vsim')
    print(f"  Found {len(vsim_events)} flux events")

    # Filter to just SHIFT events for bit-by-bit comparison
    mame_shifts = [e for e in mame_events if e.event_type == 'SHIFT']
    vsim_shifts = [e for e in vsim_events if e.event_type == 'SHIFT']

    mame_bytes = [e for e in mame_events if e.event_type == 'BYTE_COMPLETE']
    vsim_bytes = [e for e in vsim_events if e.event_type == 'BYTE_COMPLETE']

    print(f"\nMAME: {len(mame_shifts)} SHIFT events, {len(mame_bytes)} BYTE_COMPLETE events")
    print(f"vsim: {len(vsim_shifts)} SHIFT events, {len(vsim_bytes)} BYTE_COMPLETE events")

    if not mame_shifts or not vsim_shifts:
        print("No SHIFT events found in one or both logs.")
        return

    # Find the first byte that differs
    print(f"\n=== Byte-level comparison ===")
    print(f"{'#':>4}  {'MAME':>6} {'Line':>10}  {'vsim':>6} {'Line':>10}  {'Match':>6}")
    print("-" * 55)

    max_bytes = min(len(mame_bytes), len(vsim_bytes))
    if limit > 0:
        max_bytes = min(max_bytes, start + limit)

    first_diff_idx = -1
    for i in range(start, max_bytes):
        m_byte = mame_bytes[i]
        v_byte = vsim_bytes[i]

        match = "OK" if m_byte.data == v_byte.data else "DIFF"
        if match == "DIFF" and first_diff_idx < 0:
            first_diff_idx = i

        print(f"{i:>4}  0x{m_byte.data:02X}  {m_byte.line_num:>10}  0x{v_byte.data:02X}  {v_byte.line_num:>10}  {match:>6}")

    print("-" * 55)

    if first_diff_idx >= 0:
        print(f"\nFirst difference at byte #{first_diff_idx}")
        print(f"  MAME: 0x{mame_bytes[first_diff_idx].data:02X} at line {mame_bytes[first_diff_idx].line_num}")
        print(f"  vsim: 0x{vsim_bytes[first_diff_idx].data:02X} at line {vsim_bytes[first_diff_idx].line_num}")

        # Show the bit sequence leading to this byte
        if byte_context > 0 or show_all:
            context_bytes = byte_context if byte_context > 0 else 1
            print(f"\n=== Bit sequence comparison for bytes {max(0, first_diff_idx - context_bytes)} to {first_diff_idx} ===")

            # Find SHIFT events that belong to bytes around the difference
            # We need to count backwards from BYTE_COMPLETE events

            # Build a mapping of byte index to SHIFT events
            def get_shifts_for_byte(shifts, bytes_list, byte_idx):
                """Get the SHIFT events that formed a specific byte"""
                if byte_idx >= len(bytes_list):
                    return []

                byte_line = bytes_list[byte_idx].line_num
                # Find shifts between previous byte and this byte
                prev_line = bytes_list[byte_idx - 1].line_num if byte_idx > 0 else 0

                return [s for s in shifts if prev_line < s.line_num <= byte_line]

            for bidx in range(max(0, first_diff_idx - context_bytes), first_diff_idx + 1):
                mame_byte_shifts = get_shifts_for_byte(mame_shifts, mame_bytes, bidx)
                vsim_byte_shifts = get_shifts_for_byte(vsim_shifts, vsim_bytes, bidx)

                m_byte_val = mame_bytes[bidx].data if bidx < len(mame_bytes) else None
                v_byte_val = vsim_bytes[bidx].data if bidx < len(vsim_bytes) else None

                m_hex = f"0x{m_byte_val:02X}" if m_byte_val is not None else "None"
                v_hex = f"0x{v_byte_val:02X}" if v_byte_val is not None else "None"
                print(f"\n--- Byte #{bidx}: MAME={m_hex}, vsim={v_hex} ---")

                # Show bit sequences side by side
                mame_bits = ''.join([str(s.bit) for s in mame_byte_shifts])
                vsim_bits = ''.join([str(s.bit) for s in vsim_byte_shifts])

                print(f"  MAME bits ({len(mame_byte_shifts)}): {mame_bits}")
                print(f"  vsim bits ({len(vsim_byte_shifts)}): {vsim_bits}")

                # Show detailed shift comparison
                max_shifts = max(len(mame_byte_shifts), len(vsim_byte_shifts))
                if max_shifts > 0 and show_all:
                    print(f"\n  {'#':>3}  {'MAME bit':>8} {'rsh':>10} {'state':>8}  {'vsim bit':>8} {'rsh':>10} {'state':>8}  {'Match':>6}")
                    print("  " + "-" * 80)
                    for si in range(max_shifts):
                        m_shift = mame_byte_shifts[si] if si < len(mame_byte_shifts) else None
                        v_shift = vsim_byte_shifts[si] if si < len(vsim_byte_shifts) else None

                        m_bit = str(m_shift.bit) if m_shift else "-"
                        m_rsh = f"{m_shift.rsh_before:02X}->{m_shift.rsh_after:02X}" if m_shift else "----"
                        m_state = m_shift.state if m_shift else "----"

                        v_bit = str(v_shift.bit) if v_shift else "-"
                        v_rsh = f"{v_shift.rsh_before:02X}->{v_shift.rsh_after:02X}" if v_shift else "----"
                        v_state = v_shift.state if v_shift else "----"

                        match = "OK" if m_shift and v_shift and m_shift.bit == v_shift.bit else "DIFF"
                        print(f"  {si:>3}  {m_bit:>8} {m_rsh:>10} {m_state:>8}  {v_bit:>8} {v_rsh:>10} {v_state:>8}  {match:>6}")
    else:
        print(f"\nAll {max_bytes} bytes match!")

def main():
    parser = argparse.ArgumentParser(description='Compare IWM logs between MAME and vsim')
    parser.add_argument('mame_log', help='MAME log file')
    parser.add_argument('vsim_log', help='vsim log file')
    parser.add_argument('--data-only', action='store_true', help='Show only data reads')
    parser.add_argument('--limit', type=int, default=50, help='Limit output to N events (default: 50)')
    parser.add_argument('--start', type=int, default=0, help='Start from event N')
    parser.add_argument('--show-bytes', action='store_true', help='Show byte-by-byte comparison only')
    parser.add_argument('--motor-on', action='store_true', help='Only show events after motor is on')
    parser.add_argument('--mame-only', action='store_true', help='Only show MAME events')
    parser.add_argument('--vsim-only', action='store_true', help='Only show vsim events')
    parser.add_argument('--summary', action='store_true', help='Show summary statistics only')
    parser.add_argument('--sectors', action='store_true', help='Find and show GCR sector headers')
    parser.add_argument('--headers', action='store_true', help='Detailed D5 AA 96 header comparison with context')
    parser.add_argument('--vsim-bug', action='store_true', help='Show vsim result vs assembled data discrepancy')
    parser.add_argument('--repeats', action='store_true', help='Analyze repeated byte returns (handshake issue)')
    parser.add_argument('--cpu', action='store_true', help='Compare CPU instruction sequences')
    parser.add_argument('--status', action='store_true', help='Compare IWM status/sense line reads')
    parser.add_argument('--status-motor', action='store_true', help='Compare status reads only when motor is on')
    parser.add_argument('--cpu-bytes', action='store_true', help='Show CPU accesses with returned byte values')
    parser.add_argument('--positions', action='store_true', help='Show disk positions in byte comparison')
    parser.add_argument('--flux', action='store_true', help='Compare bit-level flux decoding (SHIFT operations)')
    parser.add_argument('--flux-detail', action='store_true', help='Show detailed bit-by-bit comparison for differing bytes')
    parser.add_argument('--byte-context', type=int, default=2, help='Number of bytes before diff to show in flux mode (default: 2)')

    args = parser.parse_args()

    # Handle --flux mode separately (doesn't need IWMEvent parsing)
    if args.flux:
        compare_flux_events(args.mame_log, args.vsim_log, args.start, args.limit,
                           args.flux_detail, args.byte_context)
        return

    print(f"Loading MAME log: {args.mame_log}")
    mame_events = parse_mame_log(args.mame_log)
    print(f"  Found {len(mame_events)} IWM events")

    print(f"Loading vsim log: {args.vsim_log}")
    vsim_events = parse_vsim_log(args.vsim_log)
    print(f"  Found {len(vsim_events)} IWM events")

    if args.summary:
        # Just show summary
        mame_data = [e for e in mame_events if e.event_type == 'DATA']
        vsim_data = [e for e in vsim_events if e.event_type == 'DATA']
        mame_status = [e for e in mame_events if e.event_type == 'STATUS']

        print(f"\nMAME: {len(mame_data)} DATA, {len(mame_status)} STATUS")
        print(f"vsim: {len(vsim_data)} DATA")

        # Count valid bytes
        mame_valid = sum(1 for e in mame_data if e.result & 0x80)
        vsim_valid = sum(1 for e in vsim_data if e.result & 0x80)
        print(f"\nValid data bytes (bit7=1):")
        print(f"  MAME: {mame_valid}")
        print(f"  vsim: {vsim_valid}")

        # Motor state analysis
        print(f"\n=== Motor State Analysis ===")

        # MAME motor events
        mame_motor_on = [e for e in mame_events if e.event_type == 'MOTOR_ON']
        mame_motor_off = [e for e in mame_events if e.event_type == 'MOTOR_OFF']
        print(f"MAME: {len(mame_motor_on)} MOTOR_ON, {len(mame_motor_off)} MOTOR_OFF events")
        if mame_motor_on:
            print(f"  First MOTOR_ON at line {mame_motor_on[0].line_num}")

        # Count MAME DATA with active=1
        mame_active = sum(1 for e in mame_data if e.active == 1)
        print(f"  DATA with active=1: {mame_active}")

        # vsim motor state from DATA events
        vsim_motor_on = sum(1 for e in vsim_data if e.motor == 1)
        vsim_motor_off = sum(1 for e in vsim_data if e.motor == 0)
        print(f"vsim: DATA with motor=1: {vsim_motor_on}, motor=0: {vsim_motor_off}")

        # Check for non-0xFF data in vsim
        vsim_non_ff = [e for e in vsim_data if e.result != 0xFF]
        print(f"  DATA with result != 0xFF: {len(vsim_non_ff)}")
        if vsim_non_ff[:5]:
            print(f"  First non-FF values: {[f'0x{e.result:02X}' for e in vsim_non_ff[:5]]}")

        return

    if args.sectors:
        show_sector_headers(mame_events, vsim_events)
        return

    if args.headers:
        compare_headers_detailed(mame_events, vsim_events, args.limit if args.limit > 0 else 10)
        return

    if args.vsim_bug:
        # Show vsim events where result != assembled data
        print("\n=== vsim: Result vs Assembled Data Discrepancy ===")
        print("This shows cases where the returned value differs from the assembled GCR byte")
        print("(IWM may be returning shift register instead of assembled data)\n")

        vsim_data = [e for e in vsim_events if e.event_type == 'DATA' and e.motor == 1]
        discrepancies = [(e, e.result, e.status) for e in vsim_data
                         if e.status is not None and e.result != e.status and (e.status & 0x80)]

        print(f"Total DATA events with motor=1: {len(vsim_data)}")
        print(f"Events where result != assembled (and assembled has bit7): {len(discrepancies)}")
        print()

        print(f"{'Line':>8}  {'Returned':>10}  {'Assembled':>10}  {'ShiftReg':>10}  {'Match?':>8}")
        print("-" * 60)

        for i, (event, returned, assembled) in enumerate(discrepancies[:50]):
            match = "OK" if returned == assembled else "WRONG"
            print(f"{event.line_num:>8}  0x{returned:02X}        0x{assembled:02X}          0x{event.shift_reg:02X}          {match}")

        if len(discrepancies) > 50:
            print(f"... and {len(discrepancies) - 50} more")

        return

    if args.repeats:
        print("\n=== Byte Repeat Analysis (Handshake Issue) ===")
        print("Counts how many times each byte is returned consecutively")
        print("(In correct IWM, each read should get a NEW byte)\n")

        # Analyze MAME
        mame_data = [e for e in mame_events if e.event_type == 'DATA' and e.active == 1 and (e.result & 0x80)]
        # Analyze vsim
        vsim_data = [e for e in vsim_events if e.event_type == 'DATA' and e.motor == 1 and (e.result & 0x80)]

        def count_repeats(events):
            if not events:
                return [], 0, 0
            repeats = []
            current_byte = events[0].result
            current_count = 1
            for e in events[1:]:
                if e.result == current_byte:
                    current_count += 1
                else:
                    repeats.append((current_byte, current_count))
                    current_byte = e.result
                    current_count = 1
            repeats.append((current_byte, current_count))
            avg_repeat = sum(r[1] for r in repeats) / len(repeats) if repeats else 0
            max_repeat = max(r[1] for r in repeats) if repeats else 0
            return repeats, avg_repeat, max_repeat

        mame_repeats, mame_avg, mame_max = count_repeats(mame_data)
        vsim_repeats, vsim_avg, vsim_max = count_repeats(vsim_data)

        print(f"MAME: {len(mame_data)} valid reads -> {len(mame_repeats)} unique bytes")
        print(f"  Average repeats per byte: {mame_avg:.1f}")
        print(f"  Max repeats: {mame_max}")

        print(f"\nvsim: {len(vsim_data)} valid reads -> {len(vsim_repeats)} unique bytes")
        print(f"  Average repeats per byte: {vsim_avg:.1f}")
        print(f"  Max repeats: {vsim_max}")

        # Show first few sequences for vsim
        if vsim_repeats:
            print(f"\nFirst 20 vsim byte sequences (byte: repeat_count):")
            for i, (byte, count) in enumerate(vsim_repeats[:20]):
                print(f"  0x{byte:02X}: {count}x", end="")
                if (i + 1) % 5 == 0:
                    print()
            print()

        # Compare: do both have D5 AA 96 sequences?
        def find_header_sequences(repeats):
            """Find D5 AA 96 patterns in the repeat list"""
            headers = []
            for i in range(len(repeats) - 2):
                if repeats[i][0] == 0xD5 and repeats[i+1][0] == 0xAA and repeats[i+2][0] == 0x96:
                    headers.append((i, repeats[i][1], repeats[i+1][1], repeats[i+2][1]))
            return headers

        mame_headers = find_header_sequences(mame_repeats)
        vsim_headers = find_header_sequences(vsim_repeats)

        print(f"\nD5 AA 96 header sequences found:")
        print(f"  MAME: {len(mame_headers)}")
        print(f"  vsim: {len(vsim_headers)}")

        if vsim_headers:
            print(f"\nFirst 5 vsim header sequences (D5 repeats, AA repeats, 96 repeats):")
            for i, (idx, d5_cnt, aa_cnt, s96_cnt) in enumerate(vsim_headers[:5]):
                print(f"  #{i+1}: D5 x{d5_cnt}, AA x{aa_cnt}, 96 x{s96_cnt}")

        return

    if args.cpu:
        print("\n=== CPU Instruction Comparison Around IWM Accesses ===")
        print("Comparing CPU instructions that access IWM registers ($C0Ex)\n")

        # Parse CPU instructions from both logs
        cpu_pattern = re.compile(r'^([0-9A-F]{2}):([0-9A-F]{4}): (.+)$')
        iwm_access_pattern = re.compile(r'\$c0e[0-9a-f]|\$c031|DISKREG', re.IGNORECASE)

        def parse_cpu_with_iwm(filename):
            """Parse CPU instructions and find IWM accesses"""
            instructions = []
            try:
                with open(filename, 'rb') as f:
                    content = f.read().decode('utf-8', errors='replace')
                for line_num, line in enumerate(content.split('\n'), 1):
                    m = cpu_pattern.match(line.strip())
                    if m:
                        bank, addr, instr = m.group(1), m.group(2), m.group(3)
                        is_iwm = bool(iwm_access_pattern.search(instr))
                        instructions.append((line_num, f"{bank}:{addr}", instr, is_iwm))
            except Exception as e:
                print(f"Error parsing {filename}: {e}")
            return instructions

        print("Parsing MAME CPU instructions...")
        mame_cpu = parse_cpu_with_iwm(args.mame_log)
        mame_iwm_instrs = [(ln, addr, instr) for ln, addr, instr, is_iwm in mame_cpu if is_iwm]

        print("Parsing vsim CPU instructions...")
        vsim_cpu = parse_cpu_with_iwm(args.vsim_log)
        vsim_iwm_instrs = [(ln, addr, instr) for ln, addr, instr, is_iwm in vsim_cpu if is_iwm]

        print(f"\nMAME: {len(mame_cpu)} total instructions, {len(mame_iwm_instrs)} IWM accesses")
        print(f"vsim: {len(vsim_cpu)} total instructions, {len(vsim_iwm_instrs)} IWM accesses")

        # Compare IWM access sequences
        # Use --limit (default 50, or 0 for unlimited)
        limit_cmp = args.limit if args.limit > 0 else max(len(mame_iwm_instrs), len(vsim_iwm_instrs))
        max_cmp = min(limit_cmp, len(mame_iwm_instrs), len(vsim_iwm_instrs))
        print(f"\n--- First {max_cmp} IWM accesses comparison ---")
        print(f"{'#':>4}  {'MAME Addr':>10} {'MAME Instr':<30} {'vsim Addr':>10} {'vsim Instr':<30} {'Match':>6}")
        print("-" * 100)
        mismatches = 0
        for i in range(max_cmp):
            m_ln, m_addr, m_instr = mame_iwm_instrs[i]
            v_ln, v_addr, v_instr = vsim_iwm_instrs[i]
            # Normalize instruction for comparison (remove extra spaces, lowercase)
            m_norm = ' '.join(m_instr.lower().split())
            v_norm = ' '.join(v_instr.lower().split())
            match = "OK" if m_addr == v_addr and m_norm == v_norm else ("addr" if m_addr != v_addr else "instr")
            if match != "OK":
                mismatches += 1
            print(f"{i:>4}  {m_addr:>10} {m_instr:<30} {v_addr:>10} {v_instr:<30} {match:>6}")

        print("-" * 100)
        print(f"Compared {max_cmp} accesses, Mismatches: {mismatches}")

        # Find where sequences diverge
        if mismatches > 0:
            print(f"\n--- First divergence point ---")
            for i in range(min(len(mame_iwm_instrs), len(vsim_iwm_instrs))):
                m_ln, m_addr, m_instr = mame_iwm_instrs[i]
                v_ln, v_addr, v_instr = vsim_iwm_instrs[i]
                if m_addr != v_addr or m_instr.lower() != v_instr.lower():
                    print(f"Divergence at IWM access #{i}:")
                    print(f"  MAME line {m_ln}: {m_addr}: {m_instr}")
                    print(f"  vsim line {v_ln}: {v_addr}: {v_instr}")
                    # Show context - 5 instructions before in each
                    print(f"\n  MAME context (5 before):")
                    mame_idx = next((j for j, (ln, a, ins, _) in enumerate(mame_cpu) if ln == m_ln), -1)
                    if mame_idx > 0:
                        for j in range(max(0, mame_idx-5), mame_idx+1):
                            ln, addr, instr, is_iwm = mame_cpu[j]
                            marker = " >>>" if j == mame_idx else "    "
                            print(f"    {marker} {addr}: {instr}")
                    print(f"\n  vsim context (5 before):")
                    vsim_idx = next((j for j, (ln, a, ins, _) in enumerate(vsim_cpu) if ln == v_ln), -1)
                    if vsim_idx > 0:
                        for j in range(max(0, vsim_idx-5), vsim_idx+1):
                            ln, addr, instr, is_iwm = vsim_cpu[j]
                            marker = " >>>" if j == vsim_idx else "    "
                            print(f"    {marker} {addr}: {instr}")
                    break

        return

    if args.status:
        print("\n=== IWM Status/Sense Line Comparison ===")
        print("Compares status register reads (Q6=1, Q7=0) between MAME and vsim")
        print("Bit 7 should reflect sense line status, NOT data_rdy\n")

        # Get status events
        mame_status = [e for e in mame_events if e.event_type == 'STATUS']
        vsim_status = [e for e in vsim_events if e.event_type == 'STATUS']

        print(f"MAME: {len(mame_status)} status reads")
        print(f"vsim: {len(vsim_status)} status reads")

        # Analyze MAME status values
        if mame_status:
            mame_values = {}
            for e in mame_status:
                val = e.result
                mame_values[val] = mame_values.get(val, 0) + 1
            print(f"\nMAME status value distribution:")
            for val, count in sorted(mame_values.items(), key=lambda x: -x[1])[:10]:
                bit7 = "NEG" if val & 0x80 else "pos"
                motor = "motor=1" if val & 0x20 else "motor=0"
                print(f"  0x{val:02X}: {count:>6}x  (bit7={bit7}, {motor})")

        # Analyze vsim status values
        if vsim_status:
            vsim_values = {}
            vsim_extras = {}
            for e in vsim_status:
                val = e.result
                vsim_values[val] = vsim_values.get(val, 0) + 1
                if e.extra and val not in vsim_extras:
                    vsim_extras[val] = e.extra
            print(f"\nvsim status value distribution:")
            for val, count in sorted(vsim_values.items(), key=lambda x: -x[1])[:10]:
                bit7 = "NEG" if val & 0x80 else "pos"
                motor = "motor=1" if val & 0x20 else "motor=0"
                extra = vsim_extras.get(val, "")
                print(f"  0x{val:02X}: {count:>6}x  (bit7={bit7}, {motor}) {extra}")

        # Compare: show first N status reads side by side with sense register info
        print(f"\n--- First 30 status reads comparison (with sense register) ---")
        print(f"{'#':>4}  {'MAME':>6} {'ph':>4} {'latch':>5}  {'vsim':>6} {'m_reg':>5} {'latch':>5} {'sel':>3}  {'Match':>6}")
        print("-" * 75)

        max_cmp = min(30, len(mame_status), len(vsim_status))
        mismatches = 0
        for i in range(max_cmp):
            m_evt = mame_status[i]
            v_evt = vsim_status[i]
            m_val = m_evt.result
            v_val = v_evt.result

            # Get phases/latched values
            m_phases = f"{m_evt.phases:x}" if m_evt.phases is not None else "?"
            m_latched = f"{m_evt.latched:x}" if m_evt.latched is not None else "?"
            v_m_reg = f"{v_evt.m_reg:x}" if v_evt.m_reg is not None else "?"
            v_latched = f"{v_evt.latched:x}" if v_evt.latched is not None else "?"
            v_sel = f"{v_evt.sel}" if v_evt.sel is not None else "?"

            # Check match - now also compare latched values
            if m_val == v_val:
                if m_evt.latched is not None and v_evt.latched is not None and m_evt.latched != v_evt.latched:
                    match = "latch!"
                    mismatches += 1
                else:
                    match = "OK"
            elif (m_val & 0x80) != (v_val & 0x80):
                match = "bit7!"
                mismatches += 1
            else:
                match = "diff"
                mismatches += 1

            print(f"{i:>4}  0x{m_val:02X}  {m_phases:>4} {m_latched:>5}  0x{v_val:02X}  {v_m_reg:>5} {v_latched:>5} {v_sel:>3}  {match:>6}")

        print("-" * 75)
        print(f"Mismatches in first {max_cmp}: {mismatches}")

        # Show bit7 analysis
        mame_bit7_set = sum(1 for e in mame_status if e.result & 0x80)
        vsim_bit7_set = sum(1 for e in vsim_status if e.result & 0x80)
        print(f"\nBit 7 analysis (negative/sense line active):")
        print(f"  MAME: {mame_bit7_set}/{len(mame_status)} ({100*mame_bit7_set/len(mame_status):.1f}%) have bit7=1")
        if vsim_status:
            print(f"  vsim: {vsim_bit7_set}/{len(vsim_status)} ({100*vsim_bit7_set/len(vsim_status):.1f}%) have bit7=1")

        # Check for the specific bug: vsim always returning bit7=1
        if vsim_status and vsim_bit7_set == len(vsim_status):
            print(f"\n*** BUG DETECTED: vsim returns bit7=1 for ALL status reads! ***")
            print(f"    This causes 'bmi' branches to always take error path.")
            print(f"    Fix: Status bit7 should reflect sense line, not data_rdy.")

        return

    if args.status_motor:
        print("\n=== IWM Status Comparison (Motor-On Only) ===")
        print("Compares status reads where motor is active in both logs\n")

        # Filter to motor-on status events only
        mame_status = [e for e in mame_events if e.event_type == 'STATUS' and e.motor == 1]
        vsim_status = [e for e in vsim_events if e.event_type == 'STATUS' and e.motor == 1]

        print(f"MAME: {len(mame_status)} status reads with motor=1")
        print(f"vsim: {len(vsim_status)} status reads with motor=1")

        if not mame_status or not vsim_status:
            print("No motor-on status reads found in one or both logs.")
            return

        # Show value distributions
        print(f"\nMAME status values (motor=1):")
        mame_values = {}
        for e in mame_status:
            mame_values[e.result] = mame_values.get(e.result, 0) + 1
        for val, count in sorted(mame_values.items(), key=lambda x: -x[1])[:10]:
            bit7 = "sense=1" if val & 0x80 else "sense=0"
            print(f"  0x{val:02X}: {count:>6}x  ({bit7})")

        print(f"\nvsim status values (motor=1):")
        vsim_values = {}
        for e in vsim_status:
            vsim_values[e.result] = vsim_values.get(e.result, 0) + 1
        for val, count in sorted(vsim_values.items(), key=lambda x: -x[1])[:10]:
            bit7 = "sense=1" if val & 0x80 else "sense=0"
            m_reg_ex = next((ev.m_reg for ev in vsim_status if ev.result == val and ev.m_reg is not None), None)
            m_reg_str = f" m_reg={m_reg_ex:x}" if m_reg_ex is not None else ""
            print(f"  0x{val:02X}: {count:>6}x  ({bit7}){m_reg_str}")

        # Side-by-side comparison
        limit = min(args.limit, len(mame_status), len(vsim_status))
        print(f"\n--- First {limit} motor-on status reads ---")
        print(f"{'#':>4}  {'MAME':>6} {'ph':>4} {'latch':>5}  {'vsim':>6} {'m_reg':>5} {'latch':>5} {'sel':>3}  {'Match':>6}")
        print("-" * 75)

        mismatches = 0
        for i in range(limit):
            m_evt = mame_status[i]
            v_evt = vsim_status[i]
            m_val = m_evt.result
            v_val = v_evt.result

            m_phases = f"{m_evt.phases:x}" if m_evt.phases is not None else "?"
            m_latched = f"{m_evt.latched:x}" if m_evt.latched is not None else "?"
            v_m_reg = f"{v_evt.m_reg:x}" if v_evt.m_reg is not None else "?"
            v_latched = f"{v_evt.latched:x}" if v_evt.latched is not None else "?"
            v_sel = f"{v_evt.sel}" if v_evt.sel is not None else "?"

            # Determine match status
            if m_val == v_val:
                # Check if latched values match
                if m_evt.latched is not None and v_evt.latched is not None:
                    if m_evt.latched != v_evt.latched:
                        match = "latch!"
                        mismatches += 1
                    else:
                        match = "OK"
                else:
                    match = "OK"
            elif (m_val & 0x80) != (v_val & 0x80):
                match = "bit7!"
                mismatches += 1
            else:
                match = "diff"
                mismatches += 1

            print(f"{i:>4}  0x{m_val:02X}  {m_phases:>4} {m_latched:>5}  0x{v_val:02X}  {v_m_reg:>5} {v_latched:>5} {v_sel:>3}  {match:>6}")

        print("-" * 75)
        print(f"Mismatches in first {limit}: {mismatches}")

        # Analyze the sense line pattern differences
        mame_bit7_pattern = ''.join(['1' if e.result & 0x80 else '0' for e in mame_status[:100]])
        vsim_bit7_pattern = ''.join(['1' if e.result & 0x80 else '0' for e in vsim_status[:100]])
        print(f"\nFirst 100 sense bit patterns (1=sense active, 0=inactive):")
        print(f"  MAME: {mame_bit7_pattern}")
        print(f"  vsim: {vsim_bit7_pattern}")

        return

    if args.cpu_bytes:
        print("\n=== CPU Accesses with Returned Byte Values ===")
        print("Shows each IWM data register read ($C0EC) with the byte returned\n")

        # Parse CPU instructions from both logs
        cpu_pattern = re.compile(r'^([0-9A-F]{2}):([0-9A-F]{4}): (.+)$')
        # Match reads from C0EC (data register) - various instruction forms
        data_read_pattern = re.compile(r'\$c0ec', re.IGNORECASE)

        def parse_cpu_data_reads(filename):
            """Parse CPU instructions that read from C0EC"""
            reads = []
            try:
                with open(filename, 'rb') as f:
                    content = f.read().decode('utf-8', errors='replace')
                for line_num, line in enumerate(content.split('\n'), 1):
                    m = cpu_pattern.match(line.strip())
                    if m:
                        bank, addr, instr = m.group(1), m.group(2), m.group(3)
                        # Check if this is a read from C0EC
                        if data_read_pattern.search(instr):
                            # Also capture if it's a write (sta/stx/sty)
                            is_write = any(instr.lower().startswith(x) for x in ['sta', 'stx', 'sty'])
                            if not is_write:  # Only reads
                                reads.append((line_num, f"{bank}:{addr}", instr))
            except Exception as e:
                print(f"Error parsing {filename}: {e}")
            return reads

        print("Parsing MAME CPU data reads...")
        mame_reads = parse_cpu_data_reads(args.mame_log)

        print("Parsing vsim CPU data reads...")
        vsim_reads = parse_cpu_data_reads(args.vsim_log)

        # Get IWM DATA events to correlate byte values
        mame_data_events = [e for e in mame_events if e.event_type == 'DATA']
        vsim_data_events = [e for e in vsim_events if e.event_type == 'DATA']

        print(f"\nMAME: {len(mame_reads)} data reads, {len(mame_data_events)} DATA events")
        print(f"vsim: {len(vsim_reads)} data reads, {len(vsim_data_events)} DATA events")

        # The CPU reads and DATA events should correspond 1:1
        # Build a mapping from line number to byte value
        def build_byte_map(reads, data_events):
            """Map CPU reads to byte values from nearby DATA events"""
            byte_map = {}
            event_idx = 0
            for read_ln, addr, instr in reads:
                # Find the DATA event closest to this line
                while event_idx < len(data_events) and data_events[event_idx].line_num < read_ln:
                    event_idx += 1
                # Use the event at or just after this line, or the last one before
                if event_idx < len(data_events):
                    byte_map[read_ln] = data_events[event_idx].result
                elif event_idx > 0:
                    byte_map[read_ln] = data_events[event_idx - 1].result
            return byte_map

        mame_byte_map = build_byte_map(mame_reads, mame_data_events)
        vsim_byte_map = build_byte_map(vsim_reads, vsim_data_events)

        # Compare side by side
        limit_cmp = args.limit if args.limit > 0 else max(len(mame_reads), len(vsim_reads))
        max_cmp = min(limit_cmp, len(mame_reads), len(vsim_reads))

        print(f"\n--- First {max_cmp} data register reads with values ---")
        print(f"{'#':>5}  {'MAME Instr':<28} {'Val':>6}  {'vsim Instr':<28} {'Val':>6}  {'Match':>8}")
        print("-" * 100)

        mismatches = 0
        first_mismatch = None
        for i in range(max_cmp):
            m_ln, m_addr, m_instr = mame_reads[i]
            v_ln, v_addr, v_instr = vsim_reads[i]

            m_val = mame_byte_map.get(m_ln)
            v_val = vsim_byte_map.get(v_ln)

            m_val_str = f"0x{m_val:02X}" if m_val is not None else "----"
            v_val_str = f"0x{v_val:02X}" if v_val is not None else "----"

            # Truncate instruction for display
            m_instr_disp = m_instr[:26] if len(m_instr) > 26 else m_instr
            v_instr_disp = v_instr[:26] if len(v_instr) > 26 else v_instr

            # Determine match status
            instr_match = m_instr.lower().split()[0] == v_instr.lower().split()[0]  # Same opcode
            val_match = m_val == v_val if m_val is not None and v_val is not None else True

            if instr_match and val_match:
                match = "OK"
            elif not instr_match:
                match = "INSTR!"
                mismatches += 1
                if first_mismatch is None:
                    first_mismatch = i
            else:
                match = "VAL!"
                mismatches += 1
                if first_mismatch is None:
                    first_mismatch = i

            # Highlight valid bytes (bit7 set)
            m_valid = "*" if m_val is not None and m_val & 0x80 else " "
            v_valid = "*" if v_val is not None and v_val & 0x80 else " "

            print(f"{i:>5}  {m_instr_disp:<28} {m_val_str}{m_valid:<2} {v_instr_disp:<28} {v_val_str}{v_valid:<2} {match:>8}")

        print("-" * 100)
        print(f"Compared {max_cmp} reads, Mismatches: {mismatches}")
        if first_mismatch is not None:
            print(f"First mismatch at read #{first_mismatch}")

        # Show summary of valid data bytes around divergence
        if first_mismatch is not None:
            print(f"\n--- Context around first mismatch (#{first_mismatch}) ---")
            start_ctx = max(0, first_mismatch - 5)
            end_ctx = min(max_cmp, first_mismatch + 10)
            print(f"{'#':>5}  {'MAME Instr':<28} {'Val':>6}  {'vsim Instr':<28} {'Val':>6}  {'Note':>12}")
            print("-" * 100)
            for i in range(start_ctx, end_ctx):
                m_ln, m_addr, m_instr = mame_reads[i]
                v_ln, v_addr, v_instr = vsim_reads[i]
                m_val = mame_byte_map.get(m_ln)
                v_val = vsim_byte_map.get(v_ln)
                m_val_str = f"0x{m_val:02X}" if m_val is not None else "----"
                v_val_str = f"0x{v_val:02X}" if v_val is not None else "----"
                m_instr_disp = m_instr[:26] if len(m_instr) > 26 else m_instr
                v_instr_disp = v_instr[:26] if len(v_instr) > 26 else v_instr
                note = "<<<MISMATCH" if i == first_mismatch else ""
                # Check if MAME has valid sync byte
                if m_val is not None and m_val in (0xD5, 0xAA, 0x96):
                    note += f" sync"
                print(f"{i:>5}  {m_instr_disp:<28} {m_val_str:>6}  {v_instr_disp:<28} {v_val_str:>6}  {note:>12}")

        return

    if args.show_bytes or args.positions:
        compare_data_streams(mame_events, vsim_events, args.start, args.limit, args.motor_on, args.positions)
        return

    if args.mame_only:
        show_event_stream(mame_events, 'mame', args.data_only, args.start, args.limit)
        return

    if args.vsim_only:
        show_event_stream(vsim_events, 'vsim', args.data_only, args.start, args.limit)
        return

    # Default: show both streams
    show_event_stream(mame_events, 'mame', args.data_only, args.start, args.limit)
    show_event_stream(vsim_events, 'vsim', args.data_only, args.start, args.limit)

    # Also show byte comparison
    compare_data_streams(mame_events, vsim_events, 0, 20, args.motor_on)

if __name__ == '__main__':
    main()
