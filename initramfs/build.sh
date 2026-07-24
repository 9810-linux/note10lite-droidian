#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# build.sh — build the Droidian r7 D0 bring-up initramfs.
#
# /init is freestanding (raw aarch64 syscalls, no libc) because the host's
# aarch64 cross-gcc has no glibc sysroot. Compiles with the bare cross-toolchain.
#
# Produces (all gitignored binaries):
#   initramfs/init                 (static freestanding aarch64 ELF)
#   initramfs/ramdisk.cpio.gz      (gzip cpio initramfs — input to mkbootimg)
#
# This is the D0 probe initramfs, NOT the full Droidian initramfs-tools one.
# The full Halium initramfs (mount userdata rootfs + switch_root to Droidian
# systemd) is the Docker-packaging follow-up (see PROGRESS.md TASK 2.5 note).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${CROSS_COMPILE:-aarch64-linux-gnu-}gcc"

echo "[initramfs] compiling freestanding /init with $CC ..."
"$CC" -nostdlib -ffreestanding -fno-builtin -fno-stack-protector \
      -static -O2 -s -o "$ROOT/initramfs/init" "$ROOT/initramfs/init.c"
file "$ROOT/initramfs/init" | grep -qi aarch64 \
	|| { echo "FAIL: init did not compile to an aarch64 ELF"; file "$ROOT/initramfs/init"; exit 1; }
file "$ROOT/initramfs/init"

echo "[initramfs] building cpio.gz ..."
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"/{dev,proc,sys,tmp}
cp "$ROOT/initramfs/init" "$STAGE/init"
chmod 755 "$STAGE/init"
( cd "$STAGE" && find . -print0 | cpio --null -H newc -o --owner=0:0 2>/dev/null | gzip -9 ) \
	> "$ROOT/initramfs/ramdisk.cpio.gz"

echo "[initramfs] sizes:"
ls -lh "$ROOT/initramfs/init" "$ROOT/initramfs/ramdisk.cpio.gz"
echo "[initramfs] cpio contents:"
gzip -cd "$ROOT/initramfs/ramdisk.cpio.gz" | cpio -tv 2>/dev/null