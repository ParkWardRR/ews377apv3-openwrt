# Quick Start

The fastest path from stock EnGenius firmware to OpenWrt on your EWS377AP v3, ECW230v3, or EWS377-FIT.

> **Read the [full install guide](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/install-and-restore.md) for detailed instructions.** This page is a condensed overview.

## Prerequisites

- One of: EWS377AP v3, ECW230v3, EWS377-FIT
- A computer on the same network
- SSH client (built into macOS/Linux; PuTTY or Windows Terminal on Windows)
- Downloaded firmware from the [Releases page](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/releases)
- **Recommended:** USB-to-serial adapter (3.3V TTL) for UART access — this is your safety net

## Step 0 — Verify SHA256

Before anything else, verify the download integrity:

```bash
shasum -a 256 openwrt-qualcommax-ipq807x-engenius_ews377ap-v3-squashfs-factory.ubi
```

Compare the output against `SHA256SUMS` in the release.

## Step 1 — Back up your AP

**This is not optional.** Your AP's ART partition contains unique radio calibration data. If lost, the radios cannot be recalibrated.

Connect via SSH (stock firmware uses port **8822**, not 22):

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -p 8822 root@<AP_IP>
```

Password is your web admin password (`admin` on a factory-reset unit).

Back up critical partitions:

```bash
# On the AP — dump to /tmp first
cat /dev/mtd11 > /tmp/art-backup.bin
cat /dev/mtd8 > /tmp/appsbl-backup.bin
cat /dev/mtd7 > /tmp/env-backup.bin

# From your computer — pull the dumps
scp -P 8822 -o HostKeyAlgorithms=+ssh-rsa root@<AP_IP>:/tmp/*-backup.bin ./
```

Store these backups somewhere safe. The ART dump is irreplaceable.

## Step 2 — Choose your install method

| Method | Cable needed? | Proven? | Best for |
|---|---|---|---|
| **UART / u-boot** | Yes (serial adapter) | **Yes — hardware-proven** | Safest option, recommended for first flash |
| **SSH + ubiformat** | No | Untested on EWS377 (proven on WAX218) | Experienced users, no serial adapter |
| **Web upload** | No | Experimental | Easiest but needs UART as backup |

**For your first flash, use UART if you have a serial adapter.** It is the only method proven end-to-end on real hardware.

## Step 3 — Flash

### UART method (recommended)

1. Connect serial adapter to header **J2** (115200 8N1)
2. Power on the AP, interrupt u-boot (press any key during countdown)
3. Transfer the firmware via TFTP and write to NAND:

```
# In u-boot
setenv ipaddr 192.168.1.1
setenv serverip 192.168.1.100
tftpboot openwrt-qualcommax-ipq807x-engenius_ews377ap-v3-squashfs-factory.ubi
nand erase 0x1000000 0x6f00000
nand write $fileaddr 0x1000000 $filesize
```

4. Set boot to slot 0 and reboot:

```
setenv active_fw 0
saveenv
reset
```

### SSH method

See the [full install guide](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/install-and-restore.md) — section on SSH + `ubiformat`.

### Web upload method

See the [full install guide](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/install-and-restore.md) — section on web upload. Use `web-ui-factory.fit`.

## Step 4 — First boot

After flashing and rebooting:

1. The AP will boot into OpenWrt (takes ~60 seconds)
2. Connect to `192.168.1.1` in your browser — the LuCI web interface loads
3. Set a root password immediately
4. Configure Wi-Fi via LuCI → Network → Wireless

## If something goes wrong

- **AP doesn't boot:** Use UART to access u-boot and re-flash, or restore your NAND backup
- **AP boots but no network:** Check that you are connected to the `lan` port (the single 2.5G Ethernet port)
- **Wi-Fi doesn't show up:** Check LuCI → Network → Wireless — radios may need to be enabled and configured
- **Want to go back to stock:** See the restore section in the [full install guide](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/blob/main/docs/install-and-restore.md)

## Report your results

Whether it worked or not, your report helps. [Open an issue](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/issues/new) with:

- Your model (EWS377AP v3 / ECW230v3 / EWS377-FIT)
- Install method used
- What happened (success, partial, failure)
- Output of `ubus call system board` if you can get a shell
