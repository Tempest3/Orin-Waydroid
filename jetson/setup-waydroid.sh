#!/usr/bin/env bash
# Install Waydroid (official repo, Ubuntu noble) and initialise it with the LineageOS 20 GAPPS images.
# Run as root while booted into the Waydroid kernel. Leaves Android on software rendering; jetson/gpu.sh
# switches it to the GPU.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
need_root
[ "$(uname -r)" = "$KREL" ] || die "boot the Waydroid kernel first"

say "Kernel features"
grep -q binder /proc/filesystems && ok "binderfs available" || die "no binderfs in this kernel"
ip -6 rule >/dev/null 2>&1 && ok "IPv6 policy routing (Android networking)" || die "ip -6 rule fails (CONFIG_IPV6_MULTIPLE_TABLES missing?)"

if ! command -v waydroid >/dev/null; then
  say "Adding the Waydroid apt repository (repo.waydro.id)"
  curl -fsSL https://repo.waydro.id | bash
  if apt-cache madison waydroid | awk '{print $3}' | grep -q "^$WAYDROID_VERSION"; then
    v=$(apt-cache madison waydroid | awk '{print $3}' | grep "^$WAYDROID_VERSION" | head -1)
    say "Installing waydroid $v (the version the GPU patch is written for)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "waydroid=$v"
    apt-mark hold waydroid >/dev/null && ok "held waydroid at $v (apt-mark unhold waydroid to allow upgrades)"
  else
    warn "waydroid $WAYDROID_VERSION is no longer in the repo; installing the latest (GPU patch may not apply)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y waydroid
  fi
fi
ok "waydroid $(dpkg-query -W -f='${Version}' waydroid)"

if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
  say "Initialising Waydroid with GAPPS images (downloads ~1.5 GB; takes a while)"
  waydroid init -s GAPPS
  # init auto-picks /dev/dri/renderD128 (host1x, no Mesa driver) → SurfaceFlinger never starts.
  # Use software rendering until jetson/gpu.sh switches to the GPU.
  FAKE_TOUCH_APPS=$FAKE_TOUCH_APPS python3 - /var/lib/waydroid/waydroid.cfg <<'PY'
import configparser, os, sys
c = configparser.ConfigParser(); c.optionxform = str; c.read(sys.argv[1])
if not c.has_section("properties"): c.add_section("properties")
c["properties"].update({"ro.hardware.gralloc": "default", "ro.hardware.egl": "swiftshader"})
c["properties"].setdefault("persist.waydroid.fake_touch", os.environ["FAKE_TOUCH_APPS"])
with open(sys.argv[1], "w") as f: c.write(f)
PY
  waydroid upgrade --offline >/dev/null
fi
ok "Waydroid initialised ($(grep -E '^vendor_type' /var/lib/waydroid/waydroid.cfg | cut -d= -f2 | tr -d ' '))"
systemctl enable --now waydroid-container >/dev/null 2>&1 || true
ok "waydroid-container service enabled"
