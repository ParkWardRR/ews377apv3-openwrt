# Install OpenWrt on the EWS377AP v3 — and restore to stock

Community/unofficial OpenWrt for the EnGenius **EWS377AP v3** (`ap-hk07`, Qualcomm
IPQ8072A). Validated on hardware: persistent NAND boot, Ethernet, WiFi (WPA2), config
survives reboots.

> **Downloads:** [Releases](https://github.com/ParkWardRR/ews377apv3-openwrt/releases)
> (tag `v0.1`). Verify `SHA256SUMS` before flashing.

## ⚠️ Read this first
- **You can brick your AP.** Unofficial; overwrites the OEM firmware.
- **Only the UART + u-boot method (Method A) is hardware-proven.** The web-upload
  `.bin` (Method B) and QSDK FIT (Method C) match the OEM format but are
  **community-untested** — only try them with UART recovery on hand.
- **Single-slot install:** OpenWrt lands on slot 0; there is **no on-device OEM
  fallback** afterward. **Back up your own NAND first** (Part 1) — your MAC and radio
  calibration are unique; never reuse someone else's dump.
- **Never erase or write the ART partition or the region below `0x1000000`.** Losing
  ART is a true brick.
- Secure boot was **unfused** on the test unit. If yours is fused, custom images
  won't boot and you'd restore OEM.

## Images
| File | Purpose | Status |
|---|---|---|
| `…-squashfs-factory.ubi` | bare UBI — Method A (`nand write` to slot 0) | ✅ proven |
| `…-initramfs-uImage.itb` | RAM boot (dry-run / recovery, nothing written) | ✅ proven |
| `…-squashfs-sysupgrade.bin` | upgrades once on OpenWrt | standard |
| `…-web-ui-factory.bin` | OEM web/LuCI updater (Method B) | ⚠️ untested |
| `…-squashfs-qsdk-factory.itb` | OEM CLI updater (Method C) | ⚠️ untested |

## Partition map (256 MiB NAND)
| Region | Offset | Size | Note |
|---|---|---|---|
| bootloader / config / **ART** | `0x0`–`0x1000000` | 16 MiB | **never touch** |
| `rootfs` (slot 0) | `0x1000000` | 111 MiB | ← OpenWrt goes here |
| `0:wififw` | `0x7f00000` | 9 MiB | leave as-is |
| `rootfs_1` (slot 1) | `0x8800000` | 111 MiB | OEM A/B slot (unused by OpenWrt) |
| `0:wififw_1` | `0xf700000` | 9 MiB | leave as-is |

Slot chosen by u-boot `active_fw` (`0` = slot 0).

## Prerequisites
- USB-TTL serial adapter (**3.3V**) on the console header **J2**, **115200 8N1**.
- A TFTP server reachable from the AP over LAN.
- Downloaded images, checksums verified.

---

## Part 1 — Back up YOUR device first (do not skip)
Interrupt u-boot, then dump each OS/critical partition to TFTP and keep the files safe:
```
setenv ipaddr <ap-ip> ; setenv serverip <tftp-ip> ; ping $serverip
nand read 0x44000000 0x1000000 0x6f00000 ; tftpput 0x44000000 0x6f00000 oem-rootfs.bin
nand read 0x44000000 0x8800000 0x6f00000 ; tftpput 0x44000000 0x6f00000 oem-rootfs_1.bin
nand read 0x44000000 0x7f00000 0x900000  ; tftpput 0x44000000 0x900000  oem-wififw.bin
```
Also save your `printenv` output (esp. `ethaddr` and any serial fields). These are
your only rollback once slot 0 is overwritten.

## Part 2 — Install OpenWrt (Method A, proven)
Optional dry run (RAM only, nothing written): `tftpboot 0x44000000 …-initramfs-uImage.itb ; bootm 0x44000000`, look around, power-cycle back.

Flash to slot 0:
```
setenv ipaddr <ap-ip> ; setenv serverip <tftp-ip> ; ping $serverip
tftpboot 0x44000000 openwrt-…-squashfs-factory.ubi
#   $filesize must read 0xe80000 (≈15.2 MB); if not, STOP
nand device 0
nand erase 0x1000000 0x6f00000
nand write 0x44000000 0x1000000 0xe80000
setenv active_fw 0 ; saveenv
reset
```
`nand write` skips the factory bad block; UBI tolerates bad blocks. Boots to
`root@OpenWrt:~#`; LuCI/LAN at `192.168.1.1`.

## Part 3 — OEM web updater (Method B, experimental / untested)
From stock firmware, upload `…-web-ui-factory.bin` via the EnGenius web UI / LuCI
firmware updater. It carries a flash script that erases slot 0 and writes OpenWrt.
**If rejected or interrupted, recover with Method A** — only try with UART on hand,
and please report the result so this can be promoted.

## Part 4 — First boot & upgrades
Set a root password; configure WiFi with WPA2/WPA3 (never leave an open SSID). Later
upgrades stay on OpenWrt: `sysupgrade -n openwrt-…-squashfs-sysupgrade.bin`.

---

## Part 5 — Restore to stock EnGenius firmware
**Route 1 — from your Part 1 backup (most reliable):**
```
setenv ipaddr <ap-ip> ; setenv serverip <tftp-ip> ; ping $serverip
tftpboot 0x44000000 oem-rootfs.bin
nand device 0
nand erase 0x1000000 0x6f00000
nand write 0x44000000 0x1000000 <size-of-oem-rootfs.bin-in-hex>
setenv active_fw 0 ; saveenv
reset
```
Restore `oem-wififw.bin` to `0x7f00000` if you overwrote it, and re-set any
`ethaddr`/serial env fields that changed.

**Route 2 — official EnGenius `.bin`:** once stock boots (Route 1), re-apply any
official EWS377AP v3 firmware through the normal web/cloud updater.

**Never write the ART partition or below `0x1000000`.** Because secure boot is
unfused, u-boot + TFTP always recover the OS as long as ART and the bootloader are
intact.

## Why it works
1. The FIT kernel exposes a config named **`config@hk07`** — the OEM u-boot `bootipq`
   selects the FIT config by board name and aborts otherwise.
2. OpenWrt must live on **slot 0** (`rootfs` @`0x1000000`) — its root-mount targets
   the partition labeled `rootfs` regardless of which slot booted the kernel.

Full engineering write-up: `PORT-STATUS-ews377ap-v3.md` on the `ews377ap-v3` branch of
the [`openwrt-nss-edma`](https://github.com/ParkWardRR/openwrt-nss-edma) fork.
