# Community landscape — the ecosystem around IPQ807x OpenWrt and EnGenius/Senao APs

A map of the people, projects, forums, tools, and related hardware that shape this
port. Last updated 2026-10-06.

## 1. Key people and maintainers

### Upstream OpenWrt `qualcommax` target

| Person | Role | Where |
|---|---|---|
| **Robert Marko** ([robimarko](https://github.com/robimarko)) | Primary maintainer of the OpenWrt `qualcommax` target (IPQ807x, IPQ60xx, IPQ50xx). Reviews and merges DTS, driver, and board-support patches. His fork ([robimarko/openwrt](https://github.com/robimarko/openwrt), 393 stars) tracks `main` closely and is where bleeding-edge qualcommax work lands before upstream. | [OpenWrt forum](https://forum.openwrt.org), `#openwrt-devel` on OFTC |
| **Christian Marangi / Ansuel** ([Ansuel](https://github.com/Ansuel)) | Author of the upstream `qca_edma` and `qca_ppe` ethernet/PPE drivers that replaced the out-of-tree QSDK `qca-nss-dp`/`qca-ssdk` stack. His EDMA/PPE work is the foundation both mainline OpenWrt and the NSS-EDMA forks build on. Also maintains the `ath11k` firmware packaging. | GitHub, OpenWrt mailing list |

### NSS offload forks

| Person / Project | Role | Where |
|---|---|---|
| **qosmio** ([qosmio/openwrt-ipq](https://github.com/qosmio/openwrt-ipq)) | The original and most widely used NSS fork. 494 stars, 152 forks. Maintains NSS firmware packaging, the `nss-packages` feed, and prebuilt images via the Qualcommax_NSS_Builder CI. Branches: `main-nss` (kernel 6.12, unstable) and `24.10-nss` (kernel 6.6, stable). Covers IPQ807x and IPQ60xx. | [OpenWrt forum: Qualcommax NSS Build](https://forum.openwrt.org/t/qualcommax-nss-build), [GitHub Discussions](https://github.com/qosmio/openwrt-ipq/discussions) |
| **JuliusBairaktaris** ([JuliusBairaktaris/openwrt-nss-edma](https://github.com/JuliusBairaktaris/openwrt-nss-edma)) | A newer NSS fork (52 stars, 15 forks) that takes a different approach: runs NSS firmware on top of the **upstream** `qca_edma`/`qca_ppe` drivers (kernel 6.18) instead of the legacy out-of-tree `qca-nss-dp`/`qca-ssdk`. This is the tree our EWS377AP v3 port is based on. Branch: `nss-edma-rework`. Covers IPQ807x and IPQ60xx. Offloads: NAT, PPPoE, SQM, bridge, ath11k Wi-Fi. | [Wiki](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki), [nss-packages feed](https://github.com/JuliusBairaktaris/nss-packages) (branch `edma-nss`) |
| **ParkWardRR** ([ews377apv3-openwrt](https://github.com/ParkWardRR/ews377apv3-openwrt)) | **This project.** Fork of the JuliusBairaktaris NSS-EDMA tree with the EWS377AP v3 / ECW230v3 / EWS377-FIT port on branch `ews377ap-v3`. Also maintains the [engenius-field-guide](https://github.com/ParkWardRR/engenius-field-guide) and [pelegrun firmware tools](https://github.com/ParkWardRR/pelegrun-engenius-ews377-ecw230-firmware-tools). | This repo, [GitHub Issues](https://github.com/ParkWardRR/ews377apv3-openwrt/issues) |

### EnGenius/Senao community

| Person / Project | Role | Where |
|---|---|---|
| **DaveCorder** ([DaveCorder/EnGenius](https://github.com/DaveCorder/EnGenius)) | Early community notes on EnGenius hardware: Fit Controller hacking, cross-flashing, serial number format, ENS620EXT teardown. The foundational reference the engenius-field-guide builds on (credited in CREDITS.md). 2 stars. | GitHub |
| **cybrnook** | OpenWrt forum user who reported having EWS357 (v1/v3) and EWS377 (v1/v3) hardware and wanting an OpenWrt port. Potential collaborator / second test unit. Cited in the [research notes](research-notes.md). | OpenWrt forum: "Adding OpenWrt support for Senao like Devices" |
| **Pelegrún tools** ([pelegrun-ap-hk07-firmware-tools](https://github.com/ParkWardRR/pelegrun-engenius-ews377-ecw230-firmware-tools)) | No-brick cross-flash toolkit (Rust + Go) for the ap-hk07 family. `quarry rehead` changes the Senao header `product_id` field; `pelegrun` TUI guides the full discover → backup → install flow. Born from the cross-flash + recovery saga documented in the engenius-field-guide. | GitHub releases |

## 2. The NSS offload landscape

Qualcomm's NSS (Network Subsystem) is a dedicated hardware offload engine on
IPQ SoCs — separate CPU cores that handle NAT, routing, PPPoE, bridging, and
(in newer firmware) Wi-Fi acceleration, bypassing the main Linux networking
stack entirely. Getting NSS working in OpenWrt has been a years-long community
effort with three distinct approaches:

### Approach 1: qosmio's `openwrt-ipq` (out-of-tree NSS-DP/SSDK)

The dominant community NSS fork. Uses Qualcomm's legacy `qca-nss-dp` (network
datapath) and `qca-ssdk` (switch SDK) drivers — out-of-tree code that doesn't
ship in mainline OpenWrt. Mature, widely tested, large user base (494 stars).
**Trade-off:** carries significant out-of-tree kernel patches that are invasive
to maintain across kernel versions and block upstreaming.

- Branches: `main-nss` (kernel 6.12, tracks upstream `main`), `24.10-nss` (kernel 6.6, tracks `openwrt-24.10`)
- Prebuilt images: [Qualcommax_NSS_Builder releases](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder/releases)
- Forum thread: [Qualcommax NSS Build](https://forum.openwrt.org/t/qualcommax-nss-build)
- Support matrix: NAT, PPPoE, L2TPv2, GRE, PPTP, bridge, VLAN, VXLAN, multicast, SQM qdiscs, ath11k Wi-Fi AP/STA offload. IPsec/PVXLAN/CAPWAP/TLS not available in current NSS firmware.

### Approach 2: JuliusBairaktaris's `openwrt-nss-edma` (upstream EDMA/PPE + NSS)

Newer approach (52 stars). Runs the NSS firmware on top of Ansuel's **upstream**
`qca_edma` and `qca_ppe` drivers that are already in mainline OpenWrt 6.18.
Does NOT use the out-of-tree `qca-nss-dp`/`qca-ssdk`. This means the core
ethernet/PPE code stays closer to upstream, reducing the maintenance burden and
making an eventual upstream path more plausible. **This is the tree our port
uses.**

- Branch: `nss-edma-rework` (kernel 6.18)
- NSS packages feed: [nss-packages](https://github.com/JuliusBairaktaris/nss-packages), branch `edma-nss`
- Wiki: [architecture, runtime operation, SQM, hardware support, known limitations](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki)
- IPQ60xx support is new and lightly tested; maintainer has no IPQ60xx hardware.

### Approach 3: Mainline OpenWrt (no NSS)

Stock `qualcommax` target in upstream OpenWrt. Uses the same `qca_edma`/`qca_ppe`
drivers but does NOT load NSS firmware — all packet processing happens on the
host CPU. Works fine for most use cases; NSS is only needed for gigabit+
throughput with NAT/PPPoE/SQM where the host CPU would otherwise bottleneck.

### How they relate

```
upstream openwrt/openwrt main
  └─ qca_edma + qca_ppe drivers (Ansuel's upstream work)
       ├─ mainline qualcommax (no NSS) ← stock OpenWrt
       └─ JuliusBairaktaris/openwrt-nss-edma (NSS on upstream drivers) ← THIS PROJECT'S BASE
            └─ ParkWardRR/openwrt-nss-edma (ews377ap-v3 branch)
                 └─ EWS377AP v3 / ECW230v3 / EWS377-FIT port

qosmio/openwrt-ipq (legacy NSS-DP/SSDK) ← separate tree, most users
```

## 3. Mainline-supported IPQ807x devices (the `qualcommax` target)

These are officially in upstream OpenWrt and serve as reference boards for our
port. The NETGEAR WAX218 is the most important — same `ap-hk07` board as the
EWS377 family.

| Device | SoC | Key traits | OpenWrt status | Relevance to this port |
|---|---|---|---|---|
| **NETGEAR WAX218 v1** | IPQ8072A | 4×4 AX, 2.5GbE QCA8081, `ap-hk07`, `config@hk07` | **Officially supported** since 23.05 | **Same board.** The direct upstream reference — identical FIT config, same `qcom,smem-part`/`ubi.block`/ath11k caldata-variant mechanisms. Its SSH `ubiformat` install method is the template for our no-serial path. |
| **Aliyun AP8220** | IPQ8071 | 2.5G on port@6/uniphy2 | Officially supported | Closest in-tree 2.5G IPQ8072 AP (different radio config). Ethernet template. |
| **Dynalink DL-WRX36** | IPQ8072A | 4×4 AX, 1GbE | Officially supported | Same SoC class, different board. Widely tested. |
| **TP-Link EAP660HD** | IPQ8072A | 4×4 AX enterprise AP | Officially supported | EnGenius-adjacent enterprise AP, same SoC. |
| **Netgear WAX620** | IPQ8072A | 4×4 AX, 2.5GbE | Officially supported | Same SoC, similar enterprise AP form factor. |
| **Linksys MX4300 / MR7350** | IPQ807x | Mesh / consumer | Officially supported | NSS-EDMA tested. |
| **Xiaomi AX3600 / Redmi AX6** | IPQ8071A | 4×4 AX consumer | Officially supported | Primary validation target for the NSS-EDMA fork. All NSS offload benchmarks come from this hardware. |
| **GL.iNet GL-AX1800** | IPQ6018 | Consumer | Officially supported | NSS-EDMA tested. |

## 4. EnGenius/Senao device ecosystem

### The `ap-hk07` family (this project's hardware)

Three SKUs, one board. All share IPQ8072A, `config@hk07`, identical DTS
properties (LEDs, reset GPIO, WiFi board-id `0x290`, 2.5G PHY), and differ only
in Senao firmware header fields.

| Model | Product ID | Management | Status |
|---|---|---|---|
| EWS377AP v3 | 282 (0x011a) | Controller (EWS) | Hardware-proven |
| ECW230v3 | 284 (0x011c) | Cloud (ECW) | DTS-validated |
| EWS377-FIT | 300 (0x012c) | Standalone (FIT) | Hardware-proven |

The NETGEAR WAX218 v1 is the same `ap-hk07` reference board and is the
officially-supported upstream sibling. See
[wax218-equivalence.md](wax218-equivalence.md).

### Related EnGenius/Senao devices (not `ap-hk07`, but in the ecosystem)

| Device | SoC | Notes |
|---|---|---|
| EWS377AP v2 | IPQ807x (older) | Product ID 182. Different revision — NOT the same board as v3. |
| EWS357AP v1/v3 | IPQ807x | Reported by cybrnook as having hardware available for porting. |
| ECW230 (non-v3) | IPQ807x | Product ID 275. Earlier ECW230 revision. |
| ECW230S | IPQ807x | Product ID 285. Different SKU — not yet analyzed. |
| ENS620EXT | IPQ40xx | Older EnGenius extender. DaveCorder has notes. Different SoC family entirely. |
| ENH1350EXT | IPQ40xx | ezMaster-era. Not IPQ807x. |

### Controller generations

| Controller | Manages | Status |
|---|---|---|
| **ezMaster** | EWS/ENS managed line | EOL. Security concerns (default creds, cleartext). |
| **Fit Controller / EPC** | -FIT, ECW, ECS/ECS-Lite | Current. Self-hostable (Docker on x86 or ARM). See [engenius-field-guide](https://github.com/ParkWardRR/engenius-field-guide). |

Cross-SKU flashing between the three `ap-hk07` models is possible with the
`quarry rehead` tool — change the `product_id` header field, flash via the OEM
web GUI. See [pelegrun firmware tools](https://github.com/ParkWardRR/pelegrun-engenius-ews377-ecw230-firmware-tools).

## 5. Tools and utilities

### Firmware manipulation

| Tool | Language | What it does | Source |
|---|---|---|---|
| **quarry** (Pelegrún) | Rust | Senao image header re-head (`product_id` change), Code27 serial generation, firmware inspection | [pelegrun-ap-hk07-firmware-tools](https://github.com/ParkWardRR/pelegrun-engenius-ews377-ecw230-firmware-tools) |
| **pelegrun** (Pelegrún) | Go | TUI dashboard + CLI: discover firmware family, env safety check, secret redaction, no-UART A/B flash | Same repo |
| **mksenaofw** | C | Build Senao-wrapped firmware images. Already in OpenWrt's `firmware-utils`. | Upstream OpenWrt `tools/firmware-utils` |
| **dumpimage** | C | Extract sub-images from FIT containers. | Upstream U-Boot tools |

### WiFi board data

| Tool | What it does | Source |
|---|---|---|
| **ath11k-bdencoder** | Encode/decode ath11k `board-2.bin` firmware containers | [qca/ath11k-bdencoder](https://github.com/qca/ath11k-bdencoder) |

### OpenWrt build

| Tool / Project | What it does | Source |
|---|---|---|
| **Qualcommax_NSS_Builder** | CI that produces prebuilt NSS images for every IPQ807x/IPQ60xx board | [JuliusBairaktaris/Qualcommax_NSS_Builder](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder) |
| **OpenWrt Firmware Selector** | Web UI to pick and download images for any supported device | [firmware-selector.openwrt.org](https://firmware-selector.openwrt.org/) |

## 6. Community forums and discussion venues

| Venue | URL | What happens there |
|---|---|---|
| **OpenWrt Forum: IPQ807x SoC Investigation** | `forum.openwrt.org` (thread title: "IPQ807x SoC Investigation / Status [WIP]") | The long-running thread where robimarko, Ansuel, and others debugged IPQ807x bring-up. Secure boot priors, boot chain analysis, DTS work. |
| **OpenWrt Forum: Adding OpenWrt support for Senao like Devices** | `forum.openwrt.org` | Where cybrnook reported having EWS357/EWS377 hardware. Potential collaborator thread. |
| **OpenWrt Forum: OpenWrt support for WAX218** | `forum.openwrt.org` | WAX218-specific support thread. Bootlog cited as covering EWS377AP v3 / ECW230v3. |
| **OpenWrt Forum: Qualcommax NSS Build** | `forum.openwrt.org` | qosmio's NSS fork discussion. Bug reports, feature requests, benchmark sharing. |
| **OpenWrt Forum: Support for EnGenius EWS377APv1** | `forum.openwrt.org` | v1 investigation — found incompatible (non-"A" IPQ8072 revision). Dead end; only v3 works. |
| **Level1Techs forum** | `forum.level1techs.com` | Hardware merits of EWS377AP — first Wi-Fi 6 AP with 2.5 GbE, no 1 GbE bottleneck. Interest in hardware, no OpenWrt discussion. |
| **OpenWrt IRC: `#openwrt`** | OFTC network | General support. |
| **OpenWrt IRC: `#openwrt-devel`** | OFTC network | Development discussion. |
| **OpenWrt Mailing List** | `lists.openwrt.org/mailman/listinfo/openwrt-devel` | Patches, code review, upstreaming discussion. |
| **GitHub Issues: this repo** | [ews377apv3-openwrt/issues](https://github.com/ParkWardRR/ews377apv3-openwrt/issues) | Project-specific: Method B persistence validation, community hardware testing. |

## 7. The upstreaming path

The long-term goal is a mainline OpenWrt PR for the EWS377 family, following the
WAX218 precedent. The path:

1. **Device profile in `qualcommax/ipq807x`** — `Device/engenius_ews377ap-v3`
   with `DEVICE_DTS_CONFIG := config@hk07`, pointing at the shared
   `ipq8072-ews377ap-v3.dts`. Per-SKU profiles for ECW230v3 and EWS377-FIT.
2. **WiFi board data** — `ipq-wifi-engenius_ews377ap-v3` package carrying
   `bdwlan.b290` extracted from stock firmware. Redistribution terms must be
   confirmed.
3. **`SUPPORTED_DEVICES` / `DEVICE_COMPAT_VERSION`** — set correctly per SKU
   so sysupgrade identity checks pass.
4. **Build and boot-test against current upstream `main`** — not just the
   NSS-EDMA fork. NSS patches can hide a dependency mainline reviewers can't
   reproduce.
5. **Commit + PR** to `openwrt/openwrt`, targeting `qualcommax/ipq807x`.

The NSS offload itself is **separate** from the upstreaming effort. The mainline
PR covers basic boot, ethernet, WiFi, LEDs, sysupgrade — no NSS. NSS stays as
a community fork feature until/unless the upstream driver situation changes.

### Key commit references

| Commit | What |
|---|---|
| [`7801161c`](https://github.com/openwrt/openwrt/commit/7801161c4bb2413817b3dfd01695050e2da27bf3) | WAX218 `DEVICE_DTS_CONFIG := config@hk07` — the precedent for our FIT config name |

## 8. How to get involved

| Want to... | Do this |
|---|---|
| **Test on a second unit** (Method B persistence) | See [issue #1](https://github.com/ParkWardRR/ews377apv3-openwrt/issues/1) — re-head a release image with `quarry rehead`, upload via OEM web GUI, report whether it boots persistently. |
| **Test SSH install on ECW230v3** | ECW230v3 cloud firmware has root SSH on port 8822. The `ubiformat` install method is documented but untested on ECW230v3 hardware. See [install-and-restore.md](install-and-restore.md). |
| **Port another EnGenius IPQ807x device** | Check if it's `ap-hk07` (same board = trivial) or a different reference design (needs its own DTS). The engenius-field-guide has [model equivalence](https://github.com/ParkWardRR/engenius-field-guide/blob/main/model-equivalence.md) data. |
| **Contribute to NSS offload** | The JuliusBairaktaris fork accepts PRs. qosmio's fork has the larger user base. Both need IPQ60xx testers. |
| **Upstream a device** | Follow the WAX218 PR pattern. The OpenWrt [submitting patches guide](https://openwrt.org/docs/guide-developer/submitting-patches) and `#openwrt-devel` IRC are the channels. |
| **Self-host an EnGenius controller** | The [engenius-field-guide](https://github.com/ParkWardRR/engenius-field-guide) has Docker/Podman deploy guides for EPC, plus the Fit Controller on ARM. |
| **Add OpenWrt wiki device pages** | Submit a ToH entry for the EWS377AP v3. Requires a working port (done) and the standard device-page template. |
| **Benchmark NSS on IPQ8072A** | NSS offload numbers currently come from Xiaomi AX3600 (IPQ8071A). Nobody has benchmarked NSS on the EWS377's IPQ8072A yet. |

## 9. Licensing and legal notes

- **OpenWrt:** GPL-2.0.
- **NSS firmware:** Proprietary Qualcomm blobs. Not redistributable in source
  form. The NSS forks ship them as prebuilt binaries; mainline OpenWrt does not
  include them.
- **ath11k board data (`board-2.bin` / `bdwlan.b290`):** Extracted from vendor
  firmware. Redistribution terms are ambiguous — the same question OpenWrt
  navigates for IPQ807x WiFi firmware. Where a blob isn't clearly redistributable,
  keep it a build-time input the user supplies.
- **EnGenius/Senao firmware images:** Vendor proprietary. Not redistributed in
  this repo. Cross-SKU flashing may have licensing implications beyond the pure
  hardware question (EnGenius Cloud subscription features, etc.).
- **Pelegrún tools:** Blue Oak Model License 1.0.0.
- **engenius-field-guide:** Blue Oak Model License 1.0.0.
- **DaveCorder/EnGenius:** The foundational community notes that much of the
  EnGenius ecosystem knowledge builds on. Credited in the engenius-field-guide
  CREDITS.md.