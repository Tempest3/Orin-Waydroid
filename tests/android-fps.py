#!/usr/bin/env python3
"""Parse android-fps.sh output: dedupe frames by actual-present time (col 2), report FPS + frame-time stats."""
import sys, statistics
pres = set(); period = None
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) == 1 and f[0].isdigit(): period = int(f[0])
    elif len(f) == 3 and f[1].isdigit() and 0 < int(f[1]) < 2**62: pres.add(int(f[1]))
p = sorted(pres)
if len(p) < 3: sys.exit("not enough frames")
dt = [(b - a) / 1e6 for a, b in zip(p, p[1:])]
gaps = [d for d in dt if d < 500]                 # ignore gaps between non-overlapping samples
span = sum(gaps) / 1000
q = sorted(gaps)
print(f"vsync period {period/1e6:.2f} ms" if period else "", f"frames {len(gaps)+1}, covered {span:.1f}s")
print(f"avg FPS {len(gaps)/span:.1f} | frame ms: median {statistics.median(gaps):.1f}, "
      f"p95 {q[int(.95*len(q))-1]:.1f}, p99 {q[int(.99*len(q))-1]:.1f}, max {max(gaps):.1f}")
print(f"frames >33 ms: {sum(d>33.4 for d in gaps)} ({100*sum(d>33.4 for d in gaps)/len(gaps):.1f}%)")
