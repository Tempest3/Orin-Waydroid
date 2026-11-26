#!/usr/bin/env bash
# Remove what orin-waydroid installed. Never touches the stock kernel, initrd or 'primary' entry.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/lib/common.sh"
need_root
[ "$(uname -r)" = "$KREL" ] && die "you are running the Waydroid kernel — reboot into 'primary' first"
if [ -f /var/lib/waydroid/waydroid.cfg ]; then
  bash "$HERE/jetson/gpu.sh" undo || true
fi
if command -v waydroid >/dev/null && ask "Also remove Waydroid and ALL Android data (apps, accounts, images)?" n; then
  waydroid session stop 2>/dev/null || true
  systemctl disable --now waydroid-container 2>/dev/null || true
  apt-mark unhold waydroid >/dev/null 2>&1 || true
  apt-get remove -y waydroid
  rm -rf /var/lib/waydroid /home/*/.local/share/waydroid
  ok "Waydroid removed"
fi
EXT=/boot/extlinux/extlinux.conf
cp -a "$EXT" "$EXT.orin-waydroid-uninstall.bak"
python3 "$HERE/lib/extlinux.py" remove "$EXT.orin-waydroid-uninstall.bak" "$EXT"
grep -q '^LABEL primary' "$EXT" || { cp -a "$EXT.orin-waydroid-uninstall.bak" "$EXT"; die "extlinux edit failed; restored"; }
rm -f /boot/Image-waydroid /boot/initrd-waydroid
rm -rf "/lib/modules/$KREL" /var/lib/orin-waydroid
ok "Waydroid kernel and boot entry removed (backup: $EXT.orin-waydroid-uninstall.bak)"
