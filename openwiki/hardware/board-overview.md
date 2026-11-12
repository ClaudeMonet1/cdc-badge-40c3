---
type: hardware overview
title: CDC Badge hardware overview
description: Board-level map of the CDC Badge (riatlabs/cdc-badge KiCad project) — ESP32-S3-WROOM-1, GDEY029T94-FL03 e-paper with frontlight, TROPIC01 secure element, TCA9535 keypad expander, BQ25895 power path, expansion ports, revisions and power budget.
tags: [hardware, esp32-s3, kicad, power, expansion-ports]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-74b275fa9c10858379ce54d3
    resource: repo://references/cdc-badge-hardware/cdc-badge/cdc-badge.kicad_sch
  - id: openwiki-source-dd48a1447fe860b588570d79
    resource: repo://references/cdc-badge-hardware/CHANGELOG.md
  - id: openwiki-source-72c9ac63f5e59b7aed1a202e
    resource: repo://references/cdc-badge-hardware/docs/design-choices.md
  - id: openwiki-source-a893e42b7081dbabd7efc3d8
    resource: repo://references/cdc-badge-hardware/README.md
  - id: openwiki-source-22b27fa017c8baa103976611
    resource: repo://references/cdc-badge-nametag/boards/cdc-badge-usb.json
  - id: openwiki-source-cc422b0007a641930b4dfa5a
    resource: repo://references/cdc-badge-os/platformio.ini
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# CDC Badge hardware overview

The CDC Badge is an open-hardware (CERN-OHL-P) hacker badge designed by the RIAT
Institute for the Critical Decentralization Cluster. The source of truth is the
KiCad project vendored at `references/cdc-badge-hardware/` (upstream
`riatlabs/cdc-badge`); the rationale for each part lives in
`references/cdc-badge-hardware/docs/design-choices.md`.

For a Rust/WASM application developer the board matters indirectly: a sandboxed
plugin never touches these chips directly, it goes through the host functions of
[cdc-badge-os](../os/architecture.md). But the hardware explains the constraints
those host functions inherit — a slow e-paper panel, a keypad behind an I²C
expander, a secure element on a shared SPI bus and a battery-powered power budget.

## Block diagram

```
                    USB-C (device only, CC = 5.1 kΩ pull-downs)
                       │
                 ┌─────┴──────┐  I²C0 (100 kHz)   ┌──────────────┐
  LiPo 1200 mAh ─┤  BQ25895   ├───────────────────┤ ESP32-S3-    │
  (JST-PH)       │ charger /  │                   │ WROOM-1      │
                 │ power path │   ┌──────────┐    │ (Octal PSRAM)│
                 └─────┬──────┘   │ TCA9535  ├────┤              │
      VSYS ─► TLV62569 3.3 V buck │ 12 keys  │IRQ │              │
      VSYS ─► TLV61070A 5 V boost └──────────┘    │              │
                                                  │   SPI (shared)
                 ┌───────────────┐   CS/DC/RST/BUSY │
                 │ GDEY029T94-FL03├─────────────────┤
                 │ e-paper + FL  │◄── PWM via Si1308EDL MOSFET
                 └───────────────┘                  │
                 ┌───────────────┐   CS             │
                 │ TROPIC01      ├──────────────────┤
                 └───────────────┘                  │
   I²C1 (400 kHz) ─► Raspberry Pi 40-pin header, SAO port
   IO pins        ─► Grove connector (selectable 3.3 V / 5 V)
```

Exact GPIO numbers, bus assignments and the places where the sources disagree are
on [Pin map, I2C and SPI buses](pin-map-and-buses.md).

## Main components

| Function | Part | Notes |
|---|---|---|
| MCU | Espressif **ESP32-S3-WROOM-1** | Dual-core Xtensa, Wi-Fi + BLE, USB OTG-capable. Chosen over ESP32-C3/C6 for OTG, GPIO count and performance. The schematic notes that several module pins are "Connected to the Octal SPI PSRAM. Not available for other uses." |
| Display | Good Display **GDEY029T94-FL03** | 2.9" e-paper bonded with a frontlight. See [display and graphics](display-and-graphics.md). |
| Frontlight driver | Si1308EDL MOSFET + 5.1 Ω resistor | Driven from an ESP32 LED PWM pin; voltage capped at 3.0 V (~67 mA). |
| Secure element | Tropic Square **TROPIC01** (TR01-C2P-T301 in the schematic) | On the shared SPI bus. See [secure element](secure-element.md). |
| Keypad | 12 SMD tactile buttons on a **TCA9535** 16-bit I²C expander | Digits 0-9 plus yes/no, RC hardware debounce. See [keypad and I/O expander](keypad-and-io-expander.md). |
| Charger / power path | TI **BQ25895** | Power-path management, USB D+/D- detection, ADC for battery voltage. See [power and charging](power-and-charging.md). |
| 3.3 V rail | TI TLV62569 buck (2 A) | Feeds the ESP32, TROPIC01, display and header. |
| 5 V rail | TI TLV61070A boost (2.5 A) | For the header (e.g. a Sipeed M1 / Grove AI HAT). |
| Battery | PKCELL LP503562, 3.7 V 1200 mAh LiPo | Protection is inside the battery pack; cut-off chosen at 3.3 V. |

