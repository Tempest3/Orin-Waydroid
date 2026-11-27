# How it works

```
 Android app (GLES / Vulkan)
   │  GLES → Mesa Zink (GL on Vulkan)        Vulkan → directly
   ▼
 Mesa NVK  (Vulkan driver for NVIDIA GPUs)  ── NAK shader compiler (SM 8.7 for Orin's GA10B)
   │  nvkmd/nvgpu backend (MR 34914 + patches)
   ▼
 /dev/nvgpu/igpu0/*, /dev/nvmap, /dev/host1x-fence   ← passed into the Waydroid LXC container
   ▼
 NVIDIA's nvgpu / nvmap / host1x kernel modules (stock JetPack 7.2 driver stack, rebuilt for the new kernel)
```

Buffers are allocated by Android's `minigbm_gbm_mesa` gralloc (→ Mesa GBM on Zink → NVK → nvmap dma-bufs);
SurfaceFlinger composes with Zink; Waydroid hands the frames to the host Wayland compositor (GNOME).

## Kernel (why a new one is needed)

| Option | Why |
|---|---|
| `ANDROID_BINDER_IPC`, `ANDROID_BINDERFS` | Android IPC (Waydroid uses binderfs) |
| `PSI` | Android's low-memory killer |
| `IPV6_MULTIPLE_TABLES` | `netd` adds IPv6 policy-routing rules for every network; without it it can't attach `eth0` → no network, no Google check-in |
| `NET_KEY`, `NETFILTER_XT_MATCH_OWNER`, `NETFILTER_XT_CONNMARK`, `IPV6_ROUTER_PREF`, `IPV6_ROUTE_INFO` | netd's traffic accounting / firewall chains |

`IPV6_MULTIPLE_TABLES` changes `struct net`, so every module (including NVIDIA's out-of-tree nvgpu, nvmap,
display, …) must be rebuilt against the new kernel; the release ships them all under
`/lib/modules/6.8.12-1021-tegra-waydroid`. The initrd is generated on the Jetson from the stock one with the
same module set swapped in (so no NVIDIA initrd is redistributed).

## Mesa patches (patches/mesa)

0001–0006: MR 34914 (nvkmd nvgpu backend) rebased onto current Mesa. Ours on top:

| Patch | Fixes |
|---|---|
| 0007, 0009 | L4T R39 device nodes and nvgpu/nvmap UAPI headers |
| 0008, 0010 | dma-buf import alignment; GA10B chip ID (arch/impl split) and shared-memory info |
| 0011 | syncpoint waits via SYNCPOINT_WAIT |
| 0012, 0013 | report the Tegra display device as the DRM device; DRM syncobj path only where it exists |
| 0014 | dma-buf import (Android gralloc buffers) |
| 0015 | fence correctness: GPU L2 flush before signalling (CPU/other devices saw stale data) |
| 0016 | sync_file import/export via `/dev/host1x-fence` (Android fences) |
| 0017 | GBM on Zink on Android (DRI3 screen type instead of the Kopper stub) |
| 0018 | shader heap mapped GPU-uncached (stale L2 → `ILLEGAL_INSTR_ENCODING` in Play Services' DroidGuard) |
| 0019–0020 | fault triage: SM error state + faulting PC logging; NAK debug output on Android |
| 0021 | tolerate unaligned flush ranges (Unity) instead of asserting |
| 0022 | invalidate the GPU L2's sysmem lines before every submission: Orin's L2 does not snoop CPU writes and nvgpu never invalidates it, so CPU-updated buffers were otherwise read stale indefinitely |
| 0023 | tolerate 3D views of single-layer 2D images (3DMark Wild Life Extreme aborted in NIL) |
| 0024 | `NVMAP_IOC_FREE` takes the handle, not a pointer: every freed allocation leaked (gralloc grew until lmkd killed apps) |

## Waydroid integration

Waydroid 1.6.3 regenerates its LXC config on every start and has no hook for extra devices, so
`patches/waydroid/0001` patches `/usr/lib/waydroid/tools/helpers/lxc.py` (bind `/dev/nvgpu`, `/dev/nvmap`,
`/dev/host1x-fence`, all `/dev/dri`) and `container_manager.py` (permissions). Mesa options are passed as
Android properties — on Android 13 Mesa only reads `debug.mesa.*` / `vendor.mesa.*`:

```
ro.hardware.gralloc=minigbm_gbm_mesa   ro.hardware.egl=mesa   ro.hardware.vulkan=nouveau
gralloc.gbm.device=/dev/dri/renderD<N> (the nvidia-drm display node)
debug.mesa.loader.driver.override=zink   debug.mesa.nvk.on.nvgpu=1
debug.mesa.nvk.i.want.a.broken.vulkan.driver=1
```
