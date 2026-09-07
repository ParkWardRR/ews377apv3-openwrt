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
</content>
