#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Zulfikar Aji Kusworo (zakusworo) <greataji13@gmail.com>
"""Minimal scripted telnet client for the Halium initramfs busybox telnetd."""
import socket, sys, time

HOST, PORT = "192.168.2.15", 23
IAC, DONT, DO, WONT, WILL = 255, 254, 253, 252, 251

def negotiate(sock, data, out):
    i = 0
    while i < len(data):
        if data[i] == IAC and i + 2 < len(data):
            verb, opt = data[i+1], data[i+2]
            if verb == DO:
                sock.sendall(bytes([IAC, WONT, opt]))
            elif verb == WILL:
                sock.sendall(bytes([IAC, DONT, opt]))
            i += 3
        elif data[i] == IAC and i + 1 < len(data) and data[i+1] in (DO, DONT, WILL, WONT):
            i += 2
        else:
            out.append(data[i]); i += 1

def run(cmd, timeout=25):
    s = socket.create_connection((HOST, PORT), timeout=10)
    s.settimeout(2)
    out = bytearray()
    # drain banner + negotiate
    t0 = time.time()
    while time.time() - t0 < 3:
        try:
            d = s.recv(4096)
            if not d: break
            negotiate(s, d, out)
        except socket.timeout:
            break
    marker = "ZZDONEZZ"
    s.sendall((cmd + f'; echo "{marker}$?"\n').encode())
    out = bytearray()
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            d = s.recv(65536)
            if not d: break
            negotiate(s, d, out)
            if marker.encode() in bytes(out).replace(b"\r", b""):
                # make sure marker isn't just the echoed command
                txt = bytes(out).decode(errors="replace")
                lines = [l for l in txt.replace("\r", "").split("\n")]
                for l in lines:
                    if l.startswith(marker) and not l.startswith(marker + "$?"):
                        s.close()
                        # print everything except echoed cmd line and marker
                        for o in lines:
                            if marker in o or (cmd[:40] in o and "echo" in o):
                                continue
                            print(o)
                        print(f"[exit={l[len(marker):]}]")
                        return
        except socket.timeout:
            continue
    s.close()
    print(bytes(out).decode(errors="replace"))
    print("[timeout]")

if __name__ == "__main__":
    run(" ".join(sys.argv[1:]))
