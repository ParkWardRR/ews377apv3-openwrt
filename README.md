# EWS377AP v3 → OpenWrt

Porting notes, hardware reference, and extraction plans for bringing **mainline OpenWrt** to the
**EnGenius EWS377AP v3** access point (Qualcomm IPQ807x, board `ap-hk07`).

> **Status:** research / planning. No custom firmware flashed yet. The OEM A/B slots + UART + TFTP
> make this fully recoverable, but assume every step here can brick a unit until proven on a
> sacrificial AP.

## TL;DR feasibility

| Factor | Verdict |
|---|---|
| SoC in mainline OpenWrt | ✅ IPQ807x is in-tree (`qualcommax`), ath11k + ethernet work |
| **Stock firmware is QSDK-based OpenWrt** | ✅ **Biggest de-risker** — DTS/board files/partitions already exist downstream (see below) |
| Secure boot fuse | ⚠️ **The one go/no-go unknown** — must verify at u-boot; stock loads MD5-only FITs, so probably *not* fused |
| Recovery | ✅ Dual A/B slots + UART (J2) + TFTP |
| Ethernet performance | ⚠️ Mainline has no NSS hardware offload (QSDK-only) → below stock. **Recoverable via Target C (NSS-EDMA fork)** — see below |
| ath11k board data (BDF) | 🟡 Extractable from firmware; may need board-ID reconciliation |

## Three firmware targets

| Target | What | Purpose |
|---|---|---|
| **A** — OEM EnGenius QSDK | stock firmware | throughput baseline to beat |
| **B** — OpenWrt mainline | clean `qualcommax` port | upstreamable, correct, but no NSS offload |
| **C** — OpenWrt NSS-EDMA | B + community NSS-EDMA fork (NSS offload, EDMA/PPE, ath11k offload) | recover most QSDK forwarding perf |

**Do B first; C layers on the same board port.** The NSS-EDMA fork is validated on **Xiaomi AX3600 /
IPQ8071A, not the EWS377** — its published numbers are AX3600 figures, not an EWS377 benchmark. The
EWS377's IPQ8072A part is close enough to make NSS a plausible target, but every EWS377-specific piece
(NSS bring-up, EDMA binding to this board's Ethernet, ECM offload engaging, ath11k offload) must be
independently validated. See [Phase 7 in the porting plan](docs/openwrt-porting-plan.md#phase-7--target-c-nss-edma-experimental-performance).

## The key finding

The FIT sub-images inside stock firmware are named:

- `openwrt-ipq-ipq807x-ubi-root.img`   (EWS377-FIT 1.1.30)
- `openwrt-ipq807x-ipq807x_32-ubi-root.img`   (ECW230v3 cloud)

**EnGenius stock firmware is a downstream QSDK OpenWrt build.** Consequences:

1. The device tree, `board-2.bin`, partition map, LED/GPIO mapping, and pinmux **already exist** in
   EnGenius's OpenWrt source — we harvest and translate them, not invent them.
2. The live OS is already `uci` / `procd` / `sysupgrade`-shaped, so config semantics carry over.
3. The gap to *mainline* is: downstream QSDK bindings (NSS, edma, ess-switch, proprietary qca-wifi)
   → mainline bindings (ipqess, ath11k). That translation is the actual porting work.

## Hardware at a glance

- **SoC:** Qualcomm IPQ807x (IPQ8072A class), 4×4 802.11ax — same board as ECW230v3 / EWS377-FIT
- **Board name:** `ap-hk07` (Qualcomm reference-design designator)
- **Boot:** u-boot, `bootcmd=bootipq`, dual A/B firmware slots
- **UART:** header **J2** on the v3 PCB, 115200 8N1 (see [docs/uart-extraction-plan.md](docs/uart-extraction-plan.md))
- **Flash (MTD):** DEVCFG=mtd3, APPSBLENV=mtd7, APPSBL=mtd8, cert=mtd9, **ART=mtd11**, rootfs slots mtd12/mtd14

Full detail: [docs/hardware-reference.md](docs/hardware-reference.md)

## Documents

| File | Purpose |
|---|---|
| [docs/openwrt-porting-plan.md](docs/openwrt-porting-plan.md) | The end-to-end plan: what to extract, translate, build, flash, upstream |
| [docs/uart-extraction-plan.md](docs/uart-extraction-plan.md) | Exact procedure to pull DTB / board data / caldata off a live unit once UART is hooked up |
| [docs/hardware-reference.md](docs/hardware-reference.md) | MTD map, boot chain, u-boot env, serial/MAC facts, recovery notes |

## Related work

- EnGenius field guide (firmware format, cross-flash, EPC adoption): `github.com/ParkWardRR/engenius-field-guide`
- These APs are a real deployed fleet (`*.alpina.casa`); do porting on a **sacrificial unit**, not production.

## Safety / recovery ground rules

- **Back up before touching flash:** mtd7 (env), mtd8 (APPSBL), **mtd11 (ART — calibration + MAC; corruption = real brick)**, plus a pristine stock `.bin`.
- Never hand-rebuild a partial u-boot env. A *valid-but-incomplete* env is worse than an erased one
  (erased → u-boot uses full compiled defaults and still boots).
- Keep one OEM slot intact as your fallback until OpenWrt sysupgrade + failsafe are proven.
