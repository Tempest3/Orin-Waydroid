#!/usr/bin/env python3
"""android-fps.py <trace.txt> [app-substring]: FPS + frame-time stats from an android-fps.sh trace.

One frame = one BLASTBufferQueue "onFrameAvailable - <layer>" mark (emitted once per queued frame, GL or
Vulkan). Without app-substring the layer with the most frames is used."""
import collections, re, statistics, sys
rx = re.compile(r'\s(\d+\.\d+): tracing_mark_write: B\|\d+\|onFrameAvailable - (.+?)(#\d+)?(\(f:.*)?$')
frames = collections.defaultdict(list)
for line in open(sys.argv[1], errors="ignore"):
    m = rx.search(line.rstrip())
    if m: frames[m.group(2)].append(float(m.group(1)))
if not frames: sys.exit("no frames in trace (is the app in the foreground?)")
want = sys.argv[2] if len(sys.argv) > 2 else None
layer = max((k for k in frames if not want or want in k), key=lambda k: len(frames[k]), default=None)
if not layer: sys.exit(f"no layer matching {want!r}: {sorted(frames)}")
t = sorted(frames[layer])
if len(t) < 3: sys.exit("not enough frames")
dt = [(b - a) * 1e3 for a, b in zip(t, t[1:])]
span = t[-1] - t[0]
q = sorted(dt)
print(f"layer {layer}: frames {len(t)}, covered {span:.1f}s")
print(f"avg FPS {len(dt)/span:.1f} | frame ms: median {statistics.median(dt):.1f}, "
      f"p95 {q[int(.95*len(q))-1]:.1f}, p99 {q[int(.99*len(q))-1]:.1f}, max {max(dt):.1f}")
print(f"frames >33 ms: {sum(d>33.4 for d in dt)} ({100*sum(d>33.4 for d in dt)/len(dt):.1f}%)")
