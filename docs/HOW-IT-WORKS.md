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

### Performance work (0.1.2, 0.1.3)

Measured on an Orin Nano at 25 W with a microbenchmark against NVIDIA's own Vulkan driver on the same board, and with
3DMark Wild Life Extreme (WLE) in Waydroid. WLE: about 1830 → about 1930, all of it from ZCULL.

| Patch | Change | Effect |
|---|---|---|
| 0025 | enable ZCULL: report ZCULL geometry from `ZCULL_GET_INFO`/`GET_CTX_SIZE`; fix the ZCULL bind, which passed the mode constant as the ioctl number, so it returned 0 without binding anything | occluded-pixel rejection 14 → 121 GPix/s (NVIDIA 196); WLE +5 % |
| 0026 | NAK: reuse a block's legalizer copies of immediates/cbuf values instead of a `mov` before every FFMA | `x*uniform+imm` ALU throughput +43 %; no WLE change |
| 0027 | compression: comptags requested at register for compressible kinds; map with compressed + uncompressed fallback kind (4K pages are fine on ga10b) | blend 10.7 → 14.5, depth write 7.1 → 14.5 GPix/s (= NVIDIA) |
| 0028 | `NVK_NVGPU_SHADER_UNCACHED=0` (`debug.mesa.nvk.nvgpu.shader.uncached=false`) maps the shader heap L2-cached, for measuring | default unchanged (uncached); no measurable WLE difference |
| 0029 | report `HOST_TRANSFER` usage as non-optimal for compressible images, so Zink drops it and its render targets get compressed | Zink color targets compressed |
| 0030, 0031 | compression for sub-allocated images (64K-aligned binds; plain buffers left unregistered so nvgpu allocates comptags lazily); **off by default** (0031), `NVK_NVGPU_COMPRESSION_SUBALLOC=1` enables it | −1 % in WLE when on |
| 0032 | NAK (sm70+): set the operand-reuse flags (`NAK_NO_REUSE=1` disables); optional "keep issuing" scheduling bit by NVIDIA's rule (`NAK_YIELD=1`, off: +30–43 % on pure ALU loops but 2–6 % slower on WLE shaders) | heavy WLE fragment shaders ≈ 1 % faster; WLE unchanged (~1920) |
| 0033 | nvgpu syncs: a timed-out syncpoint wait (EAGAIN) was retried forever and "wait forever" (-1) counted as already expired, so every GPU wait busy-spun and every status poll blocked until the GPU finished; `VK_SYNC_WAIT_PENDING` waited for completion. Android present: use the common sync-file path instead of nouveau's `QueueWaitIdle` workaround | The Tower 52 → 63 FPS at 60–70 FPS settings; with its 120 FPS setting ~117 FPS at default clocks. Present 4.5 → 0.6 ms; a CPU core no longer spins |

Off switches: `NVK_NVGPU_ZCULL=0`, `NVK_NVGPU_COMPRESSION=0` (Android: `debug.mesa.nvk.nvgpu.zcull=false`, etc.).

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
