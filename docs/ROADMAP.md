# Roadmap — aligning to the WAX218, and covering all three EnGenius `ap-hk07` SKUs

Two goals, one plan: (1) keep this project as close as possible to the officially
mainline-supported **NETGEAR WAX218** — same board, proven recipe, easiest upstream
path — and (2) extend OpenWrt support from just the **EWS377AP v3** to all three
EnGenius SKUs built on this hardware: **EWS377AP v3**, **ECW230v3**, and
**EWS377-FIT**.

## 0. Validated foundation (checked against real firmware, 2026-09-07)

These are not assumptions — each was confirmed by decoding real vendor firmware files
and the real upstream WAX218 build:

| Fact | Evidence |
|---|---|
| WAX218, EWS377AP v3, ECW230v3, EWS377-FIT are the **same silicon** (`ap-hk07` / IPQ8072A) | Shared FCC ID (WAX218 ↔ EWS377AP v3); [wax218-equivalence.md](wax218-equivalence.md) |
| All three EnGenius SKUs' own stock kernel images contain **`config@hk07` / `fdt@hk07`** | Decoded `EWS377APv3-v3.9.3.2_c1.9.51.bin`, `Cloud6_4x4_ECW230v3_firmware_v1.8.114-1.bin`, `ews377-fit-1.1.30-13.bin` — each carries `config@hk07`/`fdt@hk07` in its kernel FIT (ECW230v3 and EWS377-FIT ship it inside a larger multi-board QSDK bundle covering many `hk0X` reference designs; EnGenius builds one shared kernel per SDK release and each device auto-selects its own config) |
| WAX218's official `bootipq` needs the FIT config named after the board (`config@hk07`) — mainline sets this via `DEVICE_DTS_CONFIG` | Upstream commit [`7801161c`](https://github.com/openwrt/openwrt/commit/7801161c4bb2413817b3dfd01695050e2da27bf3); reproduced independently on our EWS377AP v3 hardware |
| Each SKU is differentiated **only by its Senao/capwap firmware header**, not by different silicon | vendor `0x0101` shared by all; `product_id` EWS377AP v3=`0x011a`(282), ECW230v3=`0x011c`(284), EWS377-FIT=`0x012c`(300); capwap `model` field = `"EWS377APv3"` / `"ECW230v3"` / `"EWS377-FIT"` respectively |
| The stock web updater (`upload.cgi`) validates **that header** before flashing — this is *why* Pelegrún's cross-flash tool works by re-heading exactly this field | see [`pelegrun-ap-hk07-firmware-tools`](https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools) |
| The EWS377AP v3's `upload.cgi` currently rejects **any** upload at argument validation, before content is read | 2026-09-07 hardware test, see [install-and-restore.md](install-and-restore.md) status box |

**Net implication:** one OpenWrt build (kernel + `ipq8072-ews377ap-v3.dts` + `config@hk07`)
is very likely enough for all three SKUs — the differentiation work is almost entirely
in the **outer vendor header**, not the OS. The open question is whether each SKU's
physical LEDs/antennas/board-id variant differ enough to need their own DTS entry —
not yet validated (see §4).

## 1. Principles — stay as close to the WAX218 as this hardware allows

1. **Same bootloader contract.** `DEVICE_DTS_CONFIG := config@hk07` for every device we
   add — never invent a different config name.
2. **Same install target.** OpenWrt lives on the `rootfs`-labeled partition (slot 0,
   `0x1000000`) — matches both WAX218 and the OEM's own installer.
3. **Same web-artifact construction.** `web-ui-factory.fit` = a kernel-only UBI built
   from the **initramfs** image via `ubinize-kernel | qsdk-ipq-factory-nand` — already
   done for EWS377AP v3 ([`v0.2`](https://github.com/ParkWardRR/ews377apv3-openwrt/releases/tag/v0.2),
   verified structurally identical to the real upstream artifact). This is the one part
   that's **shared across all three SKUs** — see §3.
4. **Same no-UART install method.** SSH + `ubiformat`, mirroring WAX218's documented
   method — already written up as "3b" in [install-and-restore.md](install-and-restore.md),
   not yet hardware-tested on EWS377AP v3 (and not yet on ECW230v3/EWS377-FIT).
5. **Prefer upstream idioms over inventing our own.** When something WAX218 already
   solved (LED triggers, caldata extraction, env geometry) applies unchanged, copy it
   verbatim; when it doesn't apply (WAX218's 3-LED shift register vs. our single RGB
   LED), say so explicitly rather than force a fit.
