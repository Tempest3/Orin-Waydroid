# Troubleshooting

Collect logs first:

```sh
./install.sh status
sudo waydroid shell -- logcat -d > logcat.txt          # Android log (while Android runs)
journalctl -k -b | grep -iE 'nvgpu|sm_exception|ctxsw|mmu' # GPU faults
```

## The Jetson doesn't boot the Waydroid kernel
Choose `primary kernel` in the boot menu (HDMI or serial, 30 s timeout) — it is unchanged. If you used
`--make-default`, `sudo ./install.sh uninstall` from the stock kernel resets the default. Backups of
`extlinux.conf` are in `/boot/orin-waydroid-backup-*`.

## Android starts but stays black / "Starting waydroid session" hangs
`./install.sh status` should say `rendering: GPU`. If `drm_device` isn't the nvidia-drm display node, re-run
`sudo ./install.sh gpu`. To rule out the GPU stack: `sudo ./install.sh gpu-off` (software rendering, slow).

## Container shows FROZEN, `waydroid shell` hangs
Waydroid suspends Android when no window is open. Open it (`waydroid show-full-ui`) or
`sudo waydroid container unfreeze`.

## Networking (no internet in Android, no Google ID)
- `ip -6 rule` must work on the host while running the Waydroid kernel (it fails on the stock kernel).
- `sudo waydroid shell -- dumpsys connectivity | grep VALIDATED` should print a line.
- Docker or a firewall with a `FORWARD DROP` policy can block Waydroid's NAT (`waydroid0`, 192.168.240.0/24).

## Play Store: "device is not Play Protect certified" / sign-in loops
Register the ID from `sudo ./install.sh gapps-id`, wait, restart Android. The first start updates the Play
Store and Play Services, which restarts them; a sign-in started during that is killed — wait it out.
Wiping Waydroid's data creates a new ID that must be registered again.

## An app crashes / GPU errors
- `journalctl -k | grep sm_exception` → a GPU shader fault. For triage, set (until the next Android restart):
  ```sh
  sudo waydroid shell -- setprop debug.mesa.nvk.log.shader.addr true
  ```
  restart the app; on a failed submission Mesa logs `nvgpu: SM <n> fault: … pc 0x…` (logcat tag MESA),
  which can be matched to the shader address lines.
- Shader dumps for one process (needs a Mesa build; prints the final NAK shaders to logcat tag NAK):
  ```sh
  sudo waydroid shell -- setprop debug.mesa.nak.debug.proc <process name>
  sudo waydroid shell -- setprop debug.mesa.nak.debug asm
  ```
- Release builds have assertions disabled. A `debugoptimized` build (`MESA_BUILDTYPE=debugoptimized
  build/mesa-android.sh`) turns invalid API usage into an abort with a message — useful for bug reports.

## A game reacts to mouse clicks but not to drags, swipes or press-and-hold
Waydroid passes the mouse to Android as a mouse. Many Unity games handle mouse clicks but read drags and
swipes only from touch input. `persist.waydroid.fake_touch` makes Waydroid send the mouse as touch events
for the listed apps. The installer sets it for The Tower (`FAKE_TOUCH_APPS` in lib/common.sh); for other
games, as your normal user with Android running (comma-separated package names, `*` = all apps):
```sh
waydroid prop set persist.waydroid.fake_touch "com.TechTreeGames.TheTower,<other.package>"
```
Then restart the game. Multi-finger gestures (pinch-to-zoom) still don't work with a single mouse.

## Measuring FPS
`tests/android-fps.sh` (copy to `~/.local/share/waydroid/data/local/tmp/`, run with
`sudo waydroid shell -- sh /data/local/tmp/android-fps.sh 10 > trace.txt` while the app is in front: a 10 s
atrace), then `tests/android-fps.py trace.txt [app]` on any machine (counts the app's frames; `app` is a substring
of its package name). It doesn't query SurfaceFlinger, so it doesn't disturb what it measures.
