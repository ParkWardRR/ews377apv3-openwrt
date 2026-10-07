# OEM firmware tuning analysis — EnGenius ap-hk07 (IPQ8072A)

Extracted from stock EnGenius firmware DTS files. These are the vendor-tuned
values that the OpenWrt port should match or deliberately differ from.
Last updated 2026-10-06.

Sources:
- `hk07-oem-native-v3.9.3.2.dts` — EWS377AP v3 managed firmware v3.9.3.2
- `hk07-oem-fit-1.1.30.dts` — EWS377-FIT firmware v1.1.30
- `wax218-mainline-25.12.2.dts` — WAX218 mainline (upstream reference)
- Decoded `ecw230v3-1.8.114-1.decoded.bin` — ECW230v3 cloud firmware

## 1. NSS core configuration

### Core 0 (nss@40000000) — data plane

| Property | OEM value | Notes |
|---|---|---|
| `qcom,id` | `0x00` | Primary NSS core |
| `qcom,num-queue` | `0x04` | 4 queues per core |
| `qcom,num-irq` | `0x09` | 9 IRQs |
| `qcom,num-pri` | `0x04` | 4 priority levels |
| `qcom,load-addr` | `0x40000000` | Firmware load address |
| `qcom,low-frequency` | `0x2ca1c800` (750 MHz) | Low-frequency NSS clock |
| `qcom,mid-frequency` | `0x59439000` (1500 MHz) | Mid-frequency NSS clock |
| `qcom,max-frequency` | `0x64b54000` (1690 MHz) | Max NSS clock — **higher than stock AX3600** |

**Offloads enabled on Core 0:**
- `qcom,bridge-enabled`
- `qcom,ipv4-enabled` + `qcom,ipv4-reasm-enabled`
- `qcom,ipv6-enabled` + `qcom,ipv6-reasm-enabled`
- `qcom,pppoe-enabled`
- `qcom,l2tpv2-enabled`
- `qcom,gre-enabled` + `qcom,gre-redir-enabled` + `qcom,gre-redir-mark-enabled`
- `qcom,map-t-enabled`
- `qcom,ppe-enabled`
- `qcom,shaping-enabled` (NSS QoS/SQM)
- `qcom,wlan-dataplane-offload-enabled` (ath11k offload)
- `qcom,vlan-enabled`
- `qcom,igs-enabled`
- `qcom,portid-enabled`

**NOT enabled on Core 0** (handled by Core 1 instead):
- capwap, dtls, crypto, ipsec, qvpn, pvxlan, clmap

### Core 1 (nss@40800000) — crypto/security plane

| Property | OEM value |
|---|---|
| `qcom,id` | `0x01` |
| `qcom,load-addr` | `0x40800000` |

**Offloads enabled on Core 1:**
- `qcom,capwap-enabled`
- `qcom,dtls-enabled`
- `qcom,crypto-enabled`
- `qcom,ipsec-enabled`
- `qcom,qvpn-enabled`
- `qcom,pvxlan-enabled`
- `qcom,clmap-enabled`
- `qcom,rmnet_rx-enabled`

**Implication:** The OEM firmware runs a two-core NSS split — Core 0 handles
data plane (NAT, bridge, PPPoE, Wi-Fi offload), Core 1 handles crypto/security
(IPsec, CAPWAP, DTLS). Our OpenWrt port should activate both cores to match.

### NSS crypto (eip197)

| Property | OEM value |
|---|---|
| `qcom,max-contexts` | `0x40` (64) |
| `qcom,max-context-size` | `0x20` (32 bytes) |
| `crypto_clk` | 600 MHz (`0x23c34600`) |
| `crypto_nocclk` | 600 MHz |
| `crypto_ppeclk` | 300 MHz (`0x11e1a300`) |
| Algorithms | aes128-cbc, aes192-cbc, aes256-cbc, aes-ctr, ccm, gcm, sha1, sha256, sha384, sha512, md5, hmac variants |

## 2. EDMA (ethernet DMA) configuration

| Property | OEM value | Notes |
|---|---|---|
| Base address | `0x3ab00000` | |
| TX descriptor ring start | `0x17` (23) | |
| TX descriptor rings | `0x01` | |
| TX completion ring start | `0x07` | |
| TX completion rings | `0x01` | |
| RX fill ring start | `0x07` | |
| RX fill rings | `0x01` | |
| RX descriptor ring start | `0x0f` (15) | |
| RX descriptor rings | `0x01` | |
| Interrupts | 4 (`0x159`, `0x161`, `0x169`, `0x158`) | |

