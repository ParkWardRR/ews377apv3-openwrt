# ELI5 — What is this project?

_Explain Like I'm 5 — no networking degree required._

## The short version

You have (or are thinking about buying) an **EnGenius EWS377AP v3**, **ECW230v3**, or **EWS377-FIT** access point. These are enterprise-grade Wi-Fi 6 devices that normally require EnGenius's own management software. This project replaces the stock firmware with **OpenWrt** — an open-source operating system that turns the AP into something you fully control.

## What are these access points?

They are ceiling/wall-mount Wi-Fi access points made by EnGenius (a brand of Senao Networks). Think "the Wi-Fi box in a hotel or office" — except these are powerful enough to cover a large home or small office with a single unit.

**Key specs (shared by all three models):**
- **Wi-Fi 6** (802.11ax) — the current-generation standard, 4 antennas per band
- **2.5 Gigabit Ethernet** uplink — faster than the typical 1 Gbps port
- **Qualcomm IPQ8072A** processor — a quad-core ARM chip designed for networking
- **1 GB RAM, 256 MB flash storage**

The three models are literally the same hardware. The only difference is which EnGenius management system they are configured for out of the box:

| Model | Stock management | What that means |
|---|---|---|
| **EWS377AP v3** | EWS / ezMaster | Managed by an on-premise controller |
| **ECW230v3** | EnGenius Cloud | Managed by EnGenius's cloud service |
| **EWS377-FIT** | Standalone | Works on its own, or with a FIT controller |

## Why replace the stock firmware?

The stock EnGenius firmware works fine for its intended use — but it locks you into EnGenius's ecosystem. With OpenWrt:

- **You own the software.** No cloud dependency, no subscription, no vendor lock-in.
- **Full package manager.** Install ad-blockers, VPN servers, traffic shapers, monitoring tools — anything in the OpenWrt package repository.
- **Hardware acceleration.** This build includes Qualcomm NSS offload — the dedicated networking processor handles NAT, routing, and Wi-Fi forwarding so the CPU stays idle. Translation: **fast**.
- **LuCI web UI.** Clean, capable web interface for configuration — or SSH if you prefer the command line.
- **Community support.** OpenWrt is one of the largest open-source networking projects. Decades of documentation, forums, and packages.

## Is this safe?

**It is not risk-free.** Be honest with yourself about your comfort level:

- **You can brick your AP** if something goes wrong during the flash process. "Brick" means it stops working and may need a serial cable to recover.
- **This is alpha software.** It has been tested on one EWS377AP v3 unit. It works — boots, Wi-Fi works, Ethernet works, survives reboots. But it has not been tested on many units or in many environments.
- **ECW230v3 and EWS377-FIT have not been tested on real hardware** — they should work (identical silicon) but nobody has confirmed it yet.
- **There is a documented path to restore stock firmware.** You can go back.

### Who should try this?

- You are comfortable with SSH and a command line
- You have a spare AP (not your only Wi-Fi) or you are comfortable with downtime
- Ideally, you have (or can get) a USB-to-serial adapter for UART access — this is the safety net

### Who should wait?

- You need your AP working reliably right now with zero risk
- You have never used a terminal / command line
- You bought the AP for EnGenius Cloud management and want to keep that

## How does it work? (the 30-second version)

1. **Back up** your AP's current firmware and calibration data (important — this contains your unique radio settings)
2. **Download** the firmware file from the [Releases page](https://github.com/ParkWardRR/ews377apv3-openwrt/releases)
3. **Flash** it to the AP using one of three methods:
   - **Serial/UART** (most reliable, needs a cable) — write the firmware directly via the bootloader
   - **SSH** (no cable needed) — connect over the network and write via `ubiformat`
   - **Web upload** (easiest but experimental) — upload through the stock web interface
4. **Reboot** — the AP comes up running OpenWrt with a web interface at `192.168.1.1`

The full step-by-step guide is at **[docs/install-and-restore.md](https://github.com/ParkWardRR/ews377apv3-openwrt/blob/main/docs/install-and-restore.md)**.

## What about the cross-flash tool?

If your AP is an ECW230v3 (cloud) or EWS377-FIT (standalone) and you want to install OpenWrt, or if you want to switch between management modes, there is a companion tool called **[Pelegrún](https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools)**. It handles the firmware header conversion over the network — no serial cable needed for that part.

## What is NSS / hardware offload?

The Qualcomm IPQ8072A chip has a separate processor dedicated to networking tasks — Qualcomm calls it the **Network Subsystem (NSS)**. Normally, your main CPU handles every network packet (routing, NAT, firewall). With NSS offload enabled, the dedicated networking processor handles the heavy lifting:

- **NAT** (translating between your internal and external IP addresses)
- **Routing** (deciding where packets go)
- **Wi-Fi forwarding** (moving data between Wi-Fi clients and the wired network)
- **Traffic shaping** (SQM / QoS)

The result: the main CPU barely does anything during normal operation, which means lower power consumption, less heat, and headroom for other tasks. This is the same acceleration that makes enterprise routers fast — and it is included in this build.

## How can I help?

If you have one of these APs and are willing to test:

1. **Flash the firmware** using the install guide
2. **Report your results** — did it boot? Does Wi-Fi work? Ethernet? What model do you have?
3. **Open an issue** at [github.com/ParkWardRR/ews377apv3-openwrt/issues](https://github.com/ParkWardRR/ews377apv3-openwrt/issues/new)

We especially need testers with **ECW230v3** and **EWS377-FIT** units — these have never been tested on real hardware.

## Glossary

| Term | What it means |
|---|---|
| **OpenWrt** | Open-source operating system for routers and access points |
| **Firmware** | The software that runs on the AP (like the OS on your computer) |
| **Flash** | Writing new firmware to the AP's storage |
| **Brick** | When an AP stops working due to bad firmware — usually recoverable with a serial cable |
| **UART / Serial** | A physical debug port on the circuit board, accessed with a USB adapter |
| **SSH** | Secure Shell — a way to get a command line on the AP over the network |
| **NSS** | Network Subsystem — Qualcomm's dedicated networking processor |
| **NAND** | The flash storage chip where firmware lives |
| **ART** | A protected partition containing radio calibration data — never overwrite this |
| **DTS** | Device Tree Source — a file that tells the kernel what hardware exists on the board |
| **UBI** | A flash filesystem format used on NAND storage |
| **Sysupgrade** | OpenWrt's built-in upgrade mechanism |
| **LuCI** | OpenWrt's web-based management interface |
