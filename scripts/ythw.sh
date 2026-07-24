#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
# ythw.sh — HW-decoded YouTube player scaffold for r7 Droidian (sesi-16).
# scp to the phone and run there:  ./ythw.sh <youtube-url> [1080|720|480]
#
# STATUS: SCAFFOLD, NOT FINISHED. The HW DECODE works (Exynos MFC via gst-droid droidvdec,
# H.264/VP9 up to 1080p), but the DISPLAY is DIAGONALLY SKEWED + color-broken because the
# droidvdec ! videoconvert ! waylandsink (SHM) path misreads the gralloc buffer's padded stride,
# and it can't be corrected downstream (capssetter breaks droidvdec's pool). The correct fix is
# the GL/Clapper path (see docs/hw-video-decode.md). Keep this only as a reproducer / to swap in
# a working sink once the GL crash is fixed.
#
# Needs on-device: gstreamer1.0-droid, gstreamer1.0-tools, gstreamer1.0-plugins-base-apps, yt-dlp.
# Session env: droidian UID 32011, Wayland socket wayland-0.
set -euo pipefail
URL="${1:-}"; RES="${2:-1080}"
[ -z "$URL" ] && { echo "usage: $0 <youtube-url> [1080|720|480]"; exit 1; }
export XDG_RUNTIME_DIR="/run/user/$(id -u)" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

echo "resolving H.264 <=${RES}p (droidvdec HW-decodes H264 cleanly; VP9->videoconvert crashes)..."
STREAM=$(yt-dlp -f "bestvideo[height<=$RES][vcodec^=avc1][fps<=30]/bestvideo[height<=$RES][vcodec^=avc1]/best[height<=$RES][ext=mp4]" -g "$URL" 2>/dev/null | head -1)
[ -z "$STREAM" ] && { echo "could not resolve an H.264 stream"; exit 2; }

# 1080 pads 1080->1088 (16-align) => crop 8 green rows. 720/480 are 16-aligned already.
CROP=""; [ "$RES" = "1080" ] && CROP="videocrop bottom=8 !"

echo "playing fullscreen (HW decode; expect SKEW until GL path fixed). Ctrl-C to stop."
exec gst-launch-1.0 souphttpsrc location="$STREAM" ! qtdemux ! h264parse ! droidvdec ! \
  videoconvert ! $CROP waylandsink fullscreen=true
