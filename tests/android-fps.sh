#!/system/bin/sh
# In Waydroid (sudo waydroid shell -- sh /data/local/tmp/android-fps.sh "<layer>" [samples]):
# dump SurfaceFlinger --latency for <layer> every 1.5 s (buffer holds 127 frames); host parses with android-fps.py.
L="$1"; N=${2:-20}
i=0; while [ $i -lt $N ]; do
  echo "== sample $i"; dumpsys SurfaceFlinger --latency "$L"; sleep 1.5; i=$((i+1)); done
