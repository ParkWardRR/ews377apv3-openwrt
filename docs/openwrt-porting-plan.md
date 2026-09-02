# OpenWrt porting plan — EWS377AP v3 (`ap-hk07`, IPQ807x)

End-to-end plan to bring mainline OpenWrt to the EnGenius EWS377AP v3. Ordered so that the
**go/no-go decision (secure boot)** and the **non-destructive proof (TFTP initramfs)** come before
anything writes to flash.

---

## Firmware targets

We track three distinct firmware targets, in ascending order of ambition. The board port
(Phases 0–4) is shared; the targets diverge at packaging/config.

| Target | What it is | Purpose |
|---|---|---|
| **A — OEM EnGenius QSDK image** | Stock firmware (QSDK OpenWrt) | Baseline: maximum known-good AP throughput; the number to beat |
| **B — OpenWrt upstream/mainline** | Clean `qualcommax` port, ath11k, ipqess | Upstreamability, clean kernel/drivers, functional correctness |
| **C — OpenWrt NSS-EDMA experimental** | Mainline-style port **plus Qualcomm NSS offload** via the community NSS-EDMA fork/feed | Performance: recover most of the QSDK forwarding throughput while keeping a mainline-shaped board port |

**Do B first.** C builds on B's device tree and board files — it's the same port with an
accelerated Ethernet/PPE stack and NSS-backed forwarding layered on. Don't chase C until B boots,
calibrates WiFi, and passes traffic.

