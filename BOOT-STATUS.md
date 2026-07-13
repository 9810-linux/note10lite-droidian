# Droidian boot status — SM-N770F (r7) — RESUME HERE (sesi-19, 2026-07-13)

## TL;DR (sesi-19 — **D2 ACHIEVED: usable Droidian phone**)
**Phosh boots to a working desktop.** Confirmed on-device by the user (photo/fastfetch):
`Kernel 4.9.191-samsung-r7`, `DE: Phosh (GNOME)`, `WM: phoc (Wayland)`, `GPU: ARM Mali-G72`,
1080×24xx display. **Working: display + touchscreen, Phosh shell, PIN login (`1234`),
WiFi, Settings, charging (battery reads, 100%), display scaling, on-screen keyboard,
terminal on-device, AUDIO (speaker, sesi-17), VIDEO HW-DECODE (sesi-18), **YouTube 1080p60
in Chromium (sesi-19, SW decode, smooth on stock scaling)**.** Stable. Boots straight to
Phosh (`default-target = graphical.target`).

### Sesi-19 — Chromium YouTube 1080p60 SOLVED — **current video-thread state**
**Goal:** 1080p60 YouTube in the browser without stutter (downstream kernel). **Outcome:
SOLVED on stock frequency scaling** — recipe + measurements in `device-r7/video/README.md`:
- ✅ **YouTube ambient mode + annotations OFF** (biggest fix — ambient = per-frame blur canvas).
- ✅ **enhanced-h264ify: block VP9+AV1, do NOT block 60fps** → `avc1` at all resolutions
  (YT's VP9-at-720p60 made 720p60 stutter *worse* than 1080p60: Chromium's libvpx < its
  ffmpeg-H.264 path). Manual options — see `device-r7/video/README.md`.
- ✅ Measured: SW decode H.264 1080p60 = 2.4× realtime, VP9 = 3.6×; Chromium composites on
  Mali-G72 (hybris ANGLE); freq pinning bracket-tested → **not needed when cool** (floors
  for hot conditions archived in the video README).
- ⚠️ Cost = heat (~51°C SoC after an hour of SW decode). Sesi-18's "Chromium 1080p60
  reboots the phone" did NOT reproduce; worst case = phoc restart on abrupt fullscreen
  teardown (self-recovers).
- 🧹 **Housekeeping:** `youtube-hw` launcher, Video Boost toggle, SMPlayer + VacuumTube
  flatpaks all REMOVED from device (Chromium is the YouTube path; Clapper stays for local
  files). VA-API / native-V4L2 ruled out on the 4.9 kernel (see PROGRESS.md sesi-19).

### Sesi-18 — HW video decode (YouTube) — *(historical; superseded by sesi-19 above)*
**Goal:** smooth YouTube. **Outcome: SOLVED via native app; in-browser partially solved.**
- ✅ **`youtube-hw` app** ("YouTube (HW)" in app grid): copy link → tap → **60fps + audio, HW `droidvdec`** (Exynos MFC). User-confirmed smooth. yt-dlp+ffmpeg mux video+audio through a FIFO into Clapper. `/usr/local/bin/youtube-hw` + `.desktop`.
- ✅ **Key correction:** sesi-16's "GL crash blocks Clapper/HW video" was a **test-harness artifact** (ran over SSH without the session hybris-GL env: `GDK_GL=gles GST_GL_API=gles2 LD_PRELOAD=…libglesshadercache.so`). With that env (or launched from the app grid) HW video just works.
- ✅ **Epiphany EGL fix:** WebKitGTK `dlopen`s unversioned `libEGL.so`/`libGLESv2.so` (Droidian ships only versioned glvnd) → added symlinks via `/etc/tmpfiles.d/r7-webkit-egl.conf`. Now WebKit HW-decodes **plain HTML5 `<video>`** (local video plays, no crash).
- ⏸️ **PAUSED / NEXT:** **YouTube in Epiphany still crash-loops** — WebKit's **MSE** path SIGSEGVs on this Halium/Mali platform. Ruled out: JIT (JSC_useJIT=0 worse), sandbox (already off), page weight (`/embed/` also crashes). Deep WebKit issue (needs debug syms + likely a WebKit patch). **Next lead to try: Invidious/Piped frontend** (plain `<video>`, not MSE = the path that works) → likely genuine in-browser HW YouTube.
- ⚠️ **Browser video is fragile:** Chromium 1080p60 crashed the GPU/phoc → session/reboot; Firefox broken for video (Mali GL). Palliatives shipped (Chromium+Firefox h264ify).
- **All artifacts + re-apply steps:** `device-r7/video/README.md`. **All fixes reboot-safe (rootfs), lost only on a rootfs reflash.**