Datasheet links for every part are collected in
`references/cdc-badge-hardware/docs/datasheets.md`.

### Flash and PSRAM size

The KiCad symbol is the generic `ESP32-S3-WROOM-1`, so the schematic does not fix
the flash/PSRAM variant. The firmware references disagree:

- cdc-badge-os builds for **16 MB flash with PSRAM enabled**
  (`references/cdc-badge-os/platformio.ini`, board `cdc-badge-usb.json`,
  partition table `default_16MB.csv`).
- The vendor nametag firmware's board files declare **8 MB** flash
  (`references/cdc-badge-nametag/boards/cdc-badge-usb.json`).

The OS is the newer and more demanding consumer; treat 16 MB + Octal PSRAM as the
production assumption and 8 MB as the vendor's conservative lower bound. See
[open questions](../reference/open-questions-and-discrepancies.md).

## Expansion ports

The badge has three expansion ports (README "Expansions"):

- **Raspberry Pi 40-pin header** — accepts HATs/pHATs. UART TX/RX are on header
  pins 8 and 10 (used for UART flashing), and I²C bus 1 is broken out here.
- **SAO port** — 2×3, 2.54 mm, bottom-entry SMD header so add-ons sit on the
  outside while tall parts stay on the body side. Shares I²C bus 1.
- **Grove-compatible connector** — selectable 3.3 V or 5 V supply; the design
  doc says its signal pins go to ESP32 IO1/IO2, while cdc-badge-os maps Grove to
  GPIO2/GPIO3 (see [pin map](pin-map-and-buses.md)). Pull-ups for I²C use are
  left as unpopulated 0603 pads. Because the Grove connector is proprietary, the
  BOOMELE HY-4P is used as a substitute footprint.

### External SPI access to internal devices

Two mechanical slide switches can connect Raspberry Pi header pins 24 and 26 to
the chip-select lines of the e-paper display and the TROPIC01. The display's DC,
RST and BUSY lines are on header pins 29, 31 and 36 and the TROPIC01 interrupt on
pin 37. This lets an external microcontroller (e.g. Sipeed M1) drive the screen
and use the secure element directly — bypassing the ESP32 and therefore any
sandbox enforced by cdc-badge-os.

## Buttons outside the keypad

- **Reset (EN) and Flash (IO0)** connect directly to the ESP32. The flash button
  is also the documented trigger for a full power-off (see the
  [firmware checklist](power-and-charging.md)).
- **PW ON / RESET** connects to the BQ25895 with fixed behaviour: 2 s press exits
  shipping mode, 12 s press on battery forces a full power reset.

## USB

USB-C with fixed 5.1 kΩ pull-downs on CC1/CC2, so the badge always appears as a
USB device (UFP). USB host/OTG mode is **currently unsupported** in hardware; it
would need a different CC resistor configuration, the BQ25895 in boost mode and a
PMID bulk capacitor.

## Power budget

| Item | Value |
|---|---|
| Max current, 3.3 V bus | 2 A (shared by every on-board chip) |
| Max current, 5 V bus | 2.5 A |
| Peak design estimate | ≈3.44 W @ 5 V ≈ 0.69 A (ESP32 1.65 W, Sipeed M1 1.5 W, TROPIC01 0.08 W, display + frontlight 0.21 W) |
| ESP32-S3 deep sleep / light sleep | 8 µA / 240 µA |
| TROPIC01 sleep | 945 µA — about 90 % of total sleep current |
| ESP32-S3 Wi-Fi listen | ~95 mA |

There was no free GPIO to switch the TROPIC01 supply, so for the lowest standby
power the exposed VCC trace to the TROPIC01 can be cut (0603 pads allow
re-bridging). The same trace is an access point for power-glitch testing.

## Hardware revisions

| Version | Date | Changes |
|---|---|---|
| v0.1 | 2025-11-25 | Test run with all planned components. |
| v1.0 | 2025-12-11 | First mass production: flash/enable buttons further apart, IO silkscreen labels, larger flex cut-out, Grove moved 1 mm. |
| v1.1 | 2026-01-23 | Second mass production: larger keycaps with better feedback, new front graphic. |

cdc-badge-os targets "CDC Badge v1.0/v1.1"; neither revision changes the
electrical interface relevant to firmware.

## Flashing

Two paths: native USB, or UART via header pins 8/10. A first USB flash may need
the classic hold-Flash-then-Reset sequence to escape a boot loop. Firmware-level
flashing tooling is described in
[OS build, partitions and flashing](../os/build-flash-and-partitions.md).

## Other firmware for the board

The hardware README lists cdc-badge-os, the vendor
[nametag firmware](../vendor/nametag-firmware.md), an ESPHome port, a Monero
wallet and a Rust PIV smartcard (rugart) — useful prior art for anyone writing
bare-metal Rust instead of a sandboxed plugin.
