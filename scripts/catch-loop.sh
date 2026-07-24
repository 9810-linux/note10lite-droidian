#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
LOG="$1"
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 -o LogLevel=ERROR -o PreferredAuthentications=password -o PubkeyAuthentication=no"
echo "catch2 start $(date +%T)" > "$LOG"
end=$((SECONDS+300)); n=0
while [ $SECONDS -lt $end ]; do
  n=$((n+1))
  # minimal fast payload: mask + set target, detached via setsid so it survives ssh drop
  out=$(timeout 5 sshpass -p 1234 ssh $SSHOPTS droidian@10.15.19.82 \
    "echo GOT_\$(cut -d' ' -f1 /proc/uptime); printf '1234\n' | sudo -S -p '' setsid sh -c 'systemctl mask lxc@android.service lxc-net.service; systemctl set-default multi-user.target; touch /run/CAUGHT' >/dev/null 2>&1; echo SENT" 2>&1)
  if echo "$out" | grep -q GOT_; then
     echo "[$n $(date +%T)] $out" | tee -a "$LOG"
     if echo "$out" | grep -q SENT; then echo ">>> MASK SENT, breaking loop <<<" | tee -a "$LOG"; fi
  fi
  # detect stable state: if we can connect AND /run/CAUGHT exists AND uptime keeps growing -> stable
  if echo "$out" | grep -q GOT_; then
     up=$(echo "$out" | grep -o 'GOT_[0-9.]*' | head -1 | cut -d_ -f2)
     # if uptime > 60 the reboot loop is broken
     if awk "BEGIN{exit !($up>60)}"; then echo "=== STABLE (uptime $up > 60s) — loop broken ===" | tee -a "$LOG"; break; fi
  fi
done
echo "catch2 end $(date +%T) attempts=$n" >> "$LOG"
