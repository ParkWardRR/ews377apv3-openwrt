# WAX218 (mainline) vs EWS377AP v3 (OEM) — device-tree diff

Concrete, node-level comparison feeding the EWS377AP v3 port. The WAX218 side is
**decompiled from the official OpenWrt image** `openwrt-25.12.2-qualcommax-ipq807x-netgear_wax218-initramfs-uImage.itb`
(FDT sub-image → `reference/wax218-mainline-25.12.2.dts`, extracted 2026-09-07 with the
python `fdt` lib). The EWS377 side is the decompiled OEM DTS in
`reference/hk07-oem-fit-1.1.30.dts` + live-unit facts in `docs/hardware-reference.md`.

Both are the `ap-hk07` / IPQ8072A reference board, so the SoC plumbing is identical; the
only real deltas are LEDs, Wi-Fi caldata, and the vendor image wrapper.

## Identical (copy straight across)

| Node / property | Value (both) |
|---|---|
| FIT config selected by `bootipq` | **`config@hk07`** (verified in both the WAX218 image wrapper and the EWS377 requirement) |
| `compatible` SoC | `qcom,ipq8074` (IPQ8072A) |
| Partitions | **no static node** — `qcom,smem-part` reads the table from SMEM at runtime |
| Root mount | `chosen/bootargs-append = " ubi.block=0,rootfs root=/dev/ubiblock0_1"` → OpenWrt mounts the SMEM partition **labeled `rootfs`** |
| Console | `stdout-path = "serial0:115200n8"` |
| 2.5G PHY | `mdio@90000/ethernet-phy@28` `reg = <0x1c>` (QCA8081 @ MDIO 28) |
| Uplink port | `ess-switch@3a000000` `port@6` `phy_address = <0x1c>`, `port_mac_sel = "QGMAC_PORT"`, `switch_lan_bmp = <0x40>` (bit 6, via uniphy2) |
| Ethernet driver stack | `qcom,nss-dp` datapath + `qcom,ess-switch-ipq807x` (qualcommax NSS ethernet) |

The `ubi.block=0,rootfs` line is the upstream confirmation of this repo's "install to the
`rootfs`-labeled slot" rule: OpenWrt does not pick a slot by offset, it mounts whatever
SMEM labels `rootfs`.

## Different (the EWS377 device block must override these)

### LEDs — **different hardware**
WAX218 drives **4 discrete LEDs through a shift register on bit-banged SPI**:
```
/led_spi/led_gpio@0 {
    compatible = "fairchild,74hc595";     // shift register (pkg: kmod-gpio-nxp-74hc164 + spi-gpio/spi-bitbang)
    enable-gpios = <&tlmm 20 0>;
    spi-max-frequency = <1000000>;
};
/leds (gpio-leds): led_power <&led_gpio 1>, led_lan <&led_gpio 2>,
                   led_wlan_2g <&led_gpio 3>, led_wlan_5g <&led_gpio 4>;
```
**EWS377AP v3 has no shift register** — it's an **RGB status LED wired directly to SoC
GPIO 54/55/56** (active-high), reset button on **GPIO 52** (active-low). So the EWS377
DTS drops `led_spi`/`74hc595` and the `kmod-gpio-nxp-74hc164 kmod-spi-gpio
kmod-spi-bitbang` packages, and uses plain `gpio-leds` on `&tlmm 54/55/56`.

### Wi-Fi calibration variant — **different string + blob**
```
WAX218:  qcom,ath11k-calibration-variant = "Netgear-WAX218";       (ipq-wifi-netgear_wax218)
EWS377:  qcom,ath11k-calibration-variant = "EnGenius-EWS377AP-v3";  (bdwlan.b290; note lowercase -v3)
```
The EWS377 ships `ipq-wifi-engenius_ews377ap-v3` built from `bdwlan.b290`
(`reference/wifi-board-data/board-2.bin.engenius_ews377ap-v3`); per-device caldata still
comes from ART (mtd11).

### Image wrapper — **different vendor gate**
Both build the same artifact set (`initramfs-uImage.itb`, `squashfs-factory.ubi`,
`squashfs-sysupgrade.bin`, `web-ui-factory.*`) via
`append-image initramfs-uImage.itb | ubinize-kernel | qsdk-ipq-factory-nand`, with
`DEVICE_DTS_CONFIG := config@hk07`, `SOC := ipq8072`, `BLOCKSIZE := 128k`,
`PAGESIZE := 2048`. The EWS377 web-upload image additionally needs the Senao header
(`mksenaofw`, `product_id 0x011a`); the WAX218 uses a NETGEAR `.fit` wrapper instead.

## Takeaway for the port

Start from the mainline `netgear_wax218` device block and change exactly three things:
the LED/button nodes (RGB GPIO 54/55/56 + reset 52, drop the shift register), the Wi-Fi
package + `calibration-variant`, and the web-upload wrapper (Senao vs NETGEAR).
Everything else — SoC, DDR, NAND, the 2.5G QCA8081/port@6 path, `smem-part`, and the
`config@hk07` boot contract — is shared and already proven upstream.
</content>
