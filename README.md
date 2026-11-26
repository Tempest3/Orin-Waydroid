# orin-waydroid

GPU-accelerated Android with the Google Play Store on an **NVIDIA Jetson Orin Nano**, via
[Waydroid](https://waydro.id). Android renders on the Orin GPU through Mesa (NVK on NVIDIA's `nvgpu` driver
+ Zink), using the stock JetPack driver stack and no proprietary Android blobs.

| | |
|---|---|
| Board | Jetson Orin Nano developer kit (tested: p3767-0005 + p3768, "Super") |
| OS | **JetPack 7.2 = L4T R39.2** (Ubuntu 24.04, kernel 6.8.12-1021-tegra), GNOME on Wayland |
| Android | LineageOS 20 (Android 13) Waydroid image with GAPPS |
| Result | Play Store sign-in works; Unity game *The Tower*: 60 FPS (vsync-locked), GPU ≈ 30–50 % |

> **Experimental.** NVK on nvgpu is an out-of-tree Mesa backend
> ([MR 34914](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/34914)) plus 16 patches of ours (22 in total).
> It is not a conformant Vulkan driver. Expect bugs; keep backups of anything important.

## Quick start (on the Jetson)

You need: JetPack 7.2 installed and booting normally, ~8 GB free, internet, a monitor (to pick the boot entry
once) and a Google account.

```sh
git clone <this repo> orin-waydroid && cd orin-waydroid
# put the release tarballs in ./dist (or use --from <url>, see below)
sudo ./install.sh            # checks the system, installs the Waydroid kernel as an extra boot entry
sudo reboot                  # choose "waydroid kernel" in the boot menu
cd orin-waydroid && sudo ./install.sh   # installs Waydroid + GAPPS images, enables the GPU
waydroid show-full-ui        # as your normal user, in the desktop session
```

Then register for the Play Store (Google requires this for uncertified devices):

```sh
sudo ./install.sh gapps-id   # prints the Google Services ID and what to do with it
```

Paste the ID at <https://www.google.com/android/uncertified>, wait a few minutes (up to an hour),
restart Android (`waydroid session stop`, then `waydroid show-full-ui`) and sign in to the Play Store.
The first start downloads Play Store / Play Services updates; let them finish before signing in.

### Install options

| | |
|---|---|
| `--from <dir\|url>` | where the release tarballs are (default `./dist`, then `$OW_RELEASE_URL`) |
| `--make-default` | boot the Waydroid kernel by default (the stock entry stays in the menu) |
| `--yes` | don't ask |
| `sudo ./install.sh check` | preflight only, changes nothing |
| `./install.sh status` | what is installed / running |
| `sudo ./install.sh gpu-off` | back to software rendering (SwiftShader) |
| `sudo ./install.sh uninstall` | remove the kernel entry, GPU overlay and (optionally) Waydroid |

## What it changes

- **Kernel** — an extra extlinux entry `waydroid` booting `/boot/Image-waydroid` (6.8.12-1021-tegra-waydroid):
  the L4T R39.2 kernel rebuilt with binder/binderfs, PSI and the networking options Android's `netd`
  needs (`CONFIG_IPV6_MULTIPLE_TABLES`, without which Android has no network at all), plus NVIDIA's
  out-of-tree modules rebuilt to match. The stock kernel, initrd and `primary` entry are never modified;
  if anything goes wrong, pick `primary` in the boot menu. Backups: `/boot/orin-waydroid-backup-*`.
- **Waydroid** 1.6.3 from the official repo (held at that version), LineageOS 20 GAPPS images.
- **GPU** — a small patch to Waydroid's LXC setup to pass the Orin GPU devices into the container,
  our Mesa build in Waydroid's vendor overlay (`/var/lib/waydroid/overlay/vendor/lib64`) and the
  matching Android properties in `/var/lib/waydroid/waydroid.cfg` (backup: `waydroid.cfg.pre-orin-waydroid`).

Details: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md). Problems: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Building the release yourself (x86_64 Linux host)

```sh
build/all.sh                 # = fetch.sh, kernel.sh, mesa-android.sh all, package.sh → dist/
```

Everything is downloaded from upstream with pinned checksums (NVIDIA L4T R39.2 public sources, Mesa at a
fixed commit + `patches/mesa`, Android NDK r29, libdrm, libelf) into `work/` (~25 GB). Needs: git, curl,
unzip, zstd, meson ≥ 1.4, ninja, pkg-config, python3 + mako + pyyaml, bison, flex, glslang, host
LLVM/clang + libclc + SPIRV-LLVM-Translator + SPIRV-Tools development packages (for Mesa's `mesa_clc`), and
an aarch64 cross gcc ≥ 13 for the kernel — NVIDIA's R39.2 toolchain (Bootlin x-tools, from the Jetson Linux
R39.2 download page) unpacked to `work/x-tools` is what releases use. Rust is installed via rustup if
needed. Takes ~1 h on 16 threads. Tested on Fedora 44.

Copy `dist/` next to `install.sh` on the Jetson, or host it and use `--from <url>`.

## Status / known issues

- Only JetPack 7.2 (L4T R39.2) on the Orin Nano dev kit is tested.
- First Android boot and the first Play Store start are slow (dexopt, Google updates).
- Waydroid freezes Android when its window has been closed for a while (`waydroid status` shows FROZEN).
- The Mesa release build has assertions disabled; for bug reports, build with
  `MESA_BUILDTYPE=debugoptimized build/mesa-android.sh` and see docs/TROUBLESHOOTING.md for GPU fault logging.

## Credits

- Mesa NVK nvgpu backend: Mesa MR 34914 and its authors.
- Waydroid, LineageOS, Mesa (NVK, Zink, NAK) projects; NVIDIA for the open nvgpu/nvmap/display sources.

## License

The scripts and docs in this repository: MIT (see LICENSE). `patches/mesa` are under Mesa's licenses (MIT),
the kernel config and released kernel binaries under GPL-2.0 (sources: NVIDIA L4T R39.2 public sources).
