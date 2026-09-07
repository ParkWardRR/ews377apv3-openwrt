# The WAX218 connection — same board, official upstream, borrowed install path

The EnGenius **EWS377AP v3**, **ECW230 v3**, **EWS377-FIT** and the NETGEAR
**WAX218 v1** are all the **same Qualcomm reference design** — board **`ap-hk07`**,
SoC **IPQ8072A**. The WAX218 is the *only* member of that family with **official,
mainline OpenWrt support** (`qualcommax/ipq807x`, since 23.05). That makes it the
single most useful reference we have: its device tree, image recipe, and install
procedure are the upstream-blessed template for everything this repo does.

This page records exactly what the two devices share, what differs, and how to reuse
the WAX218's install method on the EWS377.

## Proof they are the same board (verified, not asserted)

The stock EnGenius bootloader accepts a FIT image only if it contains a config named
after the board (`config@hk07`) — that was the EWS377 port's first "unlocker." The
official mainline WAX218 image carries **the exact same config name**:

```
$ strings openwrt-25.12.2-qualcommax-ipq807x-netgear_wax218-initramfs-uImage.itb \
    | grep -iE 'config@|hk07'
config@hk07
Iconfig@hk07
```

`config@hk07` in NETGEAR's officially-supported image = `config@hk07` required by the
EnGenius `bootipq`. Same reference board, same bootloader contract. The WAX218 DTS also
uses the same mechanisms the EWS377 port relies on: `qcom,smem-part` (partition table
read from SMEM, not hard-coded), `ubi.block=0,rootfs root=/dev/ubiblock0_1` (root
mounts the SMEM partition **labeled `rootfs`**), and `qcom,ath11k-calibration-variant`
(per-board Wi-Fi data). (Empirically confirmed 2026-09-07 by inspecting the mainline
`25.12.2` image; see the strings dumps above.)

## What matches vs. what differs

| Trait | Shared? | Detail |
|---|---|---|
| SoC | ✅ same | Qualcomm IPQ8072A, quad A53 |
| RAM | ✅ same class | 1 GiB DDR4 (both; some units report 512 MB variants) |
| NAND | ✅ same | 256 MiB, 128k block / 2048 page |
| Ethernet | ✅ same | single 2.5 GbE, QCA8081 PHY |
| Wi-Fi | ✅ same | 4×4:4 802.11ax dual-band, ath11k |
| Bootloader contract | ✅ same | QCA u-boot, `bootcmd=bootipq`, **FIT `config@hk07`**, A/B via `active_fw` env |
| Partition model | ✅ same | `qcom,smem-part`; OpenWrt mounts the SMEM `rootfs` label |
| **LEDs** | ❌ differs | WAX218 drives 4 discrete LEDs through a **shift register on bit-banged SPI** (DT `fairchild,74hc595`, pkg `kmod-gpio-nxp-74hc164` + `kmod-spi-gpio`); EWS377 has a plain **RGB LED on GPIO 54/55/56** |
| **Wi-Fi board data** | ❌ differs | EWS377 `qcom,board_id = 0x290` → `bdwlan.b290`; WAX218 ships its own `ipq-wifi-netgear_wax218` blob |
| **Image gate** | ❌ differs | EnGenius stock gates the web-upload on a Senao `product_id` (EWS377AP v3 = `0x011a`); NETGEAR uses its own header |
| **Stock SSH access** | ❌ differs | EnGenius: `root` on **port 8822**; NETGEAR: `admin` on port 22 |
| OUI | ❌ differs | EnGenius `88:DC:97`; NETGEAR its own |

**Consequence:** the mainline **`netgear_wax218`** image *will boot* on an EWS377 (same
`config@hk07`, same SoC/DDR/NAND/PHY) — useful as a recovery/bring-up RAM image — but
its LEDs and Wi-Fi calibration won't match, so it is **not** the image to run
persistently. Use the EWS377-specific build (correct LEDs + `bdwlan.b290` + ART
caldata). The value of the WAX218 is its **DTS, recipe, and install method**, not its
binary.

