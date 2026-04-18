#!/usr/bin/env python3
"""
woz_detect_13sector.py — scan WOZ files and auto-mark 13-sector disks.

A 13-sector disk uses the pre-DOS-3.3 format. The Apple IIgs cannot boot
13-sector disks directly — they need conversion (MUFFIN, etc). This
tool reads each WOZ file's INFO chunk and flags any disk whose
`boot_sector_format` byte is 2 (13-sector only).

WOZ INFO chunk layout (v2+):
    file offset  0..3   magic "WOZ1"/"WOZ2"
    file offset  12..15 "INFO"
    file offset  16..19 chunk size (little-endian, always 60 for v2+)
    file offset  20     INFO version (>=2 needed for boot_sector_format)
    file offset  21     disk_type (1=5.25", 2=3.5")
    file offset  22     write_protected
    file offset  23     synchronized
    file offset  24     cleaned
    file offset  25..56 creator (32-byte ASCII)
    file offset  57     disk_sides
    file offset  58     boot_sector_format
                          0 = unknown
                          1 = 16-sector (DOS 3.3 / ProDOS)  ← IIgs-native
                          2 = 13-sector (DOS 3.2.1 or earlier)  ← flagged
                          3 = both 16- and 13-sector capable
    file offset  59     optimal_bit_timing

Output modes:
    default (dry run)   print findings, touch nothing
    --apply             append new entries to woz_report/triage.csv
                        with label=13_sector (never overwrites existing
                        rows — your manual triage is safe)

The review.html UI will pick these up on its next reload via the
embedded-triage seed path; run ./woz_review.sh afterwards to refresh
the HTML.
"""

import argparse
import csv
import datetime
import os
import sys


BOOT_FORMAT_UNKNOWN = 0
BOOT_FORMAT_16 = 1
BOOT_FORMAT_13 = 2
BOOT_FORMAT_BOTH = 3


def detect_woz(path):
    """Return (info_version, disk_type, boot_sector_format) or None if not a WOZ."""
    try:
        with open(path, 'rb') as f:
            head = f.read(64)
    except OSError:
        return None
    if len(head) < 64:
        return None
    if head[:4] not in (b'WOZ1', b'WOZ2'):
        return None
    if head[12:16] != b'INFO':
        return None
    info_version = head[20]
    disk_type = head[21]
    # boot_sector_format is only defined for INFO v2+
    if info_version < 2:
        return (info_version, disk_type, None)
    return (info_version, disk_type, head[58])


def read_existing_triage(path):
    """Return dict of {woz_path: (label, note, ts)} from a triage.csv."""
    existing = {}
    if not os.path.exists(path):
        return existing
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) >= 2 and row[0]:
                label = row[1] if len(row) > 1 else ''
                note = row[2] if len(row) > 2 else ''
                ts = row[3] if len(row) > 3 else ''
                existing[row[0]] = (label, note, ts)
    return existing


def main():
    ap = argparse.ArgumentParser(
        description='Auto-detect 13-sector WOZ disks.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('--woztest', default='woztest',
                    help='Directory of WOZ files to scan (default: woztest)')
    ap.add_argument('--out', default='woz_report',
                    help='Report directory containing triage.csv (default: woz_report)')
    ap.add_argument('--apply', action='store_true',
                    help='Append new 13-sector entries to triage.csv '
                         '(skips paths already triaged)')
    ap.add_argument('--verbose', '-v', action='store_true',
                    help='Also print info on non-13-sector disks as they are scanned')
    args = ap.parse_args()

    if not os.path.isdir(args.woztest):
        print(f'ERROR: {args.woztest}/ not found', file=sys.stderr)
        sys.exit(1)

    triage_path = os.path.join(args.out, 'triage.csv')
    existing = read_existing_triage(triage_path)
    if args.apply and existing:
        print(f'Existing triage.csv has {len(existing)} entries — '
              f'new auto-entries will skip any already labeled.')

    # Scan every .woz
    found_13 = []
    found_both = []
    scanned = 0
    skipped_v1 = 0
    for root, _dirs, files in os.walk(args.woztest):
        for name in sorted(files):
            if not name.lower().endswith('.woz'):
                continue
            scanned += 1
            path = os.path.join(root, name)
            info = detect_woz(path)
            if info is None:
                if args.verbose:
                    print(f'  [not-woz] {path}')
                continue
            version, disk_type, bsf = info
            if bsf is None:
                skipped_v1 += 1
                if args.verbose:
                    print(f'  [v1 skip] {path}')
                continue
            if bsf == BOOT_FORMAT_13:
                found_13.append(path)
                print(f'  13-SECTOR: {path}')
            elif bsf == BOOT_FORMAT_BOTH:
                # "Both" means the disk boots in either format; IIgs can still
                # handle it via the 16-sector boot, so don't flag it.
                found_both.append(path)
                if args.verbose:
                    print(f'  [both 13+16, ok] {path}')
            elif args.verbose:
                if bsf == BOOT_FORMAT_16:
                    print(f'  [16-sector] {path}')
                elif bsf == BOOT_FORMAT_UNKNOWN:
                    print(f'  [unknown  ] {path}')

    print()
    print(f'Scanned {scanned} .woz files')
    if skipped_v1:
        print(f'  {skipped_v1} WOZ v1 files skipped (no boot_sector_format field)')
    print(f'  13-sector only  : {len(found_13)}')
    print(f'  both 13 + 16    : {len(found_both)}  (kept — IIgs can boot these)')

    if not args.apply:
        print()
        print('Dry run. Re-run with --apply to add these to triage.csv.')
        return

    # --apply: append new entries (skipping any path already present)
    new_rows = [p for p in found_13 if p not in existing]
    if not new_rows:
        print('Nothing new to add — all 13-sector disks already in triage.csv.')
        return

    os.makedirs(args.out, exist_ok=True)
    write_header = not os.path.exists(triage_path) or os.path.getsize(triage_path) == 0
    ts = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    note = 'auto: WOZ INFO boot_sector_format=2 (pre-DOS 3.3)'
    with open(triage_path, 'a', newline='') as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        if write_header:
            writer.writerow(['woz_path', 'label', 'note', 'timestamp'])
        for p in new_rows:
            writer.writerow([p, '13_sector', note, ts])
    print(f'Added {len(new_rows)} entries to {triage_path}')
    print()
    print('Refresh the review with:')
    print(f'  ./woz_review.sh --out {args.out}')
    print('Then reload review.html in your browser.')


if __name__ == '__main__':
    main()
