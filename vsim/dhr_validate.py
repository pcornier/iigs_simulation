import sys
from PIL import Image
# usage: dhr_validate.py <png> <slowram.bin> <active_x0> [rows]
png, ram, x0 = sys.argv[1], sys.argv[2], int(sys.argv[3])
rows = int(sys.argv[4]) if len(sys.argv)>4 else 12
data = open(ram,'rb').read()
im = Image.open(png).convert('RGB'); px = im.load()
Y0 = 18  # PNG y of screen line 0
bad = 0
for r in range(rows):
    base = 0x2000 + 0x400*(r%8) + 0x80*((r//8)%8) + 0x28*(r//64)
    exp = []
    for i in range(40):
        a, m = data[0x10000+base+i], data[base+i]
        for b in range(7): exp.append((a>>b)&1)
        for b in range(7): exp.append((m>>b)&1)
    got = [0 if px[x0+j, Y0+r][0] < 128 else 1 for j in range(560)]  # 1=white
    diffs = [j for j in range(560) if exp[j] != got[j]]
    if diffs:
        bad += 1
        print('row %d: %d wrong px, first at %s' % (r, len(diffs), diffs[:12]))
        s=diffs[0]//14*14
        print('  exp', ''.join(str(x) for x in exp[s:s+28]))
        print('  got', ''.join(str(x) for x in got[s:s+28]))
print('%d/%d rows pixel-perfect' % (rows-bad, rows))