### The full fix chain that got us here (sesi-15)
1. **console** (sesi-14): `CONFIG_CMDLINE="console=tty0 …"` → rootfs boots (D1).
2. **IPC namespace** (kernel rebuild): `SYSVIPC/POSIX_MQUEUE/IPC_NS/USER_NS=y` in
   `exynos9810-r7_droidian_defconfig` → LXC `clone(CLONE_NEWIPC)` works → **Android
   container spawns**, Android init runs, binder works (`29189/-22` gone), HALs
   (gralloc, hwcomposer) start. Flashed `boot-droidian.img` md5 `450af09e…`.
3. **Bluetooth panic** (userspace mask): `bluetoothd` → `bt_sock_create` →
   `bt_sock_reclassify_lock` → `kernel BUG at net/bluetooth/af_bluetooth.c:69` (a
   `BUG_ON`, always fatal) → panic/reboot at ~24s. Fixed by masking `bluetooth.service`
   + `bluebinder.service`. (BT = known-broken, was already on the caveat list.)
4. **Camera-ISP panic** (kernel sysctl + userspace): `gst-plugin-scan` → V4L2 `QUERYCAP`
   on `fimc_is` → `Accessing user space memory outside uaccess.h routines` →
   `fimc_is_ixs_video_querycap+0x24` oops → panic/reboot at ~33s (right after the greeter
   rendered). Fixed by `kernel.panic_on_oops=0` (config default is 0; sec_debug forced it
   to 1 at runtime — this is a recoverable oops, NOT a `BUG_ON`, so 0 makes it survivable)
   + disabling the GStreamer v4l2 plugin so nothing probes the camera. (Camera = known-broken.)

### ⚠️ Persistent ON-DEVICE fixes — RE-APPLY IF ROOTFS REFLASHED (not in any package yet)
These live only in the rootfs LV; a rootfs re-image loses them. Only #1 is in the git repo.
1. Kernel defconfig IPC/NS lines — **in repo** (`exynos9810-r7_droidian_defconfig`).
2. `sudo systemctl mask bluetooth.service bluebinder.service`
3. `/etc/sysctl.d/99-r7-nopanic.conf` = `kernel.panic_on_oops=0` + `kernel.panic=0`
4. `mv …/gstreamer-1.0/libgstvideo4linux2.so{,.disabled}` (+ clear `~/.cache/gstreamer-1.0`)
5. `sudo systemctl set-default graphical.target`
6. Display scale 200% (default was 300%): `[output:HWCOMPOSER-1] scale = 2` in
   `/usr/share/phosh/phoc.ini` (phoc is launched with `-C` this file). Backup `.orig`.
   ⚠ Use INTEGER scales only (2 or 3). Fractional (150%) hangs/reboots phoc on the
   HWCOMPOSER backend — user hit this.
