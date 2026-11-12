---
type: hardware subsystem
title: Power, charging and sleep
description: BQ25895 charger and power path on the CDC Badge, the vendor firmware checklist every boot must satisfy, how cdc-badge-os and the vendor nametag firmware implement it, the light/deep/ship sleep modes, and the battery and sleep-inhibit host functions available to plugins.
tags: [power, bq25895, battery, sleep, ship-mode, frontlight, firmware-checklist]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-ba7adf9b47eac1366334c308
    resource: repo://references/cdc-badge-hardware/docs/firmware-checklist.md
  - id: openwiki-source-37bebf3c682f8803727406a8
    resource: repo://references/cdc-badge-hardware/docs/measurements.md
  - id: openwiki-source-f0f08050a7357a2b2b96ed5b
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/power_management.cpp
  - id: openwiki-source-4f5214fa0e908e5658639afa
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/BQ25895Power.cpp
  - id: openwiki-source-a23432ed86d38ff95ef2150e
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/SleepController.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-1dab2a051411eaea4e5b72b5
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_power.cpp
  - id: openwiki-source-25eaee56e60b57b4a8ed3ecc
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/power-sleep.md
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Power, charging and sleep

## Power path

```
USB-C VBUS ─► BQ25895 (I²C0 @ 0x6A) ─► VSYS ─┬─► TLV62569 buck → 3.3 V (ESP32, TROPIC01, display, header 3V3)
                 │  BATFET                    └─► TLV61070A boost → 5 V (header, Grove @5 V)
           LiPo 1200 mAh (LP503562)
```

- The **BQ25895** handles power-path management, charging, D+/D- USB source
  detection, and has an ADC that measures battery, system, VBUS and charge
  current. That ADC replaces a separate fuel gauge
  (`references/cdc-badge-hardware/docs/design-choices.md`).
- Its interrupt goes to **GPIO39** (`CHG_IRQ`, active low) and its DSEL output
  to **GPIO21** (`CHG_DSEL`). The OTG pin is tied through a resistor, and boost
  mode is unused.
- Battery range: 4.2 V full, 3.7 V mid, 3.3 V low (the chosen cut-off), 3.0 V
  depleted.

## The firmware checklist

The auxiliary chips keep no settings across a power cycle, so the vendor
(`references/cdc-badge-hardware/docs/firmware-checklist.md`) requires firmware to
do the following **on every boot**:

| # | Obligation | Register | Why |
|---|---|---|---|
| 1 | Lower fast-charge current below 1200 mA (recommended 512 mA) | REG04[6:0] | Default 2048 mA would damage the 1200 mAh cell |
| 2 | Minimum system voltage 3.3 V | REG03[3:1] | Default 3.5 V wastes usable battery |
| 3 | Get off the USB bus during charger port detection (watch DSEL, release D+/D- until CHG_IRQ), **or** disable detection | REG02[0] | Detection otherwise fails or corrupts USB traffic |
| 4 | Watch CHG_IRQ and read status | REG0B–REG13 | Learn plug/unplug, faults, voltages |
| 5 | Full power-off via ship mode, e.g. on long press of the Flash button | REG09[5] BATFET_DIS | Exit with a 2 s press on PW ON |
| 6 | Put the TROPIC01 to sleep when idle | — | It draws ~945 µA asleep, the largest standby load |

The measurements doc confirms item 3: with the ESP32 running, only the USB 2.0
default (5 V / 0.5 A) negotiates, while with the ESP32 held in reset the
charger reaches 12 V and charges at 1 A.

## How cdc-badge-os implements it

`references/cdc-badge-os/components/cdc_hal/src/BQ25895Power.cpp` (`IPowerManager`):

| Checklist item | OS behaviour |
|---|---|
| Charge current | Boots at **512 mA** ("slow"). It can switch to 1000 mA ("fast") and is hard-capped at 1024 mA, in 64 mA steps. |
| SYS_MIN | Set to 3.3 V (code 3 in REG03[3:1]). |
| USB detection | Takes the **disable** route: clears REG02[0] (DPDM). DSEL is never monitored and is only listed in the plugin GPIO block list. Charging is limited to the USB default current. |
| IRQ | GPIO39 falling-edge ISR sets a flag that `update()` consumes. It reads REG0B (charge state, power-good, VSYS_STAT), REG0C (faults), REG0E (VBAT), REG12 (ICHG). |
| Ship mode | Holding the **Flash button (GPIO0) for 3 s** sets BATFET_DIS (REG09[5]) after drawing a "Shipping mode - press PW ON 2s to re-enable" notice. The notice stays visible because e-paper is bistable. Also reachable from the expert menu and the `SHIPMODE` serial command (after `AUTH <pin>`). |
| Other | Disables the ILIM pin (uses the internal limit) and OTG boost. Kicks the charger watchdog. |

