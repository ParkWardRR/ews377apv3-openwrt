# Roadmap — aligning to the WAX218, and covering all three EnGenius `ap-hk07` SKUs

Two goals, one plan: (1) keep this project as close as possible to the officially
mainline-supported **NETGEAR WAX218** — same board, proven recipe, easiest upstream
path — and (2) extend OpenWrt support from just the **EWS377AP v3** to all three
EnGenius SKUs built on this hardware.

### Supported models

| Model | Product ID | Senao Header `model` | Management Mode | Status |
|---|---|---|---|---|
| **EWS377AP v3** | `0x011a` (282) | `EWS377APv3` | Controller-managed (EWS) | **Hardware-proven** |
| **ECW230v3** | `0x011c` (284) | `ECW230v3` | Cloud-managed (ECW) | **DTS-validated** |
| **EWS377-FIT** | `0x012c` (300) | `EWS377-FIT` | Standalone (FIT) | **DTS-validated** |

All three share `vendor_id=0x0101`, identical silicon (IPQ8072A, `ap-hk07`),
identical DTS properties (LEDs, reset GPIO, WiFi board data `0x290`, 2.5G PHY),
and the same `config@hk07` boot contract. They differ **only** in firmware header
fields. See [`reference/model-differences.md`](../reference/model-differences.md).

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
| `upload.cgi` checks the uploaded image's `product_id` against the **running firmware's own identity**, not a request contract or signature — re-heading to match unblocks the full upload → stage → flash-trigger HTTP flow | 2026-09-07 hardware test; see [`reference/method-b-findings.md`](../reference/method-b-findings.md) |
| Full persistence via that HTTP flow is **not yet confirmed on any tested unit** — the one available unit hangs on a reproducible, unit-specific bad NAND block in its spare slot, independent of image format | Same findings doc; tracked as a community-validation item, §4 |

**Net implication:** a shared base DTS (kernel + `ipq8072-ews377ap-v3.dts` +
`config@hk07`) is confirmed sufficient for all three SKUs at the DTS-property level —
LEDs, reset GPIO, WiFi board-id, and the 2.5G PHY wiring are identical (see §4). That is
**not** the same claim as "one build, no per-SKU work" — each SKU still gets its own
OpenWrt `Device/*` profile (§5 Phase 3), and DTS equivalence alone does not prove
identical flash geometry, calibration provenance, regulatory certification, or
sysupgrade behavior across units — those are separate, still-open items (§4).

## 1. Principles — stay as close to the WAX218 as this hardware allows

1. **Same bootloader contract.** `DEVICE_DTS_CONFIG := config@hk07` for every device we
   add — never invent a different config name.
2. **Same install target.** OpenWrt lives on the `rootfs`-labeled partition (slot 0,
   `0x1000000`) — matches both WAX218 and the OEM's own installer.
3. **Same web-artifact construction.** `web-ui-factory.fit` = a kernel-only UBI built
   from the **initramfs** image via `ubinize-kernel | qsdk-ipq-factory-nand` — already
   done for EWS377AP v3 ([`v0.2`](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/releases/tag/v0.2),
   verified structurally identical to the real upstream artifact). This is the one part
   that's **shared across all three SKUs** — see §3.
4. **Same no-UART install method.** SSH + `ubiformat`, mirroring WAX218's documented
   method — already written up as "3b" in [install-and-restore.md](install-and-restore.md),
   not yet hardware-tested on EWS377AP v3 (and not yet on ECW230v3/EWS377-FIT). **Hard
   rule: never hardcode an mtd number.** `/dev/mtd12` is not portable across boards or
   even across firmware generations of the *same* board — always verify the target
   partition live (`cat /proc/mtd`) on the actual unit immediately before writing.
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
artifacts once, so end users on any of the three SKUs get a file their own GUI accepts.

**Update, 2026-09-07 — resolved, and a new finding.** `upload.cgi`'s check turned out
to be a `product_id` match against the **currently-running firmware's own identity**
(not the SKU printed on the case — these units are cross-flashable), not a
request-contract problem. Correctly headed, the full HTTP flow (upload → stage →
flash-trigger) genuinely works. But the resulting boot has not yet persisted on the one
unit tested — a reproducible, unit-specific bad NAND block in the spare slot the OEM
updater always targets, confirmed independent of image format. See
[`reference/method-b-findings.md`](../reference/method-b-findings.md) for the full
trail. §5 Phase 2 is now "get a second unit to confirm persistence," not "crack the
request contract."

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

