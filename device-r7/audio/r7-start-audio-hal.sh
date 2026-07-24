#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# r7: start the 32-bit vendor.audio-hal in the Android container so it registers
# android.hardware.audio@5.0::IDevicesFactory/default. Init does NOT start it on
# its own: stock /vendor/etc/init/android.hardware.audio.service.rc has no
# `interface` lines, so on-demand ctl.interface_start can't map to the service,
# and `class hal` skips it. Without this, pulseaudio module-droid-hidl loops
# "Could not find ...IDevicesFactory" -> times out -> restart-loops, no sinks.
# Pairs with the 64-bit HIDL-compat shim in android-mount.service.d/30-audio-hidl.conf.
# NOTE: must use an absolute shell + explicit PATH; from systemd's env, bare `sh`
# is not resolvable inside the lxc-attach container context.
exec lxc-attach -n android -- /system/bin/sh -c '
  export PATH=/system/bin:/system/xbin:/vendor/bin:/vendor/xbin
  IFACE="audio@5.0::IDevicesFactory/default"
  i=0; while [ $i -lt 60 ]; do
    [ "$(getprop init.svc.hwservicemanager 2>/dev/null)" = "running" ] && break
    i=$((i+1)); sleep 1
  done
  if lshal 2>/dev/null | grep -q "$IFACE"; then
    echo "audio HAL already registered"; exit 0
  fi
  setsid /vendor/bin/hw/android.hardware.audio.service >/dev/null 2>&1 </dev/null &
  i=0; while [ $i -lt 20 ]; do
    if lshal 2>/dev/null | grep "$IFACE" | grep -qE "[0-9][0-9][0-9]"; then
      echo "audio HAL registered"; exit 0
    fi
    i=$((i+1)); sleep 1
  done
  echo "audio HAL start attempted (verify: lshal | grep IDevicesFactory)"; exit 0
'
