# note10lite-droidian

[Droidian](https://droidian.org/) (Debian-based mobile Linux, Halium) port for the
**Samsung Galaxy Note 10 Lite** — `SM-N770F`, codename **`r7`** (Exynos 9810).
This repo holds the **port documentation and device adaptation** (scripts, service
units, config), not the rootfs image.

> **Status: D2 — daily-usable phone with Android apps and mobile data.** Phosh
> boots straight to a working desktop, confirmed on-device and stable.
> **Waydroid runs LineageOS 20 with Play Store** (sesi-20), **mobile data and LTE
> work** on an unattended clean boot (sesi-21/22), and **flatpak apps launch**
> after a kernel `statx()` backport (sesi-22). D2 is still short of complete
> because **Bluetooth panics** and stays masked; calls and SMS (D3) have not been
> verified yet. Latest field reports are sesi-23 — see [`PROGRESS.md`](PROGRESS.md).

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
with HW decode, smoother than the browser) ·
**mobile data / telephony** (ofono-binder-plugin + ofono2mm + ModemManager;
SIM detect, LTE registration, mobile data all confirmed working on an unattended
clean boot — needs a startup gate that holds ModemManager until ofono has actually
enumerated the SIM, or the modem latches `sim-missing` forever, plus a 4G-only
restriction and an RSRP-corrected signal scale, all in `device-r7/modem/`) ·
**Software store + flatpak apps** (flathub; confirmed with a 1.4 GB ONLYOFFICE
install via the UI — note gnome-software says "Pending installation" with no
progress bar while it downloads, cosmetic only. Launching any flatpak needed a
kernel `statx()` backport, see below) ·
**Portfolio & Python GTK4 apps** (crash on GL renderer via libhybris EGL; per-app
`GSK_RENDERER=cairo` desktop override, `device-r7/apps/`).

