#!/system/bin/sh
# In Waydroid (sudo waydroid shell -- sh /data/local/tmp/android-fps.sh [seconds] > trace.txt):
# record an atrace "gfx" trace; the host counts the app's frames with android-fps.py.
# Unlike `dumpsys SurfaceFlinger --latency`, tracing does not block SurfaceFlinger (which stalled
# heavy scenes by ~0.5 s per sample).
atrace -t "${1:-10}" -b 16384 gfx 2>/dev/null