## The WAX218 official install method (the upstream template)

OpenWrt documents two routes for the WAX218; the SSH route is the recommended one.

**A. From stock, over SSH (`ubiformat`) — no serial needed:**
```
# 1. point the NEXT boot at the OTHER slot, so a power loss mid-write
#    still leaves an intact system to boot from
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 admin@<ip> \
    /usr/sbin/fw_setenv active_fw 1
# 2. copy the factory UBI into RAM
scp -O -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa \
    openwrt-...-netgear_wax218-squashfs-factory.ubi admin@<ip>:/tmp/openwrt.ubi
# 3. write it to the rootfs NAND partition
ssh ... admin@<ip> /usr/sbin/ubiformat /dev/mtd12 -f /tmp/openwrt.ubi
# 4. boot the freshly written slot 0
ssh ... admin@<ip> /usr/sbin/fw_setenv active_fw 0
```

**B. From stock, web UI:** upload `...-web-ui-factory.fit` in the vendor page, then once
OpenWrt is up flash `...-squashfs-sysupgrade.bin`. (Upstream notes the vendor web UI is
"problematic" on the WAX218 — same caution applies to the EWS377 web-upload path, which
is why it's still unproven here.)

Image artifacts the WAX218 recipe emits (names track the release; `25.12.2` shown):
`netgear_wax218-initramfs-uImage.itb`, `-squashfs-factory.ubi`,
`-squashfs-sysupgrade.bin`, `-web-ui-factory.fit`. The EWS377 build deliberately mirrors
these.

### What `factory.ubi` actually contains (so you know what `ubiformat` lays down)

Extracting the mainline `25.12.2` `netgear_wax218-squashfs-factory.ubi` (with
`ubireader`, on the Mac mini) shows a standard **ubinize** image — the exact structure
the EWS377 image must match:

| UBI volume | id | type | size | role |
|---|---|---|---|---|
| `kernel` | 0 | dynamic | 43 PEBs (~5.4 MB) | the **FIT** (kernel + DTB), carries `config@hk07` (verified) |
| `rootfs` | 1 | dynamic | 62 PEBs | squashfs; booted as `ubi.block=0,rootfs` → `/dev/ubiblock0_1` |
| `rootfs_data` | 2 | dynamic, **autoresize** | reserved 9 PEBs | the writable overlay; grows to fill the NAND slot on first boot |

Geometry: PEB `0x20000` (128 KiB), LEB `126976`, min-I/O `2048` — i.e. `BLOCKSIZE :=
128k`, `PAGESIZE := 2048`. `ubiformat /dev/mtdN -f factory.ubi` writes this whole image
to the `rootfs` NAND slot; u-boot's `bootipq` then loads the `kernel` volume's FIT
(picking `config@hk07`) and the kernel mounts vol 1 as root with vol 2 overlaid. The
EWS377 factory image is byte-for-byte the same shape, differing only in the DTB inside
the `kernel` FIT and the squashfs contents.

## How that maps onto the EWS377

The SSH `ubiformat` route is directly portable — the EWS377 stock firmware is itself a
QSDK-OpenWrt build with `fw_setenv` and (very likely) `ubiformat`, and it exposes a
**root exec channel on port 8822**. It gives a **no-serial, from-stock** install that is
lower-risk than the blind web-upload. Translated:

```
AP=<ap-ip>
SSHOPTS="-p 8822 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"

# 0. VERIFY the target partition first — it MUST be the one at offset 0x01000000.
#    Do NOT assume mtd12; confirm on YOUR unit:
ssh $SSHOPTS root@$AP 'cat /proc/mtd'          # find the mtdN at 0x01000000

# 1. safety: fall back to the intact slot if the write is interrupted
ssh $SSHOPTS root@$AP 'fw_setenv active_fw 1'

# 2. copy the EWS377 factory image
scp -O -P 8822 -o HostKeyAlgorithms=+ssh-rsa \
    openwrt-...-ews377ap-v3-squashfs-factory.ubi root@$AP:/tmp/openwrt.ubi

# 3. write it (replace mtd12 with the device you verified in step 0)
ssh $SSHOPTS root@$AP 'ubiformat /dev/mtd12 -f /tmp/openwrt.ubi -y'

# 4. select slot 0 (the proven OpenWrt slot) and reboot
ssh $SSHOPTS root@$AP 'fw_setenv active_fw 0 && reboot'
```

> ⚠️ **Status on the EWS377: NOT yet hardware-proven.** This method is proven on the
> WAX218 and every prerequisite is confirmed present on the EWS377 (SSH port 8822 root
> exec, `fw_setenv`, the `0x01000000` rootfs slot), but it hasn't been run end-to-end on
> a real EWS377 yet. Until it is, treat it as experimental: **verify `/proc/mtd`, never
> `ubiformat` a partition below `0x01000000` (ART/bootloader), and keep a serial cable
> ready.** The serial/u-boot `nand write` route in
> [install-and-restore.md](install-and-restore.md) remains the fully-proven install.

## Why this matters for the port itself

The porting plan's "biggest shortcut" — *find an already-supported IPQ8072A 4×4 sibling
and copy its `.dts` + `board-2.bin`* — resolves to exactly one device: **`netgear_wax218`**.
Anyone building or debugging the EWS377 image should diff against the mainline
`netgear_wax218` sources first. A **decompiled copy of the shipping WAX218 device tree**
is checked in at `reference/wax218-mainline-25.12.2.dts`, with a node-by-node comparison
in `reference/wax218-vs-ews377-dts.md` (identical SoC/2.5G/`smem-part` plumbing; only
LEDs, Wi-Fi caldata, and the image wrapper differ).

- DTS: `target/linux/qualcommax/dts/ipq8072-wax218.dts` (or the `files-*/…/ipq8072-wax218.dts`)
- Recipe: the `netgear_wax218` `Device/` block in `image/Makefile` — note
  `DEVICE_DTS_CONFIG := config@hk07`, `SOC := ipq8072`, `BLOCKSIZE := 128k`,
  `PAGESIZE := 2048`, and the factory recipe
  `append-image initramfs-uImage.itb | ubinize-kernel | qsdk-ipq-factory-nand`.

The EWS377 device block should differ only in: the DTS peripheral nodes (RGB LED on
GPIO 54/55/56 vs the WAX218 shift register; reset GPIO 52), the Wi-Fi package
(`ipq-wifi-engenius_ews377ap-v3` carrying `bdwlan.b290` vs `ipq-wifi-netgear_wax218`),
and the Senao web-upload wrapper (`product_id 0x011a`). Everything else — the SoC/DDR/
NAND/PHY plumbing and the `config@hk07` boot contract — is shared, and the WAX218 proves
it works upstream.

## Sources

- [OpenWrt PR #11959 — ipq807x: add support for Netgear WAX218](https://github.com/openwrt/openwrt/pull/11959)
- [OpenWrt commit — ipq807x: add support for Netgear WAX218](http://lists.infradead.org/pipermail/lede-commits/2023-March/017611.html)
- [OpenWrt hwdata — netgear_wax218_1](https://openwrt.org/toh/hwdata/netgear/netgear_wax218_1)
- [Forum — Netgear WAX218 install & recovery](https://forum.openwrt.org/t/netgear-wax218/165585)
- [Forum — WAX218 installation report (SSH factory.ubi)](https://forum.openwrt.org/t/netgear-wax218-installation-report/249112)
- Mainline image inspected: `downloads.openwrt.org/releases/25.12.2/targets/qualcommax/ipq807x/`
  (`config@hk07` confirmed present, 2026-09-07).
</content>
</invoke>
