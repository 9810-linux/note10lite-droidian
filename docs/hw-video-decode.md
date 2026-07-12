> **✅ RESOLVED sesi-18 (2026-07-10).** HW video decode **works** via Clapper. The "three
> display walls" below (esp. the GL crash) were a **test-harness artifact**: sesi-16 ran
> Clapper/`gst-launch` over SSH **without the graphical session's hybris-GL env**
> (`GDK_GL=gles`, `GST_GL_API=gles2`, `LD_PRELOAD=…:libglesshadercache.so`, `EGL_PLATFORM=wayland`).
> With that env replicated — or simply by launching from the Phosh app grid (which inherits it) —
> **Clapper creates `droidvdec` (Exynos MFC HW decoder) and plays local H.264 + live YouTube
> (yt-dlp) smoothly, correct picture, no skew, no GL crash** (user-confirmed on-device). The
> diagonal-skew described below was only the hand-rolled `waylandsink` SHM path; Clapper's
> GTK4-GL paintable path is correct. Deliverables in **`device-r7/video/`** (`youtube-hw` launcher +
> Firefox H.264 palliative). Browsers still can't reach the HW decoder (no VA-API / Mali accel off)
> → HW video is native-app-only. The investigation below is kept for historical context.

# HW video decode on r7 Droidian — investigation (sesi-16, 2026-07-09 night)

**Goal:** stop YouTube stutter by getting hardware video decode. User daily-drives the phone
(D2, Phosh). Reported: browser YouTube stutters.

## TL;DR
- **The HW decoder WORKS.** Exynos MFC (`/dev/video6 = s5p-mfc-dec0`) is reachable via
  `gst-droid` → element **`droidvdec`**, which HW-decodes **H.264 + VP9 up to 1080p60**.
  Proven by streaming a live YouTube VP9 1080p60 feed through it with zero decode errors.
- **The stutter is NOT the decoder.** The default browser is **Chromium**, which decodes
  `<video>` internally (would need VA-API, absent here) → always software decode → stutter.
  No browser setting changes this.
- **BUT: displaying the decoded frames correctly is blocked** by three separate walls (below).
  We could decode but not show a *watchable* (un-skewed, correct-color) picture. This is the
  "HW video decode is largely unsolved on Halium" reality the earlier notes warned about.
- **Decision pending (user, next day):** pick a path — see "Resume: pick one" at the bottom.

## What works / what was verified
- `gstreamer1.0-droid` installed and healthy. `droidvdec` **Rank primary+1 (257)** — outranks
  every software decoder (`avdec_h264`=256, `avdec_vp9`=64, `vp9dec`, `openh264dec`). So
  GStreamer's decodebin/playbin *auto-selects the HW decoder* for H.264 and VP9.
- `droidvdec` sink caps: `video/mpeg, video/x-h264, video/x-h263, video/x-vp8, video/x-vp9`.
- Android media HAL server side is fully up in the container: `minimediaservice` (pid ~240),
  `samsung.software.media.c2@1.0-service` (real Samsung Codec2 HW codec), `media.codec`,
  `vendor.media.omx`, `media.swcodec` — all `[running]`.
- `droidvdec` SRC pad output: `video/x-raw(memory:DroidMediaQueueBuffer), format=YV12,
  1920x1088` — an **opaque Android gralloc buffer** straight from the HW decoder.
- **A pipeline that DISPLAYS video (but skewed):**
  `filesrc ! qtdemux ! h264parse ! droidvdec ! videoconvert ! waylandsink fullscreen=true`
  → shows a *recognizable but diagonally-skewed, color-broken* Big Buck Bunny. Recognizable
  ⇒ the buffer is **linear with a padded stride**, NOT tiled.

## The three display walls (root causes)
1. **GL path crashes (the *correct* path).** `droideglsink`/`droidvideotexturesink` are the
   intended consumers of the opaque gralloc buffer (GPU samples it → correct stride/color,
   zero-copy). But any GTK/GStreamer-GL app crashes at GL init:
   `Unable to interpret GL_VERSION string:` (empty) → core dump. Confirmed on **Clapper** AND
   **Epiphany/WebKit** (identical crash). The Phosh UI itself works because GTK apps fall back
   to software (cairo); a GStreamer GL video sink demands a real HW GL context that libhybris
   doesn't hand to apps outside the compositor.
   - NB: bare `droidvdec ! droideglsink` from `gst-launch` does *not* crash and runs at realtime
     with no error — but shows **nothing**, because `droideglsink` has **no window of its own**
     (it only does caps/`propose_allocation`; it renders into a window an *app* must provide).
