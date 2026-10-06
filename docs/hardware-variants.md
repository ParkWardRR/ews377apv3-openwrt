# Which firmware for which hardware

One OpenWrt image per **SKU**, not per hardware revision. The three SKUs are the same IPQ8072A / `ap-hk07`
board but each image carries its own device tree (model string, Wi-Fi calibration *variant*) and its own
Wi-Fi board file. **Flash the file named for your SKU.**

| Your AP | Files to use (release `v0.5.1`) | Status |
|---|---|---|
| **EnGenius EWS377AP v3** | `…-engenius_ews377ap-v3-squashfs-factory.ubi` (first install), `…-sysupgrade.bin` (later), `…-initramfs-uImage.itb` (RAM test) | hardware-proven (1 GiB unit, earlier builds); v0.5 per-SKU rebuild not re-run on hardware |
| **EnGenius EWS377-FIT** | `…-engenius_ews377-fit-…` (same three) | **hardware-proven 2026-10-06** on a 512 MiB / u-boot 2.1.0 unit — [report](ews377-fit-hardware-validation.md) |
| **EnGenius ECW230v3** | `…-engenius_ecw230v3-…` (same three) | **untested on hardware** — see [ECW230v3 notes](#ecw230v3-notes) |
| NETGEAR WAX218 | use the official OpenWrt image | same board, [officially supported](wax218-equivalence.md) |

## Hardware revisions we have seen (same image, different procedure)

| | EWS377AP v3 unit | EWS377-FIT unit |
|---|---|---|
| RAM | 1 GiB | 512 MiB |
| u-boot | 2.0.0 — `=>` prompt, 5 s "press a key" countdown | 2.1.0 (2022) — `IPQ807x#`, **boot menu: press `4`** |
| MAC source | ART | u-boot env `ethaddr` (+ `cert` partition); ART has placeholders |
| Backup reads | one 111 MiB `nand read` worked | **chunks ≤ 32 MiB** (a 111 MiB read overwrites u-boot's FDT and resets) |

RAM size and u-boot version do **not** need a different image: the kernel takes memory from the bootloader and
both bootloaders boot FIT config `config@hk07`. This was checked by RAM-booting the EWS377AP v3 initramfs on the
512 MiB FIT unit (it booted, saw 512 MiB, brought up NSS and both radios). Only the **install procedure** differs
— follow the callouts in [install-and-restore.md](install-and-restore.md).

## Do not cross-flash SKU images (unless you know why)

The Wi-Fi board file is matched by the *variant string* in the image's own device tree. Within one image they always
agree; mixing them does not:

- An image whose DTS asks for `EnGenius-EWS377-FIT` but ships the EWS377AP v3 board file boots fine and has **no
  radios** (`failed to fetch board data … variant=EnGenius-EWS377-FIT`). That was a v0.4-era build bug, fixed in v0.5
  by building each SKU on its own.
- The three board files differ only slightly (EWS377-FIT vs v3: 56 bytes), but "slightly" has not been shown to be
  "irrelevant" for RF calibration targets — use your own SKU's file.

## How to tell which unit you have

1. The label / stock web UI model name (EWS377AP v3, ECW230v3, EWS377-FIT).
2. On UART at boot: the u-boot banner (`U-Boot 2016.01-EWS377AP-FIT-uboot_version:V2.1.0 …`), the `DRAM:` line, and
   on `printenv`: `hw_id`, `hw_ver`, `machid`, `ethaddr`. (Observed FIT unit: `hw_id=0101012B`, `machid=8010006`.)
3. `cat /proc/mtd` on stock firmware (see the label warning below).

## ECW230v3 notes

No ECW230v3 unit has been tested. Known differences from the other two SKUs, from the stock firmware analysis
([`sibling-sku-firmware-analysis.md`](https://github.com/ParkWardRR/openwrt-nss-edma/blob/ews377ap-v3/ews377ap-v3-port/sibling-sku-firmware-analysis.md)):

- Stock kernel is 5.4.213 (newer SDK) and its FIT's **default configuration is `config@hk08`**, not `config@hk07`.
  The ECW230v3 image therefore carries **both** `config@hk07` and `config@hk08` (same kernel and DTB) so either
  name boots. Verified by listing the FIT with `mkimage -l`.
- Its stock flash script validates `soc_hw_version` and `machid` before flashing; the EWS377 ones do not.
- The `rootfs` / `rootfs_1` partition **labels are reversed** on observed ECW230v3 units (slot at `0x1000000` is
  labelled `rootfs_1`). OpenWrt mounts the partition *labelled* `rootfs`, so on those units the install target may
  be the other slot. **Check `cat /proc/mtd` on your stock firmware first and do not blindly use `0x1000000`** — if
  you are the first ECW230v3 tester, please report `/proc/mtd`, `printenv` and the u-boot banner in an issue.

If it does not boot, nothing is lost: stop at the u-boot prompt and restore your backup ([guide §6](install-and-restore.md#6-go-back-to-stock-engenius-firmware)).