7. **Camera-panic guard** — WHY: `fimc_is_*_video_querycap` NULL-derefs → **kernel panic on
   ANY `VIDIOC_QUERYCAP`** of an `exynos-fimc-is-*` V4L2 node. Browsers enum cameras (WebRTC)
   → Firefox/Chromium reboot the phone; gst + `v4l2test` too. `panic_on_oops=0` does NOT save
   it (`sec_debug` forces the panic). Two-part block (chmod alone is DEFEATED by logind
   `uaccess` ACL `user:droidian:rw-` from `70-camera.rules`):
   - `/etc/udev/rules.d/99-block-fimc-cam.rules`: `SUBSYSTEM=="video4linux",
     ATTR{name}=="exynos-fimc-is-*", TAG-="uaccess", OWNER="root", GROUP="root", MODE="0000"`
     (strips the ACL at device creation — the real fix; no boot-window race).
   - `block-fimc-cam.service` + `/usr/local/sbin/block-fimc-cam.sh`: loop `setfacl -b` +
     `chmod 000` as backup. (NOT `Before=phosh` — that delayed the greeter.)
   MFC codec (`s5p-mfc`, video6-12) + scaler (video50) left working. ⚠ Still bypassable by a
   ROOT process (root ignores mode+ACL) — no known persistent one, but **the bulletproof fix
   is a KERNEL rebuild disabling the `fimc_is` driver** (nodes never exist). Same rebuild
   should also fix Bluetooth (`af_bluetooth.c:69` BUG_ON). Sesi-15b.
8. **Video (sesi-18/19, current state in `device-r7/video/README.md` — follow THAT list):
   `chromium/h264ify.json` → `/etc/chromium/policies/managed/` + manual extension options
   (**block VP9+AV1, NOT 60fps**); `webkit/r7-webkit-egl.conf` → `/etc/tmpfiles.d/`
   (`systemd-tmpfiles --create` — unversioned `libEGL.so`/`libGLESv2.so` symlinks so
   Epiphany HW-decodes plain HTML5 `<video>`); YouTube player: ambient mode + annotations
   OFF (per-account). The sesi-18 `youtube-hw` launcher + Firefox h264ify policies were
   REMOVED in sesi-19 housekeeping (obsoleted by smooth Chromium 1080p60; `youtube-hw`
   recoverable from git `30638f1`).**
**TODO (make reproducible):** bake #2–#5 + #8 into a Droidian adaptation `.deb` / first-boot
hook, or into the rootfs image build. See PROGRESS.md TASK 3.x / adaptation package.

### Known-broken (expected — matches caveat list)
- **Bluetooth**: 2 blockers, one fixed one not. (1) **vhci — FIXED sesi-17:** stock r7 defconfig
  had `CONFIG_BT_HCIVHCI` (+HCIUART/RFCOMM/HIDP/BNEP) OFF → no `/dev/vhci` → `bluebinder` couldn't
  make `hci0`. Enabled to match crownlte (commit 6c70665b2), rebuilt+flashed → `/dev/vhci` confirmed.
  (2) **kernel panic — STILL OPEN:** with vhci present, starting `bluebinder`/`bluetoothd` →
  `bt_sock_create+0xc4` → `bt_sock_reclassify_lock` → `BUG_ON` at `af_bluetooth.c:69` → **kernel
  panic** (confirmed via `/proc/last_kmsg`: proc `bluebinder`, "RESET CAUSE - Kernel Panic"). crownlte
  runs byte-identical `af_bluetooth.c` fine → r7-specific runtime (NULL `sk` or owned sk_lock). The
  workaround-pack BT patch aimed at `bt_sock_create` (no BUG_ON there) = wrong site; real fix =
  soften the two `BUG_ON`s in `bt_sock_reclassify_lock` (lines 69-70) to graceful returns, then
  retry with services PRE-MASKED (see caution below).
  ⚠ **BOOTLOOP CAUTION (learned sesi-17):** `bluetooth.service` ships ENABLED
  (`/etc/systemd/system/bluetooth.target.wants/bluetooth.service`, since the Jul-8 image). Merely
  `unmask`-ing it re-activates auto-start → on the panic-reboot it re-launches `bluetoothd` →
  panic → **infinite bootloop** (uncatchable: panic precedes the USB-net window, so no SSH catch).
  Recovery required a Download-Mode heimdall flash of a kernel with
  `systemd.mask=bluetooth.service systemd.mask=bluebinder.service` in `CONFIG_CMDLINE`
  (commit after 6c70665b2). **Before ever unmasking BT again:** first `systemctl mask` (persistent,
  in /etc — done) so the enabled symlink can't win, then test by MANUAL start only.
  Current flashed kernel = the recovery one (BT masked via cmdline); a clean rebuild later should
  drop the cmdline mask (rootfs mask now covers it) and carry the `bt_sock_reclassify_lock` patch.
