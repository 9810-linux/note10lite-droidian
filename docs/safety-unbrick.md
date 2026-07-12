# Safety & unbrick framework — Droidian track (SM-N770F, r7)

> Net for the case where `boot-droidian.img` does **not** boot. Read this
> *before* the first flash. Pairs with `../r7-mainline/docs/unbrick.md` (shared
> deep-unbrick, Lapis 2) and `../r7-mainline/docs/uart-jig.md` (UART debug).
>
> Track scope: this track writes **only the `BOOT` partition** (and optionally
> `USERDATA` for the rootfs, in a later task — never done in the D0 flash).
> **BL / modem / efs / super are never written.** That single fact is the whole
> reason a failed boot is recoverable in one command.

## Why a failed boot is NOT a brick

The Droidian boot.img is flashed to `BOOT`. Samsung's bootloader (BL / S-Boot)
lives on a **separate `BOOTLOADER` partition we never touch**. So:

- S-Boot stays intact even if `BOOT` is garbage → **Download Mode always boots.**
- A boot-loop / blank screen / hang = recoverable: re-flash a known-good `BOOT`.
- The known-good image is `../r7-mainline/firmware/images/boot-preM1.img`
  (stock boot + Magisk, proven to boot Android in sesi 5/6 of the mainline track).

## Before you flash — the flash-test-observe-restore protocol

The first flash of any new boot.img is a **probe**, not a deploy. Follow it:

1. **Backup current boot** so a local restore source exists:
   `./scripts/backup-stock-boot.sh` (idempotent — skips if `firmware/images/boot-pre-droidian.img` exists).
2. **Run the safety gate** (refuses to flash on any precondition failure):
   `./scripts/pre-flash-check.sh` — verifies `boot-droidian.img` is a valid
   Samsung dt-table boot.img with the initramfs embedded, the restore image
   exists + is valid, heimdall is installed, and scope is BOOT-only.
3. **Flash** (orchestrated, runs 1+2 then flashes): `./scripts/flash-droidian.sh`.
4. **Observe — do not walk away.** Reboot and watch the screen for ~30s:
   - **SUCCESS (D0):** kernel log scrolls and/or the `D0 REACHED` banner shows.
     Note it in `PROGRESS.md`; proceed to TASK 3 (device adaptation) + the full
     Halium initramfs (switch_root to Droidian systemd).
   - **FAILED:** screen frozen/blank/hang at logo, no banner. Go to step 5.
5. **Restore** (one command): `./scripts/restore-stock.sh` → re-flashes
   `boot-preM1.img` to BOOT → reboots to stock Android+Magisk. Phone is back.
   Then debug per the decision tree below; fix; re-wrap; re-flash.

> Or run the orchestrated flow directly: `./scripts/flash-droidian.sh` does
> steps 1–3 and prints the exact restore command for step 5. It does **not**
> auto-restore — the human decides, because the phone is in hand and can see
> the screen. Restoring is always one command.

## Lapis 1 — primary unbrick (covers 100% of this track's flashes)

**When:** boot-droidian.img failed to boot (any failure mode), or you just want
Android back.

```
# 1. Phone -> Download Mode:
#    power off -> Vol Down + Vol Up + plug USB -> hold Vol Up
#    (from an adb bootloop: `adb reboot download`)
# 2. Restore:
./scripts/restore-stock.sh
# 3. Reboot -> stock Android (Magisk).
```

Prereqs: phone in Download Mode, a **DATA cable** in a **direct USB port**
(charge-only cable or a hub makes `lsusb` see no `04e8:685d` — learned sesi 6),
heimdall installed. `restore-stock.sh` validates the restore image is a valid
Samsung dt-table boot.img before flashing, so it can't make things worse.

## Lapis 2 — deep unbrick (only if BL itself is corrupt — NOT in scope)

Used **only** if the `BOOTLOADER` partition is corrupt, which this track never
causes. If you ever experiment outside the runbook and brick BL, Exynos 9810 is
vulnerable to CVE-2024-56426 (BootROM USB ACE). See
`../r7-mainline/docs/unbrick.md` Lapis 2 for the tooling (houston / exynos-usbdl)
and the sboot-split procedure. **Do not flash `--BOOTLOADER`** in any Droidian
experiment — that is the one action that escapes Lapis 1 coverage.

## Boot-diagnosis decision tree (image didn't boot — what to fix)

After `restore-stock.sh` has you back in Android, classify the failure and pick
the fix. The downstream 4.9 kernel has **all** drivers (no CMU wall, unlike
mainline), so most "works in mainline impossible" things just work here; failures
are usually boot-image mechanics or config.

