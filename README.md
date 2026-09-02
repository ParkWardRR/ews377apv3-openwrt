# EWS377AP v3 → OpenWrt (NSS-accelerated)

Porting the **EnGenius EWS377AP v3** (Qualcomm IPQ8072A, board `ap-hk07`) to **OpenWrt with Qualcomm
NSS hardware offload**, using the community NSS-EDMA tree (NSS offload layered on the *upstream*
qca_edma/qca_ppe stack). Goal: OpenWrt's flexibility while recovering most of the OEM QSDK forwarding
throughput.

> **Status:** active development, pre-flash. OEM device tree + WiFi board data already extracted
> offline; GPIO/LED/PHY values confirmed. Remaining unknowns need the running unit / UART (ETA ~2
> days). Every step can brick a unit until proven on a sacrificial AP.

## Why NSS (and not plain mainline)

Stock mainline OpenWrt on IPQ807x runs the Ethernet/PPE path on the host CPU with **no NSS offload**,
so forwarding throughput sits well below the OEM. The **NSS-EDMA** fork drives the Qualcomm NSS block
(NAT, PPPoE, SQM, multicast, bridge, ath11k Wi-Fi offload) while keeping an upstream-oriented
EDMA/PPE driver stack — materially closer to the QSDK performance model. That is the target here.

> The fork is validated on **Xiaomi AX3600 / IPQ8071A, not the EWS377** — its published NSS numbers
> are AX3600 figures, not an EWS377 benchmark. The EWS377's IPQ8072A part is close enough to make NSS
> a plausible target, but every EWS377-specific piece (NSS bring-up, EDMA binding to this board's
> Ethernet, ECM offload engaging, ath11k offload) is validated independently — see the porting plan.

The OEM stock firmware remains only as the **throughput baseline to measure against**, not a target
to build.

## Where the work lives

- **Fork:** `github.com/ParkWardRR/openwrt-nss-edma` (of `JuliusBairaktaris/openwrt-nss-edma`)
- **Branch:** `ews377ap-v3`
- **Scaffolded:** `ipq8072-engenius-ews377ap-v3.dts`, the `Device/engenius_ews377ap-v3` image recipe
  (FitImage/UbiFit + stubbed Senao factory image), and the `ipq-wifi-engenius_ews377ap-v3` board-data
  package. Status + TODOs: `PORT-STATUS-ews377ap-v3.md` in the fork.

## Confirmed from OEM firmware (offline)

Extracted `fdt@hk07` (the firmware's **default config**) from stock EWS377-FIT 1.1.30 — model
*"Qualcomm IPQ807x/AP-HK07"*, i.e. exactly this board:

- **LEDs:** RGB status LED, active-high — GPIO 54 (R) / 55 (G) / 56 (B)
- **Reset:** GPIO 52, active-low
- **Ethernet:** 2.5G uplink PHY (QCA8081) at MDIO addr 28; internal gigabit PHYs at 0–4; PHY reset on GPIO 43/44
- **Partitions:** SMEM-defined (`qcom,smem-part` auto-reads them)
- **WiFi:** QSDK `WLAN.HK.2.5.r4-00745`; board data extracted (default `bdwlan.b210`, ECW230v3 `bdwlan.b290`)

Artifacts in [reference/](reference/) (decompiled OEM DTS + board data + notes).

## Key enabler

Stock firmware's FIT sub-images are named `openwrt-ipq-ipq807x-ubi-root.img` — **EnGenius stock is a
QSDK OpenWrt build**, so the device tree, board files, and partition map already exist and are
harvestable (done, above). The gap to the NSS-EDMA tree is translating QSDK downstream bindings
(NSS/edma/ess-switch) to the fork's upstream ones.

## Hardware at a glance

- **SoC:** Qualcomm IPQ8072A, 4×4 802.11ax — same board as ECW230v3 / EWS377-FIT
- **Board:** `ap-hk07` (Qualcomm HK reference derivative)
- **Boot:** u-boot, `bootcmd=bootipq`, dual A/B firmware slots
- **UART:** header **J2**, 115200 8N1 (see [docs/uart-extraction-plan.md](docs/uart-extraction-plan.md))
- **Flash (MTD):** DEVCFG=mtd3, APPSBLENV=mtd7, APPSBL=mtd8, cert=mtd9, **ART=mtd11**, rootfs slots mtd12/mtd14

Full detail: [docs/hardware-reference.md](docs/hardware-reference.md)

## Documents

| File | Purpose |
|---|---|
| [docs/openwrt-porting-plan.md](docs/openwrt-porting-plan.md) | End-to-end NSS-EDMA port plan: extract → bring-up → DTS → WiFi → NSS validation → install |
| [docs/uart-extraction-plan.md](docs/uart-extraction-plan.md) | What to pull off the live unit once UART is connected |
| [docs/hardware-reference.md](docs/hardware-reference.md) | MTD map, boot chain, u-boot env, serial/MAC facts, recovery |
| [reference/](reference/) | Extracted OEM device tree + WiFi board data |

## Safety / recovery ground rules

- **Back up before touching flash:** mtd7 (env), mtd8 (APPSBL), **mtd11 (ART — calibration + MAC; corruption = real brick)**, plus a pristine stock `.bin`.
- Never hand-rebuild a partial u-boot env — a *valid-but-incomplete* env is worse than an erased one.
- Keep one OEM slot intact until OpenWrt sysupgrade + failsafe are proven.
- Do all work on a **sacrificial unit** — these APs are a deployed fleet (`*.alpina.casa`).
