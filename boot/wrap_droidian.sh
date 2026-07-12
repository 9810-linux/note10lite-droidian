#!/usr/bin/env bash
# wrap_droidian.sh — package the Droidian/Halium r7 boot image for Samsung S-Boot.
#
# Droidian boots via the STOCK S-Boot path (NOT uniLoader): boot.img = downstream
# r7 kernel Image + real Halium initramfs + Samsung dt-table, flashed to the BOOT
# partition. S-Boot (r7, Exynos 9810) validates the boot image's dt section as a
# Samsung dt TABLE (big-endian, magic 0xd7b7ab1e) — NOT a raw dtb — and expects a
# "SEANDROIDENFORCE\0" marker after it. AOSP mkbootimg alone yields a raw-dtb dt
# section + no marker → S-Boot rejects with "dt table header check failed"
# (proven on-device, r7-mainline sesi 6). Same fix as wrap_uniloader.sh: pass
# the STOCK Samsung dt table verbatim as --dtb, append SEANDROIDENFORCE\0,
# zero-pad to the partition size. No AVB footer (S-Boot checks dt-table before
# AVB; unlocked device is AVB-lenient — proven r7-mainline sesi 6).
#
# Inputs (gitignored binaries, present in working dir — NOT committed):
#   build-droidian-r7/arch/arm64/boot/Image         downstream r7 kernel (Halium config)
#   initramfs/initrd.img-halium-generic              real Halium boot initramfs (gzip cpio,
#                                                   ~16.85 MB, from the linux-initramfs-
#                                                   halium-generic .deb). Replaces the
#                                                   minimal D0 probe (initramfs/init.c).
#   ../r7-mainline/firmware/images/boot-preM1.img   stock/Magisk boot (source of
#                                                   the Samsung dt table)
# Output (gitignored binary):
#   boot/boot-droidian.img                          S-Boot-compatible image (padded to partition)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAINLINE="$(cd "$ROOT/../r7-mainline" && pwd)"
# Since sesi 13: artifacts come from the official Droidian packaging build
# (kernel-n770f-oss debian/ + quay.io/droidian/build-essential container,
# clang-android-9.0-r353983c) — NOT the old host-gcc-16 build-droidian-r7 dir.
KBUILD="$(cd "$ROOT/../kernel-n770f-oss/out/KERNEL_OBJ" && pwd)"
IMAGE="$KBUILD/arch/arm64/boot/Image"
RAMDISK="$KBUILD/initramfs.gz"
STOCK="$MAINLINE/firmware/images/boot-preM1.img"
DTTABLE="$ROOT/boot/r7-stock-dttable.bin"
OUT="$ROOT/boot/boot-droidian.img"

PART_SIZE=61865984               # r7 BOOT partition size in bytes (golden value from stock image)
DT_OFF=29769728; DT_LEN=189700   # stock Samsung dt table offset/len in boot-preM1.img (golden values)

# Halium cmdline. NOTE: r7's CONFIG_CMDLINE is EMPTY (unlike crownlte, which bakes
# "console=tty0 droidian.lvm.prefer" into the kernel + CONFIG_CMDLINE_EXTEND=y), so
# the ENTIRE Halium cmdline must come from THIS boot.img cmdline — the kernel
# supplies none of it.
#
#   console=ttySAC0,115200 console=tty0  tty0 LAST -> /dev/console (init stdout) =
#                                        screen (no UART jig needed); ttySAC0 first
#                                        = UART bonus if a 1.8V jig is attached.
#                                        Kernel printk goes to BOTH.
#   loglevel=8 ignore_loglevel            verbose early log on screen (debug aid).
#   cgroup_disable=schedtune              crownlte Halium tweak: schedtune umount.
#   systemd.journald.forward_to_kmsg=yes  Exynos 9810 journald hang workaround.
#   log_buf_len=8M                        big kernel log buffer.
#   droidian.lvm.prefer                   Droidian rootfs is an LVM LV on userdata.
#   androidboot.hardware=exynos9810       vendor blob expectation.
#   androidboot.selinux=permissive        Halium/libhybris needs permissive
#                                        (CONFIG_SECURITY_SELINUX_BOOTPARAM=y).
#   androidboot.boot_devices=11120000.ufs UFS boot-device path for vendor mount.
#
# NO init=/init — let the REAL Halium initramfs /init run (crownlte doesn't set
# init=; the kernel defaults to the initramfs /init, which prints
# "Loading, please wait..." on screen = the kernel-good signal). NO systempart=.
#
# Phase-1 diagnostic: userdata still holds Android (no Droidian rootfs flashed
# yet), so the initramfs runs, fails to activate the droidian-rootfs LVM LV, and
# gets STUCK in initramfs (docs/debugging-tips.md). Stuck/hang + "Loading, please
# wait..." = KERNEL CONFIG GOOD (-> Phase 3: flash Droidian rootfs to USERDATA).
# Bootloop = kernel config bad -> bisect vs the proven crownlte defconfig.
# Sesi 13: cmdline = proven crownlte Droidian cmdline + r7 androidboot args,
# EXACTLY matching debian/kernel-info.mk (KERNEL_BOOTIMAGE_CMDLINE) in the
# packaging build. console=tty0 is safe with fbcon OFF (VT only, no fb console
# binding — fbcon on DECON = NULL-deref panic, the sesi-12 bootloop cause).
# No ttySAC0 (no UART jig), no loglevel spam: observation channel = the halium
# initramfs USB RNDIS gadget (18d1:d001) + telnet 192.168.2.15, NOT the screen.
CMDLINE="console=tty0 cgroup_disable=schedtune systemd.journald.forward_to_kmsg=yes \
log_buf_len=8M droidian.lvm.prefer androidboot.hardware=exynos9810 \
androidboot.selinux=permissive androidboot.boot_devices=11120000.ufs"

