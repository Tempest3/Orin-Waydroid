#!/usr/bin/env bash
# Switch Waydroid to GPU rendering (Mesa NVK on nvgpu + Zink) or back to Waydroid's defaults.
#   jetson/gpu.sh apply <orin-waydroid-mesa-android-*.tar.zst>
#   jetson/gpu.sh undo
# apply: 1) patch Waydroid's LXC setup to pass the Orin GPU nodes into the container
#           (/dev/nvgpu, /dev/nvmap, /dev/host1x-fence, all /dev/dri; permissions) — patches/waydroid/0001
#        2) put our Mesa into the vendor overlay (/var/lib/waydroid/overlay/vendor/lib64)
#        3) waydroid.cfg: render node of the NVIDIA display driver + gralloc/EGL/Vulkan/Mesa properties
#        4) waydroid upgrade --offline + restart the container service
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/lib/common.sh"
need_root
WD=/usr/lib/waydroid
CFG=/var/lib/waydroid/waydroid.cfg
OV=/var/lib/waydroid/overlay/vendor/lib64
PATCH=$HERE/patches/waydroid/0001-nvgpu-nodes-and-perms.patch
FILES="libgallium_dri.so dri_gbm.so libgbm_mesa.so egl/libEGL_mesa.so egl/libGLESv1_CM_mesa.so
egl/libGLESv2_mesa.so hw/vulkan.nouveau.so"

[ -f "$CFG" ] || die "Waydroid is not initialised (run: sudo ./install.sh waydroid)"

stop_session() {
  if ! waydroid status 2>/dev/null | grep -q "Session:.*STOPPED"; then
    say "Stopping the running Waydroid session"
    local u; u=$(waydroid status 2>/dev/null | sed -n 's/^Session user:\s*\([^(]*\).*/\1/p' | tr -d ' ')
    if [ -n "$u" ]; then sudo -u "$u" XDG_RUNTIME_DIR=/run/user/$(id -u "$u") waydroid session stop || true
    else waydroid session stop || true; fi
    for _ in $(seq 1 20); do waydroid status | grep -q "Session:.*STOPPED" && break; sleep 1; done
  fi
}

render_node() {  # render node of the NVIDIA display controller (nv_platform, 13800000.display)
  local n
  for n in /sys/class/drm/renderD*; do
    case $(basename "$(readlink -f "$n/device")") in *.display) echo "/dev/dri/$(basename "$n")"; return;; esac
  done
  die "no render node for the NVIDIA display driver (is nvidia-drm loaded?)"
}

cfg_edit() {  # cfg_edit apply <node> | undo
  python3 - "$CFG" "$@" <<'EOF'
import configparser, sys
path, mode = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser(); c.optionxform = str; c.read(path)
ours = ["ro.hardware.gralloc", "ro.hardware.egl", "ro.hardware.vulkan", "gralloc.gbm.device",
        "debug.mesa.loader.driver.override", "debug.mesa.nvk.on.nvgpu",
        "debug.mesa.nvk.i.want.a.broken.vulkan.driver"]
if not c.has_section("properties"): c.add_section("properties")
p = c["properties"]
if mode == "apply":
    node = sys.argv[3]
    c["waydroid"]["drm_device"] = node
    p.update({"ro.hardware.gralloc": "minigbm_gbm_mesa", "ro.hardware.egl": "mesa",
              "ro.hardware.vulkan": "nouveau", "gralloc.gbm.device": node,
              "debug.mesa.loader.driver.override": "zink", "debug.mesa.nvk.on.nvgpu": "1",
              "debug.mesa.nvk.i.want.a.broken.vulkan.driver": "1"})
else:
    for k in ours: p.pop(k, None)
    c["waydroid"].pop("drm_device", None)
with open(path, "w") as f: c.write(f)
EOF
}

case ${1:-} in
apply)
  TAR=${2:?usage: $0 apply <mesa tarball>}
  stop_session
  if patch -p1 -d "$WD" --dry-run -R -s -f < "$PATCH" >/dev/null 2>&1; then ok "Waydroid GPU patch already applied"
  elif patch -p1 -d "$WD" --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    patch -p1 -d "$WD" --no-backup-if-mismatch -s < "$PATCH"; ok "patched Waydroid ($WD)"
  else die "patches/waydroid/0001 does not apply to waydroid $(dpkg-query -W -f='${Version}' waydroid) (needs $WAYDROID_VERSION)"; fi
  W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
  tar -C "$W" -xf "$TAR"
  for f in $FILES; do [ -f "$W/lib64/$f" ] || die "Mesa tarball lacks lib64/$f"; install -D -m644 "$W/lib64/$f" "$OV/$f"; done
  ok "Mesa ($(head -1 "$W/MESA_VERSION" 2>/dev/null || echo ?), $(sed -n 2p "$W/MESA_VERSION" 2>/dev/null)) installed into $OV"
  [ -f "$CFG.pre-orin-waydroid" ] || cp -a "$CFG" "$CFG.pre-orin-waydroid"
  node=$(render_node); cfg_edit apply "$node"; ok "waydroid.cfg: drm_device=$node + GPU properties"
  waydroid upgrade --offline >/dev/null 2>&1 || waydroid upgrade --offline
  systemctl restart waydroid-container
  ok "GPU acceleration enabled — start Android with: waydroid show-full-ui"
  ;;
undo)
  stop_session
  patch -p1 -d "$WD" --dry-run -R -s -f < "$PATCH" >/dev/null 2>&1 && patch -p1 -d "$WD" -R --no-backup-if-mismatch -s < "$PATCH"
  for f in $FILES; do rm -f "$OV/$f"; done
  cfg_edit undo
  # Without a working GPU driver Android needs software rendering (see docs/TROUBLESHOOTING.md).
  python3 - "$CFG" <<'EOF'
import configparser, sys
c = configparser.ConfigParser(); c.optionxform = str; c.read(sys.argv[1])
if not c.has_section("properties"): c.add_section("properties")
c["properties"].update({"ro.hardware.gralloc": "default", "ro.hardware.egl": "swiftshader"})
with open(sys.argv[1], "w") as f: c.write(f)
EOF
  waydroid upgrade --offline >/dev/null 2>&1 || true
  systemctl restart waydroid-container
  ok "back to software rendering (SwiftShader)"
  ;;
*) die "usage: $0 apply <tarball> | undo";;
esac
