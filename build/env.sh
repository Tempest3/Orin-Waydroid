# shellcheck shell=bash
# Build-host environment (x86_64 Linux). Sourced by build/*.sh.
OW_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$OW_ROOT/lib/common.sh"
WORK=${OW_WORK:-$OW_ROOT/work}                  # everything downloaded/built lives here (≈ 25 GB)
DL=$WORK/dl
J=${J:-$(nproc)}
L4T=$WORK/l4t
KSRCROOT=$L4T/Linux_for_Tegra/source
KSRC=$KSRCROOT/kernel/kernel-noble
KOUT=$WORK/build/kernel
KSTAGE=${KSTAGE:-$WORK/stage/kernel}               # boot/Image-waydroid, lib/modules/$KREL
MESA_SRC=$WORK/mesa
NDK=$WORK/android-ndk-r29
TOOLS=$WORK/tools
MESA_NATIVE=$TOOLS/mesa-native
MSTAGE=${MSTAGE:-$WORK/stage/mesa-android}         # DESTDIR of the Android Mesa install (vendor/lib64/...)
DIST=${OW_DIST:-$OW_ROOT/dist}
export RUSTUP_HOME=${RUSTUP_HOME:-$TOOLS/rustup} CARGO_HOME=${CARGO_HOME:-$TOOLS/cargo}
export PATH=$MESA_NATIVE/bin:$CARGO_HOME/bin:$PATH

# Cross compiler for the kernel: NVIDIA's R39.2 toolchain (gcc 13.2, crosstool-NG) is what releases use.
# Download "Bootlin/x-tools toolchain" from the Jetson Linux R39.2 page and unpack it to $WORK/x-tools,
# or set CROSS_COMPILE to another aarch64 gcc ≥ 13 (e.g. Fedora/Ubuntu aarch64-linux-gnu-gcc; untested).
if [ -z "${CROSS_COMPILE:-}" ]; then
  if [ -x "$WORK/x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" ]; then
    CROSS_COMPILE=$WORK/x-tools/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
  elif command -v aarch64-linux-gnu-gcc >/dev/null; then
    CROSS_COMPILE=aarch64-linux-gnu-
  fi
fi
export ARCH=arm64 CROSS_COMPILE

fetch() {  # fetch url sha256 dest
  [ -f "$3" ] && echo "$2  $3" | sha256sum -c --status - && return 0
  mkdir -p "$(dirname "$3")"
  say "Downloading $(basename "$3")"
  curl -fL --retry 3 -o "$3.part" "$1" && mv "$3.part" "$3"
  sha256_check "$3" "$2"
}