[ -f "$IMAGE" ]  || { echo "FAIL: kernel Image not found: $IMAGE"; exit 1; }
[ -f "$RAMDISK" ] || { echo "FAIL: initramfs not found: $RAMDISK (fetch from linux-initramfs-halium-generic .deb; see PROGRESS.md)"; exit 1; }
[ -f "$STOCK" ] || { echo "FAIL: stock boot not found: $STOCK"; exit 1; }

# 1. Extract the stock Samsung dt table (magic 0xd7b7ab1e) if not already staged.
#    (Reuses the same staged file as r7-mainline if present; S-Boot dt-table
#    check + dtbo_idx=5 overlay match the stock downstream dtb inside it.)
if [ ! -f "$DTTABLE" ]; then
  echo "[wrap] extracting stock Samsung dt table from $STOCK @ $DT_OFF ($DT_LEN B) -> $DTTABLE"
  python3 - "$STOCK" "$DTTABLE" "$DT_OFF" "$DT_LEN" <<'PY'
import sys, struct
src, dst, off, ln = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
d = open(src, 'rb').read()
dt = d[off:off+ln]
magic = struct.unpack_from('>I', dt, 0)[0]
assert magic == 0xd7b7ab1e, f"extracted dt table magic 0x{magic:08x} != 0xd7b7ab1e"
open(dst, 'wb').write(dt)
print(f"[wrap] staged {len(dt)} B (magic 0x{magic:08x}) -> {dst}")
PY
fi

# 2. mkbootimg: header v2, kernel=downstream Image, ramdisk=real Halium initramfs,
#    dtb=stock Samsung dt table. base/pagesize = golden values (same as stock).
echo "[wrap] mkbootimg (header v2, kernel=downstream Image, ramdisk=real Halium initramfs, dtb=stock Samsung dt table)..."
mkbootimg --kernel "$IMAGE" --ramdisk "$RAMDISK" --dtb "$DTTABLE" \
          --base 0x10000000 --pagesize 2048 --header_version 2 \
          --cmdline "$CMDLINE" -o "$OUT"

# 3. Append SEANDROIDENFORCE\0 + zero-pad to the partition size.
echo "[wrap] appending SEANDROIDENFORCE marker + zero-pad to $PART_SIZE bytes..."
python3 - "$OUT" "$PART_SIZE" <<'PY'
import sys
path, part = sys.argv[1], int(sys.argv[2])
d = open(path, 'rb').read() + b"SEANDROIDENFORCE\x00"
if len(d) > part:
    print(f"FAIL: image {len(d)} > partition {part}", file=sys.stderr); sys.exit(1)
d += b"\x00" * (part - len(d))
open(path, 'wb').write(d)
print(f"[wrap] wrote {path}: {len(d)} bytes")
PY

# 4. Verify the structure S-Boot will check (same checks as wrap_uniloader.sh).
echo "[wrap] verifying..."
python3 - "$OUT" "$PART_SIZE" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(); part = int(sys.argv[2])
ks = struct.unpack_from('<I', d, 8)[0];  rs = struct.unpack_from('<I', d, 16)[0]
ss = struct.unpack_from('<I', d, 24)[0]; ps = struct.unpack_from('<I', d, 36)[0]
hv = struct.unpack_from('<I', d, 40)[0]
rdtbo = struct.unpack_from('<I', d, 1632)[0]; dtb_sz = struct.unpack_from('<I', d, 1648)[0]
pa = lambda x: (x + ps - 1) // ps * ps
off = pa(ps) + pa(ks) + pa(rs) + pa(ss) + pa(rdtbo)
magic = struct.unpack_from('>I', d, off)[0]
se = d.find(b'SEANDROID')
print(f"  size={len(d)}  ANDROID!={d[:8]}  hdrver={hv}  kernel_size={ks}  ramdisk_size={rs}  dtb_size={dtb_sz}  page={ps}")
print(f"  dt section @ {off}: magic=0x{magic:08x} ({'OK Samsung dt table' if magic == 0xd7b7ab1e else 'WRONG'})")
print(f"  SEANDROID @ {se} ({'present' if se >= 0 else 'MISSING'})")
assert d[:8] == b'ANDROID!' and magic == 0xd7b7ab1e and se >= 0 and len(d) == part, "VERIFY FAILED"
assert rs > 0, "VERIFY FAILED: ramdisk empty (initramfs not embedded)"
print("  VERIFY OK (kernel + initramfs + Samsung dt-table all present)")
PY
echo "[wrap] done -> $OUT"
echo "[wrap] flash: heimdall flash --BOOT $OUT"
echo "[wrap] restore stock: heimdall flash --BOOT $MAINLINE/firmware/images/boot-preM1.img"
echo "[wrap]   (run scripts/restore-stock.sh for the one-command restore)"