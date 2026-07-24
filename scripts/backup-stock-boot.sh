#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# backup-stock-boot.sh — back up the CURRENT BOOT partition before the first
# Droidian flash, creating the local restore source for this track.
#
# r7-mainline already keeps boot-preM1.img (stock+Magisk, proven boots Android)
# as the shared restore image, and restore-stock.sh uses that. This script
# makes an ADDITIONAL track-local copy at firmware/images/boot-pre-droidian.img
# so the Droidian track is self-contained and the pre-flash state is pinned.
#
# Two ways to obtain it (pick what the phone is currently running):
#   (A) If phone is in Android/Magisk NOW: pull the live BOOT partition via adb.
#       Reboot to Download Mode afterward (the flash needs it).
#   (B) If phone is in Download Mode NOW: heimdall read --BOOT.
#
# The backup is validated as a Samsung dt-table boot.img before being accepted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/firmware/images/boot-pre-droidian.img"
mkdir -p "$(dirname "$OUT")"

validate() {  # $1 = path  -> asserts valid Samsung dt-table boot.img
  python3 - "$1" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
ps=struct.unpack_from('<I',d,36)[0]
ks=struct.unpack_from('<I',d,8)[0]; rs=struct.unpack_from('<I',d,16)[0]
pa=lambda x:(x+ps-1)//ps*ps
off=pa(ps)+pa(ks)+pa(rs)+pa(struct.unpack_from('<I',d,1632)[0])+pa(struct.unpack_from('<I',d,24)[0])
m=struct.unpack_from('>I',d,off)[0]
assert d[:8]==b'ANDROID!' and m==0xd7b7ab1e, "not a valid Samsung dt-table boot.img"
assert len(d)==61865984, f"size {len(d)} != expected partition 61865984"
print(f"[backup] valid boot.img ({len(d)} B, dt magic 0x{m:08x})")
PY
}

if [ -f "$OUT" ]; then
  echo "[backup] $OUT already exists; validating."
  validate "$OUT"; echo "[backup] nothing to do (keep existing pre-flash boot)."; exit 0
fi

echo "[backup] backing up current BOOT -> $OUT"
if adb get-state >/dev/null 2>&1; then
  # (A) live Android pull
  echo "[backup] phone in Android (adb). Pulling BOOT via adb root dd."
  adb shell 'su -c "dd if=/dev/block/by-name/BOOT /data/local/tmp/boot-pre-droidian.img"' 2>/dev/null \
    || adb shell 'dd if=/dev/block/by-name/BOOT /data/local/tmp/boot-pre-droidian.img'
  adb pull /data/local/tmp/boot-pre-droidian.img "$OUT"
  adb shell 'rm -f /data/local/tmp/boot-pre-droidian.img' 2>/dev/null || true
elif lsusb | grep -qi '04e8:685d'; then
  # (B) Download Mode read
  echo "[backup] phone in Download Mode. heimdall read --BOOT."
  heimdall read --BOOT "$OUT"
else
  echo "FAIL: phone neither in adb (Android) nor Download Mode (04e8:685d)."
  echo "  Boot to Android (for adb pull) or enter Download Mode (for heimdall read)."
  exit 1
fi

validate "$OUT"
echo "[backup] DONE -> $OUT (gitignored; this is your local restore source)."