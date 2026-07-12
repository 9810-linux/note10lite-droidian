# r7 porting study — Droidian/Halium 13 on Samsung Galaxy Note 10 Lite (SM-N770F)

> Study deliverable (user request: "analyze the successful Droidian build on
> crownlte, forward to Halium 13, then make a study to port it to r7").
> Written sesi 11, after the D0 probe bootlooped. Grounded in the local `ref/`
> set (the Sexynos crownlte port + Droidian porting guide + the project runbook
> `ref/README.md`). Every load-bearing fact cites its source file.
>
> This document replaces the ad-hoc hand-rolled D0 probe path with the proven
> Droidian packaging/build flow. See `PROGRESS.md` for the runbook and
> `docs/safety-unbrick.md` for the flash/restore protocol.

## 0. TL;DR — what the bootloop taught us

The D0 probe (`boot/wrap_droidian.sh` + `initramfs/init.c`) **bootlooped** but
S-Boot **accepted** the image (proven: it left Download Mode). That tells us the
Samsung wrap (dt-table + `SEANDROIDENFORCE`) is correct — the failure is
**downstream of S-Boot, and architectural**: we hand-rolled a freestanding `/init`
in a custom cpio and bypassed the entire Halium boot flow.

The proven crownlte port does **not** build boot.img that way. It builds boot.img
through the **Droidian kernel packaging** (`debian/kernel-info.mk`), which embeds
the real `linux-initramfs-halium-generic` initramfs. That initramfs is the one
that actually boots Droidian: `datapart=` → mount the userdata LVM →
`switch_root` → systemd → `lxc@android` (the GSI Android container, with the
device's real `vendor` partition bind-mounted in) → Phosh.

**The fix is not to debug the probe. It is to stop hand-rolling the boot.img and
produce it the way crownlte does — via the Droidian kernel packaging, with r7
settings.** That simultaneously (a) supplies the real Halium initramfs (the
thing the probe was missing) and (b) keeps the Samsung S-Boot bits the packaging
already emits (`KERNEL_PREBUILT_DT` + `DEVICE_VBMETA_IS_SAMSUNG=1` → the dt-table
+ `SEANDROIDENFORCE` we proved S-Boot accepts). Everything below flows from that.

---

## 1. The proven reference: "successful Droidian on crownlte"

crownlte = Galaxy Note 9 (SM-N960F), **same Exynos 9810 SoC as r7**. The Sexynos
project is a complete Droidian/Halium device-port effort with crownlte as the
finished example. r7 reuses the SoC layers wholesale and only forks the
board-specific layer.

### 1.1 Version split (the crux for "forward to Halium 13")

crownlte sits across **three** version layers — this is the key thing to get
right when advancing to Halium 13:

| Layer | crownlte version | Source |
|---|---|---|
| AOSP/LineageOS device-tree build base | **Android 12** (git branch `twelve`) | `sexynos-local-manifests/*.xml` `revision="twelve"`; HIDL HALs `audio@7.0`, `graphics.composer@2.4`, `gnss@2.0/2.1`, `health@2.1` in `configs/vintf/manifest.xml` |
| Droidian/Halium hybris runtime base | **API 29 = Android 10 (Halium 10)** | `sexynos-adaptation-exynos9810/debian/control`: `Depends: adaptation-hybris-api29-phone`; rootfs installs `adaptation-hybris-api29` + `android-system-gsi-29:arm64` |
| Debian base | **trixie (Debian 13)** | apt sources `http://production.repo.droidian.org/ trixie`; `droidian_phosh.yaml` `suite: "trixie"` |

So the device **trees/HALs/sepolicy** are Android-12-era, but the **hybris glue +
GSI** are API 29. The two are decoupled: the Android-12 trees are forward-compatible
with an API-33 hybris userspace (HIDL HALs @7.0/2.4 satisfy libhybris's
expectations). **"Forward to Halium 13" is a hybris-layer change (api29→33), not a
device-tree rebase.** This is the runbook's chosen path (`ref/README.md` Risk #1).

### 1.2 The 3-layer device adaptation (TASK 3 structure, from `ref/README.md`)

| Layer | Repo | r7 action | Why |
|---|---|---|---|
| **Common (SoC)** | `sexynos-device-exynos9810-common` (70M) | **Reuse as-is** | SoC-identical (universal9810). `BoardConfigCommon.mk` has the golden boot geometry, all HALs, `sepolicy/vendor`, `mkbootimg`, `dtbhtool`, fstab structure |
| **Device (board)** | `sexynos-device-crownlte` (188K) | **Fork → `device-r7`** | thin, board-specific: product ID, panel, keys, sensors, proprietary-files, power_profile, kernel defconfig name |
| **Adaptation (Debian glue)** | `sexynos-adaptation-exynos9810` (448K) | **Revive + re-point api29→33, drop bixby** | systemd overrides, udev rules, `droid-vendor-overlay` init disabling, `phoc.ini`, `droid-get-bt-address`. Generic 9810 → only the hybris-api dep + bixby change |

Golden boot geometry from `BoardConfigCommon.mk` (matches our on-device golden
values): `BOARD_KERNEL_BASE=0x10000000`, `BOARD_KERNEL_OFFSET=0x00008000`,
`BOARD_KERNEL_PAGESIZE=2048`, `RAMDISK_OFFSET=0x01000000`, `TAGS_OFFSET=0x00000100`.
Note: common declares `BOARD_BOOT_HEADER_VERSION=1`, but **r7 stock is header v2**
— our wrap used v2 and S-Boot accepted it; keep v2 (see §4.1).

### 1.3 The Halium boot flow (why a hand-rolled /init is wrong)

From `porting-guide/debugging-tips.md` + the crownlte kernel packaging:

1. The boot.img is built by the **kernel packaging**, not mkbootimg-from-scratch.
   `kernel-compilation.md`: "The kernel image already embeds the Droidian
   initramfs." The initramfs is the apt package **`linux-initramfs-halium-generic`**
   (`:arm64`, `:armhf` fallback), pulled as a kernel **build dependency** and
   packed into boot.img at `KERNEL_BOOTIMAGE_INITRAMFS_OFFSET=0x01000000`
   (`ref/linux-android-samsung-crownlte/debian/kernel-info.mk`).
2. On boot, that initramfs finds the **userdata partition** via the `datapart=`
   cmdline arg (value `/dev/disk/by-partlabel/userdata` or `/dev/sdaNN`), mounts
   it, and `switch_root`s into the Droidian rootfs.
3. **Halium refuses to start `/init` if `console=` is not a console device**
   (debugging-tips). A stock cmdline like `console=ttyMSM0,115200n8` must become
   `console=tty0`. The `systempart=` option (Ubuntu Touch) must be **removed**
   (Droidian uses userdata, not system).
4. After switch_root, systemd brings up **`lxc@android`** (enabled by
   `setup-gsi.sh` during rootfs build). The Android container rootfs is the GSI
   (`android-system-gsi-{apilevel}` package) at
   `/var/lib/lxc/android/android-rootfs.img`; the device's real `vendor`
   partition is bind-mounted to `/var/lib/lxc/android/rootfs/vendor`. libhybris +
   the container provide the Android HALs to the Debian/Phosh userspace.

Our D0 probe skipped **all** of this: a freestanding `/init` + a custom cpio +
`init=/init` overriding the (absent) Halium initramfs. The kernel had no real
initramfs to run the Halium flow, and our `/init` apparently never stabilized
(bootloop). The packaging path fixes the root cause.

### 1.4 Image assembly + flashing (the crownlte artifact)

From `sexynos-rootfs-templates-crownlte/` + `sexynos-image-flashing-template/`:

- crownlte ships a **fastboot** zip via `scripts/genzip.sh` (the `type: rootfs`
  path — note: `community_devices.yml` says `type: image`, which is
  **inconsistent** with the actual artifact; a reproduction must set
  `type: rootfs`). `genzip.sh` builds an **LVM** userdata image (`userdata.raw`
  → `pvcreate` → `vgcreate droidian` → `droidian-rootfs` LV → `mkfs.ext4` →
  `img2simg` → `userdata.img`), plus a `boot-crownlte.img` downloaded from the
  kernel release, zipped into `data/boot.img` + `data/userdata.img`.
- Flashing (`template/flash_all.sh`): **`fastboot flash BOOT data/boot.img` +
  `fastboot flash USERDATA data/userdata.img`**, then `fastboot reboot`. Only
  BOOT + USERDATA; system/vendor are NOT reflashed (the GSI lives inside the
  rootfs, the device vendor partition is bind-mounted, not flashed).

### 1.5 The kernel (proven Halium config template)

`ref/linux-android-samsung-crownlte/`, branch `droidian`, **4.9.218**, defconfig
`arch/arm64/configs/exynos9810-crownlte_defconfig`. Proven Halium deltas:
`# CONFIG_ANDROID_PARANOID_NETWORK is not set`, `CONFIG_DEVTMPFS=y`,
`CONFIG_DEVTMPFS_MOUNT=y`,
`CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"`,
`CONFIG_SECURITY_SELINUX_BOOTPARAM=y`. The entire Knox stack is source-stripped
on this branch. This is the template the r7 defconfig copied deltas from.

---

## 2. Forward to Halium 13 (api33) — concrete deltas

Halium 13 = api33 = Android 13. **r7's firmware IS Android 13**
(`N770FXXS9HXA3`), so r7 is natively aligned with Halium 13 — the vendor blobs we
already have on-device are the right ones. The deltas to advance crownlte
(api29) → r7 Halium 13 (api33):

| Knob | crownlte (api29) | r7 Halium 13 (api33) | Where |
|---|---|---|---|
| apilevel | 29 | **33** | device entry (`community_devices.yml`) → retargets `adaptation-hybris-api29`→`api33`, `android-system-gsi-29`→`android-system-gsi-33:arm64` |
| Adaptation `.deb` Depends | `adaptation-hybris-api29-phone` + `bixby-state` | `adaptation-hybris-api33-phone`, **drop bixby-state** (r7 has no Bixby) | `sexynos-adaptation-exynos9810/debian/control` |
| Builder container | `rootfs-builder:bookworm-amd64` | `rootfs-builder:next-arm64` | `.github/workflows/release.yml` |
| CI runner | `ubuntu-20.04` | `ubuntu-24.04-arm` | same |
| `DROIDIAN_VERSION` (nightly) | `nightly` | `next` | same |
| `generate_device_recipe.py` args | 5 | 6 (add `droidian_variant`) | align with generic `droidian-images` |
| Kernel | 4.9.218 crownlte (`exynos9810-crownlte_defconfig`) | **4.9.191 r7 Base A** (`exynos9810-r7_droidian_defconfig`, branch `droidian-r7`) | kernel packaging |
| Debian suite | trixie | **trixie (unchanged)** | apt sources — no suite change needed |
| Rootfs | build custom (debos) | **start from the already-downloaded generic api33 rootfs** + inject adaptation | `firmware/droidian/droidian-OFFICIAL-phosh-phone-rootfs-api33-arm64-next_*.zip` |

The project already has the generic api33 rootfs downloaded + sha256-verified
(`ref/README.md` "Rootfs (TASK 1.2)"). So the rootfs base is ready; the work is the
r7 adaptation layer + the r7-packaged boot.img, not a from-scratch rootfs.

---

## 3. The r7 port — what reuses vs. what forks/deviates

### 3.1 Reuse as-is (SoC-identical)

- **`sexynos-device-exynos9810-common`** — `BoardConfigCommon.mk` (golden boot
  geometry), all HALs (`common.mk`), `sepolicy/vendor/` (43 .te/contexts),
  `mkbootimg/`, `dtbhtool`, fstab structure. No SoC changes.
- **`sexynos-sepolicy` + common sepolicy** — `BOARD_SEPOLICY_TEE_FLAVOR` path.
  **⚠ VERIFY r7's TEE flavor**: crownlte = `mobicore` (Trustonic). r7 (Android 13)
  may use `teegris` or a Knox-based TEE — this selects different `tee/*` sepolicy.
  Check r7's stock vendor init or the kernel defconfig's TEE config before
  reusing. (`sexynos-sepolicy/sepolicy.mk` branches on the flavor.)
- **`sexynos-adaptation-exynos9810`** — the systemd/udev/vendor-overlay payload
  is generic 9810; reuse, just re-point the hybris dep + drop bixby (§3.2).

### 3.2 Fork (board-specific): `device-crownlte` → `device-r7`

Per the crownlte→r7 diff table (`ref/README.md`), the board-specific changes:

| Subsystem | crownlte (Note 9) | r7 (Note 10 Lite) |
|---|---|---|
| Product | SM-N960F | **SM-N770F** |
| Panel | 1440×2560 QHD (s6e3ha*) | **1080×2400 FHD (s6e3fa9_fhd)**, DTBO `dtbo_idx=5` |
| Density | 560 | **~440** |
| Keys | + wink/Bixby gpa0-6 | **no wink/Bixby** |
| Touch | `sec,sec_ts` | `melfas,mms_ts` + a96t3x6 |
| Audio codec | Cirrus CS47L93 + MAX98512 | **Realtek RT5665 + TI TAS2562** |
| Memory | 6 GB | **8 GB / 6-region** |
| Barometer | present | **absent** |
| Cameras | 2l3/3m3/3h1/5f1 | **2l2/3l6/3m3/imx333/imx616** |
| proprietary-files | N960FXXU9FUK1 blobs | **N770FXXS9HXA3 blobs** (extract from rooted r7 or stock AP) |
| Kernel defconfig | `exynos9810-crownlte_defconfig` | **`exynos9810-r7_droidian_defconfig`** |

Concretely: copy `aosp_crownlte.mk`→`aosp_r7.mk`, `BoardConfig.mk`, `device.mk`;
keep `include device/samsung/exynos9810-common/common.mk`; change the board bits
above; swap `proprietary-files.txt` to the r7 vendor package.

### 3.3 r7-specific DEVIATIONS from the crownlte flow (the two big ones)

**(A) boot.img via Droidian kernel packaging, NOT hand-rolled** — the bootloop fix.
`porting-guide/kernel-compilation.md` is the procedure. Set up
`debian/kernel-info.mk` in the Base A kernel tree with r7 values:

- `KERNEL_BASE_VERSION=4.9.191`, `KERNEL_DEFCONFIG=exynos9810-r7_droidian_defconfig`
- `KERNEL_BOOTIMAGE_CMDLINE`: `console=tty0 droidian.lvm.prefer
  androidboot.selinux=permissive androidboot.hardware=exynos9810
  androidboot.boot_devices=11120000.ufs` — **no `systempart=`, no `init=/init`**
  (let the Halium initramfs `/init` run). Add `datapart=/dev/disk/by-partlabel/userdata`
  only if Phase-1 shows the initramfs can't find userdata.
- `KERNEL_BOOTIMAGE_PAGE_SIZE=2048`, `KERNEL_BOOTIMAGE_BASE_OFFSET=0x10000000`,
  `KERNEL_BOOTIMAGE_KERNEL_OFFSET=0x00008000`,
  `KERNEL_BOOTIMAGE_INITRAMFS_OFFSET=0x01000000`, `KERNEL_BOOTIMAGE_TAGS_OFFSET=0x00000100`
- `KERNEL_BOOTIMAGE_VERSION=2` (Android 10+; r7 stock is v2 — also needs
  `KERNEL_BOOTIMAGE_DTB_OFFSET`)
- **`DEVICE_VBMETA_IS_SAMSUNG=1`** (Samsung-specific — emits the boot.img structure
  S-Boot expects)
- **`KERNEL_PREBUILT_DT` = the r7 stock dt-table** (`boot/r7-stock-dttable.bin`,
  magic `0xd7b7ab1e`, 189700 B — already staged by `wrap_droidian.sh`; proven
  S-Boot-accepted). This is what makes the packaging's boot.img Samsung-correct
  (the crownlte `boot-crownlte.img` boots on Samsung S-Boot the same way).
- `DEB_TOOLCHAIN`: prefer `clang-android-14.0-r450784d` (android13-recommended).
  Note: Base A built with host **gcc-16** (`CC` override at `Makefile:351`). If
  the packaging's clang-android-14 rejects Base A, fall back to gcc (the guide
  allows `BUILD_CC=aarch64-linux-android-gcc-4.9`); reconcile the toolchain in
  kernel-info.mk.
- `DEB_BUILD_FOR=arm64`, `KERNEL_ARCH=arm64`
- Build dep **`linux-initramfs-halium-generic:arm64`** (the real initramfs —
  this is what the probe was missing)
- `FLASH_*`: `FLASH_INFO_MANUFACTURER=samsung`, `FLASH_INFO_MODEL=SM-N770F`
  (for on-device OTA later; not needed for the first flash)

Build (Docker): `docker run --rm -v $PACKAGES_DIR:/buildd -v $KERNEL_DIR:/buildd/sources -it quay.io/droidian/build-essential:current-amd64 bash`; inside: `apt-get install linux-packaging-snippets`, create `debian/{rules,compat,source/format,kernel-info.mk}`, `debian/rules debian/control`, `RELENG_HOST_ARCH=arm64 releng-build-package`. Extract `boot.img` from the resulting `linux-bootimage-4.9.191-samsung-r7*.deb` (or `out/KERNEL_OBJ/boot.img`). **This boot.img replaces `boot/boot-droidian.img`.**

**(B) Flashing via heimdall (Download Mode), NOT fastboot** — r7 is Samsung.
crownlte's `flash_all.sh` uses `fastboot flash BOOT/USERDATA` from a `fastbootd`
recovery; r7 has no fastboot. Use heimdall (proven on this cable, sesi 11):

- `heimdall flash --BOOT boot.img` — **proven** (S-Boot accepted our wrap; restore
  via heimdall also proven).
- `heimdall flash --USERDATA userdata.raw` — heimdall flashes raw partition data
  and does **not** un-sparse like fastboot. The crownlte `userdata.img` is an
  Android sparse image (`img2simg`). **Un-sparse first**: `simg2img userdata.img
  userdata.raw`, then flash `userdata.raw`. (If building the rootfs ourselves,
  emit a plain ext4 image instead.)
- **USERDATA flash erases all Android userdata** — warn explicitly. Recoverable
  (re-flash stock boot; userdata re-encrypts on first Android boot, or reflash
  stock userdata from the AP tar). This is the step that escapes BOOT-only scope
  — still Lapis-1-recoverable (see `docs/safety-unbrick.md`).

---

## 4. Phased plan (checkpoints, not a single big-bang flash)

> Golden rule preserved: backup → gate → flash → observe → restore-if-fail. The
> BOOT-only phases keep Lapis-1 coverage; the USERDATA phase is still
> recoverable but erases Android data. No phase touches BL/modem/efs/super.

### Phase 0 — DONE (as of sesi 11)
- Generic api33 rootfs downloaded + sha256-verified.
- Base A kernel (4.9.191) built with host gcc-16: `Image` 29.8 MB + 6 r7 dtbo
  (`eur_open_05` target) + `vmlinux` 268 MB; Halium defconfig
  `exynos9810-r7_droidian_defconfig` on branch `droidian-r7`; whole Knox stack off.
- Safety/unbrick framework + pre-flash gate (passing).
- S-Boot acceptance of the Samsung wrap **proven** (dt-table + SEANDROIDENFORCE).
- D0 probe flash-tested → **bootlooped** → restored to stock via
  `restore-stock.sh` (Lapis 1, confirmed Android came back). **Lesson: hand-rolled
  initramfs bypassed the Halium flow; pivot to the packaging path.**

### Phase 1 — Droidian-packaged r7 boot.img; flash BOOT only
- Set up `debian/kernel-info.mk` in Base A (§3.3A), build in Docker, extract
  `boot.img` (with the real `linux-initramfs-halium-generic` + Samsung dt-table).
- Run `pre-flash-check.sh` against it (adapt the gate to the new image).
- `heimdall flash --BOOT <packaged-boot.img>`.
- **Checkpoint A (clean diagnostic, replaces the D0 probe):**
  - Kernel boots to the Halium **initramfs** and is **stuck** (e.g. "Failed to
    boot" looking for userdata, or drops to an initramfs shell with devtools) →
    **kernel config is GOOD**; the initramfs is running; proceed to Phase 3
    (rootfs). (This is the expected Phase-1 outcome with no userdata rootfs
    flashed yet.)
  - **Bootloop** again (with the real initramfs this time) → the Base A kernel
    **config** is the problem, not the initramfs. Bisect: diff the r7 defconfig
    vs the proven `exynos9810-crownlte_defconfig`, re-test the Halium/Knox deltas
    one at a time (re-enable a suspect Knox option / revert a delta, re-wrap,
    re-flash). The Exynos 9810 journald/resolved/timesyncd issues
    (`debugging-tips.md`) can also hang boot — try masking via recovery if it
    reaches the rootfs.
  - This is unambiguous because the real initramfs gives a distinct "stuck in
    initramfs" state vs the kernel's "bootloop" — unlike the hand-rolled probe
    which conflated the two.

### Phase 2 — r7 adaptation `.deb` + `device-r7` tree
- Fork `sexynos-adaptation-exynos9810` → re-point `adaptation-hybris-api33-phone`,
  drop `bixby-state`, rebuild the `.deb` on trixie (reuses the systemd/udev/
  vendor-overlay payload).
- Fork `sexynos-device-crownlte` → `device-r7` (§3.2). Verify TEE flavor (§3.1).
- Extract r7 proprietary vendor blobs (N770FXXS9HXA3) from a rooted r7 or the
  stock AP tar; also fetch the common vendor blobs
  (`Sexynos/android_vendor_samsung_exynos9810-common`, 128M — not yet cloned).

### Phase 3 — rootfs (light path first; custom build only if needed)
- **Light path:** the downloaded generic api33 rootfs is already a full Droidian
  Phosh rootfs. Inject the r7 adaptation + r7 kernel modules into it: mount the
  rootfs image (or `chroot` via the debos builder), `apt install` the r7
  adaptation `.deb` + `linux-image-4.9.191-samsung-r7` (modules), re-pack. OR use
  `package-sideload-create` (porting-guide `rootfs-creation.md`) to make a
  recovery-flashable adaptation zip.
- **Full path (later):** fork `droidian-images` + `rootfs-templates` → r7
  `community_devices.yml` (r7, api33, r7 kernel packages, adaptation), debos
  build → custom LVM rootfs (the crownlte `genzip.sh` flow, re-pointed).
- Determine if the downloaded rootfs is LVM (fastboot, `data/userdata.img`) or
  plain-ext4 (recovery, `data/rootfs.img`) — check the zip contents. Prepare the
  userdata image for heimdall (un-sparse if sparse).
- `heimdall flash --USERDATA <userdata>` (warn: erases Android data).

### Phase 4 — D1: Droidian userspace boots (the real target)
- Boot: initramfs → rootfs → systemd → `lxc@android` → Phosh login (user
  `droidian`, password `1234`).
- Debug per `debugging-tips.md` (Exynos 9810 has known issues here):
  - mask `systemd-journald` / `systemd-resolved` / `systemd-timesyncd` if boot
    hangs (Exynos 9810/9820 known).
  - ensure `vendor` partition is mounted into the LXC container
    (`/var/lib/lxc/android/pre-start.sh` `# Halium 9` section).
  - regenerate udev rules from `ueventd*.rc`.
  - `phoc.ini` for the 1080×2400 panel; `test_hwcomposer` to validate the
    composer.
  - if stuck at the Droidian logo with no RNDIS, ensure
    `CONFIG_USB_CONFIGFS_RNDIS` in the kernel.

### Phase 5 — D2/D3: WiFi+BT, telephony (known-broken precedents)
- WiFi/BT: bcmdhd driver, `droid-get-bt-address.sh` for the MAC (crownlte uses
  the adaptation's helper). Telephony: ril, **dual-SIM known-broken (one SIM
  only)**, GPS/fingerprint/offline-charging known-broken on the crownlte
  precedent (`ref/README.md` Risk #5).

---

## 5. Open verification items / risks

1. **TEE flavor (mobicore vs teegris) for r7** — selects sepolicy `tee/*`. Must
   verify before reusing `sexynos-sepolicy` as-is. (crownlte = mobicore.)
2. **Base A kernel first-boot unverified** — the D0 bootloop was ambiguous
   (hand-rolled initramfs confounded it). Phase 1 gives a clean answer. If it
   bootloops even with the real initramfs, the config is at fault → bisect the
   Halium/Knox deltas vs `exynos9810-crownlte_defconfig`.
3. **heimdall USERDATA + sparse handling** — heimdall doesn't un-sparse; use
   `simg2img` or build a plain-ext4 image. Erases Android userdata (recoverable).
4. **Exynos 9810 systemd quirks** — journald/resolved/timesyncd may need masking
   (`debugging-tips.md`, explicitly calls out Exynos 9810/9820).
5. **r7 vendor blobs** — proprietary-files for N770FXXS9HXA3 + common 9810
   vendor blobs (128M, not yet cloned) needed at flash/boot time.
6. **Toolchain reconcile** — Base A built with host gcc-16; the Droidian packaging
   prefers clang-android-14 (android13). Decide in kernel-info.mk; fall back to
   gcc if clang rejects Base A.
7. **Repo age** — Sexynos 9810 repos archived (~2023); adaptation updated
   2025-08-25; core Droidian active (nightly 2026-07-08). The SoC + Halium-13
   layers are supported by core; the device bits are the revive work.
8. **Known-broken (crownlte precedent, expect similar r7):** GPS, fingerprint,
   offline charging, dual-SIM (one SIM only). Track in `PROGRESS.md` Issue log.

---

## 6. Cross-references (don't duplicate — reuse)

- Project runbook + the 3-layer plan + kernel decision + crownlte→r7 diff:
  `ref/README.md`
- Droidian porting guide: `ref/porting-guide/{README,kernel-compilation,rootfs-creation,debugging-tips}.md`
- Proven Halium kernel config template: `ref/linux-android-samsung-crownlte/arch/arm64/configs/exynos9810-crownlte_defconfig` (+ `debian/kernel-info.mk`)
- SoC common layer + golden boot geometry: `ref/sexynos-device-exynos9810-common/BoardConfigCommon.mk`
- Device-tree template to fork: `ref/sexynos-device-crownlte/`
- Adaptation to revive: `ref/sexynos-adaptation-exynos9810/`
- Image assembly + flashing template: `ref/sexynos-rootfs-templates-crownlte/`, `ref/sexynos-image-flashing-template/`
- Flash/restore protocol + unbrick: `docs/safety-unbrick.md`
- HW BOM + golden values: `../r7-mainline/docs/samsung-r7-device-page.md`, `../r7-mainline/PROGRESS.md` golden-values table
- UART jig (1.8V, for the blind-debug cases): `../r7-mainline/docs/uart-jig.md`