- **Camera**: `fimc_is` V4L2 querycap oops — needs a kernel driver fix; probe disabled + oops
  made non-fatal for now.
- **GPU / GL: WORKS (HW accelerated).** `eglinfo`: renderer `Mali-G72`, `OpenGL ES 3.2
  v1.r38p1` (vendor blob via libhybris), `/dev/mali0`, `init.svc.gpu: running`. NOT software,
  NOT panfrost. UI is GPU-accelerated. User's "GPU broken" was a misdiagnosis.
- **HW video decode: WORKS via Clapper — SOLVED sesi-18.** (Was "stutters/glitches", sesi-16.)
  The sesi-16 "GL crash blocks Clapper" conclusion was a **false alarm**: that test ran
  Clapper/`gst-launch` over SSH **without the graphical session's hybris-GL env**, which is what
  produced `Unable to interpret GL_VERSION string`. The real Phosh session (and any app-grid
  launch) exports `EGL_PLATFORM=wayland GDK_GL=gles GST_GL_API=gles2` +
  `LD_PRELOAD=libtls-padding.so:libgtk6216workaround.so:libglesshadercache.so` (set by
  `droidian-quirks-hybris-gl`). With that env, **Clapper creates `droidvdec` (Exynos MFC HW
  decoder) and plays local H.264 + live YouTube (via yt-dlp) — smooth, correct picture, no skew,
  no GL crash.** User-confirmed on-device. The old diagonal-skew was only the hand-rolled
  `droidvdec ! videoconvert ! waylandsink` SHM path; Clapper's GTK4-GL paintable handles stride
  on the GPU. **Chromium/Firefox can't reach the HW decoder** (Chromium: no VA-API; Firefox: GPU
  accel disabled on Mali) — but **Epiphany (WebKitGTK) CAN** (WebKit decodes `<video>` via
  GStreamer→droidvdec): fixed by adding the missing unversioned `libEGL.so`/`libGLESv2.so`
  symlinks (`device-r7/video/webkit/r7-webkit-egl.conf` → `/etc/tmpfiles.d/`) — WebKit dlopen'd
  them but Droidian ships only the versioned glvnd libs.
  **Sesi-19 update:** browser YouTube no longer needs the HW decoder — Chromium plays
  **1080p60 smooth with SW decode on stock scaling** (ambient mode off + h264ify codec lock);
  the sesi-18 `youtube-hw` launcher was removed in housekeeping (Clapper itself stays for
  local files). VA-API / native V4L2 on the 4.9 kernel = ruled out (PROGRESS.md sesi-19).
  Full writeup: `device-r7/video/README.md` + `docs/hw-video-decode.md`.
