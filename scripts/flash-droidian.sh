#!/usr/bin/env bash
# flash-droidian.sh — orchestrated, fail-safe first flash of boot-droidian.img.
#
# Implements the flash-test-observe-restore protocol from docs/safety-unbrick.md:
#   1. back up current BOOT (so a local restore source exists)
#   2. run the pre-flash safety gate (refuse to flash on any failure)
#   3. flash boot-droidian.img to BOOT (ONLY boot — never BL/modem/efs/super)
#   4. reboot and OBSERVE — do not walk away; classify the outcome:
#        - D0 banner on screen / kernel log scrolling = SUCCESS (D0 reached)
#        - frozen/blank/hang = boot.img failed -> run restore-stock.sh
#   5. print the exact restore command prominently for the failure case
#
# This script does NOT auto-restore. The human decides, because the phone is
# in hand and can see the screen. Restoring is one command: restore-stock.sh.
#
# What this track writes: ONLY BOOT. Unbrick = re-flash stock BOOT (Lapis 1,
# 100% of our flash scope). BL is never written, so Download Mode always lives.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$ROOT/boot/boot-droidian.img"

echo "############ Droidian r7 — fail-safe flash ############"
echo

# 1. Backup current boot (idempotent — skips if already backed up)
echo "### Step 1/4: back up current BOOT ###"
"$ROOT/scripts/backup-stock-boot.sh"
echo

# 2. Pre-flash safety gate (exits non-zero on failure -> we stop here)
echo "### Step 2/4: pre-flash safety gate ###"
"$ROOT/scripts/pre-flash-check.sh"
echo

# 3. Confirm device is in Download Mode before flashing
echo "### Step 3/4: flash boot-droidian.img to BOOT ###"
if ! lsusb | grep -qi '04e8:685d'; then
  echo "No Samsung device in Download Mode. Enter it now:"
  echo "  power off -> Vol Down + Vol Up + plug USB -> hold Vol Up"
  echo "  (DATA cable, DIRECT USB port — a charge-only cable or hub hides the device)"
  echo "Re-run this script once 'lsusb' shows 04e8:685d."
  exit 1
fi
heimdall detect || { echo "FAIL: heimdall detect failed"; exit 1; }
heimdall flash --BOOT "$IMG"
echo "[flash] boot-droidian.img flashed to BOOT."
echo

# 4. Reboot + observe (human in the loop)
echo "### Step 4/4: reboot and OBSERVE (phone in hand, watch the screen) ###"
echo "Reboot: power off -> power on (or 'heimdall reboot' if supported)."
echo
echo "Classify what happens within ~30s:"
echo "  ✅ SUCCESS (D0):  kernel log scrolls / 'D0 REACHED' banner on screen."
echo "                    -> Note the result in PROGRESS.md, proceed to TASK 3+."
echo "  ❌ FAILED:         screen frozen/blank/hang at logo, or no Droidian banner."
echo "                    -> Restore with ONE command:"
echo
echo "                         ./scripts/restore-stock.sh"
echo
echo "                    (This re-flashes the stock+Magisk boot -> back to Android."
echo "                     BL was never written, so this always works. Then debug:"
echo "                     see docs/safety-unbrick.md 'boot-diagnosis decision tree'.)"
echo
echo "⚠ Do NOT walk away on the first flash. If it hangs and you're not watching,"
echo "  you won't know whether to restore. Stay until you see a banner or a freeze."
echo "############ flash done — observe now ############"