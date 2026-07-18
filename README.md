# note10lite-droidian

[Droidian](https://droidian.org/) (Debian-based mobile Linux, Halium) port for the
**Samsung Galaxy Note 10 Lite** — `SM-N770F`, codename **`r7`** (Exynos 9810).
This repo holds the **port documentation and device adaptation** (scripts, service
units, config), not the rootfs image.

> **Status: D2 — usable phone, now with Android app support.** Phosh boots to a
> working desktop on `4.9.191-samsung-r7`, confirmed on-device. Stable, boots
> straight to Phosh. **Waydroid runs LineageOS 20 with Play Store** (sesi-20).

## What works
Display · touchscreen · Phosh shell · PIN login · WiFi · Settings · charging ·
display scaling · on-screen keyboard · on-device terminal · **audio (speaker +
3.5mm jack with auto-switch**, `device-r7/audio/r7-jack-router`) ·
**hardware video decode** (Clapper / `droidvdec`, Exynos MFC) ·
**YouTube 1080p60 in Chromium** (SW decode, smooth on stock scaling — see
`device-r7/video/README.md` for the 3-part recipe) ·
**notch-aware shell layout** (clock clears the punch-hole, `device-r7/display/`) ·
**Waydroid** (LineageOS 20 GSI + MindTheGapps/Play Store; **camera works inside
Waydroid** — currently the only camera path — and the YouTube app plays 1080p60
with HW decode, smoother than the browser).

Waydroid needed three kernel fixes (branch `droidian-r7`): `BRIDGE`/`VETH` +
`NETFILTER_XT_TARGET_CHECKSUM` for `waydroid-net` (`856ffe866`, `57fbcf609`),
a **fimc-is2 `querycap` wrong-struct deref** that kernel-panicked the phone on any
V4L2 `QUERYCAP` (`4c225c879`), and a **Mali kbase pid-namespace bug** that broke
GPU context creation inside the container (`88323bf90`).

## Known-broken (expected)
- **Bluetooth** — `af_bluetooth.c:69` `BUG_ON` panic; masked in userspace (kernel-rebuild fix pending).
- **Native (Droidian-side) camera** — no libcamera path; the old `QUERYCAP` kernel panic is **fixed** (`4c225c879`), and the camera works via Waydroid's Android HAL.
- **PulseAudio → Samsung HAL routing/volume parameters never arrive** (dies in the droid-hidl/HIDL-shim chain) — output selection in GNOME Settings is empty and max speaker volume trails stock Android; the 3.5mm jack works via the mixer-level `r7-jack-router` daemon instead (sub-second speaker blip at stream start is a known quirk).
- **Browsers can't reach the HW video decoder** (no VA-API/usable V4L2 on the 4.9 kernel) — browser video is SW-decoded; runs hot on long sessions. Epiphany crashes on YouTube (WebKit MSE). The Waydroid YouTube app is the HW-decode path.

## Layout
| Path | What |
|------|------|
| `BOOT-STATUS.md` | **start here** — current state + the full fix chain that got to D2 |
| `PROGRESS.md` | session-by-session bring-up log |
| `docs/` | porting study, HW video-decode notes, safety/unbrick guide |
| `device-r7/` | adaptation files — `audio/`, `bluetooth/`, `video/`, `display/` (services, scripts, configs) |
| `scripts/` | flash / restore / debug helpers |
| `workaround/` | best-effort HW-accel notes |
| `debug/` | captured `kmsg` / journal crash logs from bring-up |
| `firmware/`, `ref/`, `out/`, `*.img` | **gitignored** (large blobs / build output) |

## Re-apply after a rootfs reflash
Several fixes live only in the rootfs LV (bluetooth mask, `panic_on_oops=0`,
camera-block udev rule, HW-video launcher). Only the kernel defconfig change is in
the kernel repo. The exact re-apply list is in **`BOOT-STATUS.md`** (the
"RE-APPLY IF ROOTFS REFLASHED" section) and `device-r7/*/README.md`.

## Related
- Kernel source (the `droidian-r7` branch that boots this): **[9810-linux/android_kernel_samsung_n770f](https://github.com/9810-linux/android_kernel_samsung_n770f)**
- Mainline kernel effort (WIP): **[9810-linux/note10lite-r7-mainline](https://github.com/9810-linux/note10lite-r7-mainline)**
