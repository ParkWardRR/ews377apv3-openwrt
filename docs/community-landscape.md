# Community landscape — where this project sits

Last updated: 2026-10-02

## OpenWrt support for EnGenius EWS377AP / ECW230 / EWS377-FIT

### What exists today

**Mainline OpenWrt:** None. The EWS377AP v3, ECW230v3, and EWS377-FIT are not in
the [OpenWrt Table of Hardware](https://openwrt.org/toh/engenius/start). There is
no device page, no mainline commit, no pending PR.

**This project:** The only working OpenWrt port for these boards. Hardware-validated
on a real EWS377AP v3 (persistent NAND boot, Ethernet, Wi-Fi). Built on the
community NSS-EDMA fork with Qualcomm NSS hardware offload, kernel 6.18.

**OpenWrt forum threads:**

| Thread | What's there | Status |
|---|---|---|
| [Support for EnGenius EWS377APv1](https://forum.openwrt.org/t/support-for-engenius-ews377apv1/191978) | Discussion of the v1 — found incompatible (non-"A" IPQ8072 revision, `ath11k` doesn't support it). **v1 is not viable.** Only the v3 works. | Dead end |
| [Adding OpenWrt support for Senao-like devices](https://forum.openwrt.org/t/adding-openwrt-support-for-senao-like-devices/88170) | User expressed interest in EWS357 and EWS377 (v1 and v3). No significant progress posted. | Stalled |
| [Qualcommax NSS Build](https://forum.openwrt.org/t/qualcommax-nss-build/148529) | The mega-thread for NSS offload builds. Covers IPQ807x broadly (Xiaomi AX3600, Dynalink, etc.). EWS377AP v3 is not yet in the supported device list. | Active, but no EWS377 content |

**OpenWrt wiki:** No device page for any of these three models. The
[EnGenius devices page](https://openwrt.org/toh/engenius/start) lists older
models (ENS202, EAP1300, etc.) but nothing IPQ807x-based.

### The WAX218 connection

The **NETGEAR WAX218 v1** shares the same `ap-hk07` reference design and IPQ8072A
SoC. It has the same FCC ID (`A8J-EWS377APV3`) as the EWS377AP v3 — literally the
same board from the same manufacturer (Senao).

The WAX218 [is officially supported in mainline OpenWrt](https://openwrt.org/toh/netgear/wax218)
since commit [`7801161c`](https://github.com/openwrt/openwrt/commit/7801161c4bb2413817b3dfd01695050e2da27bf3).
This project mirrors the WAX218's boot contract (`config@hk07`), install method
(SSH + `ubiformat`), and factory image construction. The long-term plan is to
upstream the EnGenius boards using the WAX218 PR as the template — see
[ROADMAP.md](ROADMAP.md).

### Other community interest

| Source | Discussion | Takeaway |
|---|---|---|
| [Level1Techs forum](https://forum.level1techs.com/t/question-regarding-engenius-ews357ap-and-ews377ap/169248) | Hardware merits of EWS377AP — first Wi-Fi 6 AP with 2.5 GbE, no 1 GbE bottleneck | Interest in the hardware, no OpenWrt discussion |
| eBay / secondary market | EWS377AP v3 units available $30–60 used | Affordable entry point for testers |
| EnGenius/Senao | No official OpenWrt support or acknowledgement | Expected — vendor ships their own QSDK-based firmware |

### Companion projects (all by the same author)

| Project | What it does |
|---|---|
| [openwrt-nss-edma](https://github.com/ParkWardRR/openwrt-nss-edma) | The build tree — OpenWrt fork with NSS hardware offload |
| [pelegrun-ap-hk07-firmware-tools](https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools) | Cross-flash toolkit — SKU conversion, serial provisioning, no UART. Rust + Go. |
| [engenius-field-guide](https://github.com/ParkWardRR/engenius-field-guide) | Unofficial field guide for EnGenius/Senao hardware — controllers, firmware format, adoption |

### What's missing (where you can help)

1. **Hardware testers** for ECW230v3 and EWS377-FIT — identical silicon, but nobody
   has flashed OpenWrt on one yet.
2. **OpenWrt forum presence** — no dedicated thread for this port. A post in the
   Qualcommax NSS Build thread or a new device-support thread would reach the right
   audience.
3. **OpenWrt wiki device pages** — submitting a ToH entry for the EWS377AP v3 would
   make it discoverable. Requires a working port (done) and the standard device-page
   template.
4. **Mainline upstreaming** — the WAX218 precedent makes this straightforward in
   principle, but requires stripping NSS-specific patches, building against upstream
   `main`, and providing per-unit evidence (boot logs, `ubus call system board`,
   radio test results).
5. **NSS throughput benchmarks** — the NSS offload numbers come from the Xiaomi
   AX3600 (IPQ8071A). Nobody has benchmarked NSS performance on the EWS377AP v3's
   IPQ8072A yet.
