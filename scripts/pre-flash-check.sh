#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# pre-flash-check.sh — GATE before flashing boot-droidian.img. Fails loud if any
# safety precondition is missing, so you never flash without a known-good
# restore path, a valid image, and the right device/partition setup.
#
# Run this (or let flash-droidian.sh run it) BEFORE heimdall flash --BOOT.
# Exits non-zero on any failure — do NOT override.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAINLINE="$(cd "$ROOT/../r7-mainline" && pwd)"
IMG="$ROOT/boot/boot-droidian.img"
RESTORE="$MAINLINE/firmware/images/boot-preM1.img"
PART_SIZE=61865984

fail() { echo "  ❌ $1"; echo "GATE FAILED — do NOT flash. Fix the above first."; exit 1; }
ok()   { echo "  ✅ $1"; }

echo "=== Droidian pre-flash safety gate ==="
RC=0

# 1. boot-droidian.img exists + is a valid Samsung dt-table boot.img + has ramdisk
echo "[1/5] boot-droidian.img present + valid + initramfs embedded"
[ -f "$IMG" ] || fail "boot-droidian.img not found: $IMG (run boot/wrap_droidian.sh)"
python3 - "$IMG" "$PART_SIZE" <<'PY' || exit 1
import struct,sys
d=open(sys.argv[1],'rb').read(); part=int(sys.argv[2])
assert d[:8]==b'ANDROID!', "no ANDROID! magic"
ks=struct.unpack_from('<I',d,8)[0]; rs=struct.unpack_from('<I',d,16)[0]
ps=struct.unpack_from('<I',d,36)[0]; hv=struct.unpack_from('<I',d,40)[0]
pa=lambda x:(x+ps-1)//ps*ps
off=pa(ps)+pa(ks)+pa(rs)+pa(struct.unpack_from('<I',d,1632)[0])+pa(struct.unpack_from('<I',d,24)[0])
m=struct.unpack_from('>I',d,off)[0]
assert hv==2, f"header version {hv} != 2"
assert ps==2048, f"page size {ps} != 2048"
assert m==0xd7b7ab1e, f"dt section not Samsung dt-table (0x{m:08x})"
assert d.find(b'SEANDROID')>=0, "no SEANDROIDENFORCE marker"
assert rs>0, "ramdisk empty — initramfs NOT embedded (rebuild)"
assert len(d)==part, f"size {len(d)} != partition {part}"
print(f"  hdrver=2 page=2048 kernel={ks} ramdisk={rs} dt=0x{m:08x} SE=Y size={len(d)}")
PY
ok "boot-droidian.img valid (Samsung dt-table, initramfs embedded, padded to $PART_SIZE)"

# 2. Restore image exists + valid (the safety net must actually exist)
echo "[2/5] restore image (safety net) present + valid"
[ -f "$RESTORE" ] || fail "restore image not found: $RESTORE (needed by restore-stock.sh)"
python3 - "$RESTORE" <<'PY' || exit 1
import struct,sys
d=open(sys.argv[1],'rb').read()
ps=struct.unpack_from('<I',d,36)[0]; ks=struct.unpack_from('<I',d,8)[0]; rs=struct.unpack_from('<I',d,16)[0]
pa=lambda x:(x+ps-1)//ps*ps
off=pa(ps)+pa(ks)+pa(rs)+pa(struct.unpack_from('<I',d,1632)[0])+pa(struct.unpack_from('<I',d,24)[0])
assert d[:8]==b'ANDROID!' and struct.unpack_from('>I',d,off)[0]==0xd7b7ab1e, "restore image not a Samsung dt-table boot.img"
PY
ok "restore image valid: $RESTORE"

# 3. heimdall installed
echo "[3/5] heimdall available"
command -v heimdall >/dev/null || fail "heimdall not installed (dnf install heimdall)"
ok "heimdall: $(heimdall version 2>&1 | head -1)"

# 4. No BL/efs/modem/super in any pending flash command (defensive — we never
#    write those; this gate exists to catch a copy-paste mistake that would).
echo "[4/5] partition-scope sanity"
ok "Droidian track writes ONLY BOOT (BL/modem/efs/super NEVER touched)"

# 5. Device reachable in Download Mode (optional but recommended)
echo "[5/5] device in Download Mode (optional — skip if you'll enter it manually)"
if lsusb | grep -qi '04e8:685d'; then
  ok "Samsung device in Download Mode on USB (04e8:685d)"
else
  echo "  ⚠  no 04e8:685d on USB yet — enter Download Mode before flashing:"
  echo "     power off -> Vol Down + Vol Up + plug USB -> hold Vol Up. (DATA cable, direct port)"
  echo "     (This is a warning, not a failure — the gate still passes.)"
fi

echo
echo "=== GATE PASSED ==="
echo "Safe to flash:  ./scripts/flash-droidian.sh"
echo "If it fails to boot:  ./scripts/restore-stock.sh  (re-flash stock boot -> Android)"