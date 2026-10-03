# Method B (OEM web updater) — findings, 2026-09-07

Full investigation trail for the one-click web-upload install path. Net result: **the
HTTP mechanism is now proven to work end-to-end** — a real, reusable technique — but
full persistence validation is currently blocked on the one test unit available, by a
hardware issue unrelated to the mechanism or image format. Documented here in detail so
someone with a second unit can pick up exactly where this left off. See
[GitHub issue #1 tracking community validation](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/issues/1).

## 1. The original "argument validation" rejection — resolved

Earlier testing found the stock `upload.cgi` rejecting every upload identically —
a 4 KB garbage file and the real 15 MB image both got `400
INVALID VALUE OF ARGUMENTS:firmware`, with `image_size` staying `0`. That looked like a
request-contract problem (wrong auth surface, wrong multipart field). It wasn't.

Byte-for-byte replicating the real GUI's request (correct port, correct Bearer token
source, correct multipart field name/content-type, matching the JS bundle exactly)
still failed identically. Isolating auth from content confirmed the rejection happens
at the **same validation stage** regardless of whether the auth token is even valid —
ruling out an auth-surface mismatch.

**Actual root cause: `upload.cgi` checks the uploaded image's `product_id` against the
*running* firmware's own identity**, and rejects anything that doesn't match — before
even comparing file sizes, hence "garbage vs. real image" looking identical. The test
unit was running the ECW230v3-cloud SKU (`product_id 284`), not EWS377AP v3
(`product_id 282`) that the test image was headed for.

## 2. The fix — and proof the HTTP mechanism genuinely works

Re-heading the image to the correct `product_id` (matching whatever SKU firmware is
*currently running* on the target unit — not necessarily the SKU printed on the case,
since these devices are cross-flashable) unblocks it completely:

```
POST /cgi-bin/upload.cgi          → 200 (was 400) — accepted, staged, checksum populated
POST /api/mgm/fw_upgrade {"mode":"Upgrade_locally"}  → 200 — genuinely flashes and reboots
```

The device rebooted into the OpenWrt kernel. **This confirms the web-upload path is a
real, working install mechanism — no UART needed for the upload/trigger.**

## 3. The OEM's actual upgrade mechanism — a proper A/B updater

Watching the console during the write revealed something not previously documented:
this live path is **not** the same as the standalone `flash.scr` bootscript decoded
earlier from a static `.bin` file (which does a plain single-slot `nand write`). The
device's own upgrade agent uses a "Senao dual image" mechanism instead:

```
senao dual image: change active partition from 0 to 1
[erase + write mtd7 — the u-boot env partition]
senao dual image upgrade, save conf to the alternative partion: rootfs_1
```

This writes the **inactive** slot, then flips `active_fw` via a **single targeted env
field update** — the same safe pattern this whole project follows everywhere else, not
a wholesale env rebuild. Worth documenting because it means the OEM's own live upgrade
path is architecturally more like a proper A/B updater than the static-file installer
we'd reverse-engineered — a positive finding, and consistent with normal safe operation
of this device's env partition.

## 4. The boot hang — and why it's not an image-format problem

The first flash used `web-ui-factory.bin`/`.fit` (the WAX218-style kernel-only UBI).
The resulting boot hung: `ubi_io_read: error -74 (ECC error)` on **PEB 709**, stalled
permanently (confirmed via a sustained no-output check, not just a slow boot).

The working theory at the time was that `web-ui-factory.fit` is a RAM-boot-oriented
artifact, not meant to be written directly and expected to persist (true, and now
documented in [`ROADMAP.md`](../docs/ROADMAP.md) and
[`install-and-restore.md`](../docs/install-and-restore.md) — see the artifact-state
table). So the natural next test was the **full 3-volume UBI** (`squashfs-factory.ubi`
— the exact same bytes already proven bootable and persistent via UART, containing
`kernel`/`rootfs`/`rootfs_data`), Senao-wrapped with the correct `product_id` and
headed with the SKU's real capwap fields.

**That also hung — at the identical PEB (709), the identical error, the identical stall
point.** Same failure, different payload. That rules out "wrong image type" as the
(sole) explanation: a genuinely different image landing on the exact same failure
signature points to something **PEB-709-specific**, not payload-specific.

## 5. Conclusion: a real, reproducible bad/marginal NAND block, not a mechanism or image problem

PEB 709 sits within the spare slot (`rootfs_1`) that the OEM's dual-image mechanism
always targets for safety. It is **not** in the factory-registered bad-block table —
if it were, both the OEM's own writer and u-boot's `nand write` should skip it the same
way `nand write` has cleanly skipped the *one* factory-registered bad block in the
*other* slot (`rootfs`) across dozens of writes this project. The OEM's UBI-based
dual-image writer apparently does not detect/route around this PEB the way u-boot's raw
`nand write` does.

**Net status:**
- ✅ Method B's HTTP mechanism (upload → stage → trigger → flash) is proven correct and
  reusable, once the image is headed with the correct `product_id`.
- ❌ Full persistence validation is blocked **on this specific test unit**, by a
  reproducible hardware defect in its spare slot — not something a different image or
  a different request would fix.
- The unit was fully recovered via the already-proven UART restore procedure after each
  attempt; nothing was left in a broken state.

## What's needed to close this out

Someone with **a second EWS377AP v3 / ECW230v3 / EWS377-FIT unit** (ideally one whose
spare slot doesn't have this specific wear pattern) repeating steps 1–2 above:
re-head the correctly-built `squashfs-factory.ubi` (see
[Releases](https://github.com/ParkWardRR/openwrt-engenius-ews377ap-v3-ecw230v3-ews377-fit-ipq8072a-ap-hk07/releases)) to that unit's
own running `product_id`, upload via the stock GUI, and confirm it boots to a shell and
survives a reboot. If it does, Method B flips to fully proven for that SKU/unit
combination and the docs' status marker updates accordingly. Please report back either
way — a second data point that also hangs (even at a different PEB) would suggest
something more systemic in the OEM's dual-image writer worth investigating further.
