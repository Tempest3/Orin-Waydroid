#!/usr/bin/env bash
# Cross-compile the L4T R39.2 kernel 6.8.12 + NVIDIA out-of-tree modules for Waydroid.
# Config = stock R39.2 config + configs/binder.diff (binder, binderfs, PSI) + configs/android-net.diff
# (IPv6 policy routing etc. — without it Android has no network). Release string: $KREL.
# Output: $KSTAGE/boot/Image-waydroid, $KSTAGE/lib/modules/$KREL
set -euo pipefail
. "$(dirname "$0")/env.sh"
[ -n "${CROSS_COMPILE:-}" ] || die "no cross compiler (see build/env.sh)"
LOCALVERSION=${KREL#6.8.12}            # -1021-tegra-waydroid
KMAKE=(make -C "$KSRC" O="$KOUT" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" LOCALVERSION="$LOCALVERSION")
OOT=(make -C "$KSRCROOT" KERNEL_HEADERS="$KSRC" KERNEL_OUTPUT="$KOUT" kernel_name=noble
     CROSS_COMPILE="$CROSS_COMPILE" LOCALVERSION="$LOCALVERSION")

mkdir -p "$KOUT"
[ -f "$KOUT/.config" ] || cp "$OW_ROOT/configs/stock-$KREL_STOCK.config" "$KOUT/.config"
# = configs/binder.diff: binder + binderfs (built in), PSI on by default (lmkd)
"$KSRC/scripts/config" --file "$KOUT/.config" -e ANDROID_BINDER_IPC -e ANDROID_BINDERFS \
  --set-str ANDROID_BINDER_DEVICES "" -e PSI -d PSI_DEFAULT_DISABLED
"${KMAKE[@]}" -s olddefconfig
# = configs/android-net.diff: netd needs IPv6 policy routing, PF_KEY, owner/connmark matches
"$KSRC/scripts/config" --file "$KOUT/.config" -e IPV6_MULTIPLE_TABLES -m NET_KEY \
  -m NETFILTER_XT_MATCH_OWNER -m NETFILTER_XT_CONNMARK -e IPV6_ROUTER_PREF -e IPV6_ROUTE_INFO
"${KMAKE[@]}" -s olddefconfig
for o in ANDROID_BINDER_IPC=y ANDROID_BINDERFS=y PSI=y IPV6_MULTIPLE_TABLES=y NET_KEY=m; do
  grep -q "^CONFIG_$o\$" "$KOUT/.config" || die "config check failed: CONFIG_$o"
done
ok "config checked"

say "Building kernel ($J jobs)"
"${KMAKE[@]}" -j"$J" Image modules
rel=$("${KMAKE[@]}" -s kernelrelease); [ "$rel" = "$KREL" ] || die "kernelrelease is $rel, expected $KREL"
say "Building NVIDIA out-of-tree modules"
"${OOT[@]}" -j"$J" modules

say "Staging into $KSTAGE"
rm -rf "$KSTAGE"; mkdir -p "$KSTAGE/boot"
"${KMAKE[@]}" -s INSTALL_MOD_PATH="$KSTAGE" INSTALL_MOD_STRIP=1 modules_install
"${OOT[@]}" -s INSTALL_MOD_PATH="$KSTAGE" INSTALL_MOD_STRIP=1 modules_install
cp "$KOUT/arch/arm64/boot/Image" "$KSTAGE/boot/Image-waydroid"
rm -f "$KSTAGE/lib/modules/$KREL/build" "$KSTAGE/lib/modules/$KREL/source"
for m in nvgpu.ko nvmap.ko nvidia-drm.ko host1x-fence.ko; do
  find "$KSTAGE/lib/modules/$KREL" -name "$m" | grep -q . || die "missing module $m"
done
ok "kernel $KREL staged ($(du -sh "$KSTAGE" | cut -f1))"
