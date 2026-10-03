# Install OpenWrt on the EnGenius EWS377AP v3 — the friendly guide

This walks you all the way from stock EnGenius firmware to a working **OpenWrt**
router, and back again if you change your mind. There are three ways to do it — a
**reliable way** (a serial cable, always works), an **SSH way** (no cable, borrowed from
the officially-supported sibling WAX218), and an **easy way** (one web upload, if it pans
out). Pick the one that fits you.

New to flashing? Don't worry — every step says exactly what to type and what you
should see. A short [glossary](#glossary-plain-english) at the end explains the jargon
(UART, u-boot, "slot", "brick"). If a word is unfamiliar, it's defined there.

---

## 0. Is this for you? (30-second read)

- **Hardware:** EnGenius **EWS377AP v3** only (Qualcomm IPQ8072A, board `ap-hk07`).
  Not the v1/v2, not other models.
- **What you get:** real OpenWrt — LuCI web UI, SSH, package manager — instead of the
  locked vendor firmware. No cloud, no controller.
- **The risk, honestly:** flashing firmware can **brick** (permanently kill) a device.
  This build is community-made and unofficial. We've designed the steps to be
  recoverable, but *you* are responsible for your hardware.
- **Golden rule:** **make your own backup first** (Section 2). Your access point's
  Wi-Fi calibration and MAC address are unique to it — no one else's backup can
  replace them.

---

## 1. Pick your path

<!-- METHOD-B-STATUS: mechanism-proven-persistence-unit-blocked -->
> 🧪 **Easy path (web upload): the HTTP mechanism now works — persistence needs a
> second unit to confirm.** The earlier "rejected" result was a `product_id` header
> mismatch, not a request-contract problem — the OEM's `upload.cgi` checks the image
> against the *running* firmware's own SKU identity. Re-headed correctly, upload →
> stage → flash-trigger all genuinely work over HTTP, no UART needed for that part. But
> on the one test unit available, the resulting boot hangs on a reproducible bad NAND
> block in the spare slot — a hardware issue on that unit, not the image or mechanism
> (confirmed: two different image types failed at the identical block). Full findings:
> [`reference/method-b-findings.md`](../reference/method-b-findings.md). Use the
> reliable or SSH path for now; **if you try the easy path and it works cleanly on your
> unit, please report it** — see the tracking issue linked from the README.

| | 🟢 Reliable path (recommended) | 🔵 SSH path (no serial) | 🟡 Easy path |
|---|---|---|---|
| **How** | Serial cable + bootloader commands | `ubiformat` over stock SSH | Upload one file in the vendor web page |
| **Tools needed** | A USB-to-serial (UART) adapter, ~$10, and opening the case | An SSH client; stock firmware reachable | Nothing — just a browser |
| **Difficulty** | Moderate (copy-paste commands) | Moderate (copy-paste commands) | Easy |
| **Proven?** | ✅ Yes, on real hardware | 🧪 Proven on the sibling WAX218; not yet on EWS377 | 🧪 HTTP mechanism proven; persistence unconfirmed (see status box) |
| **If it goes wrong** | You're already on serial — recover in place | You'll *need* a serial cable to recover | You'll *need* a serial cable to recover |
| **Go to** | [Section 4](#4-reliable-path--serial-cable) | [Section 3b](#3b-ssh-path--from-stock-no-serial) | [Section 3](#3-easy-path--web-upload) |

**Our honest advice:** if you own a USB-serial adapter (or can borrow one), use the
reliable path — it can't strand you. If you have no adapter: the **SSH path** (mirrored
from the officially-supported NETGEAR WAX218, the same `ap-hk07` board — see
[wax218-equivalence.md](wax218-equivalence.md)) is more predictable than the blind
web-upload, but neither is proven on the EWS377 yet, so keep a serial cable within reach
for both.

---

## 2. Back up your device FIRST (everyone, no exceptions)

You need a serial cable for a *complete* backup (and the reliable path needs one
anyway). If you truly can't get one and are using the easy path, at minimum download
an **official EnGenius EWS377AP v3 firmware `.bin`** from EnGenius's site and keep it —
it's your fallback to reinstall stock later.

**Full backup over serial (recommended):** connect UART (Section 4.1), interrupt the
bootloader, then:
```
setenv ipaddr <your-ap-ip> ; setenv serverip <your-pc-ip> ; ping $serverip
nand read 0x44000000 0x1000000 0x6f00000 ; tftpput 0x44000000 0x6f00000 backup-rootfs.bin
nand read 0x44000000 0x8800000 0x6f00000 ; tftpput 0x44000000 0x6f00000 backup-rootfs_1.bin
nand read 0x44000000 0x7f00000 0x900000  ; tftpput 0x44000000 0x900000  backup-wififw.bin
printenv
```
(`tftpput` sends the file to a TFTP server on your PC — see Section 4.2.) Copy the
`printenv` output into a text file too. **Keep these off the device.** They're how you
get stock back byte-for-byte (Section 6).

> You do **not** need to (and must not) back up or write the ART / bootloader area
> below `0x1000000`. Leaving it untouched is what keeps recovery possible.

---

## 3. Easy path — web upload

> ⚠️ **Persistence not yet confirmed on any tested unit** — re-read the status box in
> [Section 1](#1-pick-your-path) first. The upload/flash *mechanism* genuinely works;
> if the OEM page rejects your file, it's most likely a `product_id` mismatch against
> your device's *currently running* firmware (see the status box), not a broken path —
> try a build headed for your unit's actual SKU. But even a successful upload+flash
> hasn't yet produced a confirmed-persistent boot on the one unit tested (a hardware
> issue specific to that unit, not the mechanism — see
> [`reference/method-b-findings.md`](../reference/method-b-findings.md)). Keep a serial
> cable handy, and please report your result either way.

1. Make sure you're on stock EnGenius firmware and can reach its web interface.
2. Download **`…-web-ui-factory.fit`** and **`SHA256SUMS`** from the
   [release](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-ecw230-ews377fit/releases), and check it:
   ```
   sha256sum -c SHA256SUMS --ignore-missing
   ```
   It must say `OK`. If it doesn't, re-download — do not flash a bad file. (This
   artifact is built the same way as the officially-supported sibling WAX218's own
   web-UI image — a kernel-only UBI wrapping the initramfs kernel, not our earlier
   Senao-wrapped attempt.)
