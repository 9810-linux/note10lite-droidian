# r7 Bluetooth bring-up (matches crownlte)

## Root cause (sesi-17)
The r7 kernel had `CONFIG_BT_HCIVHCI` (+ HCIUART/RFCOMM/HIDP/BNEP) **off**, so
`/dev/vhci` never existed and `bluebinder` could not bridge the Android BT HAL
(`android.hardware.bluetooth@1.0`, which DOES run, PID-registered IBluetoothHci)
into a BlueZ `hci0`. The sesi-15 `af_bluetooth.c:69` "panic" was the missing-vhci
error path, NOT a real kernel bug — crownlte runs the identical `af_bluetooth.c`.

## Fix
1. **Kernel** (in git, commit 6c70665b2): enable in `exynos9810-r7_droidian_defconfig`
   `CONFIG_BT_HCIVHCI=y` `CONFIG_BT_HCIUART=y` `CONFIG_BT_HCIUART_H4=y`
   `CONFIG_BT_RFCOMM=y` `CONFIG_BT_RFCOMM_TTY=y` `CONFIG_BT_HIDP=y`
   `CONFIG_BT_BNEP=y` (+MC/PROTO filters). Rebuild + reflash BOOT.
2. **Userspace** (these files): `systemctl unmask bluebinder.service bluetooth.service`
   then enable them; `droid-get-bt-address` seeds the MAC from EFS; the bluebinder
   drop-in unblocks rfkill + settles 2s before grabbing the HAL.

## Install (after new kernel flashed)
    sudo cp droid-get-bt-address.sh /usr/bin/droid/ && sudo chmod +x /usr/bin/droid/droid-get-bt-address.sh
    sudo cp droid-get-bt-address.service /etc/systemd/system/
    sudo mkdir -p /etc/systemd/system/bluebinder.service.d
    sudo cp bluebinder.service.d/10-sleep.conf /etc/systemd/system/bluebinder.service.d/
    sudo systemctl unmask bluebinder.service bluetooth.service
    sudo systemctl daemon-reload
    # TEST first (do NOT enable until proven no-panic):
    sudo systemctl start bluebinder.service      # should create hci0 via /dev/vhci
    sudo systemctl start bluetooth.service
    bluetoothctl show ; bluetoothctl scan on
    # only after confirmed stable:
    sudo systemctl enable bluebinder.service bluetooth.service droid-get-bt-address.service
