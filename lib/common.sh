# shellcheck shell=bash
# Shared constants and helpers for orin-waydroid (sourced by install.sh, jetson/*.sh and build/*.sh).

OW_VERSION=$(cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION")

# Supported platform: JetPack 7.2 = L4T R39.2 on a Jetson Orin Nano developer kit.
L4T_RELEASE=39.2.0
L4T_TAG="R39 (release), REVISION: 2.0"
KREL_STOCK=6.8.12-1021-tegra
KREL=6.8.12-1021-tegra-waydroid
WAYDROID_VERSION=1.6.3          # patches/waydroid/0001 is written against this version

# Upstream sources (pinned + checksummed; used by build/fetch.sh).
L4T_SOURCES_URL=https://developer.nvidia.com/downloads/embedded/l4t/r39_release_v2.0/sources/public_sources.tbz2
L4T_SOURCES_SHA256=87d2e31ff55beaf2373e2f288538585995b231fd5745ec21f39a668e36efab2f
MESA_GIT=https://gitlab.freedesktop.org/mesa/mesa.git
MESA_BASE=edce88a39ed49284ad18b2745eb1b592fd5d0440   # upstream main, 2026-11-25; patches/mesa apply on top
NDK_URL=https://dl.google.com/android/repository/android-ndk-r29-linux.zip
NDK_SHA256=4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf
LIBDRM_URL=https://dri.freedesktop.org/libdrm/libdrm-2.4.133.tar.xz
LIBDRM_SHA256=fc68f9d0ba2ea63c9432a299e14fea09fad7a8a66e8039fcd7802ca59f77b4f5
LIBELF_URL=https://fossies.org/linux/misc/old/libelf-0.8.13.tar.gz
LIBELF_SHA256=591a9b4ec81c1f2042a97aa60564e0cb79d041c52faa7416acb38bc95bd2c76d

# Release artifact names (build/package.sh writes them, install.sh reads them).
ART_KERNEL=orin-waydroid-kernel-$KREL-$OW_VERSION.tar.zst
ART_MESA=orin-waydroid-mesa-android-$OW_VERSION.tar.zst

if [ -t 1 ]; then C_B=$'\e[1m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_0=$'\e[0m'; else C_B= C_G= C_Y= C_R= C_0=; fi
say()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '  %s[ok]%s   %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s[warn]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run with sudo"; }
ask() {  # ask "question" default(y|n) → returns 0 for yes
  local def=${2:-n} a
  [ "${OW_YES:-0}" = 1 ] && return 0
  read -r -p "$1 [$([ "$def" = y ] && echo Y/n || echo y/N)] " a || true
  a=${a:-$def}; [[ $a =~ ^[Yy] ]]
}
sha256_check() {  # sha256_check file expected
  echo "$2  $1" | sha256sum -c --status - || die "checksum mismatch: $1"
}
