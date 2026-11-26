#!/usr/bin/env bash
# Show what orin-waydroid has installed (read-only).
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
say "orin-waydroid $OW_VERSION"
echo "  running kernel:   $(uname -r)$([ "$(uname -r)" = "$KREL" ] && echo '  (Waydroid kernel)')"
[ -f "/lib/modules/$KREL/modules.dep" ] && echo "  installed kernel: $KREL" || echo "  installed kernel: no"
grep -q '^LABEL waydroid' /boot/extlinux/extlinux.conf 2>/dev/null && echo "  boot entry:       waydroid ($(grep -m1 '^DEFAULT' /boot/extlinux/extlinux.conf))" || echo "  boot entry:       none"
if command -v waydroid >/dev/null; then
  echo "  waydroid:         $(dpkg-query -W -f='${Version}' waydroid 2>/dev/null)"
  waydroid status 2>/dev/null | sed 's/^/    /'
  CFG=/var/lib/waydroid/waydroid.cfg
  if [ -f /var/lib/waydroid/overlay/vendor/lib64/hw/vulkan.nouveau.so ] && grep -q 'minigbm_gbm_mesa' "$CFG" 2>/dev/null; then
    echo "  rendering:        GPU (NVK + Zink, $(grep -m1 drm_device "$CFG" | cut -d= -f2 | tr -d ' '))"
  else echo "  rendering:        software / Waydroid default"; fi
else echo "  waydroid:         not installed"; fi