**Battery percentage** is a straight line between 3200 mV (0 %) and 4200 mV
(100 %). It isn't coulomb counting. "Low" means below 20 %. The OS infers battery
presence from VSYS_STAT plus the VBAT range, because a USB-powered badge with no
battery reads ~4.0–4.25 V passthrough.

### Sleep modes (`SleepController.cpp`, user guide `guide/power-sleep.md`)

| Mode | Entry | Wake sources | Effect |
|---|---|---|---|
| Light sleep | After 2 min idle **on the lock screen** only; not while USB is connected or while any sleep inhibitor is held | Keypad IRQ (GPIO1 low), charger IRQ (GPIO39 low, i.e. USB plug), timer (the "Sleep Interval" setting, used to refresh the clock) | CPU paused, then resumes. Registered wakeup callbacks run. |
| Deep sleep | Hold **N for 5 s** on the lock screen | Keypad only (`ext1` on GPIO1 any-low) | Full reboot on wake. An RTC-memory flag records that the badge came from deep sleep. |
| Ship mode | Flash button 3 s / expert menu / `SHIPMODE` | PW ON 2 s, or USB plug | Battery disconnected by the BATFET |

Sleep is driven from the lock screen, so **a running plugin keeps the badge
awake only while the badge is unlocked** or while the plugin holds an inhibitor.

## Vendor nametag firmware

`references/cdc-badge-nametag/lib/cdc-badge/power_management.cpp` writes the
BQ25895 directly over `I2C0_Bus`. It reads REG14 (part number), disables ILIM
(REG00[6]) and OTG (REG03[5]), configures DSEL as an input, attaches a falling
interrupt to the Flash button, and implements ship mode via REG09[5]. It
**doesn't** program REG04 (charge current) or SYS_MIN. In this snapshot it skips
checklist items 1 and 2, so prefer cdc-badge-os as the reference for safe
charger setup.

## Frontlight

The frontlight sits on **GPIO8** (LEDC PWM, 10-bit, 10 kHz) and drives a
Si1308EDL MOSFET. A 5.1 Ω resistor caps the LED at about 3.0 V / 67 mA. At full
brightness it is the largest controllable load after the radios, so the OS
switches it off before sleep. See
[display and graphics](display-and-graphics.md).

## What a plugin can see and control

From `host_api.h` (power group), implemented in `host_api_power.cpp`:

| Function | Returns |
|---|---|
| `host_battery_mv()` | Battery voltage (mV) |
| `host_battery_pct()` | 0–100 % (linear estimate as above) |
| `host_is_usb_connected()` | VBUS present |
| `host_power_source()` | `POWER_SRC_*` |
| `host_charge_status()` | `CHARGE_NOT_CHARGING` 0, `PRE_CHARGE` 1, `FAST` 2, `DONE` 3, `FAULT` 4 |
| `host_is_battery_low()` / `host_is_battery_critical()` | Threshold flags |
| `host_set_sleep_inhibit(on)` | Holds or releases a light-sleep inhibitor keyed by plugin id. **Released automatically when the plugin unloads.** |

Plugins can subscribe to `EVENT_POWER_USB_CONN/DISCONN`, `EVENT_POWER_CHARGING`,
`EVENT_POWER_BATT_LOW/CRIT` and `EVENT_SYSTEM_SLEEP/WAKE`. The charger
registers, charge current, ship mode and the frontlight PWM pin itself are not
reachable from a plugin. Only the backlight level is, through
`host_display_set_backlight`.

### Guidance for a Rust plugin

- A background plugin that has to keep ticking (e.g. a network poller) needs
  `host_set_sleep_inhibit(1)` and should release it as soon as possible. A held
  inhibitor keeps the ESP32 out of light sleep, where Wi-Fi listening alone
  costs ~95 mA.
- Handle `EVENT_SYSTEM_SLEEP` / `EVENT_SYSTEM_WAKE` to pause timers and
  re-establish network state after light sleep.