```
Phone hangs / blank / boot-loop with boot-droidian.img
│
├─ Did S-Boot even ACCEPT the image?
│  ├─ "dt table header check failed" → dt section is wrong.
│  │   Fix: ensure wrap_droidian.sh used the STOCK Samsung dt table (magic
│   0xd7b7ab1e) as --dtb, not a raw dtb. Re-run boot/wrap_droidian.sh; the
│   staged table is boot/r7-stock-dttable.bin (189700 B). Check SEANDROIDENFORCE
│   is present (pre-flash-check.sh already asserts both).
│  └─ Accepted but blank (proven accepted = no Download-Mode fallback msg)
│     → S-Boot fine; kernel/initramfs problem. ↓
│
├─ Accepted, screen frozen at "Samsung" logo / kernel never logs
│  ├─ SCREEN-FIRST (no jig required here, unlike mainline): the downstream 4.9
│  │   kernel has ALL drivers (CMU/DECON/fbcon/UFS), so fbcon comes up early and
│  │   the kernel boot log + any panic trace appear ON SCREEN. The D0 /init
│  │   writes the banner explicitly to /dev/tty0 (screen) — so the screen is the
│  │   primary channel. Classify what's on screen:
│  │   - D0 banner + /proc/version + /proc/cmdline shown → SUCCESS (D0 reached).
│  │   - kernel log ends mid-boot / a panic stack trace → hang point is visible.
│  │     Most likely: a Halium config delta, or a Knox option we disabled had a
│  │     dependency. Diff .config vs the proven crownlte defconfig
│  │     (ref/linux-android-samsung-crownlte) and re-test the deltas one at a
│  │     time (re-enable a suspect, re-wrap, re-flash).
│  │   - blank/frozen at the Samsung logo, phone STAYS ON (no reboot), no log at
│  │     all → the kernel hung BEFORE fbcon initialized (very early). This is the
│  │     ONE case that's blind without UART — same situation as mainline M1.
│  │     Restore (restore-stock.sh), then either bisect the config blind
│  │     (re-wrap with a smaller delta set, re-flash, see if it gets further)
│  │     or get a 1.8V UART jig (r7-mainline/docs/uart-jig.md) to see the exact
│  │     hang point. The initramfs already prints to ttySAC0, so a jig "just
│  │     works" when you have one.
│  │
│  └─ UART jig connected (1.8V) as well? → bonus: full boot log incl. pre-fbcon
│     lines. ttySAC0 is in the cmdline and /init writes to it explicitly, so a
│     jig shows everything the screen does plus earlier lines.
│
├─ Accepted, reboots in a loop (watchdog)
│  → kernel panics. UART log shows the panic. Common cause: a Halium config
│    delta broke boot, or a Knox option we disabled had a dependency. Diff
│    .config vs the proven crownlte defconfig and re-test deltas one at a time.
│
└─ Accepted, boots but no D0 banner (reaches userspace but init didn't print)
   → unlikely (init is tiny + proven pattern from mainline track); if it
     happens, the initramfs cpio may be malformed. Verify with
     `gzip -cd initramfs/ramdisk.cpio.gz | cpio -tv` shows `/init` mode 755,
     and unpack_bootimg shows ramdisk_size > 0 (pre-flash-check.sh asserts this).
```

Golden rule for every iteration: **backup → gate → flash → observe → (restore
if fail) → fix → repeat.** Never flash a second variation without the restore
image confirmed present (`pre-flash-check.sh` step 2 enforces it).

## What is recoverable vs not

| State | Recoverable? | How |
|---|---|---|
| boot.img blank/hang/loop (this track's only write) | ✅ always | `restore-stock.sh` (Lapis 1) |
| USERDATA overwritten with Droidian rootfs (later task) | ✅ Android userdata gone, phone fine | re-flash stock boot; userdata re-encrypts on first Android boot, or reflash stock userdata from AP |
| Bootloader (BL) corrupted | ⚠️ deep unbrick needed | Lapis 2 (`../r7-mainline/docs/unbrick.md`) — **do not cause this** |
| EFS/modem wiped (IMEI) | ❌ permanent IMEI loss | prevented: already backed up (mainline TASK 0.4); this track never writes them |

## Shared assets (don't duplicate — cross-reference r7-mainline)

- Restore image: `../r7-mainline/firmware/images/boot-preM1.img`
- Deep unbrick (Lapis 2): `../r7-mainline/docs/unbrick.md`
- UART jig (1.8V, not 3.3V): `../r7-mainline/docs/uart-jig.md`
- HW table (what the downstream kernel drives = what Halium gets): `../r7-mainline/docs/samsung-r7-device-page.md`
- Golden values (kernel base/pagesize/cmdline/FB/memory): `../r7-mainline/PROGRESS.md` golden-values table
- Stock Samsung dt-table extraction pattern: `../r7-mainline/boot/wrap_uniloader.sh`