- **Audio: WORKS (speaker output confirmed on-device, auto-up on cold boot ~28s) — FIXED sesi-17.**
  Two-part fix (both persistent, in repo `device-r7/audio/`):
  1. **64-bit HIDL-compat shim** (matches crownlte): the real HAL `audio.primary.exynos9810.so` is
     32-bit only; the 64-bit `audio.primary.default.so` is a segfaulting 11 KB stub. Bind-mount the
     GSI-provided 64-bit `audio.hidl_compat.default.so` over it. Persist =
     `/etc/systemd/system/android-mount.service.d/30-audio-hidl.conf`.
  2. **Start the container audio HAL service** = the real sesi-15b blocker, now root-caused: init
     does NOT start `vendor.audio-hal` (`/vendor/bin/hw/android.hardware.audio.service`, 32-bit) —
     its stock `.rc` has **zero `interface` lines**, so init's on-demand `ctl.interface_start
     android.hardware.audio@5.0::IDevicesFactory/default` can't map to it ("Could not find …"
     looping in dmesg every 1s), and `class hal` skips it at boot. The binary itself is fine (runs
     + registers @5.0::IDevicesFactory when exec'd). Persist = `r7-audio-hal.service` +
     `/usr/local/sbin/r7-start-audio-hal.sh` (waits for hwservicemanager, starts the HAL detached
     via `setsid`, then kicks the uid-32011 pulseaudio). ⚠ lxc-attach from systemd needs an absolute
     `/system/bin/sh` + explicit `PATH` (bare `sh` = "No such file or directory").
  Result: `sink.primary-out` + `sink.fast` + `source.primary-in` via `module-droid-card`. Verified
  by user (audible tone) across two cold reboots; **HW volume buttons work**.
  ⚠ **Known cosmetic gap:** GNOME **Settings → Sound** lists NO devices + its slider is dead, even
  though the pipeline is correct (default sink = `sink.primary-out`, `device.class=sound`, active
  available `output-speaker` port, same pulse server `gsd-media-keys` uses). Ruled out: pipewire
  (gnome-control-center 50 links `libpulse`, not pw; pw inactive), stale device-db (none present),
  connect error (panel launches clean, just empty). = a GNOME-50 `gvc` ↔ droid-card enumeration
  quirk; HW keys + Phosh top-bar slider control volume fine, so it's UX-only, not an audio failure.
  Still TODO: that gvc quirk, call/media routing profiles, mic test, headphone-jack detect.
  Cleaner long-term fix for the HAL-start = add `interface` lines to the audio `.rc` via
  droid-vendor-overlay so init on-demand-starts it (no host helper service).
- About→System Details: processor blank / graphics unknown = cosmetic (GNOME can't parse the
  ARM `/proc/cpuinfo` model / the libhybris GL renderer string).
- Not yet tested: calls/SMS/modem, GPS, fingerprint, sensors, offline charging, dual-SIM.
- `init_user0_failed` (`vold: Failed to prepare user 0 storage`): Android `/data` FBE setup
  fails — NON-FATAL (Droidian suppresses reboot; Android `/data` unused by Phosh). Cosmetic
  journal noise; a proper container `fstab.exynos9810` would silence it (PROGRESS TASK 3.1).

**Remaining work = Halium device adaptation (PROGRESS.md TASK 3.x):** Android container
`fstab.exynos9810` (tell vold `/data` is pre-mounted, don't manage dynamic parts / skip
FBE), create `/keydata` mount point, encryption flags — PLUS tame the 40s watchdog so a
degraded Android can still bring up hwcomposer for Phosh.

### How to reach the phone / re-flash (sesi-15 working setup)
- SSH: `sshpass -p 1234 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null droidian@10.15.19.82`
- Host USB-net: `enp4s0f3u3` carries BOTH `192.168.2.2/24` (NM "Wired connection 2") and
  `10.15.19.100/24`. If `.100` drops after a reboot:
  `sudo nmcli con mod "Wired connection 2" +ipv4.addresses 10.15.19.100/24 && sudo nmcli con up "Wired connection 2"`
- Re-flash BOOT from the running rootfs (no Download Mode):
  `scp boot-droidian.img droidian@10.15.19.82:/home/droidian/` then
  `sudo dd if=/home/droidian/boot-droidian.img of=/dev/disk/by-partlabel/boot bs=4M conv=fsync`
- Catch-the-loop trick (if a future kernel reboot-loops): `scripts/catch2.sh` hammers SSH
  and masks the offending unit inside the ~1-4s window (sshd is up by uptime ~21s).

### Previously-applied kernel fix (sesi-15): IPC namespace — DONE
Was: `arch/arm64/configs/exynos9810-r7_droidian_defconfig` had `# CONFIG_SYSVIPC is not
set` (Samsung stock) → `CONFIG_IPC_NS` compiled out → `lxc_spawn: Failed to clone a new
set of namespaces (EINVAL)` → container never spawned. Fixed by matching crownlte baseline:
```
CONFIG_SYSVIPC=y   CONFIG_POSIX_MQUEUE=y   CONFIG_IPC_NS=y   CONFIG_USER_NS=y
```

## Earlier milestone (sesi-14): D0 + rootfs handoff
Custom clang-built kernel boots, Halium initramfs runs, on-device debug shell over USB
(no jig). Rootfs flashed + verified as LVM. The `console=tty0` fix (baked into
`CONFIG_CMDLINE`) fixed the init handoff — S-Boot ignores the boot.img cmdline and
passes stock `console=ram`, so no console was registered → handoff failed at the last
step. Confirmed present in current `boot-droidian.img` (18:00).

## What is already DONE and verified on-device
- Kernel `4.9.191-samsung-r7` built with **clang-android-9.0** (Droidian packaging
  container), accepted by S-Boot, boots.
- Halium initramfs runs; on failure it raises **USB RNDIS gadget `18d1:d001`** and a
  **BusyBox telnet shell on `192.168.2.15:23`**. Host side of the USB net = set the
  interface to **`192.168.2.2/24`** (NetworkManager conn "Wired connection 2").
- Rootfs (`firmware/droidian/rootfs.img`, api33/Halium 13, contains GSI-33 at
  `/var/lib/lxc/android/android-rootfs.img`) is written to an **LVM** volume on
  userdata. Initramfs detects it: "Found LVM VG droidian", "API level 33".
- On-device LVM already created:
  - VG `droidian` on `/dev/sda31` (userdata, partlabel `userdata`)
  - LV `droidian-rootfs` (5G, holds the rootfs), LV `droidian-persistent` (32M)
  - `touch /var/lib/halium/requires-lvm-resize` set (first boot extends LV to full disk)
- BOOT partition = **`/dev/sda12`** (partlabel `boot`), size **61865984 B** (== our image).

## The current bug (root cause, confirmed on-device sesi-15)
Boots into rootfs; black screen. `lxc@android.service` fails instantly:
`lxc_spawn: Failed to clone a new set of namespaces (EINVAL)`. Kernel lacks IPC
namespace (`/proc/self/ns/` has no `ipc`): defconfig had `# CONFIG_SYSVIPC is not
set`, and `CONFIG_IPC_NS` depends on SYSVIPC → compiled out → LXC `clone(CLONE_NEWIPC)`
= EINVAL. Container never spawns → no libhybris hwcomposer → no display. The repeating
`binder: transaction failed 29189/-22` is a downstream symptom (reassess after fix).

**Fix applied (sesi-15) in `exynos9810-r7_droidian_defconfig`, matching crownlte
baseline; kernel REBUILDING now:**
```
CONFIG_SYSVIPC=y   CONFIG_POSIX_MQUEUE=y   CONFIG_IPC_NS=y   CONFIG_USER_NS=y
```

### Previously-fixed (sesi-14): no console at init handoff — RESOLVED
S-Boot ignores the AOSP boot-header cmdline; stock DTB passes `console=ram`, and r7
kernel had `CONFIG_CMDLINE=""` → no console → Halium `run-init >/dev/console` failed.
Fixed by `CONFIG_CMDLINE="console=tty0 droidian.lvm.prefer"` + `CONFIG_CMDLINE_EXTEND=y`
(commit `08c9ab4fb`). Confirmed working — rootfs now boots.

## NEXT STEPS to finish (resume here)

### 1. Wait for the kernel rebuild to finish
Container build (in background as of sesi-14). Command that produces it:
```
rm -f kernel-n770f-oss/debian/control kernel-n770f-oss/debian/changelog
podman run --rm --security-opt label=disable \
  -v $PWD/packages:/buildd \
  -v $PWD/kernel-n770f-oss:/buildd/sources \
  quay.io/droidian/build-essential:current-amd64 bash -c \
  'set -e; apt-get update -qq; apt-get install -y -qq linux-packaging-snippets >/dev/null; \
   cd /buildd/sources; debian/rules debian/control; RELENG_HOST_ARCH=arm64 releng-build-package'
