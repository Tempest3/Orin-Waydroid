#!/usr/bin/env bash
# Install the Waydroid kernel from a release tarball as an EXTRA extlinux entry ("waydroid").
#   jetson/install-kernel.sh <orin-waydroid-kernel-*.tar.zst>
# Never modifies /boot/Image, /boot/initrd or the 'primary' entry. MAKE_DEFAULT=1 makes 'waydroid' the
# default entry ('primary' stays in the menu as fallback). Backups go to /boot/orin-waydroid-backup-<time>.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
need_root
TAR=${1:?usage: $0 <kernel tarball>}
EXT=/boot/extlinux/extlinux.conf
TS=$(date +%Y%m%d-%H%M%S)
BK=/boot/orin-waydroid-backup-$TS
W=$(mktemp -d /var/tmp/orin-waydroid.XXXXXX)
trap 'rm -rf "$W"' EXIT

say "Unpacking $(basename "$TAR")"
tar -C "$W" -xf "$TAR"
[ -f "$W/boot/Image-waydroid" ] && [ -f "$W/lib/modules/$KREL/modules.dep" ] || die "tarball lacks boot/Image-waydroid or modules for $KREL"

say "Backing up to $BK"
mkdir -p "$BK"; cp -a "$EXT" "$BK/"
for f in /boot/Image-waydroid /boot/initrd-waydroid; do [ -f "$f" ] && cp -a "$f" "$BK/"; done

say "Installing kernel and modules ($KREL)"
install -m644 "$W/boot/Image-waydroid" /boot/Image-waydroid
rm -rf "/lib/modules/$KREL"
cp -r "$W/lib/modules/$KREL" /lib/modules/
chown -R root:root "/lib/modules/$KREL"
depmod "$KREL"

# initrd: the stock L4T initrd with its module set swapped for the same modules from the new kernel.
say "Building /boot/initrd-waydroid from the stock /boot/initrd"
R=$W/initrd; mkdir -p "$R"
(cd "$R" && zcat /boot/initrd | cpio -id --quiet --no-absolute-filenames)
M=$R/usr/lib/modules
[ -d "$M/$KREL_STOCK" ] || die "stock initrd has no modules for $KREL_STOCK"
(cd "$M/$KREL_STOCK" && find . -name '*.ko*' | sort) > "$W/modlist"
mkdir -p "$M/$KREL"
while read -r f; do
  src=/lib/modules/$KREL/$f
  [ -f "$src" ] || src=$(find "/lib/modules/$KREL" -name "$(basename "$f")" | head -1)
  [ -n "$src" ] && [ -f "$src" ] || die "initrd module $(basename "$f") not found in the new kernel"
  install -D -m644 "$src" "$M/$KREL/$f"
done < "$W/modlist"
cp "/lib/modules/$KREL"/modules.{builtin,builtin.modinfo,order} "$M/$KREL/"
rm -rf "${M:?}/$KREL_STOCK"
depmod -b "$R/usr" "$KREL"
[ -s "$M/$KREL/modules.dep" ] || die "depmod produced no modules.dep for the initrd"
(cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9 -n) > /boot/initrd-waydroid.new
mv /boot/initrd-waydroid.new /boot/initrd-waydroid
ok "initrd: $(wc -l < "$W/modlist") modules, $(du -h /boot/initrd-waydroid | cut -f1)"

say "Updating $EXT (entry 'waydroid')"
python3 "$(dirname "$0")/../lib/extlinux.py" add "$EXT" "$EXT.new" $([ "${MAKE_DEFAULT:-0}" = 1 ] && echo --default)
grep -q '^LABEL primary' "$EXT.new" && grep -q '^LABEL waydroid' "$EXT.new" || { rm -f "$EXT.new"; die "extlinux edit failed; nothing changed"; }
mv "$EXT.new" "$EXT"
diff -u "$BK/extlinux.conf" "$EXT" | sed -E 's/(root=)[^ ]+/\1…/' || true
sync
ok "kernel installed. Stock 'primary' entry unchanged; backup in $BK"
grep -q '^DEFAULT waydroid' "$EXT" && ok "default boot entry: waydroid" ||
  say "Pick 'waydroid kernel' in the boot menu (shown on HDMI and serial during the boot timeout)."