2. **No zero-copy dmabuf.** `waylandsink` warns `Could not bind to zwp_linux_dmabuf_v1` — **phoc
   does not advertise `linux-dmabuf`**, so waylandsink can't import the decoder's gralloc dmabuf
   directly (which would let the compositor/GPU handle stride correctly). Falls back to wl_shm.
3. **SHM/CPU path has a stride mismatch (→ diagonal skew + broken color).** `videoconvert`
   reads `droidvdec`'s YV12 buffer assuming stride = width (1920), but the real luma stride is
   **padded** (best guess **2048** = next 256-align). Off-by-stride each row ⇒ diagonal shear,
   color broken. **Cannot be corrected downstream:** inserting
   `capssetter caps=...width=2048...` to reinterpret the stride **breaks droidvdec's buffer
   pool** → `No valid frames decoded` (0 frames). The stride fix must happen *inside* gst-droid
   (attach correct `GstVideoMeta`), or be avoided via the GL/dmabuf paths.

## Sharp edges discovered (save yourself the pain)
- **`droidvdec` needs a real sink to propose its buffer pool.** `droidvdec ! fakesink`,
  `! jpegenc ! multifilesink`, and **`! decodebin`** all fail with `No valid frames decoded`
  + `gst_query_set_nth_allocation_pool: assertion 'index < array->len'`. Only a pool-proposing
  sink like `waylandsink` (via `videoconvert`) makes it decode. ⇒ **use an explicit pipeline,
  never decodebin/playbin-with-fakesink; frame-grabbing for debug is hard.**
- A failed `droidvdec` teardown leaves `gst-launch-1.0` **spinning in the GStreamer segv
  handler** ("Spinning. Please run 'gdb'…") pegging a core and **hanging SSH**. Always
  `pkill -9 -x gst-launch-1.0` between experiments.
- **Load average ~11 is MISLEADING** — `top` shows CPU basically idle (no proc >~10%, 2
  runnable). It's D-state tasks (Android container/binder). **Not** the stutter cause.
- 1080p shows an **8-row green bar** at bottom (1080→1088 16-alignment padding) — cosmetically
  fixable with `videocrop bottom=8`, but the skew is the real problem.
- `gst-play-1.0 --videosink` won't help: playbin auto-picks `droideglsink` (rank primary 256,
  beats waylandsink 64) → invisible; and forcing a sink runs into the pool/stride issues.

## On-device facts / how to reproduce
- Session env for any gst client over SSH: `export XDG_RUNTIME_DIR=/run/user/32011
  WAYLAND_DISPLAY=wayland-0` (droidian UID=32011; Wayland socket `wayland-0`).
- **Packages installed this session** (persist in the rootfs LV; **lost on a rootfs reflash**):
  `gstreamer1.0-tools`, `gstreamer1.0-plugins-base-apps`, `yt-dlp`. (`gstreamer1.0-droid` was
  already present.)
- Test clips (in `/tmp`, **gone after reboot** — re-fetch):
  `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4`
  and `.../webm/vp9/1080/...webm`. YouTube test id `aqz-KE-bpKQ` (Big Buck Bunny).
- Player script saved to repo: `scripts/ythw.sh` (scp to phone; plays YouTube via yt-dlp +
  the HW pipeline). ⚠ Currently produces the **skewed** picture — it's a scaffold for whichever
  display fix lands, not a finished player.
- Default browser = **Chromium** (`chromium.desktop`). Epiphany/WebKit installed
  (`libwebkit2gtk-4.1` 2.52.3) but GL-crashes.

## Research findings (sesi-16, web) — this reprioritizes the plan
- **Droidian officially supports HW video playback since Halium 12** — Droidian blog "State of
  Droidian Week 36 2023": *Erik fixed the issue blocking video playback; **Clapper and
  Celluloid now use hardware video playback**.* Our device is Halium **13** (api33). So HW video
  is a **solved, sanctioned Droidian path via Clapper/Celluloid** — and Clapper is already
  installed here. ⇒ **Our only real blocker is the GL crash** that kills Clapper on this device.
  Getting Clapper to run = getting HW video (correct display, done by the Droidian devs).
