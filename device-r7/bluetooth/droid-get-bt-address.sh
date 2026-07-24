#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# exynos9810: BT address lives in /mnt/vendor/efs/bluetooth/bt_addr; BlueZ reads
# /var/lib/bluetooth/board-address. Without it, hci0 comes up with a random/zero
# MAC. (Verbatim from sexynos adaptation-exynos9810.)
if [ -f "/mnt/vendor/efs/bluetooth/bt_addr" ]; then
    echo $(cat /mnt/vendor/efs/bluetooth/bt_addr) > /var/lib/bluetooth/board-address
else
    touch /var/lib/bluetooth/board-address
fi