**Note:** The upstream `qca_edma` driver in the NSS-EDMA fork may use different
ring assignments. Verify these match the EDMA driver's expectations.

## 3. Port topology and PHY mapping

| Port | Port ID | PHY address | Type | Notes |
|---|---|---|---|---|
| port@0 | 1 | `0x00` | GbE | LAN port 1 |
| port@1 | 2 | `0x01` | GbE | LAN port 2 |
| port@2 | 3 | `0x02` | GbE | LAN port 3 |
| port@3 | 4 | `0x03` | GbE | LAN port 4 |
| port@4 | 5 | `0x04` | GbE | LAN port 5 (unused on EWS377) |
| port@5 | 6 | `0x1c` | **QGMAC** | **2.5 GbE uplink** (QCA8081, `2500base-x` via uniphy2) |

The 2.5GbE port uses `port_mac_sel = "QGMAC_PORT"` — this is the critical
differentiator from GbE-only boards.

## 4. Port scheduler / QoS queues

Each port gets dedicated queue ranges for unicast and multicast traffic,
with L0 (strict priority + DRR) and L1 (DRR) scheduling:

| Port | Unicast queues | Multicast queues | L0 SP | L0 CDRR | L1 CDRR |
|---|---|---|---|---|---|
| 0 | `0x00-0x8f` (144) | `0x100-0x10f` (16) | `0x00-0x23` | `0x00-0x2f` | `0x00-0x07` |
| 1 | `0x90-0x9f` (16) | `0x110-0x113` (4) | `0x24-0x27` | `0x30-0x3f` | `0x08-0x0b` |
| 2 | `0xa0-0xaf` (16) | `0x114-0x117` (4) | `0x28-0x2b` | `0x40-0x4f` | `0x0c-0x0f` |
| 3 | `0xb0-0xbf` (16) | `0x118-0x11b` (4) | `0x2c-0x2f` | `0x50-0x5f` | `0x10-0x13` |
| 4 | `0xc0-0xcf` (16) | `0x11c-0x11f` (4) | `0x30-0x33` | `0x60-0x6f` | `0x14-0x17` |
| 5 | `0xd0-0xdf` (16) | `0x120-0x123` (4) | `0x34-0x37` | `0x70-0x7f` | `0x18-0x1b` |
| 6 | `0xe0-0xef` (16) | `0x124-0x127` (4) | `0x38-0x3b` | `0x80-0x8f` | `0x1c-0x1f` |
| 7 | `0xf0-0xff` (16) | `0x128-0x12b` (4) | `0x3c-0x3f` | `0x90-0x9f` | `0x20-0x23` |

**Port 0 has 144 unicast queues** — significantly more than other ports. This
is likely the CPU/NSS-facing port where the extra queue depth matters most.

## 5. WiFi configuration

| Property | Value | Notes |
|---|---|---|
| Compatible | `qcom,cnss-qca8074v2` / `qcom,ipq8074-wifi` | QSDK driver name (mainline uses `ath11k`) |
| `qcom,hw-mode-id` | `0x01` | |
| `qcom,tgt-mem-mode` | `0x00` | Default memory mode |
| `qcom,board_id` | `0x290` | → `bdwlan.b290` board data |
| BDF address | `0x4b400000` (from `bdf-addr`) | WiFi board data load address |
| CalDB address | `0x4ba00000` | Calibration database address |
| TX/RX chainmask | `15` (4×4 on both radios) | Confirmed in device info |

## 6. Thermal management

| Sensor | OEM trip point | Notes |
|---|---|---|
| `cpu-critical-hi` | 125°C (`0x7d`) | Critical high — triggers shutdown |
| `cpu-config-hi` | 110°C | Throttling threshold |
| TSENS sensors | IDs 4, 5, 6, 7 | Multiple thermal zones |
| `polling-delay-passive` | `0x00` | No polling — interrupt-driven |

## 7. Clock tree (ESS/NSS)

The full ESS (Ethernet Switch Subsystem) clock tree from the OEM DTS:

