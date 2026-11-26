#!/usr/bin/env bash
# Preflight checks (read-only). Exit 1 if the system is not supported.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
fail=0
bad() { warn "$*"; fail=1; }

say "Checking this system"
model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)
case $model in
  *"Orin Nano"*) ok "board: $model";;
  *Orin*) warn "board: $model — only the Orin Nano dev kit is tested; other Orin modules may work";;
  *) bad "board: $model — this needs an NVIDIA Jetson Orin (Nano)";;
esac
rel=$(head -1 /etc/nv_tegra_release 2>/dev/null || true)
[[ $rel == *"$L4T_TAG"* ]] && ok "L4T R39.2 (JetPack 7.2)" ||
  bad "L4T: '${rel:-none}' — need JetPack 7.2 (L4T R39.2). Other releases need a matching kernel build."
kr=$(uname -r)
case $kr in
  "$KREL_STOCK"|"$KREL") ok "kernel $kr";;
  *) bad "kernel $kr — expected $KREL_STOCK (stock) or $KREL";;
esac
[ -f /boot/extlinux/extlinux.conf ] && grep -q '^LABEL primary' /boot/extlinux/extlinux.conf &&
  ok "extlinux.conf with 'primary' entry" || bad "/boot/extlinux/extlinux.conf without LABEL primary"
[ -f /boot/initrd ] && ok "stock /boot/initrd present" || bad "/boot/initrd missing"
. /etc/os-release 2>/dev/null; [ "${VERSION_CODENAME:-}" = noble ] && ok "Ubuntu 24.04 (noble)" ||
  bad "OS ${PRETTY_NAME:-unknown} — need Ubuntu 24.04 (noble)"
avail=$(df -Pm / | awk 'NR==2{print $4}')
[ "$avail" -gt 8000 ] && ok "free space on /: $((avail/1024)) GiB" || bad "free space on /: $((avail/1024)) GiB (need ≥ 8 GiB)"
for t in cpio depmod gzip zstd curl python3 patch; do
  command -v "$t" >/dev/null || bad "missing tool: $t (sudo apt install ${t/depmod/kmod})"; done
if [ -n "${XDG_SESSION_TYPE:-}${SUDO_USER:-}" ]; then
  u=${SUDO_USER:-$USER}
  loginctl show-user "$u" -p Display 2>/dev/null | grep -q . && ok "desktop user: $u"
fi
if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
  bad "UEFI Secure Boot is enabled — the self-built kernel is not signed and will not boot"
fi
[ $fail = 0 ] && ok "system looks supported" || { echo; die "unsupported system (see warnings above)"; }
