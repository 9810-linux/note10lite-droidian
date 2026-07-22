#!/bin/sh
# r7: restrict cellular modem to 2G/3G/4G (no 5G/NR). See README.md.
#
# NOTE: this script deliberately does NOT restart ModemManager. An earlier
# version did that to recover the failed/sim-missing boot race, but on this
# device ModemManager.service *is* ofono2mm (Type=dbus, python) and restarting
# it mid-boot regularly ends in "Failed with result 'timeout'" — which shows up
# as GNOME Settings losing its Mobile Network panel until you re-open it.
# The race is fixed properly by ordering instead: see r7-ofono-online.service
# and the ModemManager After=ofono.service drop-in.

for i in $(seq 1 30); do
    modem=$(mmcli -L 2>/dev/null | grep -o '/org/freedesktop/ModemManager1/Modem/[0-9]*')
    [ -n "$modem" ] && break
    sleep 1
done
[ -z "$modem" ] && exit 0

state=$(mmcli -m "$modem" -K 2>/dev/null | sed -n 's/^modem\.generic\.state *: *//p')
if [ "$state" = "failed" ]; then
    # Ordering fix did not hold. Nudge ofono directly — ofono2mm picks the
    # state up on its own; do not restart ModemManager (see note above).
    echo "r7-modem-restrict-4g: modem in failed state, nudging ofono online" >&2
    busctl call org.ofono /ril_0 org.ofono.Modem SetProperty sv Online b true 2>/dev/null || true
    sleep 5
fi

mmcli -m "$modem" --set-allowed-modes='4g|3g|2g' --set-preferred-mode='4g'
