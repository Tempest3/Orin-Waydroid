#!/usr/bin/env bash
# Download and prepare all sources (idempotent): L4T R39.2 kernel + NVIDIA OOT sources, Mesa (pinned base +
# patches/mesa), Android NDK r29, libdrm, libelf, Rust Android target.
set -euo pipefail
. "$(dirname "$0")/env.sh"

# --- NVIDIA L4T R39.2 public sources (kernel, nvidia-oot, nvgpu, display drivers)
fetch "$L4T_SOURCES_URL" "$L4T_SOURCES_SHA256" "$DL/public_sources.tbz2"
if [ ! -d "$KSRC" ]; then
  say "Unpacking L4T kernel sources"
  mkdir -p "$L4T"; tar -C "$L4T" -xjf "$DL/public_sources.tbz2" \
    Linux_for_Tegra/source/kernel_src.tbz2 Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 \
    Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2 \
    Linux_for_Tegra/source/nvidia_unified_gpu_display_driver_source.tbz2 \
    Linux_for_Tegra/source/Makefile Linux_for_Tegra/source/kernel_src_build_env.sh \
    Linux_for_Tegra/source/nvcommon_build.sh 2>/dev/null ||
    tar -C "$L4T" -xjf "$DL/public_sources.tbz2"
  for t in kernel_src kernel_oot_modules_src nvidia_kernel_display_driver_source nvidia_unified_gpu_display_driver_source; do
    tar -C "$KSRCROOT" -xjf "$KSRCROOT/$t.tbz2"
  done
fi
ok "kernel sources: $KSRC"

# --- Mesa
if [ ! -d "$MESA_SRC/.git" ]; then
  say "Cloning Mesa (blobless)"
  git clone --filter=blob:none --no-checkout "$MESA_GIT" "$MESA_SRC"
fi
if ! git -C "$MESA_SRC" rev-parse -q --verify refs/heads/orin-waydroid >/dev/null; then
  say "Applying $(ls "$OW_ROOT"/patches/mesa/*.patch | wc -l) Mesa patches on $MESA_BASE"
  git -C "$MESA_SRC" fetch -q origin "$MESA_BASE" 2>/dev/null || true
  git -C "$MESA_SRC" checkout -q -b orin-waydroid "$MESA_BASE"
  git -C "$MESA_SRC" -c user.name=orin-waydroid -c user.email=build@localhost am -q --committer-date-is-author-date \
    "$OW_ROOT"/patches/mesa/*.patch
fi
ok "mesa: $(git -C "$MESA_SRC" describe --always --tags 2>/dev/null) (branch orin-waydroid)"

# --- Android NDK, libdrm, libelf
fetch "$NDK_URL" "$NDK_SHA256" "$DL/android-ndk-r29-linux.zip"
[ -d "$NDK" ] || { say "Unpacking NDK"; unzip -q "$DL/android-ndk-r29-linux.zip" -d "$WORK"; }
fetch "$LIBDRM_URL" "$LIBDRM_SHA256" "$DL/libdrm-2.4.133.tar.xz"
fetch "$LIBELF_URL" "$LIBELF_SHA256" "$DL/libelf-0.8.13.tar.gz"
ok "NDK r29, libdrm 2.4.133, libelf 0.8.13"

# --- Rust (project-local rustup unless a rustup with the Android target already exists)
if ! rustup target list --installed 2>/dev/null | grep -q aarch64-linux-android; then
  if ! command -v rustup >/dev/null; then
    say "Installing rustup into $TOOLS"
    # (a distro Rust may also be installed; ours lives in $TOOLS and wins via PATH)
    curl -fsSL https://sh.rustup.rs | RUSTUP_INIT_SKIP_PATH_CHECK=yes sh -s -- -y --no-modify-path \
      --profile minimal --component rustfmt
  fi
  rustup target add aarch64-linux-android
fi
rustup component list --installed 2>/dev/null | grep -q rustfmt || rustup component add rustfmt  # bindgen formats with it
command -v bindgen >/dev/null || cargo install --locked bindgen-cli
command -v cbindgen >/dev/null || cargo install --locked cbindgen
ok "rust: $(rustc --version)"
[ -n "${CROSS_COMPILE:-}" ] || warn "no aarch64 cross compiler found (see build/env.sh)"