## Kernel fixes this port needed
All on branch [`droidian-r7`](https://github.com/9810-linux/android_kernel_samsung_n770f/tree/droidian-r7).

For **Waydroid**: `BRIDGE`/`VETH` + `NETFILTER_XT_TARGET_CHECKSUM` for
`waydroid-net` (`856ffe866`, `57fbcf609`), a **fimc-is2 `querycap` wrong-struct
deref** that kernel-panicked the phone on any V4L2 `QUERYCAP` (`4c225c879`), and a
**Mali kbase pid-namespace bug** that broke GPU context creation inside the
container (`88323bf90`).

For **flatpak**: a **`statx()` backport** (`fc2e752fa`). Without it *no* flatpak
app could start at all — `statx()` landed upstream in 4.11 and this tree is 4.9,
so every app died on `statx(): Function not implemented`. The backport adds the
upstream `struct statx`, `SYSCALL_DEFINE5(statx)` on arm64 slot 291 and
arm32-compat slot 397 (the compat slot also helps 32-bit Waydroid apps), and
**`STATX_MNT_ID`** — reporting only `STATX_BASIC_STATS` wasn't enough, flatpak
asks for the mount ID too. `STATX_MNT_ID_UNIQUE` (6.8) is deliberately *not*
faked: flatpak runs fine on 6.1 kernels without it.

## Known-broken (expected)
- **Bluetooth** — `af_bluetooth.c:69` `BUG_ON` panic; masked in userspace (kernel-rebuild fix pending).
- **Native (Droidian-side) camera** — no libcamera path; the old `QUERYCAP` kernel panic is **fixed** (`4c225c879`), and the camera works via Waydroid's Android HAL.
- **PulseAudio → Samsung HAL routing/volume parameters never arrive** (dies in the droid-hidl/HIDL-shim chain) — output selection in GNOME Settings is empty and max speaker volume trails stock Android; the 3.5mm jack works via the mixer-level `r7-jack-router` daemon instead (sub-second speaker blip at stream start is a known quirk).
- **Browsers can't reach the HW video decoder** (no VA-API/usable V4L2 on the 4.9 kernel) — browser video is SW-decoded; runs hot on long sessions. Epiphany crashes on YouTube (WebKit MSE). The Waydroid YouTube app is the HW-decode path.
- **GPS works on stock Android but is broken inside Waydroid** — so the BCM4773 and its antenna are fine; the gap is container-side. Untested hypothesis: the vendor GNSS daemon and GNSS HAL never start in the container, the same way `vendor.audio-hal` doesn't (Android `init` skips vendor services whose `.rc` has no `interface` lines) — Maps still half-working fits a Play-Services network-location fallback. Needs a live session to confirm; see the tracker row in `PROGRESS.md`.
- **Fingerprint reader — not working, and the Settings menu doesn't mean it is** (that's Droidian's `fpd` UI, which shows up with or without a HAL behind it). Touching the reader spot with the screen off *does* wake the phone, but that's the touch controller still reporting its low-power fingerprint region, not the optical sensor (`etspi`/`et7xx`) responding — no illumination, no capture. Unverified beyond that.

## Layout
| Path | What |
|------|------|
| `BOOT-STATUS.md` | **start here** — current state + the full fix chain that got to D2 |
| `PROGRESS.md` | session-by-session bring-up log |
| `docs/` | porting study, HW video-decode notes, safety/unbrick guide |
| `device-r7/` | adaptation files — `audio/`, `bluetooth/`, `video/`, `display/`, `modem/` (services, scripts, configs) |
| `scripts/` | flash / restore / debug helpers |
| `workaround/` | best-effort HW-accel notes |
| `debug/` | captured `kmsg` / journal crash logs from bring-up |
| `firmware/`, `ref/`, `out/`, `*.img` | **gitignored** (large blobs / build output) |

## Re-apply after a rootfs reflash
Several fixes live only in the rootfs LV (bluetooth mask, `panic_on_oops=0`,
camera-block udev rule, gstreamer V4L2 plugin disabled, display scale, and
`graphical.target` as default). Only the kernel defconfig change is in the kernel
repo. The exact re-apply list is in **`BOOT-STATUS.md`** (the "RE-APPLY IF ROOTFS
REFLASHED" section) and `device-r7/*/README.md`.

## Related
- Kernel source (the `droidian-r7` branch that boots this): **[9810-linux/android_kernel_samsung_n770f](https://github.com/9810-linux/android_kernel_samsung_n770f)**
- Mainline kernel effort (WIP) — port workspace: **[9810-linux/note10lite-r7-mainline](https://github.com/9810-linux/note10lite-r7-mainline)**,
  kernel branch: **[9810-linux/linux-exynos9810 `exynos9810-r7`](https://github.com/9810-linux/linux-exynos9810/tree/exynos9810-r7)**
  (Exynos 9810 CMU clock driver, UART earlycon, CPU-topology fix, r7 board DTS)

## Authorship and license
This port — the device adaptation, the flashing and recovery tooling, the D0
bring-up initramfs, and the research written up in `PROGRESS.md` — is the
original work of **Zulfikar Aji Kusworo (`zakusworo`)**
<greataji13@gmail.com>.

Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo).
Licensed **GPL-2.0-only** — see [`LICENSE`](LICENSE) and [`AUTHORS`](AUTHORS).

Kernels built from the [`droidian-r7`](https://github.com/9810-linux/android_kernel_samsung_n770f)
branch carry the same signature: `uname -r` reports
`4.9.191-samsung-r7-zakusworo`, `/proc/version` reports `(zakusworo@9810-linux)`,
and `dmesg` names the port in its first lines. Committed 2026-07-25 — a phone
flashed before then still reports the un-suffixed `4.9.191-samsung-r7`.

Forks and derivatives are welcome under the GPL. It requires you to keep the
copyright notices intact, state your changes, and release your derivative under
the same license — please also credit the original port and link back here.
