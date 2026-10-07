# Model differences — EWS377AP v3 vs. ECW230v3 vs. EWS377-FIT

Phase 1 deliverable from [`docs/ROADMAP.md`](../docs/ROADMAP.md). Method: decoded each
model's real stock firmware (`mksenaofw -d`), extracted the multi-board kernel FIT from
each rootfs UBI, pulled out each one's own `fdt@hk07` sub-image, and decompiled it with
`dtc`. Compared property values directly (not just presence/absence of a node) —
raw `dtc` output uses arbitrary per-file phandle numbers as the first cell of a
`<phandle pin flags>` triplet, so only the **second** value (the real pin number) is
meaningful across files; that distinction is called out below because an early pass
nearly misread it as a real difference.

## Hardware variants observed on real units (2026-10-06)

DTS-level identical does **not** mean every unit is identical. The first physical EWS377-FIT
differs from the documented EWS377AP v3 unit in ways that matter for install and MAC handling:

| | EWS377AP v3 (documented) | EWS377-FIT (observed) |
|---|---|---|
| RAM | 1 GiB | **512 MiB** |
| u-boot | 2.0.0, `=>`, 5 s countdown | **2.1.0 (2022), `IPQ807x#`, boot menu — press `4`** |
| MAC source | ART | **u-boot env `ethaddr` + `cert` partition; ART holds placeholders** |
| Stock console | — | password-protected; `admin` rejected |

Full report: [`docs/ews377-fit-hardware-validation.md`](../docs/ews377-fit-hardware-validation.md).

## Result: functionally identical at the DTS level

| Property | EWS377AP v3 | ECW230v3 | EWS377-FIT | Same? |
|---|---|---|---|---|
| Reset button GPIO | 52 | 52 | 52 | ✅ |
| LED red (`led_r`) GPIO | 54 | 54 | 54 | ✅ |
| LED green (`led_g`) GPIO | 55 | 55 | 55 | ✅ |
| LED blue (`led_b`) GPIO | 56 | 56 | 56 | ✅ |
| WiFi `qcom,board_id` | `0x290` | `0x290` | `0x290` | ✅ |
| 2.5G uplink: `port_id=6` → `phy_address` | `0x1c` (28) | `0x1c` (28) | `0x1c` (28) | ✅ |
| Internal GbE PHYs (`port_id` 1–5 → `phy_address` 0–4) | present | present | present | ✅ |
| DTS `compatible` string | `qcom,ipq807x-hk07`, `qcom,ipq807x` | `qcom,ipq8074-ap-hk07`, `qcom,ipq8074` | `qcom,ipq807x-hk07`, `qcom,ipq807x` | ⚠️ cosmetic difference only (see below) |

**Every property that affects an OpenWrt device profile (LEDs, reset, WiFi board data,
Ethernet/PHY wiring) is identical across all three SKUs.** The only difference found is
a cosmetic `compatible` string naming convention, explained below — it does not require
a different DTS.

## Why the `compatible` string differs (SDK generation, not hardware)

ECW230v3's stock firmware kernel FIT is timestamped **2023-10-11**; EWS377AP v3's and
EWS377-FIT's are **2026** builds. EnGenius evidently rebuilds and re-releases the shared
multi-board QSDK kernel bundle over time, and the SoC compatible-string convention
changed between those SDK generations (`ipq807x-hk07` → `ipq8074-ap-hk07`) while the
physical board and every pin/PHY mapping stayed the same. This also explains why
ECW230v3's root filesystem image is named differently
(`openwrt-ipq807x-ipq807x_32-ubi-root.img` vs. the other two's
`openwrt-ipq-ipq807x-ubi-root.img`) — a build-profile name, not a hardware signal.
**Conclusion: one shared OpenWrt DTS/device-profile is sufficient for all three SKUs**
(the `compatible` array can simply list all three product `compatible` strings for
clarity, matching how OpenWrt normally handles same-board SKU families).

## Firmware header fields (for building the 3 wrapped web-ui artifacts)

| SKU | vendor_id | product_id | fw_ver | datecode | capwap_ver | capwap model |
|---|---|---|---|---|---|---|
| EWS377AP v3 | `0x0101` | `0x011a` (282) | 3.9.3 | `0x33903` | 1.9.51 | `EWS377APv3` |
| ECW230v3 | `0x0101` | `0x011c` (284) | 1.8.114 | `0x3f9a2` | 0.0.0 | `ECW230v3` |
| EWS377-FIT | `0x0101` | `0x012c` (300) | 1.1.30 | `0x38664` | 0.0.0 | `EWS377-FIT` |

Note: EWS377AP v3's own firmware sets a real `capwap_ver` (1.9.51); ECW230v3 and
EWS377-FIT ship `0.0.0` in that field in the files sampled here — when building their
wrapped web images, mirror whatever field values each SKU's own real firmware uses
(sampled above) rather than inventing values, so the header round-trips cleanly through
`mksenaofw -d` and passes any downstream validation that checks it.

## What's still open (needs live hardware, not just firmware analysis)

- ~~Whether the EnGenius `upload.cgi` argument-validation blocker is common to all three
  SKUs' web GUIs or specific to the EWS377AP v3 firmware train.~~ **Resolved,
  2026-09-07:** the `upload.cgi` check is a `product_id` match against the running
  firmware's own identity. Re-heading to the correct `product_id` (282/284/300)
  unblocks the upload. See [`method-b-findings.md`](method-b-findings.md).
- SSH + `ubiformat` install, hardware-tested on any EnGenius SKU (currently mirrored
  from the WAX218, unverified here). **Note:** ECW230v3 cloud firmware is confirmed to
  have root SSH on port 8822, and the MTD map shows the same physical layout (slot 0 at
  `0x1000000`, slot 1 at `0x8800000`) — only the partition **labels** differ
  (`rootfs_1`/`rootfs` are swapped vs. EWS firmware). Target by offset, not label.
- Real-radio Wi-Fi validation on ECW230v3 and EWS377-FIT specifically (board-id match
  is confirmed at the DTS level; actual RF performance/regulatory behavior not yet
  tested on those two SKUs).