### Artifact state model — `web-ui-factory.fit` is NOT persistent, and that must be explicit

"Kernel-only UBI" is correct but easy to misread as "the whole install." It isn't. Per
the WAX218's own documented method (which this whole approach mirrors), uploading
`web-ui-factory.fit` boots a **temporary initramfs/recovery OpenWrt environment** — not
a persistent install. A second, separate step (`sysupgrade.bin`, run from inside that
temporary environment via LuCI or CLI) is what actually persists OpenWrt to NAND. A
real WAX218 field report documents exactly the failure mode this ambiguity risks: a
unit that booted the factory image fine, then got stuck permanently returning to
initramfs after a later persistent-flash attempt failed.

| Artifact | Source state | Resulting state | Persistent? | Recovery if it fails here |
|---|---|---|---|---|
| Senao-wrapped `web-ui-factory.fit` | Stock OEM GUI | Temporary initramfs/recovery OpenWrt | **No** | Reboot returns to the stock slot (untouched) or UART/u-boot |
| `initramfs-uImage.itb` | u-boot `bootm` (RAM) | Temporary OpenWrt | **No** | Reboot |
| `squashfs-factory.ubi` | UART/u-boot `nand write`, or SSH+`ubiformat` | Persistent OpenWrt on slot 0 | **Yes, once boot succeeds** | UART + byte-exact backup restore |
| `squashfs-sysupgrade.bin` | Running OpenWrt (any of the above) | New persistent OpenWrt | **Yes** | Standard OpenWrt sysupgrade recovery — **not yet validated on this NAND/partition layout**, see §4 |

Every install writeup (this roadmap, `install-and-restore.md`, any future per-SKU guide)
must state which row an artifact is, not just link the file.

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
- [x] Find the `upload.cgi` rejection cause. **Resolved, 2026-09-07** — it's a
      `product_id`-vs-running-firmware identity check, not a request-contract problem;
      see [`reference/method-b-findings.md`](../reference/method-b-findings.md).
