#!/usr/bin/env bash
# Pack the staged kernel and Android Mesa into release tarballs + SHA256SUMS in $DIST.
#   KSTAGE=… MSTAGE=… build/package.sh     (defaults: $WORK/stage/{kernel,mesa-android})
set -euo pipefail
. "$(dirname "$0")/env.sh"
STRIP=${STRIP:-$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip}
command -v "$STRIP" >/dev/null || STRIP=llvm-strip
mkdir -p "$DIST"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Kernel: boot/Image-waydroid + lib/modules/$KREL (initrd is generated on the Jetson from the stock one).
[ -f "$KSTAGE/boot/Image-waydroid" ] && [ -f "$KSTAGE/lib/modules/$KREL/modules.dep" ] || die "no staged kernel in $KSTAGE"
mkdir -p "$T/k/boot" "$T/k/lib/modules"
cp "$KSTAGE/boot/Image-waydroid" "$T/k/boot/"
cp -r "$KSTAGE/lib/modules/$KREL" "$T/k/lib/modules/"
rm -f "$T/k/lib/modules/$KREL"/{build,source}
tar -C "$T/k" --owner=0 --group=0 -cf - boot lib | zstd -q -19 -T0 -o "$DIST/$ART_KERNEL" -f
ok "$ART_KERNEL ($(du -h "$DIST/$ART_KERNEL" | cut -f1))"

# Mesa: arranged like Waydroid's vendor image /vendor/lib64 (egl/ and hw/ subdirs), stripped.
V=$MSTAGE/vendor/lib64
[ -f "$V/libvulkan_nouveau.so" ] || die "no staged Android Mesa in $MSTAGE"
m=$T/m/lib64; mkdir -p "$m/egl" "$m/hw"
cp "$V/libgallium_dri.so" "$V/libgbm_mesa.so" "$m/"
cp "$V/gbm/dri_gbm.so" "$m/dri_gbm.so"
cp "$V"/libEGL_mesa.so "$V"/libGLESv1_CM_mesa.so "$V"/libGLESv2_mesa.so "$m/egl/"
cp "$V/libvulkan_nouveau.so" "$m/hw/vulkan.nouveau.so"
find "$m" -name '*.so' -exec "$STRIP" --strip-unneeded {} +
{ [ -d "$MESA_SRC/.git" ] && echo "mesa $(cat "$MESA_SRC/VERSION") $(git -C "$MESA_SRC" rev-parse --short HEAD)" || echo "mesa (prebuilt stage)"
  echo "patches: $(ls "$OW_ROOT"/patches/mesa/*.patch | wc -l) (orin-waydroid $OW_VERSION)"; } > "$T/m/MESA_VERSION"
tar -C "$T/m" --owner=0 --group=0 -cf - lib64 MESA_VERSION | zstd -q -19 -T0 -o "$DIST/$ART_MESA" -f
ok "$ART_MESA ($(du -h "$DIST/$ART_MESA" | cut -f1); libs $(du -sh "$m" | cut -f1) stripped)"

(cd "$DIST" && sha256sum "$ART_KERNEL" "$ART_MESA" > SHA256SUMS)
ok "SHA256SUMS written — upload $DIST/* as a release, or copy dist/ to the Jetson"