```
(run from `~/Desktop/Development/Note10Lite`). New `Image` lands in
`kernel-n770f-oss/out/KERNEL_OBJ/arch/arm64/boot/Image`.

### 2. Re-wrap the flashable boot image (host)
```
cd ~/Desktop/Development/Note10Lite/Droidian
./boot/wrap_droidian.sh      # already points at out/KERNEL_OBJ Image + initramfs.gz
```
Output: `boot/boot-droidian.img` (verified 61865984 B, Samsung dt-table + SEANDROID).

### 3. Flash BOOT from the RUNNING Droidian rootfs over SSH — no Download Mode
The phone now boots the rootfs, so flash from there (host iface = 10.15.19.100/24):
```
SSH="sshpass -p 1234 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null droidian@10.15.19.82"
# copy new boot image to phone
sshpass -p 1234 scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  Droidian/boot/boot-droidian.img droidian@10.15.19.82:/tmp/
# write it to the boot partition + reboot (sudo pw = 1234)
$SSH 'echo 1234 | sudo -S dd if=/tmp/boot-droidian.img of=/dev/disk/by-partlabel/boot bs=1M; \
  echo 1234 | sudo -S sync; echo 1234 | sudo -S reboot'
```
Fallback: reboot to Download Mode and
`heimdall flash --BOOT Droidian/boot/boot-droidian.img` (BOOT-only flashes always work).

### 4. Observe D2 (Phosh)
After reboot: green Droidian logo, then either black screen (fail) or Phosh. SSH back
in and check: `systemctl --failed` and `systemctl status lxc@android`.
- `lxc@android` now **active** → container spawned; check `dmesg | grep binder` — if
  `29189/-22` is gone, watch for Phosh (login pin `1234`) → **D2 REACHED**.
- `lxc@android` still failed → read `journalctl -u lxc@android -b` for the new error.
- Container up but still black → binder ABI (`29189/-22`) is a real blocker, OR
  Phosh/phoc graphics-backend crash: `journalctl -b -u phosh` + `--user` phosh logs.

## Safety
Track writes ONLY BOOT + USERDATA (BL/modem/EFS/super never touched). One-command
restore to stock Android+Magisk: `Droidian/scripts/restore-stock.sh` (needs
Download Mode). Android userdata was overwritten by the LVM rootfs — restoring
BOOT returns a bootable phone; use `--userdata` only if you want Android data back.

## Key facts table
| Item | Value |
|------|-------|
| Phone debug IP (initramfs) | 192.168.2.15 (telnet :23, nc :5555 for transfers) |
| Host USB-net IP | 192.168.2.2/24 ("Wired connection 2") |
| BOOT partition | /dev/sda12 (partlabel `boot`), 61865984 B |
| userdata partition | /dev/sda31 (partlabel `userdata`) → PV of VG `droidian` |
| rootfs LV | /dev/droidian/droidian-rootfs (5G, ext4, UUID 54d2f605…) |
| kernel | 4.9.191-samsung-r7, clang-android-9.0, branch droidian-r7 |
| rootfs image | firmware/droidian/rootfs.img (4330618880 B, api33) |
| latest commit | 08c9ab4fb (CONFIG_CMDLINE console=tty0 fix) |