- **gst-droid already handles stride correctly** — `sailfishos/gst-droid`
  `gst/droidcodec/gstdroidvdec.c` has `gst_droidvec_copy_plane` (per-plane stride-aware copy).
  ⇒ our diagonal skew is because our hand-rolled `droidvdec ! videoconvert ! waylandsink` path
  **bypasses** the intended GL-sink path; it is NOT a gst-droid bug. Don't chase the SHM stride —
  use the sanctioned GL/Clapper path.
- The exact string `Unable to interpret GL_VERSION string:` is not documented publicly for
  Droidian. It's a GTK/GDK-GL / GStreamer-GL context-init failure (empty `glGetString(GL_VERSION)`
  = no valid current context). Next-day: search **Droidian & Clapper GitHub issues**, and compare
  this rootfs's app-side EGL/GBM/glvnd wiring against a *known-working* Droidian device (the
  compositor's Mali GL works, but **apps** don't get a GL context — likely a libhybris-EGL /
  `GBM_BACKEND` / egl-vendor config gap in the rootfs, or a missing device adaptation bit).

## Resume: pick one (REPRIORITIZED after research)
1. **Fix the GL crash → Clapper works = HW video (the sanctioned Droidian path). START HERE.**
   `Unable to interpret GL_VERSION string` kills Clapper/Celluloid/WebKit. On other Droidian
   devices these play HW video fine (Halium 12+). So this is a **device-adaptation / EGL wiring**
   gap, not a dead end. To chase:
   - Compare app-side EGL: `eglinfo`/`es2_info` as the `droidian` user (not just compositor).
     The compositor uses Mali via libhybris; check whether *apps* get the same EGL vendor.
   - Check `GBM_BACKEND`, `__EGL_VENDOR_LIBRARY_*`, `/usr/share/glvnd/egl_vendor.d/`,
     `mesa-hybris`/`libhybris-egl-platform`, and any Droidian env that points GTK/GStreamer-GL at
     hybris EGL. Try `GST_GL_PLATFORM=egl GST_GL_API=gles2 GST_GL_WINDOW=wayland`, `GDK_GL`,
     `GSK_RENDERER`.
   - Search **github.com/droidian-images/droidian** + **github.com/Kaleidoscope-** and
     **Clapper** issues for the GL_VERSION crash on Exynos/Halium-13 devices.
   - Look for the Droidian **device adaptation** that other working devices ship (hybris GL /
     egl config packages) — we reached Phosh on the *generic* rootfs and skipped full device
     adaptation (PROGRESS sesi-15b), so an app-GL adaptation bit is plausibly what's missing.
2. **crownlte / Exynos 9810 Halium reference.** crownlte is the proven 9810 Halium baseline
   (`ref/linux-android-samsung-crownlte`). Check how crownlte/star2lte Droidian ports set up
   app-side GL + gst-droid video (its `device/` adaptation, hybris-GL packages, phoc.ini). Same
   SoC ⇒ same Mali-G72 blob path; whatever it does for Clapper video applies to r7.
3. **Enable `linux-dmabuf` in phoc/wlroots** (alt proper fix, if GL stays broken). If phoc could
   advertise `zwp_linux_dmabuf_v1`, `waylandsink` imports the decoder's gralloc dmabuf zero-copy
   → GPU handles stride → correct + smooth. Unknown: wlroots **hwcomposer** backend dmabuf export.
4. **Browser palliative** (reliable, ~10 min, NOT HW — the *symptom* fix if HW paths stall):
   Chromium + `enhanced-h264ify` (force H.264, lighter than VP9 for SW decode) + cap 480/720p →
   far fewer dropped frames, stays in the browser.
   *(Dropped the "patch gst-droid stride" idea — research shows gst-droid stride is fine; the SHM
   skew is from bypassing the GL path, so fixing GL is the right lever.)*

**Also still open (unrelated, high value):** audio HAL bring-up (all HW-video paths are
video-only until audio works) — see PROGRESS.md sesi-15b (32-bit `vendor.audio-hal` HIDL
service won't start).
