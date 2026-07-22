# r7 app fixes — Python GTK4 apps crash on the GL renderer (sesi-22)

## Symptom
Portfolio (the preinstalled file manager, `portfolio-filemanager` deb) crashes
instantly on launch with an error dialog. Captured over SSH:

    Fatal Python error: _PyThreadState_Attach: non-NULL old thread state

## Root cause (device-level, NOT a Portfolio bug)
Reproduced with a minimal PyGObject/GTK4 probe: **any Python GTK4/libadwaita
app crashes the moment it creates a window** on this device. The crash is in
GTK4's GL renderer path: GL context creation goes through **libhybris EGL**
(Android blob), and a hybris-side thread ends up re-entering CPython (via
gi's GLib log-writer hook) with a corrupted/duplicate thread state →
`_PyThreadState_Attach` fatal error + SIGSEGV. Versions are NOT the issue
(Python 3.13.12 + python3-gi 3.56.2 are mutually compatible upstream).

With `GSK_RENDERER=cairo` (software rendering, no GL context) the same probe
and Portfolio itself run fine. C GTK4 apps (Settings, gnome-software,
Clapper) are unaffected — no Python interpreter to corrupt — which is why
only Python apps hit this.

## Fix (workaround level)
Per-app desktop-file override forcing the cairo renderer — do NOT set
`GSK_RENDERER=cairo` globally, it would drop GPU rendering for all GTK4 apps
that work fine on GL:

    cp dev.tchx84.Portfolio.desktop ~/.local/share/applications/

(`Exec=env GSK_RENDERER=cairo dev.tchx84.Portfolio %f` — rest identical to
the stock desktop file. The `~/.local` override survives package upgrades.)

Cairo rendering is perfectly adequate for a file manager at phone
resolution. Apply the same pattern to any other Python GTK4 app that shows
the same instant-crash (probe first with `GSK_RENDERER=cairo <app>` over
SSH with the session env).

## Proper fix (open)
The real bug is in the libhybris EGL ↔ CPython TLS interaction (or gi's log
writer being invoked on a bionic thread). Upstream-able investigation:
run the probe under gdb, find which hybris thread calls back into Python,
and either fix libhybris TLS setup for bionic threads or make pygobject's
log writer refuse threads it didn't see before. Parked — workaround is fine
for daily use.
