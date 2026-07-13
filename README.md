# note10lite-droidian

[Droidian](https://droidian.org/) (Debian-based mobile Linux, Halium) port for the
**Samsung Galaxy Note 10 Lite** — `SM-N770F`, codename **`r7`** (Exynos 9810).
This repo holds the **port documentation and device adaptation** (scripts, service
units, config), not the rootfs image.

> **Status: D2 — usable phone.** Phosh boots to a working desktop on
> `4.9.191-samsung-r7`, confirmed on-device. Stable, boots straight to Phosh.

## What works
Display · touchscreen · Phosh shell · PIN login · WiFi · Settings · charging ·
display scaling · on-screen keyboard · on-device terminal · **audio (speaker)** ·
**hardware video decode** (Clapper / `droidvdec`, Exynos MFC) ·
**YouTube 1080p60 in Chromium** (SW decode, smooth on stock scaling — see
`device-r7/video/README.md` for the 3-part recipe).

## Known-broken (expected)
- **Bluetooth** — `af_bluetooth.c:69` `BUG_ON` panic; masked in userspace (kernel-rebuild fix pending).
- **Camera** — `fimc_is` `QUERYCAP` NULL-deref panics on any camera V4L2 node; blocked via udev.
- **Browsers can't reach the HW video decoder** (no VA-API/usable V4L2 on the 4.9 kernel) — browser video is SW-decoded; runs hot on long sessions. Epiphany crashes on YouTube (WebKit MSE).

## Layout
| Path | What |
|------|------|
| `BOOT-STATUS.md` | **start here** — current state + the full fix chain that got to D2 |
| `PROGRESS.md` | session-by-session bring-up log |
| `docs/` | porting study, HW video-decode notes, safety/unbrick guide |
| `device-r7/` | adaptation files — `audio/`, `bluetooth/`, `video/` (services, scripts, configs) |
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
