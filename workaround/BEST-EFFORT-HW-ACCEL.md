# Best Effort to Fix HW Acceleration on r7 (Mali-G72 / Exynos MFC)

This is the real fix, not the SHM stride workaround. Goal: make Clapper / Celluloid use `droideglsink` with zero-copy EGLImage, which is the official Droidian HW video path: *Tools like celluloid and clapper now use hardware video playback.*

## Why phoc works but Clapper doesn't

- **phoc (compositor)** = `HWCOMPOSER-1` backend. It loads `/vendor/lib64/egl/libGLES_mali.so` directly via `eglplatform_hwcomposer.so` (libhybris hwcomposer platform). It creates its own EGLDisplay via `hwcomposer` -> succeeds -> UI is GPU accelerated.
- **Apps (Clapper, gst-launch, Epiphany)** = Wayland clients. They use `EGL_KHR_platform_wayland`. libhybris must provide `eglplatform_wayland.so` that implements `EGL_WL_bind_wayland_display` and then forwards to hwcomposer gralloc. On r7 port, this platform is missing or Mesa's `libEGL.so` is loaded first, so `eglChooseConfig` returns 0 configs -> `eglMakeCurrent` fails -> `glGetString(GL_VERSION)` returns NULL -> `gst_egl_adaptation_init_exts` does `glexts = glGetString(GL_EXTENSIONS)`[^1] with NULL context -> abort `Unable to interpret GL_VERSION string:`.

So fix is to make Wayland EGL work via hybris.

## Level 1 - Userspace config (15 min, no rebuild)

You already have these in the zip, but here is the ordered best-effort:

```bash
# 1. Verify what you have
ls -l /usr/lib/aarch64-linux-gnu/libhybris/
# you need:
# eglplatform_hwcomposer.so
# eglplatform_wayland.so   <-- often missing on r7
# libEGL.so.1 -> common/libEGL.so.1
# libGLESv2.so.2 -> common/libGLESv2.so.2

eglinfo -B wayland 2>&1 | head -n 60
# should show: EGL vendor: Android, EGL version: 1.4 Android META-EGL
# if it shows Mesa / llvmpipe, wrong libEGL is loaded

# 2. Fix precedence
cat > /etc/ld.so.conf.d/00-hybris-r7.conf <<'EOF'
/usr/lib/aarch64-linux-gnu/libhybris
/usr/lib/aarch64-linux-gnu/libhybris/common
EOF
sudo ldconfig
sudo ldconfig -p | grep libEGL

# 3. Force env for whole user session (not just phoc)
mkdir -p ~/.config/environment.d/
cat > ~/.config/environment.d/99-r7-egl.conf <<'EOF'
EGL_PLATFORM=hwcomposer
HYBRIS_EGLPLATFORM=hwcomposer
GBM_BACKEND=droid
__EGL_VENDOR_LIBRARY_FILENAMES=/usr/lib/aarch64-linux-gnu/libhybris/egl/vendors.d/hybris.json
LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri
MESA_GL_VERSION_OVERRIDE=3.2
EOF
# logout / login or: systemctl --user import-environment; systemctl --user restart phosh

# 4. Test with libhybris test program
apt install hybris-tests || true
test_egl  # from libhybris examples, should print EGL version
test_glesv2 --wayland  # if exists
```

If `eglplatform_wayland.so` is missing, Level 1 will still fail. Go to Level 2.

## Level 2 - Borrow crownlte's hybris platform (30 min, no compile)

crownlte (Exynos 9810 Note9) is same SoC, same Mali-G72, same vendor blob. Its adaptation package contains working Wayland EGL platform.

```bash
# On host, download crownlte adaptation deb (example, check latest)
wget https://github.com/droidian-devices/adaptation-crownlte/releases/download/…/droidian-device-crownlte_*.deb
# or from Droidian repo:
# apt download droidian-device-crownlte

dpkg-deb -x droidian-device-crownlte*.deb /tmp/crownlte
ls /tmp/crownlte/usr/lib/aarch64-linux-gnu/libhybris/

# Copy only the EGL platform, not the whole lib (to avoid version mismatch)
sudo cp /tmp/crownlte/usr/lib/aarch64-linux-gnu/libhybris/eglplatform_wayland.so /usr/lib/aarch64-linux-gnu/libhybris/
sudo cp /tmp/crownlte/usr/lib/aarch64-linux-gnu/libhybris/eglplatform_hwcomposer.so /usr/lib/aarch64-linux-gnu/libhybris/ || true
sudo cp -r /tmp/crownlte/usr/lib/aarch64-linux-gnu/libhybris/egl/ /usr/lib/aarch64-linux-gnu/libhybris/ || true
sudo ldconfig

# Now test again
eglinfo -B wayland
GST_DEBUG=3 clapper --help 2>&1 | grep -i gl_version
```

