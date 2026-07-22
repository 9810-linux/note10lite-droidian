# r7 modem/telephony — signal quality + rild CPU (investigated + mostly fixed, sesi-21)

Telephony (RIL/ofono, D3) works: SIM detected, LTE registration, mobile data
all functional via `ofono-binder-plugin` -> `ofono2mm` -> ModemManager ->
NetworkManager (`gsm` connection `telkomsel`, APN `internet`). Found and fixed
a real bug while chasing "signal bar stuck near 0/5 despite working data" and
"phone runs hot" — the fix below also appears to have resolved (or at least
prevented) a related rild CPU-spin issue, see below.

## Fixed: 5G/NR pref-mode retry storm (this directory)
`SM-N770F`'s modem (Shannon 360, `ril.modem.board=SHANNON360`) is **4G-only
hardware**, but ModemManager defaults to allowing 5G NR as a mode (the vendor
RIL registers `@1.4::IRadio`, which exposes an NR capability bit even though
the CP firmware doesn't implement it). With NR allowed, `ofono-binder-plugin`
(`binder_network.c: binder_network_actual_pref_modes()`) computes
`RADIO_PREF_NET_NR_LTE_GSM_WCDMA` as the preferred mode and pushes it to the
CP every ~2s forever; the baseband NAKs it every time (`Error 38 setting pref
mode` in the ofono journal, visible at the IPC level too:
`dmesg | grep mif` shows a `shmem_cp2ap_rat_mode_handler` TX/RX pair every
~2s). **Fix:** restrict ModemManager's allowed modes to 2G/3G/4G
(`mmcli -m 0 --set-allowed-modes='4g|3g|2g' --set-preferred-mode=4g`). This is
a **runtime-only** ModemManager setting — it does not survive a
`ModemManager.service` restart or reboot, hence this unit re-applies it every
boot, after ModemManager comes up.

### Install
    sudo cp r7-modem-restrict-4g.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/r7-modem-restrict-4g.sh
    sudo cp r7-modem-restrict-4g.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now r7-modem-restrict-4g.service

## Fixed: signal bar reads far too low (sesi-22) — `binder.conf`
Symptom: bar sits at 0–1 of 4 and `mmcli` reports **1–17 %** while mobile data
works perfectly; occasionally jumps to ~70 % / 3 bars. Not a radio problem —
a unit mismatch in `ofono-binder-plugin`.

`binder_netreg.c` maps dBm to percent as:

    percent = (dbm <= weak) ? 1 : (dbm >= strong) ? 100
            : 100 * (dbm - weak) / (strong - weak)

with defaults `weak = -100`, `strong = -60`
(`BINDER_DEFAULT_SLOT_DBM_WEAK/_STRONG`, `binder_plugin.c`). Those suit
**RSSI** — but for LTE the plugin feeds **RSRP** straight in as dBm
(`binder_netreg_dbm_from_rsrp()` returns simply `-rsrp`). RSRP measures power
per resource element and runs ~20–25 dB below RSSI for the same real signal,
so perfectly good LTE (−95…−105 dBm RSRP) falls at/below the −100 "weak"
clamp → pinned to **1 %**. The occasional ~70 % readings were the modem
sitting on GSM/WCDMA, where the dBm genuinely does come from RSSI.

**Fix:** set `signalStrengthRange` (syntax `MIN,MAX`, MIN < MAX) in the slot
group of `/etc/ofono/binder.conf` — see `binder.conf` in this directory:

    [slot1]
    path = /ril_0
    slot = 0
    signalStrengthRange = -115,-85

Those are AOSP's `lteRsrpThresholds` (−128/−118/−108/−98 = 1..4 bars), giving
−128 → 1 %, −118 → 33 %, −113 → 50 %, −108 → 67 %, −98 → 100 %.

⚠ **Do not use −115,−85** (tried first). It fixed 2G/3G but still pinned LTE
near 1 %, because it is stricter than Android's own scale. Verified with
`ofonod -n -d "*"`, which logs the computed value —
`binder_netreg_strength_cb() slot1 -119 dBm (1%)`, `-109 dBm (20%)`,
`-108 dBm (23%)`. That log also **proved the RSRP data is valid** (not the
`-140` "no data" fallback in `binder_netreg_get_signal_strength_dbm()`), i.e.
there is no parsing bug — LTE RSRP here genuinely sits around −108…−119 dBm,
which is weak-ish coverage; 2G reads strong because 900 MHz penetrates better.
Debug drop-in used: `/etc/systemd/system/ofono.service.d/99-debug.conf` with
`ExecStart=/usr/sbin/ofonod -n -d "*"` — **remove it afterwards**, it is very
noisy.

**Measured, same spot/cell:** LTE `Strength` 1 % → **46 %**; GSM 1 → 53–80.
Applying it needs
ofono restarted; do it in boot order or the modem stack gets confused:

    sudo systemctl stop ModemManager.service
    sudo systemctl restart ofono.service
    sudo /usr/local/bin/r7-wait-ofono-sim.sh
    sudo systemctl start ModemManager.service

Stock file backed up to `/etc/ofono/binder.conf.orig`. This lives in the
rootfs LV → re-apply after a rootfs reflash.

## Related, apparently downstream: rild SINR-thread CPU spin / low signal%
While chasing the above, also found `rild`'s `SINR` thread stuck in an
unthrottled `ppoll()`+`read()` loop (~7,700 iterations/sec, confirmed via
`strace -c -f -p <rild>`) on `/dev/drb` inside the Android container.
`/dev/drb` is a **static 16-byte regular file** (not a real char device —
`stat` shows `regular file`, content never changes), and `poll()` on a plain
file always reports `POLLIN` immediately per POSIX semantics, so the thread
never blocks — it just spins, eating ~100% of one CPU core continuously.
This was observed on a session where the 5G/NR retry storm above had already
been running for ~6.5 hours before being fixed mid-session, and `Strength`
was stuck at ~1% the whole time.

**Update (same sesi-21, later):** after a full reboot with this unit
installed (so the 4G-only restriction applies early, before any retry storm
can start), `rild` came up **idle** (0.0% CPU, ~136 syscalls in 3s vs. ~77,000
in 5s before) and `Strength` settled at a real, stable, non-decaying value
(7%, not the 80%+ you'd expect in a strong-coverage area, but no longer
stuck at 1% either). This suggests the SINR-thread spin is not an
unconditional bug — it looks like a downstream consequence of the CP being
stuck negotiating a rejected 5G/NR pref-mode request, not something that
happens regardless. **Re-check after a few days of normal use** (reboots,
Waydroid on/off, screen on/off cycles) to see if it ever recurs on its own;
if it does, the diagnosis above (and the fact that a FIFO swap fixes the
spin but breaks modem power-on elsewhere in the same binary — tested and
reverted, recovery needed a full reboot, `systemctl restart` was not enough)
is still the starting point. Don't retry that FIFO experiment without a
recovery plan.

## Fixed: ofono2mm failed/sim-missing boot race — ROOT CAUSE, ordering fix (sesi-22)
On a fresh boot the modem came up `state: failed, reason: sim-missing`
("SIM not detected" in the UI, no mobile data) even though `ofono` itself saw
the SIM perfectly (`SimManager` `Present=true`, TELKOMSEL, PIN none) — the
ofono modem had simply never been set `Online`.

**Root cause (measured, sesi-22):** on this device `ModemManager.service` *is*
`ofono2mm` — the packaged drop-in `/usr/lib/systemd/system/ModemManager.service.d/10-ofono2mm.conf`
replaces `ExecStart` with `/usr/bin/ofono2mm` (a Python daemon holding the
`org.freedesktop.ModemManager1` bus name). That unit orders itself only
`After=polkit.service`, with **no ordering against `ofono.service`** — so it
probes for modems before ofono is ready. Boot journal:

    10:29:57  Starting ModemManager.service   <- ofono2mm probes here
    10:30:08  Started ofono.service           <- ofono ready 11s TOO LATE
    10:30:12  ofono2mm: [INFO] Modem state: Failed

**Ordering alone is NOT enough.** `After=ofono.service` only waits for ofono to
take its D-Bus name — measured on this device, ofono2mm then starts **7 ms**
later and probes ~4 s in, while ofono still has not enumerated the modem/SIM:

    11:26:43.698  Started ofono.service
    11:26:43.705  Starting ModemManager      <- 7ms later
    11:26:47.862  ofono2mm: Modem state: Failed

**Fix (both pieces required):**
1. `ModemManager-after-ofono.conf` → `/etc/systemd/system/ModemManager.service.d/20-r7-after-ofono.conf`
   (`After=`/`Wants=ofono.service`).
2. `r7-wait-ofono-sim.service` + `.sh` — runs `Before=ModemManager.service` and
   polls `org.ofono.SimManager` until `Present=true`, then releases MM. It does
   **not** touch `Online` (see the rejected approach below).

Verified boot with both in place:

    11:37:01.481  Started ofono.service
    11:37:07      r7-wait-ofono-sim: SIM present after 6s; releasing ModemManager
    11:37:07.632  Starting ModemManager
    11:37:08.130  ofono2mm: Modem state: Disabled     <- not Failed
    11:37:08.145  Started ModemManager                <- 0.5s
    11:37:08.174  ofono2mm: Modem state: Enabled

### Rejected: pre-setting ofono Online before ModemManager (do not reintroduce)
A `r7-ofono-online.service` that ran `Before=ModemManager.service` and set
`org.ofono.Modem Online=true` was tried and **removed — it breaks ofono2mm**.
With the modem already online, ofono2mm never completes its own enable path,
never takes the `org.freedesktop.ModemManager1` bus name, and systemd kills it:

    ModemManager.service: start operation timed out. Terminating.
    ModemManager.service: Failed with result 'timeout'

Measured: with the unit enabled, ofono2mm exceeded the 90 s start timeout and
looped forever; with it disabled (and ofono `Online=false`), `systemctl start
ModemManager` completed in **1 second**. Let ofono2mm own the Online property.

**Knock-on effect worth knowing:** while ModemManager is stuck in that restart
loop the 4G restriction never gets applied, so `rild` enters the SINR spin
described below (~86 % of one core) and the phone gets noticeably hot — 71 °C
on both CPU clusters within ~30 min. The spin does *not* stop when the
restriction is applied late; it only stays away when the restriction lands
early in boot, so recovery is a reboot.

### Do NOT restart ModemManager to recover this
The first sesi-22 attempt fixed the symptom by restarting `ModemManager.service`
from `r7-modem-restrict-4g.sh`. **That made things worse and is now removed.**
Because the unit is `Type=dbus` running Python, a mid-boot restart repeatedly
ended in:

    ModemManager.service: Failed with result 'timeout'
    Failed to start ModemManager.service - Modem Manager

User-visible symptom (reported and confirmed in the journal): GNOME Settings
shows a "failed to start" error and the **Mobile Network panel is missing**;
re-opening the panel later picks it up once MM finally settles. The mode
restriction script now only nudges `ofono` `Online` if it still finds a failed
modem, and never restarts MM.

### Install (all three pieces)
    sudo install -m755 r7-ofono-online.sh /usr/local/bin/
    sudo install -m644 r7-ofono-online.service /etc/systemd/system/
    sudo mkdir -p /etc/systemd/system/ModemManager.service.d
    sudo install -m644 ModemManager-after-ofono.conf \
        /etc/systemd/system/ModemManager.service.d/20-r7-after-ofono.conf
    sudo systemctl daemon-reload && sudo systemctl enable r7-ofono-online.service

Verify with `systemctl show ModemManager.service -p After` — it must list both
`ofono.service` and `r7-ofono-online.service`.
