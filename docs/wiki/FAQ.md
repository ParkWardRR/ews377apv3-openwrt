# FAQ

## General

### Which model do I have?

Check the label on the bottom/back of the unit. The model name is printed there. If you can access the web UI, it is also shown on the dashboard. All three look physically identical.

- **EWS377AP v3** — says "EWS377AP" on the label, managed via ezMaster
- **ECW230v3** — says "ECW230v3", managed via EnGenius Cloud
- **EWS377-FIT** — says "EWS377-FIT", standalone or FIT controller

### Does it matter which model I have?

Not for this project. All three are the same hardware — same chip, same radios, same Ethernet, same GPIOs. The only difference is a 4-byte product ID in the firmware header that determines which EnGenius management system the stock firmware uses.

OpenWrt does not care about this distinction. The same firmware image runs on all three.

### What about the EWS377AP v1 or v2?

**Not supported.** The v1 uses a non-"A" revision of the IPQ8072 that `ath11k` does not support. Only the **v3** works.

### What about the NETGEAR WAX218?

Same board (`ap-hk07`), same chip (IPQ8072A). The WAX218 v1 is [officially supported by mainline OpenWrt](https://openwrt.org/toh/netgear/wax218). This project is built on the same foundation — same `config@hk07` boot contract, same install method template. See [docs/wax218-equivalence.md](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/wax218-equivalence.md).

## Installation

### Can I flash without a serial cable (UART)?

Yes, two methods exist:

1. **SSH + `ubiformat`** — proven on the sibling WAX218, not yet tested on these EnGenius models. No cable needed.
2. **Web upload** — upload through the stock web interface. The mechanism works but persistence has not been confirmed (see [method-b-findings](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/reference/method-b-findings.md)).

That said, **having a serial adapter is strongly recommended** as a safety net for your first flash. A 3.3V USB-to-TTL adapter costs under $5.

### Can I go back to stock firmware?

Yes. The [install & back-to-stock guide](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/install-and-restore.md) covers restoration. You need the NAND backup you made before flashing (you did make one, right?).

### SSH is on port 8822?

Yes. EnGenius stock firmware runs SSH on port **8822**, not the standard 22. You also need legacy key exchange:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -p 8822 root@<IP>
```

### My AP is managed by ezMaster / EnGenius Cloud — can I still flash?

Units adopted by a controller may have SSH disabled. You may need to un-adopt the unit first via the controller, or use the web/telnet interface. See the [EnGenius Field Guide](https://github.com/ParkWardRR/engenius-field-guide) for details on controller management.

### What is the cross-flash tool (Pelegrún)?

[Pelegrún](https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools) is a companion toolkit that handles converting between the three EnGenius management modes (EWS ↔ Cloud ↔ FIT) by rewriting the firmware header. It also handles serial number provisioning and bootloader safety. Useful if you bought an ECW230v3 but want to run it standalone, or vice versa.

## Technical

### What is NSS hardware offload?

The IPQ8072A has a dedicated networking processor (NSS) that handles packet forwarding in hardware. This means NAT, routing, bridge forwarding, PPPoE, and even Wi-Fi-to-wire forwarding happen without loading the main CPU. The result is near-line-rate throughput at minimal CPU usage.

### What kernel version?

Linux 6.18. This is an NSS-EDMA fork — see [openwrt-nss-edma](https://github.com/ParkWardRR/openwrt-nss-edma).

### Is this mainline OpenWrt?

No. This is built on a community fork that adds Qualcomm NSS hardware offload. The goal is to eventually upstream the board support to mainline OpenWrt (see the [upstreaming plan](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/ROADMAP.md)), but that requires stripping the NSS-specific patches and more hardware validation.

### Are both Wi-Fi bands working?

Yes — 2.4 GHz and 5 GHz, both 4×4 MIMO, confirmed on a real EWS377AP v3. The generic `board-2.bin` calibration data works with `ath11k`. DFS is certified.

### How fast is the 2.5G Ethernet?

The QCA8081 PHY negotiates up to 2500 Mbps with a compatible switch. The actual throughput under OpenWrt with NSS offload has not been formally benchmarked — this is one of the things we want community testers to report.

## Troubleshooting

### AP booted but I get a different IP than expected

If the u-boot env was accidentally wiped, the MAC address falls back to a default (`00:03:7f:12:3e:87`), which means DHCP assigns a different IP. Check your DHCP server's lease table. This is not a brick — the AP is running, just on a different address.

### Wi-Fi radios don't appear in LuCI

Check that `ath11k` loaded: `dmesg | grep ath11k`. If it did not load, check that the `kmod-ath11k-ahb` package is installed and the caldata extraction from ART worked (`ls /lib/firmware/ath11k/`).

### How do I report a bug?

[Open an issue](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/issues/new). Include:
- Model (EWS377AP v3 / ECW230v3 / EWS377-FIT)
- Firmware version (from the release tag)
- Install method
- `ubus call system board` output
- `dmesg` output if relevant
- What you expected vs. what happened
