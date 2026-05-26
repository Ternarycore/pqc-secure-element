#!/usr/bin/env python3
"""Convert verilog hex (byte-oriented) to 32-bit word hex for $readmemh."""
import sys

infile = sys.argv[1] if len(sys.argv) > 1 else 'firmware.hex'
outfile = sys.argv[2] if len(sys.argv) > 2 else 'firmware_words.hex'

with open(infile) as f:
    lines = [l.rstrip('\r\n') for l in f if l.strip()]

words = {}
addr = 0
for line in lines:
    if line.startswith('@'):
        addr = int(line[1:], 16)
        continue
    parts = line.split()
    for i, bh in enumerate(parts):
        ba = addr + i
        wa = ba // 4
        bp = ba % 4
        v = int(bh, 16)
        words[wa] = words.get(wa, 0) | (v << (bp * 8))
    addr += len(parts)

sa = sorted(words.keys())
out = []
for i, a in enumerate(sa):
    if i == 0 or a != sa[i - 1] + 1:
        out.append(f'@{a:08X}')
    out.append(f'{words[a]:08X}')

with open(outfile, 'w') as f:
    f.write('\n'.join(out) + '\n')

print(f'{outfile}: {len(words)} words, addr range 0x{sa[0]:X}-0x{sa[-1]:X}')
