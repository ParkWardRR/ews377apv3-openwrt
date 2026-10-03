# Senao factory image build recipe

Source: commit `23d5a88` on `openwrt-nss-edma` branch `ews377ap-v3`.

## What this adds

Per-SKU `senao-factory.bin` artifacts that the EnGenius OEM web UIs accept —
standalone, ezMaster, FIT controller, and EnGenius Cloud. Each image carries
the correct Senao header (`vendor_id`, `product_id`, XOR encryption key) so
the OEM's `check_senao_image_header.sh` validator passes.

## Build recipe (ipq807x.mk additions)

Each `Device/engenius_*` block gains a `senao-factory.bin` artifact when
building with initramfs enabled:

```makefile
# EWS377AP v3 (product_id 0x011a, ezMaster / standalone)
ifeq ($(IB),)
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
    ARTIFACTS += senao-factory.bin
    ARTIFACT/senao-factory.bin := append-image initramfs-uImage.itb | \
        ubinize-kernel | qsdk-ipq-factory-nand | \
        senao-header -r 0x0101 -p 0x011a -t 2 -m 783c9ecf67b359ac
endif
endif

# ECW230v3 (product_id 0x011c, EnGenius Cloud)
# Same pipeline, -p 0x011c

# EWS377-FIT (product_id 0x012c, FIT controller)
# Same pipeline, -p 0x012c
```

## Pipeline breakdown

1. `append-image initramfs-uImage.itb` — start with the initramfs FIT image
2. `ubinize-kernel` — wrap in a UBI volume (kernel-only, no rootfs)
3. `qsdk-ipq-factory-nand` — wrap in a QSDK FIT container (same as WAX218)
4. `senao-header` — prepend the Senao firmware header:
   - `-r 0x0101` — vendor_id (Senao/EnGenius)
   - `-p 0x011a` — product_id (per-SKU)
   - `-t 2` — firmware type 2 (kernel), matching all other OpenWrt Senao devices
   - `-m 783c9ecf67b359ac` — 8-byte XOR encryption key (shared across all 3 SKUs)

## DTS overrides

ECW230v3 and EWS377-FIT also gained explicit `DEVICE_DTS` overrides to match
the engenius-prefixed DTS filenames from the shared DTSI refactor:

```makefile
# ECW230v3
DEVICE_DTS := ipq8072-engenius-ecw230v3

# EWS377-FIT
DEVICE_DTS := ipq8072-engenius-ews377-fit
```

EWS377AP v3 doesn't need this — its DTS filename (`ipq8072-ews377ap-v3.dts`)
predates the naming convention and is already correct by convention.

## Artifact state model

The `senao-factory.bin` boots a **temporary initramfs environment**, not a
persistent install. A follow-up `sysupgrade.bin` from within that environment
is required for persistence. This matches the WAX218's documented behavior.

| Step | Artifact | Result |
|---|---|---|
| 1. Upload via OEM web UI | `senao-factory.bin` | Temporary OpenWrt (initramfs) |
| 2. Run sysupgrade from OpenWrt | `sysupgrade.bin` | Persistent OpenWrt on NAND |
