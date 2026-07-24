#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# restore-stock.sh — EMERGENCY restore of SM-N770F (r7) to stock/Magisk Android.
#
# This is the single safety net for "the flashed boot-droidian.img did not boot."
# The Droidian track ONLY ever writes the BOOT partition (never BL/modem/efs/
# super), so S-Boot stays intact and Download Mode stays alive no matter what
# the boot.img does. A failed/blank/hung boot is therefore NOT a brick — re-
# flashing the stock (Magisk-patched) boot image returns the phone to working
# Android. This is "Lapis 1" of the unbrick plan (see docs/safety-unbrick.md).
#
# Source of the restore image (golden, already known-good, boots Android+Magisk):
#   ../r7-mainline/firmware/images/boot-preM1.img
# (boot-preM1.img is the stock boot with Magisk — proven boots Android sesi 5/6.)
#
# Usage:
#   ./scripts/restore-stock.sh            # restore BOOT only (default; fixes boot.img fails)
#   ./scripts/restore-stock.sh --userdata # ALSO restore USERDATA to stock (erases Droidian rootfs)
#
# Prereqs: phone in Download Mode (power off -> Vol Down + Vol Up + plug USB ->
# hold Vol Up). heimdall + a DATA cable + a direct USB port (charge-only cable
# or a hub makes `lsusb` see no Samsung 04e8 device — learned sesi 6).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAINLINE="$(cd "$ROOT/../r7-mainline" && pwd)"
BOOT_STOCK="$MAINLINE/firmware/images/boot-preM1.img"

RESTORE_USERDATA=0
[ "${1:-}" = "--userdata" ] && RESTORE_USERDATA=1

echo "=== Droidian track — restore stock (Lapis 1) ==="
[ -f "$BOOT_STOCK" ] || { echo "FAIL: restore image not found: $BOOT_STOCK"; exit 1; }

# Sanity: confirm it's a Samsung dt-table boot image (same check S-Boot uses),
# so we never flash a truncated/corrupt restore image.
python3 - "$BOOT_STOCK" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
ps=struct.unpack_from('<I',d,36)[0]
ks=struct.unpack_from('<I',d,8)[0]; rs=struct.unpack_from('<I',d,16)[0]
pa=lambda x:(x+ps-1)//ps*ps
off=pa(ps)+pa(ks)+pa(rs)+pa(struct.unpack_from('<I',d,1632)[0])+pa(struct.unpack_from('<I',d,24)[0])
m=struct.unpack_from('>I',d,off)[0]
assert d[:8]==b'ANDROID!' and m==0xd7b7ab1e, "restore image is NOT a valid Samsung dt-table boot.img"
print(f"[restore] restore image OK ({len(d)} B, dt magic 0x{m:08x})")
PY

echo "[restore] checking for device in Download Mode (USB PID 04e8:685d)..."
if ! lsusb | grep -qi '04e8:685d'; then
  echo "FAIL: no Samsung device in Download Mode on USB."
  echo "  Put phone in Download Mode: power off -> Vol Down + Vol Up + plug USB -> hold Vol Up."
  echo "  Use a DATA cable plugged into a DIRECT USB port (not a hub)."
  echo "  (Or, if adb is still alive in a bootloop: adb reboot download)"
  exit 1
fi

echo "[restore] heimdall detect..."
heimdall detect || { echo "FAIL: heimdall detect failed"; exit 1; }

echo "[restore] flashing BOOT <- $BOOT_STOCK ..."
heimdall flash --BOOT "$BOOT_STOCK"
echo "[restore] BOOT flashed."

if [ "$RESTORE_USERDATA" -eq 1 ]; then
  echo
  echo "[restore] --userdata: restoring USERDATA from stock firmware (erases Droidian rootfs)."
  echo "  Source: the stock USERDATA image must be extracted first from the AP tar."
  echo "  This is NOT needed to recover from a bad boot.img — only if userdata was"
  echo "  overwritten with the Droidian rootfs and you want Android's userdata back."
  echo "  (Not automated here; do manually if ever required. Default restore = BOOT only.)"
fi

echo
echo "[restore] DONE. Reboot the phone (power off -> power on, or heimdall reboot)."
echo "[restore] Expected: boots to stock Android (Magisk). If it does, the Droidian"
echo "[restore] boot.img failure is fully recovered — safe to flash a fixed image."