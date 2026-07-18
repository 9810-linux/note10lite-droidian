# Display / notch layout (sesi-20)

Phosh "avoid notches" (`sm.puri.phosh shell-layout=device`) needs gmobile panel
data for this device; none exists upstream (DT compatibles are generic:
`samsung,armv8`, `samsung,exynos9810`).

- `samsung,exynos9810.json` — gmobile display-panel description (1080x2400,
  centered punch-hole approximated at cx=540 cy=60 r=50). Installed to
  `/usr/share/gmobile/devices/display-panels/` **as both**
  `samsung,exynos9810.json` and `samsung,armv8.json` (gmobile tries the first
  DT compatible first).
- `gmobile-panel.conf` — systemd drop-in for `phosh.service`
  (`/etc/systemd/system/phosh.service.d/`): gmobile ships panels inside the
  library's GResource, so we inject ours via `G_RESOURCE_OVERLAYS`.
  ⚠ Resource prefix is `/org/gnome/gmobile/...` in this gmobile build (0.4.x)
  — the phosh.mobi notch-support blog's `/mobi/phosh/gmobile/...` prefix is
  outdated (found via `grep -a` on libgmobile.so).

Result: clock moves left of the punch-hole. Upstreamable: submit the JSON to
gmobile once measured precisely.
