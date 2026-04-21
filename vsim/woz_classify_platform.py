#!/usr/bin/env python3
"""
woz_classify_platform.py — catalog each WOZ file's platform (IIgs / Apple II).

Reads each .woz's INFO chunk and writes woz_report/catalog.csv with one
row per disk:

    woz_path, platform, disk_type, note

platform is:
    iigs    3.5" disk, or 5.25" with "IIgs" in the filename (rare)
    apple2  5.25" disk (default)
    unknown malformed / not a WOZ / WOZ v1 with ambiguous data

The review UI (woz_review.sh) reads catalog.csv to add a Platform filter
row, so you can narrow the browse to just the IIgs titles — or just the
Apple II titles — without hunting through 2000+ rows.

Usage:
    ./woz_classify_platform.py                     Scan and print summary
    ./woz_classify_platform.py --apply             Also write catalog.csv
    ./woz_classify_platform.py --export-iigs FILE  Write paths of IIgs
                                                   titles, one per line,
                                                   ready for --retest
"""
import argparse
import os
import sys


def classify(path):
    """Return (platform, disk_type, note) for a WOZ file."""
    try:
        with open(path, 'rb') as f:
            h = f.read(32)
    except OSError:
        return ('unknown', 0, 'read error')
    if len(h) < 32:
        return ('unknown', 0, 'short file')
    if h[:4] not in (b'WOZ1', b'WOZ2'):
        return ('unknown', 0, 'not a WOZ')
    if h[12:16] != b'INFO':
        return ('unknown', 0, 'no INFO chunk')
    disk_type = h[21]
    fname = os.path.basename(path).lower()
    has_iigs = 'iigs' in fname
    if disk_type == 2:
        return ('iigs', 2, '3.5" disk')
    if disk_type == 1 and has_iigs:
        # Rare: IIgs title on 5.25" (most don't exist, but hedge)
        return ('iigs', 1, '5.25" with IIgs in name')
    if disk_type == 1:
        return ('apple2', 1, '5.25" disk')
    return ('unknown', disk_type, f'disk_type={disk_type}')


def main():
    ap = argparse.ArgumentParser(
        description='Classify WOZ disks by platform (IIgs vs Apple II)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('--woztest', default='woztest',
                    help='Directory of WOZ files (default: woztest)')
    ap.add_argument('--out', default='woz_report',
                    help='Report directory (default: woz_report)')
    ap.add_argument('--apply', action='store_true',
                    help='Write catalog.csv (default: dry run)')
    ap.add_argument('--export-iigs', metavar='FILE',
                    help='Also write IIgs paths to FILE, one per line')
    args = ap.parse_args()

    if not os.path.isdir(args.woztest):
        print(f'ERROR: {args.woztest}/ not found', file=sys.stderr)
        sys.exit(1)

    rows = []
    counts = {'iigs': 0, 'apple2': 0, 'unknown': 0}
    for root, _dirs, files in os.walk(args.woztest):
        for n in sorted(files):
            if not n.lower().endswith('.woz'):
                continue
            path = os.path.join(root, n)
            plat, disk_type, note = classify(path)
            rows.append((path, plat, disk_type, note))
            counts[plat] += 1

    print(f'Scanned {len(rows)} .woz files:')
    print(f'  iigs    {counts["iigs"]:>5}')
    print(f'  apple2  {counts["apple2"]:>5}')
    print(f'  unknown {counts["unknown"]:>5}')

    if args.apply:
        os.makedirs(args.out, exist_ok=True)
        # TSV: paths can contain commas and quotes but never tabs, so tab-
        # delimited is trivially parseable from bash/awk without a CSV lib.
        catalog = os.path.join(args.out, 'catalog.tsv')
        tmp = catalog + '.tmp'
        with open(tmp, 'w') as f:
            f.write('woz_path\tplatform\tdisk_type\tnote\n')
            for p, plat, dt, note in rows:
                f.write(f'{p}\t{plat}\t{dt}\t{note}\n')
        os.rename(tmp, catalog)
        print(f'\nWrote {catalog}')
        # Clean up any stale catalog.csv from an earlier version
        legacy = os.path.join(args.out, 'catalog.csv')
        if os.path.exists(legacy):
            os.remove(legacy)
            print(f'Removed stale {legacy}')

    if args.export_iigs:
        iigs = [r[0] for r in rows if r[1] == 'iigs']
        with open(args.export_iigs, 'w') as f:
            for p in iigs:
                f.write(p + '\n')
        print(f'\nWrote {len(iigs)} IIgs paths to {args.export_iigs}')
        print('Run them at higher frame count:')
        print(f'  ./test_woz_batch.sh --retest {args.export_iigs} --frames 5000 --jobs 10')


if __name__ == '__main__':
    main()
