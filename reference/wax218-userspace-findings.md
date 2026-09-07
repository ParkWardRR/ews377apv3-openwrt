# WAX218 userspace defaults — mined from the mainline rootfs (for the EWS377 port)

Findings pulled from the OpenWrt `25.12.2` `netgear_wax218-squashfs-factory.ubi` rootfs
squashfs (read on the Mac mini with `PySquashfsImage`). Each is a template for the
matching EWS377AP v3 board file, since both are the `ap-hk07` board. Committed one
finding at a time.

## Finding 1 — network: single `lan`, DHCP client (dumb-AP default)

`/etc/board.d/02_network`:
```
netgear,wax218|\
netgear,wax620)
	ucidef_set_interface_lan "lan" "dhcp"
	;;
```
The WAX218 ships as a **single-port dumb AP**: one `lan` interface, `proto dhcp` (it
pulls its management address from upstream, not a static `192.168.1.1`). Radio mapping
is **phy0 = 5 GHz, phy1 = 2.4 GHz** (confirmed by the LED triggers, Finding 2).

**For the EWS377AP v3** (also one 2.5 GbE port, also an AP): the same
`ucidef_set_interface_lan "lan" "dhcp"` is the correct default. If you prefer a
predictable first-boot address for setup, override to a static lan — but the upstream
AP-style default is DHCP-client on the single `lan`.

## Finding 2 — LED default triggers

`/etc/board.d/01_leds`:
```
netgear,wax218)
	ucidef_set_led_netdev "lan"    "LAN"         "blue:lan"     "lan"
	ucidef_set_led_wlan   "wlan5g" "WIFI 5GHz"   "blue:wlan5g"  "phy0radio"
	ucidef_set_led_wlan   "wlan2g" "WIFI 2.4GHz" "blue:wlan2g"  "phy1radio"
	;;
```
Three functional triggers: the `lan` LED follows the netdev, and the two `wlanNg` LEDs
follow their radios (`phy0radio` = 5 GHz, `phy1radio` = 2.4 GHz — matching Finding 1).
The `power` LED gets no trigger (on = powered). WAX218 LED sysfs names are
`blue:lan|wlan5g|wlan2g` because its LEDs hang off the `fairchild,74hc595` shift register.

**For the EWS377AP v3** the *trigger pattern* ports directly, but the **LED names differ**:
the EWS377 has an **RGB status LED on SoC GPIO 54/55/56** (e.g. `red:status` / `green:status`
/ `blue:status`), not per-function `blue:*` LEDs. So reuse the `ucidef_set_led_netdev`
(lan) + `ucidef_set_led_wlan` (phy0radio/phy1radio) structure, but point them at the
EWS377's actual `gpio-leds` names, and keep phy0=5G / phy1=2.4G.

## Finding 3 — ath11k caldata comes straight from ART, MAC included

`/etc/hotplug.d/firmware/11-ath11k-caldata`:
```
"ath11k/IPQ8074/hw2.0/cal-ahb-c000000.wifi.bin")
	case "$board" in
	... netgear,wax218| ... )
		caldata_extract "0:art" 0x1000 0x20000
		;;
```
The WAX218 does a **plain `caldata_extract "0:art" 0x1000 0x20000`** and **no
`ath11k_patch_mac`** — i.e. it trusts the per-radio MACs already embedded in the ART
caldata (offset `0x1000`, length `0x20000` = 128 KiB) rather than deriving them from a
label MAC. This is the simplest of all the family variants in that script (many NETGEAR/
Linksys boards patch MACs from a label).

**For the EWS377AP v3** this is the model to copy — the repo already establishes that
ath11k caldata lives in **ART (mtd11)**. Two portability notes:
- **Partition-label case:** WAX218 uses lowercase `"0:art"`; the EWS377 live `mtdparts`
  shows the label as **`0:ART`** (see `docs/hardware-reference.md`). `caldata_extract`
  matches the label literally, so the EWS377 script must use the exact case its SMEM
  table exposes — verify on hardware before assuming `0:art`.
- **MAC handling:** start with the WAX218's no-patch approach (`caldata_extract` only). If
  the EWS377's radios come up with a wrong/duplicate MAC, add `ath11k_patch_mac` from the
  ART/label MAC like the `netgear,wax620`/`wax630` cases do — but only if hardware shows
  it's needed.

## Finding 4 — first-boot config can be preseeded from u-boot env

`/etc/board.d/05_fw_defaults`:
```
fw_loadenv
...
[ -f /var/run/uboot-env/owrt_ssid -a -f /var/run/uboot-env/owrt_wifi_key ] &&
	ucidef_set_wireless all "$(cat .../owrt_ssid)" sae-mixed "$(cat .../owrt_wifi_key)"
[ -f .../owrt_country ]              && ucidef_set_country              "$(cat .../owrt_country)"
[ -f .../owrt_ssh_auth_key ]         && ucidef_set_ssh_authorized_key   "$(cat .../owrt_ssh_auth_key)"
[ -f .../owrt_root_password_plain ]  && ucidef_set_root_password_plain  "$(cat .../owrt_root_password_plain)"
[ -f .../owrt_root_password_hash ]   && ucidef_set_root_password_hash   "$(cat .../owrt_root_password_hash)"
[ -f .../owrt_timezone ]             && ucidef_set_timezone             "$(cat .../owrt_timezone)"
```
The WAX218 lets you **pre-provision first-boot state from u-boot env variables**
(`owrt_ssid`, `owrt_wifi_key` → WPA2/3 `sae-mixed`, `owrt_country`, `owrt_ssh_auth_key`,
`owrt_root_password_plain|hash`, `owrt_timezone`). Set them with `fw_setenv owrt_ssid …`
before first boot and OpenWrt comes up already configured — handy for fleet provisioning.

**For the EWS377AP v3** this works identically (same u-boot, same env partition — see
Finding 5), so a copied `05_fw_defaults` gives EnGenius units the same zero-touch
provisioning. It also closes the "SSH is open with no password on first boot" gap in the
install guide: seed `owrt_root_password_hash` (or `owrt_ssh_auth_key`) via `fw_setenv`
and the AP is never passwordless.
</content>
