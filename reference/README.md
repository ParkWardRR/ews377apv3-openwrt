# Reference artifacts (extracted from OEM firmware)

Pulled offline from de-obfuscated stock **EWS377-FIT 1.1.30** — no per-device secrets here (this is
the generic reference board data + device tree, not per-unit ART calibration).

| File | What |
|---|---|
| `hk07-oem.dts` | Decompiled OEM device tree `fdt@hk07` (the firmware's **default config**), model "Qualcomm IPQ807x/AP-HK07". The gold source for GPIO/LED/PHY/switch values. |
| `wifi-board-data/senaoBDF.note` | Senao BDF changelog — confirms ECW230v3 uses `bdwlan.b290`. |
| `wifi-board-data/fw_version.txt`, `SDK_version.txt` | QSDK WiFi FW `WLAN.HK.2.5.r4-00745` (QCA8074_v2). |
| `wifi-board-data/bdwlan.bin.b210-default` | Default board data shipped in the FIT image (== `bdwlan.b210`). |
| `wifi-board-data/bdwlan.b290-ecw230v3` | ECW230v3 board data variant. |

To turn a `bdwlan` blob into a mainline ath11k `board-2.bin`: read the qmi-board-id from the first
ath11k boot log on hardware, then `ath11k-bdencoder` the matching blob under that board-id.