See **[Phase 7 — Target C: NSS-EDMA](#phase-7--target-c-nss-edma-experimental-performance)** for the
accelerated route and its EWS377-specific validation gates.

---

## Phase 0 — Go/no-go: is secure boot fused?

This single question decides whether the whole effort is possible.

- If the IPQ807x OEM secure-boot / anti-rollback fuse is **blown**, u-boot only runs
  vendor-signed kernels → you'd need EnGenius's private key → **stop, not feasible**.
- If **not blown**, unsigned OpenWrt boots freely.

**Signal we already have:** stock `bootcmd=bootipq` loads a FIT that is only **MD5/CRC-checked in
userspace** (`check_senao_image_header.sh` gates on `product_id`, not a hardware signature). That
strongly implies **no hardware root-of-trust is enforced** — but confirm at the u-boot prompt:

```
# at u-boot over UART (J2, 115200 8N1):
printenv                      # look for secure_boot / sec_auth flags
# dump the security fuse region (QFPROM) if the u-boot build exposes it, or simply:
tftpboot 0x44000000 openwrt-initramfs.itb
bootm 0x44000000              # if an unsigned FIT boots, secure boot is NOT enforced
```

**Deliverable:** a one-line verdict — fused or not.

---

## Phase 1 — Harvest the hardware description (no flashing)

Everything here comes from the **stock QSDK-OpenWrt firmware** and/or a live unit. This is the big
shortcut: we translate EnGenius's downstream sources instead of reverse-engineering the board.

### 1a. From the firmware image (already have de-obfuscated FITs locally)

```
# de-obfuscate senao → FIT (already done: mksenaofw -d fw.bin -o dec.bin)
dumpimage -l dec.bin                       # lists ubi-root + wififw sub-images
dumpimage -T flat_dt -p 1 -o root.ubi dec.bin
# unpack ubi → ubifs → rootfs, then pull:
#   the DTB (appended to the kernel volume / in /boot)
#   /lib/firmware/IPQ8074/*  (board-2.bin, bdwlan*, regdb)
dtc -I dtb -O dts -o hk07-oem.dts <extracted>.dtb   # decompile to readable source
```

### 1b. From a live unit (when a shelled AP is available — see UART plan)

```
cat /proc/mtd
cp /sys/firmware/fdt /tmp/hk07.dtb
tar czf /tmp/wifi-fw.tgz /lib/firmware/IPQ8074
ls /sys/class/leds /sys/class/gpio
ssdk_sh sw dump          # ethernet/switch topology (or swconfig show)
cat /etc/config/*        # uci: network/wireless/system → PHY addrs, port roles
```

**Deliverable:** `hk07-oem.dts` (decompiled), the OEM `/lib/firmware/IPQ8074` tree, and the uci/switch
dumps checked into this repo under `artifacts/`.

---

## Phase 2 — Non-destructive bring-up

Prove the SoC/DDR/console under OpenWrt **without writing flash**.

1. Build (or grab) an OpenWrt **initramfs** `.itb` for the closest in-tree IPQ8074 4×4 profile.
2. `tftpboot` it into RAM and `bootm`. OEM slots stay untouched → instant recovery by power-cycle.
3. Confirm: serial console, ethernet link, `dmesg` clean, ath11k probes (even if RF not yet tuned).

**Deliverable:** an OpenWrt shell over UART with the OEM firmware still intact on flash.

---

## Phase 3 — Device tree for `ap-hk07`

Fork the closest in-tree IPQ8074 4×4 DTS and port using `hk07-oem.dts` as the map of truth:

- **Partitions:** transcribe from `/proc/mtd` / OEM DTS (DEVCFG/APPSBLENV/APPSBL/cert/ART/rootfs A/B).
- **Ethernet:** re-express QSDK `ess-switch`/`edma` as mainline `ipqess` + `qca8075`/`qca807x` PHY;
  copy PHY addresses and the uplink port role from the OEM DTS.
- **LEDs + button:** map `gpio-leds` / `gpio-keys` GPIO numbers + active-high/low straight across.
- **Pre-cal:** point ath11k at **ART (mtd11)** so it reads per-device RF calibration.

**Deliverable:** `ap-hk07.dts` that compiles and boots to a working console + ethernet.

---

## Phase 4 — WiFi (the fiddly one)

Stock uses QSDK `qca-wifi`/QSDK-ath11k; mainline uses **ath11k**. The RF ingredients are in the OEM
`/lib/firmware/IPQ8074`, but mainline ath11k looks up a board file by a **board-ID string** from SMEM.

1. Extract OEM `bdwlan*` / caldata + note the board-ID the OEM build uses.
2. Either find a matching board-ID already in upstream `ath11k-firmware`, **or** repackage the OEM bdf
   into a mainline `board-2.bin` with the correct ID.
3. Verify per-device caldata handoff from ART; confirm TX power / reg-domain look sane.

**Deliverable:** both radios calibrate and pass traffic at expected power.

---

## Phase 5 — Image packaging + install path

Two viable install routes; pick per how secure boot landed:

- **Senao header route:** OpenWrt `firmware-utils` already ships `mksenaofw`. Build a Senao-wrapped
  sysupgrade image (`product_id` matching the target slot) and flash via the OEM updater / one A/B slot.
  The OEM's userspace `check_senao_image_header.sh` only gates on vendor_id+product_id.
- **u-boot route:** after the initramfs boots, write OpenWrt sysupgrade directly to a slot from u-boot.

**Deliverable:** repeatable flash + a documented rollback to stock.

---

## Phase 6 — Finish + upstream

- Add the board profile; test WiFi / eth / LEDs / buttons / **sysupgrade** / **failsafe** / dual-boot.
- Write the commit + device page; open a PR to OpenWrt (`qualcommax` target).
- Keep the OEM slot recovery path documented for anyone flashing back.

---

## Phase 7 — Target C: NSS-EDMA (experimental performance)

Mainline OpenWrt on IPQ807x runs the Ethernet/PPE path on the host CPU with **no NSS hardware
offload** (that's a QSDK-only feature), so forwarding throughput sits well below the OEM baseline.
The viable workaround is the actively maintained community **NSS-EDMA** OpenWrt fork/feed: it drives
the Qualcomm **NSS** offload while keeping an upstream-oriented Qualcomm **EDMA/PPE** stack on
IPQ807x. Its stated scope includes **NAT, PPPoE, SQM, multicast, bridge, and ath11k Wi-Fi offload** —
materially closer to the QSDK performance model than stock mainline.

> **Reality check on the numbers.** The fork has been validated on **Xiaomi AX3600 / IPQ8071A**, *not*
> on the EWS377AP v3. Its reported results (NSS ECM NAT/PPPoE offload, NSS SQM at dramatically lower
> host CPU) are **AX3600 figures, not an EWS377 benchmark** — do not represent them as such. The
> EWS377's IPQ8072A-class part is close enough that the NSS block is a *plausible* target, but every
> EWS377-specific piece below must be independently validated.

### Prerequisites

- Target B (Phases 0–6) working: `ap-hk07.dts` boots, ath11k calibrates, sysupgrade + failsafe proven.
- A sacrificial unit with the OEM slot still intact for rollback.

### Build

- Add the NSS-EDMA feed/fork on top of the same board port (reuse `ap-hk07.dts` + the extracted BDF).
- Enable the NSS firmware/driver packages and the EDMA/PPE + ECM offload for the IPQ807x target.
- Produce it as a **separate image**, flashed to a **non-OEM slot**, never over the last known-good.

### EWS377-specific validation gates (each must pass on real hardware)

1. **NSS firmware brings up** on the EWS377's exact IPQ8072A revision — NSS cores load, no firmware
   mismatch, `dmesg` clean.
2. **EDMA/PPE binds to this board's Ethernet** — the port topology from the OEM DTS (PHY addrs, uplink
   role) works under the EDMA driver, link + traffic confirmed.
3. **ECM offload actually engages** — NAT/PPPoE/bridge flows show accelerated (offloaded) connections,
   not silent host-path fallback. Verify host CPU drops under load.
4. **ath11k Wi-Fi offload** interoperates with the extracted `board-2.bin`/caldata — no regression vs.
   Target B WiFi, TX power/reg-domain still sane.
5. **SQM under NSS** behaves (if used) — shaping accurate, no offload-vs-shaper conflict.
6. **Stability under sustained load + thermals** — NSS paths don't wedge; watchdog/failsafe still work.

### Decision rule

Keep Target C **experimental** until gates 1–4 pass on the EWS377 itself. If NSS won't bind cleanly to
this board's Ethernet or radios, fall back to Target B (correct but slower) rather than shipping an
unvalidated offload path. Record actual EWS377 measurements in `benchmarks/` — never reuse AX3600
figures as a stand-in.

---

## Effort / risk summary

| Phase | Effort | Risk |
|---|---|---|
| 0 Secure boot check | low | **project-ending if fused** |
| 1 Harvest | low | none (read-only) |
| 2 TFTP bring-up | low | none (RAM only) |
| 3 Device tree | medium | low (recoverable) |
| 4 WiFi/BDF | **medium–high** | low (recoverable) |
| 5 Packaging/install | medium | medium (flash writes) |
| 6 Upstream | medium | none |
| 7 Target C (NSS-EDMA) | **high** | medium (experimental; may not bind to this board — fall back to B) |

Realistic total for someone comfortable with OpenWrt device porting: **a few focused weekends** if
secure boot is open and a usable BDF is obtainable.

## Biggest shortcut

Before writing `ap-hk07.dts`, check the current OpenWrt tree for an **already-supported IPQ8072A 4×4
sibling** (EnGenius / Edgecore / Cambium share reference designs). An existing `.dts` + working
`board-2.bin` collapses most of Phases 3–4 into copy-and-adjust.
