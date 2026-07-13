# r7 video (current state: sesi-19, 2026-07-13)

**YouTube 1080p60 plays smooth in Chromium on stock frequency scaling** (software
decode — the 8-core 9810 decodes H.264 1080p60 at 2.4× realtime; Chromium composites
on the Mali-G72 via hybris ANGLE). Hardware decode (`droidvdec`, Exynos MFC) still
works through GStreamer for native apps — Clapper remains installed for local files.

## The recipe (all three parts required)

1. **YouTube player settings** (per account, sticky): **ambient mode OFF,
   annotations OFF**. Ambient mode re-renders every frame as a blurred canvas glow —
   it was the single biggest frame-eater.
2. **enhanced-h264ify** force-installed via `chromium/h264ify.json` →
   `/etc/chromium/policies/managed/`. Then **one manual step** (options live in
   extension local storage; no policy can set them): ⋮ → Extensions →
   enhanced-h264ify → Options →
   - ✅ block VP9  ✅ block AV1
   - ❌ block 60fps (**must stay unchecked**)
   - no resolution limit (or 1080p)

   This pins `avc1` at every resolution. Without it YouTube serves VP9 at 720p60
   (slower libvpx decoder → 720p60 stuttered *worse* than 1080p60).
3. Nothing else. Frequency pinning was bracket-tested (CPU 1794 MHz → stock, Mali
   572 MHz → none) and is **not needed** on a cool phone. If drops creep in on a hot
   phone, the floor that measured smooth mid-bracket was: `scaling_min_freq`
   1053000 (policy0) / 1170000 (policy4), Mali `dvfs_min_lock` 455000
   (`/sys/devices/platform/17500000.mali`). Resets on reboot.

## What ships here

| File | Installs to | Status |
|------|-------------|--------|
| `chromium/h264ify.json` | `/etc/chromium/policies/managed/` | **active** — codec lock (see manual options above) |
| `webkit/r7-webkit-egl.conf` | `/etc/tmpfiles.d/` | **active** — dev symlinks (`libEGL.so`, `libGLESv2.so`) so WebKitGTK gets EGL; Epiphany HW-decodes plain HTML5 `<video>` |
| `firefox/zzz-r7-youtube-h264.js` | `/usr/lib/firefox/defaults/pref/` | deployed but moot — Firefox video is broken on this port (Droidian disables Mali GL accel) |

## Re-apply after a rootfs reflash

1. `install -d /etc/chromium/policies/managed && install -m0644 chromium/h264ify.json /etc/chromium/policies/managed/`
   then set the extension options manually (block VP9+AV1, **not** 60fps).
2. `sudo install -m0644 webkit/r7-webkit-egl.conf /etc/tmpfiles.d/ && sudo systemd-tmpfiles --create /etc/tmpfiles.d/r7-webkit-egl.conf`
3. In the YouTube player: ambient mode OFF, annotations OFF, quality 1080p60.

## Removed in sesi-19 housekeeping (device + repo)

`youtube-hw` Clapper launcher (git history: commit `30638f1`), the *Video Boost*
freq-pinning toggle (values preserved in recipe step 3 above), and the SMPlayer /
VacuumTube flatpaks — all obsoleted by smooth in-browser playback.

## Known limits / facts (verified sesi-16..19)

- **Browsers cannot reach the HW decoder** on the 4.9 downstream kernel: no VA-API
  backend exists for Exynos MFC, and the Samsung `exynos/mfc` driver is HAL-only
  V4L2 (no `V4L2_EVENT_SOURCE_CHANGE`, decode-order output) → GStreamer
  `v4l2h264dec`/ffmpeg `h264_v4l2m2m` can't drive it. Only `gst-droid`/`droidvdec`
  (Codec2 HAL) works — don't re-litigate; see the 2026-07-13 kernel-source analysis.
- **Heat is the cost of SW decode** (~51 °C SoC after an hour) — throttling then eats
  the smoothness margin; Clapper (HW) is the cool path for long local playback.
- **Epiphany + youtube.com still crash-loops** (WebKit MSE SIGSEGV on Halium/Mali);
  plain `<video>` HW-decodes fine. Open lead: Invidious/Piped frontend.
- No DRM render node on Halium → no zero-copy/dmabuf anywhere (Chromium's
  `drmGetDevices2()` errors are harmless; phoc logs "Linux dmabuf unavailable").
- phoc may restart if a fullscreen client dies abruptly — self-recovers, no reboot.