- [ ] **Confirm Method B persistence on a second unit.** The HTTP mechanism is proven;
      the resulting boot has not yet persisted on the one unit available, due to a
      unit-specific bad NAND block, not the mechanism or image. Needs a different unit
      to isolate unit-specific hardware from anything systemic. Tracked publicly —
      **open, community help wanted**: [issue #1](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/issues/1).
- [ ] Hardware-test SSH + `ubiformat` (already documented) on at least one unit before
      calling it proven — currently mirrored from WAX218 but untested on any EnGenius SKU.
      **Still open — needs hardware.** Note: ECW230v3 cloud firmware is confirmed to have
      root SSH on port 8822 and all prerequisites present; the install guide now includes
      ECW230v3-specific MTD layout notes (partition labels are swapped vs. EWS firmware —
      target by offset `0x1000000`, not label). This is the **recommended path for
      ECW230v3 units** over the web upload, because it bypasses the OEM's spare-slot
      targeting and the `product_id` header gate entirely.
- [ ] **Capture the live boot/flash state machine per SKU** — full `/proc/mtd`,
      `ubinfo -a`, `fw_printenv`, and a NAND bad-block map, from a live unit, for every
      state (stock / temporary OpenWrt / persistent OpenWrt / post-sysupgrade). Don't
      infer this from vendor docs or from what worked on the EWS377AP v3 alone — a real
      WAX218 field report shows a unit stuck permanently in initramfs after a failed
      persistent-flash attempt, which is exactly the failure mode this item exists to
      rule out before it's someone else's bricked device. **Still open — needs hardware,
      one SKU at a time (§5 Phase 0/1).**
- [ ] **Radio/regulatory provenance per SKU, not just board-id.** `qcom,board_id=0x290`
      matching on all three (confirmed) is necessary but not sufficient — confirm each
      SKU carries the **same regulatory certification** (the shared FCC ID only
      establishes WAX218 ↔ EWS377AP v3; ECW230v3 and EWS377-FIT are not yet checked),
      and that antenna count/gain and the exact ath11k BDF variant are correct per SKU.
      Upstream guidance is explicit that board-calibration data can be device-specific
      even on shared silicon — don't assume one `ipq-wifi-*` package is legally and
      technically correct for all three without checking. **Still open — needs hardware
      + a compliance/regulatory-domain check per SKU.**

## 5. Phased execution plan

**Phase 1 — Data (no hardware, no risk).** Complete the §4 checklist above using the
real firmware files already available for all three SKUs. Deliverable: a
`reference/model-differences.md` recording confirmed identical-vs-different facts per
SKU, and the exact header fields needed for each wrapped image.

**Phase 2 — Confirm web-upload persistence on a second unit.** Resolved and superseded,
2026-09-07: the request-contract theory was wrong — `upload.cgi` rejects on a
`product_id` mismatch against the running firmware, not the request shape (see §0,
§4, [`reference/method-b-findings.md`](../reference/method-b-findings.md)). Correctly
headed, the HTTP flow works end-to-end and flashes the image, but the resulting boot
hasn't yet persisted on the one unit available — a reproducible bad NAND block in that
unit's spare slot, confirmed independent of image format. What's left is **not**
reverse-engineering, it's **community validation**: someone with a second unit
re-heading the current release image and confirming (or refuting) a clean, persistent
boot. Tracked as [issue #1](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/issues/1).

**Phase 3 — Extend the device recipe: shared base DTS, one profile per SKU.** §4
confirmed the DTS *properties* are identical across all three, so this is recipe-only —
**not** zero per-SKU work. Add `Device/engenius_ecw230v3` and
`Device/engenius_ews377-fit` as their own distinct `Device/*` stanzas (own
`SUPPORTED_DEVICES`/compat identity, own `DEVICE_MODEL`), each including the shared
`ipq8072-ews377ap-v3.dts` (same `DEVICE_DTS_CONFIG := config@hk07`) rather than one
generic multi-SKU device. This matters beyond bookkeeping: OpenWrt's `sysupgrade`
checks on-device board identity against the built profile, and treating three marketed
SKUs as one blurred profile risks exactly the board-name/profile mismatches upstream
has had to fix before. Each pointing at the shared `ipq-wifi-engenius_ews377ap-v3`
board package for now (same `qcom,board_id = 0x290` confirmed on all three) — revisit if
the §4 regulatory/BDF item finds a real per-SKU difference. Build and RAM-boot-test each
on real hardware before any NAND write, same gating this project has used throughout —
a shared DTS is a strong prior, not a substitute for testing.

**Phase 4 — Build & wrap three release images.** Automate: one shared kernel-only UBI
build (§3), then three `mksenaofw`-wrapped artifacts using the confirmed per-SKU header
fields from Phase 1. Publish as a single multi-SKU release (or three release assets in
one tag) on this repo, each named after its SKU, each with its own `SHA256SUMS` line.
**Include negative tests**, not just positive ones: confirm an EWS377AP v3-wrapped image
is *rejected* by ECW230v3's and EWS377-FIT's own GUIs (and vice versa), and that a
malformed header / correct header with a corrupted payload fails safely. Otherwise "all
three wrappers work" could actually mean the validator accepts anything — the same
failure mode as the argument-validation issue already found on EWS377AP v3.

**Phase 5 — Hardware validation, one SKU at a time.** For each SKU: UART/u-boot install
first (proven method, safety net always present) → capture the live boot/flash state
machine (§4) → SSH+`ubiformat` test → a `sysupgrade` round-trip (config-preserving) →
only once all of that is solid, attempt the web-upload path (gated on Phase 2's fix).
Never skip straight to the web-upload path on a new SKU. Minimum per-SKU checks before
calling a SKU "done": board identity (`ubus call system board`, compat string, MAC
source), both radios up with client association, 2.5G link, an interrupted-flash /
wrong-model-wrapper rejection test, and a documented UART recovery path specific to that
SKU (not just "inherited from the WAX218 docs"). Full soak/thermal/regulatory-lab
testing is out of scope for a hobby-scale port — treat it as a "nice to have if a tester
has the equipment," not a gate.

**Phase 6 — Docs + upstreaming.** Fold per-SKU install steps into
[install-and-restore.md](install-and-restore.md) (one guide, SKU-select at the top,
not three separate documents). Extend `UPSTREAMING-PLAN.md` (currently EWS377AP v3-only)
to cover whichever SKUs are validated, following the exact WAX218 PR shape. Before
submitting: build and boot-test against **current upstream `main`**, not just the
`openwrt-nss-edma` fork (NSS/EDMA patches can hide a dependency mainline reviewers can't
reproduce); set `SUPPORTED_DEVICES`/`DEVICE_COMPAT_VERSION` correctly per SKU; pin the
OpenWrt commit, toolchain, and vendor-firmware-input hashes used to build each release
(`SHA256SUMS` already done — extend to a short manifest); confirm the `ipq-wifi-*`
board-data package's source/redistribution terms are acceptable for a mainline
submission, not just a downstream fork.

## 6. Interactive TUI — Zig terminal dashboard

A terminal UI for guided installs, live device status, and NAND health checks,
built in Zig — zero runtime dependencies, single static binary, direct ANSI
terminal control.

**Design pillars:**

- **Tokyo Night palette** — dark background (`#1a1b26`), muted foreground
  (`#a9b1d6`), accent blue (`#7aa2f7`), accent magenta (`#bb9af7`), green
  (`#9ece6a`), red (`#f7768e`), orange (`#ff9e64`), cyan (`#7dcfff`).
- **Neon shimmer wordmark** — animated gradient title using the accent spectrum,
  subtle glow effect on the project name at launch.
- **Apple HIG-informed layout** — adapted for a terminal context:
  - **Visual hierarchy:** bold/color for primary, muted for secondary, dim for
    tertiary. No gratuitous color — every hue carries meaning.
  - **Progressive disclosure:** top-level dashboard → drill into install guides,
    device details, or validation status.
  - **Spatial consistency:** fixed gutter, aligned columns, predictable padding.
  - **Feedback:** spinner/progress for async ops, inline status badges, clear
    error states with actionable next steps.
  - **Navigation:** vim-style (`j`/`k`/`h`/`l`) + arrows + tab, breadcrumb
    trail showing current depth.
  - **Accessibility:** WCAG-informed contrast (Tokyo Night already passes on
    dark terminals), no information conveyed by color alone.

**TUI views (initial scope):**

| View | Purpose |
|---|---|
| Dashboard | SKU status matrix (EWS377AP v3 / ECW230v3 / EWS377-FIT), install method readiness, release info |
| Install Guide | Interactive walk-through of the three install paths (UART, SSH, web), with live safety checks |
| Device Info | Hardware reference card — SoC, RAM, NAND, radios, GPIOs, MTD map |
| Validation | §4 checklist rendered live — what's proven, what's open, what needs hardware |
| Releases | Current release artifacts, SHA256 sums, artifact state model (persistent vs. temporary) |

**Phasing:** the TUI ships alongside the firmware — it is a companion tool, not a
gate. Phase 1 (static views, no device interaction) ships first; Phase 2 (live
SSH-based device queries, NAND health reads) follows once the install paths are
hardware-proven.

## 7. Legal / licensing — open, not resolved

Flagging honestly rather than ignoring: this project decodes and repackages vendor FIT
images (Qualcomm QSDK-derived, via EnGenius/NETGEAR) and redistributes derived
artifacts (wrapped web images, board-data files). Two questions are **not yet
answered** and should be before any wider release or an upstream PR:

- **GPL/QSDK compliance of redistributed artifacts.** Confirm the release images don't
  ship non-redistributable Qualcomm binaries verbatim (the same question OpenWrt itself
  navigates for IPQ807x — NSS, WiFi firmware, `board-2.bin`/caldata). Where a blob isn't
  clearly redistributable, keep it a build-time input the user supplies (as
  `pelegrun-ap-hk07-firmware-tools`'s scope note already does for OEM images), not a
  shipped release asset.
- **EnGenius's own terms on cross-SKU flashing.** SKU differentiation (EWS377AP v3 vs.
  ECW230v3 vs. EWS377-FIT) may be tied to EnGenius Cloud subscription features or other
  licensing terms, separate from the pure hardware question. Not a blocker for
  personal/research use on hardware you own, but worth knowing before recommending it
  broadly.

## 8. Non-negotiables (carried over from the rest of this repo)

- Never write the ART partition or the bootloader region (`0x0`–`0x1000000`) on any SKU.
- Every new SKU gets its own byte-exact stock backup before any NAND write.
- RAM-boot (initramfs, nothing written) is the default first test on any new unit.
- No open Wi-Fi SSIDs during testing; tear down test networks after use.
- Keep a UART safety net attached for every install method until that method is proven
  on that specific SKU — proven on one SKU does not mean proven on another.
- Never hardcode an MTD number in a command or a doc — always verify live on the actual
  unit first (§1, principle 4).
- A "web-ui-factory.fit boots" result is not "OpenWrt is installed" — persistence
  requires the follow-up `sysupgrade` step (§3 artifact table). Don't conflate the two
  in any writeup.
