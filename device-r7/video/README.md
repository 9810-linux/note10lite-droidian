# r7 video / HW decode (sesi-18, 2026-07-10)

## TL;DR — hardware video decode WORKS on r7, via Clapper (not browsers)

The sesi-16 conclusion "the GL crash blocks Clapper → HW video unsolved" was a
**false alarm**. That session ran Clapper/`gst-launch` **over SSH without the
graphical session's hybris-GL environment**, which is what produced
`Unable to interpret GL_VERSION string`. The real Phosh session exports the env
that app-side GL needs (set by `droidian-quirks-hybris-gl`
`/etc/profile.d/zz-droidian.sh` + the session):

```
EGL_PLATFORM=wayland  GDK_GL=gles  GST_GL_API=gles2
COGL_DISABLE_MAPBUFFERRANGE=true
LD_PRELOAD=libtls-padding.so:libgtk6216workaround.so:libglesshadercache.so
```

With that env, **Clapper creates `droidvdec` (Exynos MFC HW decoder) and plays
local H.264 AND live YouTube (via yt-dlp) — smooth, correct picture, no skew, no
GL crash.** Confirmed on-device by the user (sesi-18). The old diagonal-skew was
only on the hand-rolled `droidvdec ! videoconvert ! waylandsink` SHM path; Clapper
uses the correct GTK4-GL paintable path, which handles stride via the GPU.

**Apps launched from the Phosh app grid inherit this env automatically** — so a
launcher only needs to run `yt-dlp -> clapper`; no env wrangling required.

## The hard limit (unchanged): browsers can't use the HW decoder

- **Chromium**: decodes `<video>` internally, needs VA-API (absent on Halium) →
  always software.
- **Firefox**: Droidian deliberately disables GPU accel on Mali
  (`layers.acceleration.disabled=true`, `hybris-gpu.js`) → software too.
- HW decode is reachable **only through GStreamer/Clapper** = a native app.

## What ships here

### Path B — native HW YouTube (the real fix), **60fps + audio**
- **`youtube-hw`** → `/usr/local/bin/youtube-hw` (0755, root)
  Takes a URL arg, or reads the Wayland clipboard (`wl-paste`). Plays via Clapper
  (HW `droidvdec`) up to **720p60 with audio** (`YT_MAXH=1080` for 1080p60).
  YouTube 60fps is video-only DASH, so the script has `yt-dlp`+`ffmpeg` **mux the
  chosen video+audio on the fly through a FIFO** into Clapper — keeping Clapper's
  working GTK4-GL display path. Format preference: H.264 60fps → VP9 60fps → any
  ≤720p → muxed 22/18. Confirmed `matroskademux → h264parse → droidvdec` on a live
  720p60 stream (sesi-18). Needs `wl-clipboard` + `ffmpeg` (installed sesi-18).
- **`youtube-hw.desktop`** → `/usr/local/share/applications/youtube-hw.desktop`
  App-grid entry "YouTube (HW)". Flow: copy a YouTube link in the browser →
  tap the icon → plays with hardware decode.
- Clapper itself (already installed) plays **local files + network video** with HW
  decode straight from the app grid.

### Path A — in-browser palliative (software, best-effort only)
⚠ **Browser video is fragile on this device.** Software decode + Mali GL under load
can crash the GPU process (then *everything* stutters until the browser is fully
closed) and, at 1080p/60fps, has **rebooted the phone** (sesi-18, under heavy
Chromium 60fps load). Treat the browser as casual/low-res only; use the HW app for
anything demanding. No browser setting fully removes this — it's the SW-decode +
libhybris-GL ceiling.

- **Chromium (the one that actually plays here)** — force-install enhanced-h264ify
  via managed policy: `chromium/h264ify.json` → `/etc/chromium/policies/managed/`.
  Chrome ext id `omkfmpieigblcllmkgbflkikinpkodlk`. **One manual step** (no policy
  can set it — extension uses local storage): Chromium ⋮ → Extensions →
  enhanced-h264ify → **Options → tick "Block 60fps"** and set max resolution 720p.
  That forces H.264 30fps ≤720p → far lighter SW decode, avoids the 60fps crash.
