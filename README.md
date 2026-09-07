# EnGenius EWS377AP v3 → OpenWrt

The canonical home for running **mainline-style OpenWrt** on the EnGenius
**EWS377AP v3** (Qualcomm **IPQ8072A**, board `ap-hk07`) — a 4×4 Wi-Fi 6 access
point with a 2.5 GbE uplink. Built on the community **NSS-EDMA** OpenWrt tree
(Qualcomm NSS hardware offload on top of the upstream `qca_edma`/`qca_ppe` stack),
kernel 6.18.

> ## ✅ Status: validated on hardware
> OpenWrt boots and runs **persistently from NAND** on a real unit: `bootipq` →
> FIT `config@hk07` → kernel → UBI root mount → squashfs + `rootfs_data` overlay →
> shell, surviving real reboots. **Ethernet**, **both Wi-Fi radios (WPA2)**, and
> **config persistence** confirmed. Secure boot is **not fused** (custom images
> boot). Unofficial / community; prerelease.

## ⬇️ Downloads

Firmware images + `SHA256SUMS`: **[Releases](https://github.com/ParkWardRR/ews377apv3-openwrt/releases)** (tag `v0.1`).

| File | Use | Status |
| --- | --- | --- |
| `…-squashfs-factory.ubi` | UART + u-boot `nand write` to slot 0 | ✅ **hardware-proven** |
| `…-initramfs-uImage.itb` | RAM boot (dry-run / recovery, nothing written) | ✅ proven |
| `…-squashfs-sysupgrade.bin` | upgrades once on OpenWrt | standard |
| `…-web-ui-factory.bin` | OEM web/LuCI updater (one-click) | 🧪 see status ↓ |
| `…-squashfs-qsdk-factory.itb` | OEM CLI updater | 🧪 see status ↓ |

<!-- METHOD-B-STATUS: pending -->
> 🧪 **One-click web-upload status: NOT YET CONFIRMED on hardware.** The
> `web-ui-factory.bin` / `qsdk-factory.itb` images are built and match the vendor
> format, but haven't been validated on a real unit yet — treat them as experimental
> and only use them with a serial cable ready to recover. **The UART/u-boot install
> (`factory.ubi`) is fully proven.** (This one line flips to ✅/❌ once tested.)

**New here?** The **[install & back-to-stock guide](docs/install-and-restore.md)** is
written for both first-timers and power users — pick the reliable (serial), SSH
(`ubiformat`, no cable — borrowed from the WAX218), or easy (web) path, with every
command and what-you-should-see spelled out.

## ⚠️ Before you flash
- **You can brick your AP.** Unofficial; overwrites the OEM firmware (single-slot).
- **Only the UART/u-boot install is hardware-proven.** The web-upload `.bin` is
  experimental — only try it with UART recovery on hand.
- **Back up your own NAND first** (your MAC + radio calibration are unique).
- **Never write the ART partition or the bootloader region (`0x0`–`0x1000000`).**
- Verify `SHA256SUMS` before flashing.

## The two board-specific fixes that made it boot
Generic `qualcommax`/`ipq807x` OpenWrt needed exactly two adjustments for the stock
EnGenius u-boot:
1. **FIT config named `config@hk07`** — OEM `bootipq` selects the FIT config by
   board name and aborts ("Config not availabale") otherwise
   (`DEVICE_DTS_CONFIG := config@hk07`). This is **not guesswork**: the officially
   supported ap-hk07 sibling `netgear_wax218` ships the *identical* `config@hk07` in its
   mainline image (verified by string-inspecting the upstream `25.12.2` build) — same
   reference board, same bootloader contract. See
   [docs/wax218-equivalence.md](docs/wax218-equivalence.md).
2. **Install to slot 0** — OpenWrt's root-mount always targets the SMEM/DTS
   partition labeled `rootfs` (slot 0, `0x1000000`), regardless of which A/B slot the
   bootloader loaded from — so OpenWrt must live on slot 0.

## Hardware at a glance
- **SoC:** Qualcomm IPQ8072A (quad Cortex-A53), 1 GiB RAM (confirmed live; some
  variants report 512 MB), 256 MB NAND. **Same `ap-hk07` reference board** as the
  ECW230v3, EWS377-FIT, and the **officially-supported NETGEAR WAX218 v1** — see
  [docs/wax218-equivalence.md](docs/wax218-equivalence.md).
- **Wi-Fi:** 4×4 802.11ax dual-band (ath11k), caldata from ART.
- **Ethernet:** single 2.5 GbE `lan` uplink (QCA8081 @ MDIO 28, `2500base-x` via
  uniphy2); `eth0` is the internal CPU conduit.
- **LEDs:** RGB status on GPIO 54/55/56. **Reset:** GPIO 52. **UART:** header **J2**, 115200 8N1.
- **Boot:** QCA u-boot 2.0.0, `bootcmd=bootipq`, dual A/B slots (`active_fw`).

## Source & related
- **Source / build:** fork branch `ews377ap-v3` of
  [`openwrt-nss-edma`](https://github.com/ParkWardRR/openwrt-nss-edma) — full
  engineering write-up in `PORT-STATUS-ews377ap-v3.md`.
- **Flashing tool + guide mirror:** [`pelegrun-ap-hk07-firmware-tools`](https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools).
- **EnGenius background (controllers, cross-flashing, firmware format):** [`engenius-field-guide`](https://github.com/ParkWardRR/engenius-field-guide).

## Documents
| File | Purpose |
| --- | --- |
| [docs/install-and-restore.md](docs/install-and-restore.md) | Install OpenWrt + restore to stock (serial / SSH / web paths) |
| [docs/wax218-equivalence.md](docs/wax218-equivalence.md) | Same board as the official OpenWrt NETGEAR WAX218 — shared/differing traits + borrowed SSH install method |
| [docs/hardware-reference.md](docs/hardware-reference.md) | MTD map, boot chain, u-boot env, recovery |
| [docs/openwrt-porting-plan.md](docs/openwrt-porting-plan.md) | End-to-end port plan (with outcomes) |
| [docs/uart-extraction-plan.md](docs/uart-extraction-plan.md) | UART data extraction method |
| [docs/research-notes.md](docs/research-notes.md) | Community findings / secure-boot priors |
| [reference/](reference/) | Decompiled OEM device trees + Wi-Fi board data |

## Safety / recovery ground rules
- **Back up before touching flash:** the OS slot(s), env, and especially **ART**
  (calibration + MAC; corruption = real brick) — keep the dumps off-device.
- Keep a byte-exact OEM backup so you can always restore stock.
- Never hand-rebuild a partial u-boot env — a *valid-but-incomplete* env bricks worse
  than an erased one.
- Because secure boot is unfused, UART + TFTP always recover the OS as long as ART and
  the bootloader are intact.

## Scope
Unofficial community work for interoperability and self-hosting on hardware you own.
"EnGenius"/"Senao" are trademarks of their owners; no affiliation or endorsement. No
vendor firmware is redistributed here. No warranty — use at your own risk.