```
cmn_ahb_clk, cmn_sys_clk
├── uniphy0_ahb_clk, uniphy0_sys_clk  (ports 1-4, GbE)
├── uniphy1_ahb_clk, uniphy1_sys_clk  (port 5, unused?)
├── uniphy2_ahb_clk, uniphy2_sys_clk  (port 6, 2.5GbE)
├── nss_ppe_clk, nss_ppe_cfg_clk
├── nss_edma_clk, nss_edma_cfg_clk
├── nss_ppe_ipe_clk, nss_ppe_btq_clk
├── gcc_mdio_ahb_clk, gcc_nss_noc_clk
├── gcc_nssnoc_snoc_clk, gcc_mem_noc_nss_axi_clk
├── gcc_nss_crypto_clk, gcc_nss_imem_clk, gcc_nss_ptp_ref_clk
└── Per-port RX/TX clocks (nss_port1-6_rx/tx_clk)
    └── uniphy0/1/2 port clocks
```

The `nss_edma_clk` and `nss_ppe_clk` are the critical clocks for data plane
performance. The upstream EDMA driver handles these.

## 8. What the upstream NSS-EDMA fork already handles

The JuliusBairaktaris fork (`nss-edma-rework`) includes patches for:
- NSS core DTS nodes (both cores) — `724adfa`, `af548f4`
- Crypto PLL fix — `23b30e6` (ensures crypto clock stability)
- EDMA/PPE shared register safety — `0cfd389`, `072bf7f`, `daaadf7`
- Per-port VSI/FDB for NSS bridge — `e48b986`, `9d5fcc3`, `4dc06d8`
- NSS qdisc kernel patches — `07dc04c`
- ECM kernel patches — `9cd34de`
- ath11k NSS Wi-Fi offload — `982ea10`, `3292f87`, `d6ceaee`
- 802.11s mesh offload — `29302dc`
- NSS runtime tools + LuCI — `bd3ff70`
- Graceful sysupgrade shutdown — `e5cc71f`
- Per-CPU RX processing — `f500b02`

**This means the upstream fork already handles the two-core NSS split,
the EDMA/PPE integration, and the ath11k Wi-Fi offload.** Our port inherits
all of this.

## 9. What needs to be verified / tuned for EWS377

| Item | Current state | Action needed |
|---|---|---|
| NSS core 1 activation | Upstream has DTS nodes; EWS377 DTS may not enable Core 1 | Verify EWS377 DTS has `nss@40800000` node with crypto/CAPWAP offloads |
| NSS clock frequencies | Upstream uses generic values | Confirm `qcom,max-frequency = 0x64b54000` (1690 MHz) is respected |
| EDMA ring assignments | Upstream has its own ring layout | Verify ring start/count match the OEM's `0x17`/`0x07`/`0x0f` pattern |
| Port scheduler queues | OEM uses 144 ucast queues on port 0 | Verify PPE queue allocation matches OEM's scheduler config |
| 2.5GbE QCA8081 | Already in our DTS (`port@6`, `phy_address=0x1c`) | ✅ Done |
| `qcom,wlan-dataplane-offload-enabled` | Needs to be in DTS for NSS Wi-Fi offload | Verify this flag is in the EWS377 DTS |
| `qcom,ppe-enabled` | Needs to be in DTS for PPE offload | Verify this flag is in the EWS377 DTS |
| `qcom,shaping-enabled` | Enables NSS SQM qdiscs | Verify or add to DTS |
| NSS crypto engine | EIP197 at `0x39800000` | Verify crypto DTS node matches OEM |
| Thermal zones | OEM: 125°C critical, 110°C throttling | Verify upstream thermal config is appropriate |
| ath11k firmware version | qosmio bumped to 2.12 | Verify our build uses latest ath11k firmware |

## 10. Newer firmware versions available

| Firmware | Version | Notes |
|---|---|---|
| EWS377AP v3 | v3.9.3.2 (c1.9.51) | Latest managed firmware — already analyzed |
| EWS377-FIT | **v1.1.65-2** | Newer than the v1.1.30 we analyzed — **should decode and diff** |
| ECW230v3 | v1.8.114-1 | Latest cloud firmware — already decoded |
| ECW230S | v1.8.114-1 | Different SKU but same SoC — may have different tunings |
| EWS377-FIT | v1.0.50-2 | Older FIT firmware |

**The FIT v1.1.65-2 firmware is newer than what we've analyzed.** It should be
decoded and diff'd against v1.1.30 to see if there are new NSS or radio tunings.
The Senao header decode requires `mksenaofw` which isn't currently installed.