- **Firefox — BROKEN for video here, do not use.** Exits/crashes immediately on
  YouTube (Halium + Mali; Droidian ships `layers.acceleration.disabled=true`).
  Prefs below are installed and harmless but do NOT make Firefox video work.
  - `firefox/zzz-r7-youtube-h264.js` → `/usr/lib/firefox/defaults/pref/`
    (force H.264, disable the broken HW-video/vaapi probe path).
  - enhanced-h264ify force-installed via `/etc/firefox/policies/policies.json`
    `ExtensionSettings` (backup `policies.json.orig-r7`):
    key `{9a41dee2-b924-4161-a971-7fb35c053a4a}`.

### Epiphany (GNOME Web / WebKitGTK) — **in-browser HARDWARE video** ✨ (sesi-18)
Unlike Chromium/Firefox (internal ffmpeg SW decode), **WebKitGTK decodes HTML5
`<video>` through GStreamer → auto-selects `droidvdec` (HW)**. It was crashing only
because of a missing library symlink:
- **Root cause:** `libwebkitgtk-6.0.so.4` `dlopen()`s **unversioned** `libEGL.so` /
  `libGLESv2.so`, but Droidian ships only the versioned glvnd dispatchers
  (`libEGL.so.1`, `libGLESv2.so.2`). Missing → WebKit's GPU/media process gets no
  EGL → web process crashes on video.
- **Fix:** `webkit/r7-webkit-egl.conf` → `/etc/tmpfiles.d/` creates the two dev
  symlinks (→ glvnd → libhybris → Mali) at boot. Apply now:
  `sudo systemd-tmpfiles --create /etc/tmpfiles.d/r7-webkit-egl.conf`.
- The WebKit **sandbox is already disabled** by `droidian-quirks-hybris-gl`
  (`WEBKIT_FORCE_SANDBOX=0` + `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` in the
  session env), which is required for the sandboxed WebProcess to resolve EGL.
- **Result:** local HTML5 video plays in WebKit with HW decode + no crash;
  YouTube builds `qtdemux/matroskademux → h264parse/vp9parse → droidvdec`
  (VP9+H.264, incl. 60fps). Verified `MiniBrowser` runs YouTube 35s with no crash.
  ⇒ **Epiphany = a real browser doing in-browser HW video on r7.**

## Re-apply after a rootfs reflash (these live only in the rootfs LV)
1. `sudo apt-get install -y wl-clipboard ffmpeg`
2. `install -m0755 youtube-hw /usr/local/bin/youtube-hw`
3. `install -m0644 youtube-hw.desktop /usr/local/share/applications/` +
   `update-desktop-database /usr/local/share/applications`
4. `install -m0644 firefox/zzz-r7-youtube-h264.js /usr/lib/firefox/defaults/pref/`
5. Add the enhanced-h264ify entry to `/etc/firefox/policies/policies.json`
   `ExtensionSettings` (see key/url above).
6. `install -d /etc/chromium/policies/managed && install -m0644 chromium/h264ify.json /etc/chromium/policies/managed/`
7. `sudo install -m0644 webkit/r7-webkit-egl.conf /etc/tmpfiles.d/ && sudo systemd-tmpfiles --create /etc/tmpfiles.d/r7-webkit-egl.conf`  (Epiphany in-browser HW video)

## Notes / future
- Default cap is **720p60** (smooth + safe on-device); `YT_MAXH=1080` allows
  1080p60 (droidvdec proven to 1080p60, but heavier on the compositor).
- FIFO path adds ~3–5s startup (yt-dlp+ffmpeg spin-up) — the notify covers it.
- Reference scaffold `scripts/ythw.sh` (sesi-16) used the skewed SHM path — the
  `youtube-hw` launcher here supersedes it (Clapper GL path = correct).
