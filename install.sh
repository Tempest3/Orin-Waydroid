#!/usr/bin/env bash
# orin-waydroid installer — run ON THE JETSON (Orin Nano dev kit, JetPack 7.2 / L4T R39.2).
#
#   sudo ./install.sh              guided install: check → kernel → (reboot) → waydroid → gpu
#   sudo ./install.sh check        preflight checks only (changes nothing)
#   sudo ./install.sh kernel       install the Waydroid kernel as an extra boot entry
#   sudo ./install.sh waydroid     install + initialise Waydroid (LineageOS 20, GAPPS) — needs the new kernel
#   sudo ./install.sh gpu          enable GPU acceleration (NVK + Zink overlay)    | gpu-off: back to software
#   sudo ./install.sh gapps-id     print the Google Services ID to register the device for the Play Store
#        ./install.sh status       show what is installed
#   sudo ./install.sh uninstall    remove everything this script added (stock kernel is never touched)
#
# Options: --from <dir|url>  where release tarballs come from (default: ./dist, then $OW_RELEASE_URL)
#          --make-default    make the Waydroid kernel the default boot entry (stock stays as fallback)
#          --yes             answer yes to prompts
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
STATE=/var/lib/orin-waydroid
FROM=${OW_FROM:-}
MAKE_DEFAULT=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --from) FROM=$2; shift 2;;
    --make-default) MAKE_DEFAULT=1; shift;;
    --yes|-y) export OW_YES=1; shift;;
    -h|--help) sed -n 2,17p "$0"; exit 0;;
    *) args+=("$1"); shift;;
  esac
done
CMD=${args[0]:-guided}
export OW_HERE=$HERE MAKE_DEFAULT

# Fetch a release artifact into $STATE/dl and verify it against SHA256SUMS.
fetch_artifact() {  # fetch_artifact name → prints local path
  local name=$1 dst=$STATE/dl src
  mkdir -p "$dst"
  if [ -z "$FROM" ]; then
    if [ -f "$HERE/dist/$name" ]; then FROM=$HERE/dist
    elif [ -n "${OW_RELEASE_URL:-}" ]; then FROM=$OW_RELEASE_URL
    else die "no release found: put the tarballs in $HERE/dist, or pass --from <dir|url>"; fi
  fi
  case $FROM in
    http://*|https://*)
      curl -fL --retry 3 -o "$dst/SHA256SUMS" "$FROM/SHA256SUMS" >&2
      [ -f "$dst/$name" ] && (cd "$dst" && grep " $name\$" SHA256SUMS | sha256sum -c --status -) ||
        curl -fL --retry 3 -o "$dst/$name" "$FROM/$name" >&2;;
    *) src=$(cd "$FROM" && pwd); cp "$src/SHA256SUMS" "$dst/"; cp "$src/$name" "$dst/";;
  esac
  (cd "$dst" && grep " $name\$" SHA256SUMS | sha256sum -c --status -) || die "checksum mismatch: $name"
  echo "$dst/$name"
}
export -f fetch_artifact 2>/dev/null || true

running_waydroid_kernel() { [ "$(uname -r)" = "$KREL" ]; }

do_guided() {
  need_root
  bash "$HERE/jetson/check.sh"
  if ! running_waydroid_kernel; then
    if [ -f "/lib/modules/$KREL/modules.dep" ] && grep -q "^LABEL waydroid" /boot/extlinux/extlinux.conf; then
      say "Waydroid kernel is installed but not running."
    else
      ask "Install the Waydroid kernel now?" y || exit 0
      do_kernel
    fi
    say "Next: reboot and choose 'waydroid kernel' in the boot menu$([ "$MAKE_DEFAULT" = 1 ] && echo ' (it is now the default)'),"
    say "      then run 'sudo $0' again to continue with Waydroid."
    exit 0
  fi
  command -v waydroid >/dev/null && [ -f /var/lib/waydroid/waydroid.cfg ] || do_waydroid
  do_gpu
  cat <<EOF

${C_B}Done.${C_0} Start Android from your desktop session (not as root):
    waydroid show-full-ui
For the Play Store: after Android has booted once, run 'sudo $0 gapps-id' and follow the instructions.
EOF
}

do_kernel() {
  need_root
  local t; t=$(fetch_artifact "$ART_KERNEL")
  bash "$HERE/jetson/install-kernel.sh" "$t"
}
do_waydroid() { need_root; running_waydroid_kernel || die "boot the Waydroid kernel first (uname -r = $(uname -r))"; bash "$HERE/jetson/setup-waydroid.sh"; }
do_gpu()      { need_root; local t; t=$(fetch_artifact "$ART_MESA"); bash "$HERE/jetson/gpu.sh" apply "$t"; }

mkdir -p "$STATE" 2>/dev/null || true
case $CMD in
  guided)    do_guided;;
  check)     bash "$HERE/jetson/check.sh";;
  kernel)    do_kernel;;
  waydroid)  do_waydroid;;
  gpu)       do_gpu;;
  gpu-off)   need_root; bash "$HERE/jetson/gpu.sh" undo;;
  gapps-id)  need_root; bash "$HERE/jetson/gapps-id.sh";;
  status)    bash "$HERE/jetson/status.sh";;
  uninstall) need_root; bash "$HERE/jetson/uninstall.sh";;
  *) die "unknown command '$CMD' (see $0 --help)";;
esac