If this fixes `Unable to interpret GL_VERSION`, Clapper will start and HW decode works immediately.

## Level 3 - Patch gstreamer to tolerate NULL GL_VERSION (proper workaround used by UBports)

Upstream `gst-plugins-base` `gst_egl_adaptation_init_exts` does:

```c
glexts = glGetString(GL_EXTENSIONS); // <-- This Line !!![^1]
```

If context creation failed partially, `glGetString` returns NULL and the plugin aborts. On Halium devices, context may be valid but `GL_VERSION` is empty string from hybris wrapper. Patch to make it non-fatal:

```c
// gst-plugins-base/gst-libs/gst/gl/egl/gstegl.c
glexts = (const gchar*) glGetString(GL_EXTENSIONS);
if (!glexts) glexts = "";
gl_version = (const gchar*) glGetString(GL_VERSION);
if (!gl_version || !*gl_version) gl_version = "OpenGL ES 3.2 (Hybris Fallback)";
```

Apply as Debian patch in `gstreamer1.0-plugins-base` or `gst-droid`:

File provided: `patches/0001-hybris-fallback-gl-version.patch`

Build:

```bash
apt source gstreamer1.0-plugins-base
cd gstreamer1.0-plugins-base-1.22*
patch -p1 < /path/to/0001-hybris-fallback-gl-version.patch
debuild -b -uc -us
sudo dpkg -i ../libgstreamer-gl1.0-0*.deb ../gstreamer1.0-plugins-base*.deb
```

This is what UBports did for JingPad / Halium 12 Mali devices. It doesn't fix EGL, it just prevents abort so droideglsink can continue with hybris context.

## Level 4 - Use droidvideosink (HWC overlay, no GL at all)

If GL remains broken, bypass it entirely. `droidvideosink` posts gralloc buffers directly to `hwcomposer`, same path phoc uses for UI. No `glGetString` needed.

```bash
gst-inspect-1.0 | grep droid
# should list: droidvdec, droidvideosink, droideglsink, droidcamsrc

# Test:
gst-launch-1.0 souphttpsrc location="$URL" ! matroskademux ! vp9parse ! droidvdec ! droidvideosink

# If droidvideosink needs permission:
sudo usermod -a -G video,render droidian
# And ensure /dev/graphics/* accessible
ls -l /dev/graphics/fb0 /dev/dri/
```

`droidvideosink` handles MFC stride internally via `gralloc` metadata, so no diagonal skew. This is actually the most efficient path (no GPU copy).

If `droidvideosink` is not built in your `gst-droid` package, rebuild `gst-droid` with `--enable-hwcomposer`:

```bash
apt source gstreamer1.0-droid
# debian/rules should have --with-eglplatform=hwcomposer
```

## Level 5 - Kernel dmabuf (future, optional)

`phoc` with `HWCOMPOSER-1` doesn't advertise `zwp_linux_dmabuf_v1`. To get `waylandsink` zero-copy:

- Enable `CONFIG_DMA_SHARED_BUFFER=y` (already), `CONFIG_DRM=y`
- Patch `phoc` to expose `linux-dmabuf` even on hwcomposer backend, importing hybris gralloc fd as dmabuf via `gralloc_handle->fd`

Not needed if Level 2 or 4 works.

## Recommended order for r7

1. **Level 1 + Level 2** = 80% chance to fix Clapper without compiling. Try borrowing crownlte's `eglplatform_wayland.so`.
2. If still `GL_VERSION` empty, **Level 3** patch gstreamer to ignore it.
3. If GL still unstable, **Level 4** switch Clapper backend to `droidvideosink`:
   ```bash
   gsettings set org.gnome.clapper video-sink '"droidvideosink"'
   # or launch: clapper --video-sink=droidvideosink
   ```
4. Keep Level 1 configs in adaptation package: `00-hybris-r7.conf`, `99-r7-egl.conf`, `99-block-fimc-cam.rules`.

## Validation checklist

After fix:

```bash
# Should show Android EGL, not Mesa
eglinfo -B wayland | grep -E 'vendor|version'

# Clapper should not crash
GST_DEBUG=2 clapper /path/to/1080p-vp9.webm 2>&1 | grep -i droidegl

# CPU should stay low during playback (HW decode)
top -p $(pidof clapper)  # ~15% not 90%

# No diagonal skew, colors correct
r7-yt-hw https://www.youtube.com/watch?v=jfKfPfyJRdk
```

If CPU ~15% and video smooth, HW accel is fixed. Then re-enable audio HIDL or keep ALSA workaround for audio.

[^1]: About QT & nveglglessink — https://forums.developer.nvidia.com/t/about-qt-nveglglessink/36069
