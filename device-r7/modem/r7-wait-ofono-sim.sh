#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# r7: hold ModemManager (= ofono2mm) until oFono has actually read the SIM.
#
# "Started ofono.service" only means ofono took its D-Bus name — on this device
# ofono2mm gets started ~7ms later and probes ~4s in, while ofono has not yet
# enumerated the modem/SIM, so ofono2mm latches "Modem state: Failed" /
# sim-missing forever ("SIM not detected" in the UI). See README.md.
#
# This waits for org.ofono.SimManager to report Present=true and then gets out
# of the way. It deliberately does NOT touch the Online property: leaving the
# modem offline is what lets ofono2mm run its own enable path (measured: MM
# starts in ~1s with Online=false vs ~70s with Online=true, and the latter
# routinely blows systemd's 90s start timeout).

MODEM=/ril_0
DEADLINE=60

i=0
while [ $i -lt $DEADLINE ]; do
    if busctl call org.ofono "$MODEM" org.ofono.SimManager GetProperties 2>/dev/null \
            | grep -q '"Present" b true'; then
        echo "r7-wait-ofono-sim: SIM present after ${i}s; releasing ModemManager"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done

echo "r7-wait-ofono-sim: SIM not seen within ${DEADLINE}s; starting ModemManager anyway" >&2
exit 0