3. In the EnGenius web UI, open the **firmware upgrade** page and upload
   `…-web-ui-factory.fit`. Let it finish and reboot **without** cutting power.
4. After a minute or two it should come up as OpenWrt — but **this is a temporary boot,
   not a finished install yet.** `web-ui-factory.fit` boots a self-contained OpenWrt
   environment from RAM; nothing is saved to flash by this step alone (mirrors exactly
   how the sibling WAX218's own web-upload method works). If you power-cycle now, you go
   back to whatever was on the flash before.
5. **To make it persistent**, while still in that temporary OpenWrt session: download
   `…-squashfs-sysupgrade.bin`, verify its checksum, and flash it —
   `sysupgrade -n openwrt-...-squashfs-sysupgrade.bin` over SSH, or LuCI → System →
   Backup/Flash Firmware. *This* step is what actually writes OpenWrt to NAND. Only
   after this reboot completes should you continue to
   [Section 5 — First boot](#5-first-boot).

**If the upload is rejected, or it reboots back into stock / doesn't come up:** the
easy path didn't take. Switch to the [reliable path](#4-reliable-path--serial-cable) —
this is exactly why we said keep a serial cable ready. If step 4 booted OpenWrt but you
skip step 5 and just power-cycle, you have not installed anything — that's expected,
not a failure.

---

## 3b. SSH path — from stock, no serial

This is the method OpenWrt uses for the sibling **NETGEAR WAX218** (the same `ap-hk07`
board — [details](wax218-equivalence.md)): write the OpenWrt image straight to NAND with
`ubiformat`, over the stock firmware's SSH, no cable and no case-opening. Everything it
needs is confirmed present on the EWS377 (a root SSH exec channel on **port 8822**,
`fw_setenv`, and the OpenWrt slot at `0x01000000`) — but **it has not yet been run
end-to-end on a real EWS377**, so treat it as experimental and keep a serial cable handy.

**Prereqs:** the AP is on stock EnGenius firmware, reachable on the network, **not**
ezMaster-managed (managed units disable SSH), and you know its admin password (`admin` on
a factory-reset unit). Download and verify `…-squashfs-factory.ubi` (Section 4.3).

```
AP=<ap-ip>
SSHOPTS="-p 8822 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"

# 0. VERIFY the target partition on YOUR unit. It MUST be the mtd at offset 0x01000000.
#    Do not assume the number below — read it here and use what you see.
ssh $SSHOPTS root@$AP 'cat /proc/mtd'          # note the mtdN whose offset is 0x01000000

# 1. Safety: aim the NEXT boot at the other slot, so a power cut mid-write still leaves
#    an intact system to boot.
ssh $SSHOPTS root@$AP 'fw_setenv active_fw 1'

# 2. Copy the image into the AP's RAM.
scp -O -P 8822 -o HostKeyAlgorithms=+ssh-rsa \
    openwrt-…-ews377ap-v3-squashfs-factory.ubi root@$AP:/tmp/openwrt.ubi

# 3. Write it. Replace mtd12 with the device you verified in step 0.
ssh $SSHOPTS root@$AP 'ubiformat /dev/mtd12 -f /tmp/openwrt.ubi -y'

# 4. Select slot 0 (where OpenWrt must live) and reboot into it.
ssh $SSHOPTS root@$AP 'fw_setenv active_fw 0 && reboot'
```

> ⛔ **Never `ubiformat` a partition below `0x01000000`** — that region holds ART (your
> Wi-Fi calibration + MAC) and the bootloader. Writing it is the one real way to brick.
> If step 0 doesn't show a partition at exactly `0x01000000`, **stop** and use the serial
> path instead.

**If `ubiformat` is missing** on your stock build, or SSH is closed (managed unit): this
path isn't available — use the [reliable serial path](#4-reliable-path--serial-cable).
After reboot, continue to [First boot](#5-first-boot).

---

## 4. Reliable path — serial cable

This is the proven method. You'll connect a serial adapter, interrupt the bootloader,
and write OpenWrt over the network with three commands.

### 4.1 Connect the serial console
- Get a **3.3V USB-to-TTL serial adapter** (FT232/CP2102/CH340 — a few dollars).
  **3.3V, not 5V** — 5V can damage the board.
- Open the AP and find header **J2**. Connect **GND↔GND, the AP's TX↔adapter RX,
  AP's RX↔adapter TX**. Do **not** connect the voltage pin.
- On your PC open a serial terminal at **115200 baud, 8N1** (e.g. `screen /dev/ttyUSB0 115200`,
  or PuTTY on Windows). Power on the AP — you should see boot text.

### 4.2 Set up a TFTP server on your PC
The AP pulls the firmware from your PC over **TFTP**. Install one (`sudo apt install
tftpd-hpa` on Linux, `brew install tftp-hpa` on macOS, or Tftpd64 on Windows) and put
the downloaded images in its serving folder. Note your PC's IP.

### 4.3 Download + verify the image
Grab **`…-squashfs-factory.ubi`** and **`SHA256SUMS`** from the
[release](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-ecw230-ews377fit/releases):
```
sha256sum -c SHA256SUMS --ignore-missing   # must print: ...factory.ubi: OK
```

### 4.4 (Optional but nice) test-drive in RAM first
This boots OpenWrt entirely in memory — **nothing is written**, so it's totally safe.
Power on, press a key to stop the countdown and get the `=>` bootloader prompt, then:
```
setenv serverip <your-pc-ip> ; setenv ipaddr <an-unused-ip-on-your-lan>
tftpboot 0x44000000 openwrt-…-initramfs-uImage.itb
bootm 0x44000000
```
If it boots to `root@OpenWrt:/#`, everything's compatible. Power-cycle to return to
stock, then do the real install below.

### 4.5 Install OpenWrt (writes to flash)
At the `=>` prompt:
```
setenv serverip <your-pc-ip> ; setenv ipaddr <an-unused-ip-on-your-lan> ; ping $serverip
tftpboot 0x44000000 openwrt-…-squashfs-factory.ubi
```
Check the line it prints — **`Bytes transferred = ... (e80000 hex)`**. If it's not
`e80000`, stop and re-download.
```
nand device 0
nand erase 0x1000000 0x6f00000
nand write 0x44000000 0x1000000 0xe80000
setenv active_fw 0 ; saveenv
reset
```
That's it. The AP reboots into OpenWrt. (Seeing `Skipping bad block` during the write
is normal — the chip has one factory-marked bad spot and the tool handles it.)

Continue to [First boot](#5-first-boot).

---

## 5. First boot

- OpenWrt comes up with LAN on **`192.168.1.1`**. Plug your PC into the AP's LAN port,
  set your PC to DHCP, and open **http://192.168.1.1** (LuCI web UI), or `ssh root@192.168.1.1`.
- **Set a root password immediately** (LuCI → System → Administration, or `passwd`).
  Until you do, SSH is open with no password.
- **Configure Wi-Fi** (LuCI → Network → Wireless). Enable a radio, set an SSID, and
  **use WPA2 or WPA3** — never leave an open network.
- Your uplink is the **2.5 GbE** port (`lan`). It negotiates up to 2.5 Gbps against a
  2.5G-capable switch; on a 1G switch it runs at 1G (normal).

**Upgrading later:** download `…-squashfs-sysupgrade.bin` and use LuCI → System →
Backup/Flash Firmware, or `sysupgrade -n …-squashfs-sysupgrade.bin`. Don't use the
`factory.ubi` for upgrades — that's only for the first install from stock.

---

## 6. Go back to stock EnGenius firmware

**Best (from your own backup, Section 2)** — over serial:
```
setenv serverip <your-pc-ip> ; setenv ipaddr <an-unused-ip> ; ping $serverip
tftpboot 0x44000000 backup-rootfs.bin
nand device 0
nand erase 0x1000000 0x6f00000
nand write 0x44000000 0x1000000 <size-of-backup-rootfs.bin-in-hex>
setenv active_fw 0 ; saveenv
reset
```
(To get the size in hex: `printf '0x%x\n' $(stat -c%s backup-rootfs.bin)`.) If you also
backed up `backup-wififw.bin`, write it to `0x7f00000` the same way. Restore any
`ethaddr`/serial env values from your saved `printenv`.

**Or, from an official file:** once stock boots again, just reinstall any official
EnGenius EWS377AP v3 firmware through the normal EnGenius updater.

---

## 7. Troubleshooting & recovery

| Symptom | What it means / fix |
|---|---|
| Web upload rejected or reboots to stock | Easy path didn't take → use the [serial path](#4-reliable-path--serial-cable). |
| `/proc/mtd` shows no partition at `0x01000000`, or `ubiformat` missing | SSH path not usable on your unit → use the [serial path](#4-reliable-path--serial-cable). |
| SSH refused / no port 8822 | ezMaster-managed (SSH disabled) or non-default firmware → unmanage it, or use serial. |
| No serial output at all | Wrong baud (use 115200 8N1), TX/RX swapped, or wrong header. Try swapping TX/RX. |
| `Bytes transferred` ≠ `e80000` | Bad/incomplete download — re-verify `SHA256SUMS`, re-fetch. |
| Boots but no `root@OpenWrt` / kernel panic on mount | You likely wrote the wrong slot — OpenWrt must go to slot 0 (`0x1000000`). Re-do Section 4.5. |
| Totally dead, only the `=>` prompt | Fine — TFTP the image back per Section 4.5, or restore stock (Section 6). |
| Wi-Fi radios missing | Reboot once; first boot initializes calibration. |

**You are only truly bricked if the ART/bootloader area is damaged — and these steps
never touch it.** As long as you get a `=>` prompt over serial, you can always
reinstall.

---

## Glossary (plain English)

- **UART / serial console** — a text console on the board over a 3-wire cable; how you
  talk to the bootloader. Needs a **3.3V USB-to-serial adapter**.
- **u-boot / bootloader** — the tiny program that runs first and loads the OS. The
  `=>` prompt is its command line. `bootipq` is its "boot the firmware" command.
- **TFTP** — a dead-simple file server; the bootloader uses it to pull the image from
  your PC.
- **slot** — this AP has two firmware "slots" (A/B). OpenWrt must live in **slot 0**
  (`0x1000000`); the vendor updater uses the same slot.
- **UBI / `factory.ubi`** — the flash filesystem format OpenWrt is packaged in.
- **ART** — a small factory partition holding your Wi-Fi calibration and MAC address.
  **Unique per device; never erase it** — that's the one real way to brick.
- **brick** — a device that won't boot and can't be recovered. Following this guide
  (backups + never touching ART) keeps that from happening.

## Appendix — partition map & why it works

| Region | Offset | Size | Note |
|---|---|---|---|
| bootloader / config / **ART** | `0x0`–`0x1000000` | 16 MiB | **never touch** |
| `rootfs` (slot 0) | `0x1000000` | 111 MiB | ← OpenWrt goes here |
| `0:wififw` | `0x7f00000` | 9 MiB | leave as-is |
| `rootfs_1` (slot 1) | `0x8800000` | 111 MiB | vendor A/B slot (unused by OpenWrt) |
| `0:wififw_1` | `0xf700000` | 9 MiB | leave as-is |

Two device-specific details make OpenWrt boot on the stock bootloader: the FIT kernel
image must expose a config named **`config@hk07`** (the bootloader picks the config by
board name), and OpenWrt must be installed to **slot 0** (its root-mount always uses
the `rootfs`-labeled partition). Both are baked into these images — you don't have to
do anything. Full write-up: `PORT-STATUS-ews377ap-v3.md` on the
[`openwrt-nss-edma`](https://github.com/ParkWardRR/openwrt-nss-edma) `ews377ap-v3` branch.
