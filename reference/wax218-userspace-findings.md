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
</content>
