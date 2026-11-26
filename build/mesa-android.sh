#!/usr/bin/env bash
# Build Mesa (NVK on nvgpu + Zink + EGL + GBM) for Waydroid's Android 13 vendor (arm64, SDK 33), NDK r29.
# Recipe adapted from Mesa CI (debian-android job). Differences: GBM enabled (Waydroid gralloc is
# minigbm_gbm_mesa → libgbm_mesa → dri_gbm), only nouveau + zink, no LLVM, static libelf,
# -Dandroid-strict=false (Zink on the Android 13 loader needs VK_KHR_maintenance5).
# Host tools mesa_clc/vtn_bindgen2 are built natively first (needs host LLVM, clang, libclc, SPIRV-LLVM-Translator).
#   build/mesa-android.sh [native|deps|setup|build|stage|all]     MESA_BUILDTYPE=release (default) | debugoptimized
set -euo pipefail
. "$(dirname "$0")/env.sh"
SDK=33 TGT=aarch64-linux-android
NDKBIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
NDKSYS=$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot
DEPS=$WORK/build/android-deps
CROSS=$WORK/build/android-cross.ini
NATIVE=$WORK/build/mesa-native
BUILD=$WORK/build/mesa-android
BUILDTYPE=${MESA_BUILDTYPE:-release}

do_native() {
  meson setup --reconfigure "$NATIVE" "$MESA_SRC" --prefix="$MESA_NATIVE" -Dbuildtype=release \
    -Dmesa-clc=enabled -Dinstall-mesa-clc=true -Dmesa-clc-bundle-headers=auto \
    -Dgallium-drivers= -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
    -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dllvm=enabled -Dshared-llvm=enabled \
    -Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=disabled >/dev/null
  ninja -C "$NATIVE" -j"$J" && ninja -C "$NATIVE" install >/dev/null
  ok "host tools: $(command -v mesa_clc) $(command -v vtn_bindgen2)"
}

write_cross() {
  local pcdir=$NDKSYS/usr/lib/$TGT/pkgconfig; mkdir -p "$pcdir" "$(dirname "$CROSS")"
  cat > "$pcdir/zlib.pc" <<EOF
prefix=$NDKSYS
libdir=$NDKSYS/usr/lib/$TGT/$SDK
includedir=$NDKSYS/usr/include
Name: zlib
Description: zlib compression library
Version: 1.2.3
Libs: -L$NDKSYS/usr/lib/$TGT/$SDK -lz
Cflags: -I$NDKSYS/usr/include
EOF
  local cc="'$NDKBIN/$TGT$SDK-clang'" cxx="'$NDKBIN/$TGT$SDK-clang++'"
  command -v ccache >/dev/null && { cc="'ccache', $cc"; cxx="'ccache', $cxx"; }
  cat > "$CROSS" <<EOF
[binaries]
ar = '$NDKBIN/llvm-ar'
c = [$cc, '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables']
cpp = [$cxx, '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$NDKBIN/llvm-strip'
rust = ['rustc', '--target', '$TGT']
pkg-config = ['pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'

[properties]
needs_exe_wrapper = true
bindgen_clang_arguments = ['-target', '$TGT', '--sysroot', '$NDKSYS']
pkg_config_libdir = '$DEPS/lib/pkgconfig:$NDKSYS/usr/lib/$TGT/pkgconfig'
EOF
}

do_deps() {
  write_cross
  local w=$WORK/build/libdrm-android
  rm -rf "$w"; mkdir -p "$w"; tar -xf "$DL/libdrm-2.4.133.tar.xz" -C "$w" --strip-components=1
  meson setup "$w/build" "$w" --cross-file "$CROSS" --prefix="$DEPS" --libdir=lib -Dbuildtype=release \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled \
    -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled \
    -Detnaviv=disabled -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled \
    -Dtests=false -Dinstall-test-programs=false -Dudev=false >/dev/null
  ninja -C "$w/build" install >/dev/null
  # libelf (NVK needs it): shipped autoconf-2.13 configure; gnu89 for its implicit-int tests, preset
  # LP64 sizes (it would run test programs, impossible when cross compiling).
  w=$WORK/build/libelf-android
  rm -rf "$w"; mkdir -p "$w"; tar -xf "$DL/libelf-0.8.13.tar.gz" -C "$w" --strip-components=1
  ( cd "$w" && export ac_cv_sizeof_short=2 ac_cv_sizeof_int=4 ac_cv_sizeof_long=8 ac_cv_sizeof_long_long=8 \
      ac_cv_sizeof___int64=0 CC=$NDKBIN/$TGT$SDK-clang AR=$NDKBIN/llvm-ar RANLIB=$NDKBIN/llvm-ranlib \
      CFLAGS="-O2 -fPIC -std=gnu89 -Wno-implicit-function-declaration" &&
    ./configure --host=x86_64-linux-gnu --disable-nls --disable-shared --enable-elf64 \
      --prefix="$DEPS" --libdir="$DEPS/lib" >/dev/null &&
    { grep -q '^#define __LIBELF64 1' config.h || { echo "libelf: no 64-bit support"; exit 1; }; } &&
    make -j"$J" >/dev/null && make install >/dev/null )
  ok "android deps in $DEPS"
}

do_setup() {
  [ -f "$CROSS" ] || write_cross
  PKG_CONFIG_LIBDIR=/disable/non/android/system/pc/files \
  meson setup --wipe "$BUILD" "$MESA_SRC" --cross-file "$CROSS" --prefix=/vendor --libdir=lib64 \
    -Dbuildtype="$BUILDTYPE" -Db_lto=false \
    -Dplatforms=android -Dandroid-stub=true -Dplatform-sdk-version=$SDK -Dandroid-strict=false \
    -Dvulkan-drivers=nouveau -Dgallium-drivers=zink \
    -Degl=enabled -Dgbm=enabled -Dglx=disabled -Dglvnd=disabled -Dopengl=true \
    -Dgles1=enabled -Dgles2=enabled -Degl-lib-suffix=_mesa -Dgles-lib-suffix=_mesa \
    -Dgbm-backends-path=/vendor/lib64 \
    -Dllvm=disabled -Dexpat=disabled -Dxmlconfig=disabled -Dzstd=disabled -Dvalgrind=disabled \
    -Dlibunwind=disabled -Dandroid-libbacktrace=disabled -Dperfetto=false -Dcpp_rtti=false \
    -Dmesa-clc=system -Dvulkan-layers= -Dtools= -Dbuild-tests=false >/dev/null
  ok "configured ($BUILDTYPE)"
}

do_build() { ninja -C "$BUILD" -j"$J"; }
do_stage() {
  rm -rf "$MSTAGE"; DESTDIR="$MSTAGE" ninja -C "$BUILD" install >/dev/null
  ok "staged $(du -sh "$MSTAGE/vendor" | cut -f1) in $MSTAGE"
}

case ${1:-all} in
  native) do_native;; deps) do_deps;; setup) do_setup;; build) do_build;; stage) do_stage;;
  all) do_native; do_deps; do_setup; do_build; do_stage;;
  *) die "usage: $0 [native|deps|setup|build|stage|all]";;
esac