6. **The long game is a mainline PR**, following the exact WAX218 precedent. Every
   fork-only shortcut we take now is tracked as a thing to strip before that PR (see the
   `UPSTREAMING-PLAN.md` on the `openwrt-nss-edma` fork).

## 2. Why three images, not one, for the web-upload path

Unlike the SSH/UART paths (which write raw NAND and don't care about vendor headers),
the **web-upload / one-click path is gated by each SKU's own stock GUI**, which
validates its own vendor/product header before accepting a file. A single generic
image will be rejected by all three GUIs. So the web-upload path needs:

- **One shared OpenWrt payload** (the kernel-only UBI, WAX218-style, built once).
- **Three different outer wrappers**, one per SKU, each carrying that SKU's own
  `vendor_id=0x0101` / `product_id` / capwap `model` string so its own `upload.cgi`
  recognizes the file as "its own" firmware.

This is exactly the header Pelegrún's `quarry rehead` tool already knows how to write —
the build-side work is to bake the right header into each of the three release
artifacts once, so end users on any of the three SKUs get a file their own GUI accepts
(once the deeper `upload.cgi` argument-validation blocker, below, is also solved).

**Important, and not yet solved by this alone:** the EWS377AP v3's `upload.cgi`
currently rejects uploads at the **request/argument** level, before it ever reads the
header — see the status box in [install-and-restore.md](install-and-restore.md). Correct
per-model headers are **necessary but not sufficient**; the request-contract issue must
be cracked (or found to differ per SKU/firmware train) independently, per §5 Phase 2.

## 3. Build plan — one payload, three wrapped artifacts

```
                 ┌─────────────────────────────┐
                 │  openwrt-nss-edma, branch    │
                 │  ews377ap-v3 (config@hk07)   │
                 └──────────────┬────────────────┘
                                │  make (kernel+DTS, shared)
                                ▼
                 initramfs-uImage.itb  (one build)
                                │
                                │  ubinize-kernel | qsdk-ipq-factory-nand
                                ▼
                    kernel-only UBI in a QSDK FIT   (one build, WAX218-style)
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
      senao-header       senao-header       senao-header
      vendor=0x0101      vendor=0x0101      vendor=0x0101
      product=0x011a     product=0x011c     product=0x012c
      model=EWS377APv3   model=ECW230v3     model=EWS377-FIT
              │                 │                 │
              ▼                 ▼                 ▼
   web-ui-factory-      web-ui-factory-      web-ui-factory-
   ews377apv3.bin        ecw230v3.bin        ews377fit.bin
```

The `squashfs-factory.ubi` / `sysupgrade.bin` / `initramfs-uImage.itb` artifacts stay
**one build for all three** (same silicon, same DTS) — only the Senao-wrapped web
artifact needs per-SKU variants, and only because of *EnGenius's* validator, not
OpenWrt's.

## 4. Open validation items (do before shipping per-model images)

- [x] **Decompile ECW230v3's and EWS377-FIT's own `fdt@hk07`** and diff against the
      EWS377AP v3 DTS. **Done, 2026-09-07 — see [`reference/model-differences.md`](../reference/model-differences.md).**
      Result: reset GPIO 52, LED GPIOs 54/55/56, WiFi `qcom,board_id = 0x290`, and the
      2.5G PHY (`port_id=6`/`phy_address=0x1c`) are **identical across all three SKUs**.
      Only the `compatible` string differs, cosmetically (SDK-generation naming drift —
      ECW230v3's stock firmware kernel is a 2023 build, the other two are 2026 builds).
      **One shared DTS/device-profile is sufficient for all three** — no per-SKU DTS
      fork needed; §5 Phase 3 is simplified accordingly (recipe-only, no new DTS work).
- [x] Confirm each SKU's own **WiFi board-id / calibration variant**. **Done** — `0x290`
      confirmed identical on all three via their own `fdt@hk07` (not just EWS377AP v3 and
      ECW230v3 as before; EWS377-FIT now confirmed too). `bdwlan.b290` in
      `reference/wifi-board-data/` should cover all three.
- [x] Extract each SKU's real capwap `firmware_ver`/`datecode` conventions. **Done** —
      recorded in [`reference/model-differences.md`](../reference/model-differences.md)
      for use when building each SKU's wrapped header.
- [ ] Test whether the `upload.cgi` argument-validation blocker (§2) is EWS377AP v3-
      specific or common across all three GUIs — needs a live test per SKU once the
      root cause is found. **Still open — needs hardware.**
- [ ] Hardware-test SSH + `ubiformat` (already documented) on at least one unit before
      calling it proven — currently mirrored from WAX218 but untested on any EnGenius SKU.
      **Still open — needs hardware.**

## 5. Phased execution plan

**Phase 1 — Data (no hardware, no risk).** Complete the §4 checklist above using the
real firmware files already available for all three SKUs. Deliverable: a
`reference/model-differences.md` recording confirmed identical-vs-different facts per
SKU, and the exact header fields needed for each wrapped image.

**Phase 2 — Crack the web-upload request contract.** Independent of Phase 1: drive the
*real* EnGenius GUI (not a replayed API call) in a headless browser to capture the
actual `upload.cgi` request, since the current blocker is the request itself, not image
content. Do this once against EWS377AP v3 first (unit already available); re-test
against ECW230v3/EWS377-FIT only once the pattern is understood, since it may be
firmware-train-specific.

**Phase 3 — Extend the device recipe.** §4 confirmed one DTS covers all three SKUs, so
this is recipe-only: add `Device/engenius_ecw230v3` and `Device/engenius_ews377-fit`
entries reusing `ipq8072-ews377ap-v3.dts` as-is (same `DEVICE_DTS_CONFIG :=
config@hk07`), each pointing at the shared `ipq-wifi-engenius_ews377ap-v3` board
package (same `qcom,board_id = 0x290` confirmed on all three — no new board-2.bin
needed unless RF testing on the other two SKUs later says otherwise). Build and
RAM-boot-test each on real hardware before any NAND write, same gating this project has
used throughout — a shared DTS is a strong prior, not a substitute for testing.

**Phase 4 — Build & wrap three release images.** Automate: one shared kernel-only UBI
build (§3), then three `mksenaofw`-wrapped artifacts using the confirmed per-SKU header
fields from Phase 1. Publish as a single multi-SKU release (or three release assets in
one tag) on this repo, each named after its SKU, each with its own `SHA256SUMS` line.

**Phase 5 — Hardware validation, one SKU at a time.** For each SKU: UART/u-boot install
first (proven method, safety net always present) → SSH+`ubiformat` test → only once
both are solid, attempt the web-upload path (gated on Phase 2's fix). Never skip
straight to the web-upload path on a new SKU.

**Phase 6 — Docs + upstreaming.** Fold per-SKU install steps into
[install-and-restore.md](install-and-restore.md) (one guide, SKU-select at the top,
not three separate documents). Extend `UPSTREAMING-PLAN.md` (currently EWS377AP v3-only)
to cover whichever SKUs are validated, following the exact WAX218 PR shape.

## 6. Non-negotiables (carried over from the rest of this repo)

- Never write the ART partition or the bootloader region (`0x0`–`0x1000000`) on any SKU.
- Every new SKU gets its own byte-exact stock backup before any NAND write.
- RAM-boot (initramfs, nothing written) is the default first test on any new unit.
- No open Wi-Fi SSIDs during testing; tear down test networks after use.
- Keep a UART safety net attached for every install method until that method is proven
  on that specific SKU — proven on one SKU does not mean proven on another.
