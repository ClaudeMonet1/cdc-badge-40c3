---
type: hardware subsystem
title: Keypad and TCA9535 I/O expander
description: How the CDC Badge's 12-button keypad is wired through a TCA9535 I²C expander, how the vendor firmware (robtillaart TCA9555 library) and cdc-badge-os (TCA9535Keypad task) read it, and how key input reaches sandboxed plugins via polling or events.
tags: [keypad, tca9535, tca9555, i2c, input, interrupts, events]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-72c9ac63f5e59b7aed1a202e
    resource: repo://references/cdc-badge-hardware/docs/design-choices.md
  - id: openwiki-source-bca213cdd2263add6212a0e4
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/badge.h
  - id: openwiki-source-9e34b7ffa9fde64ec2d76b81
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/i2c_bus.cpp
  - id: openwiki-source-0061ecdd18abc7e2551b83ca
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/pin_expander.cpp
  - id: openwiki-source-2410dd9cb6ec516492676702
    resource: repo://references/cdc-badge-os/components/cdc_hal/include/cdc_hal/hw_config.h
  - id: openwiki-source-40bcdb5a931d972c2ec7028e
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/TCA9535Keypad.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-771393785bed8e1e57c4a734
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_keypad.cpp
  - id: openwiki-source-c41e41bfa7672fcc6f2dac76
    resource: repo://references/cdc-badge-os/website/src/content/docs/start/keypad-navigation.md
  - id: openwiki-source-de342a8f413df806f14a62b4
    resource: repo://references/TCA9555/TCA9555.h
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Keypad and TCA9535 I/O expander

## Hardware

The badge has no touchscreen. Input is a **12-key phone-style keypad** (digits
0–9 plus **Y** = confirm and **N** = cancel/back), built from SMD tactile switches.
The ESP32-S3 doesn't have enough free GPIOs for them, so every key is wired
individually to a **TI TCA9535** 16-bit I²C I/O expander. That avoids matrix
multiplexing (`references/cdc-badge-hardware/docs/design-choices.md`, "Keypad and
I/O Expander").

| Aspect | Detail |
|---|---|
| Expander | TCA9535PWR, I²C address **0x20** |
| Bus | I²C bus 0 (GPIO17 SDA / GPIO18 SCL, 100 kHz), shared with the BQ25895 charger |
| Interrupt | Expander INT → **GPIO1**, active low (falling edge) |
| Key bits | Active-low: P0.0–P1.1 = keys 0–9, bit 10 = **Y**, bit 11 = **N**; mask `0x0FFF` |
| Debounce | Hardware RC per key: 4.7 kΩ pull-up ‖ 100 nF (τ ≈ 4.7 ms). Only the release (rising) edge is debounced, since only activation matters. |

Layout on the board:

```
 1  2  3
 4  5  6
 7  8  9
 N  0  Y
```

The **Flash/BOOT** button (GPIO0) and **PW ON/RESET** (BQ25895) are separate
and do not go through the expander. See the [board overview](board-overview.md).

### TCA9535 vs TCA9555

The board uses the TCA9535. The vendor firmware uses the
`robtillaart/TCA9555` Arduino library (`references/TCA9555/`), whose `TCA9535`
class derives from `TCA9555`. Both chips share the same register map (input
0x00/0x01, output 0x02/0x03, polarity 0x04/0x05, configuration 0x06/0x07). The
library API that matters here:

| Call | Meaning |
|---|---|
| `TCA9535(addr, &wire)` | Bind to an address on a given `TwoWire` bus |
| `begin()` | Probe the device |
| `pinMode16(mask)` | Configure all 16 pins (port 0 = low byte, port 1 = high byte) |
| `read16()` | Read both input ports as one 16-bit value |
| `setPolarity16(mask)` | Invert inputs |
| `lastError()`, `getType()` | Diagnostics |

## Vendor firmware (Arduino)

`references/cdc-badge-nametag/lib/cdc-badge/pin_expander.cpp`:

1. `TCA9535 TCA(EXPANDER_ADDR, &I2C0_Bus)` uses the bus started on GPIO17/18.
   (`badge.h` labels the 17/18 pair "Charging IC" and 47/48 "Expander", but the
   code attaches the expander to `I2C0_Bus` = 17/18, which matches the schematic
   and the OS.)
2. `pinMode16(0xFFFF)` sets every pin as an input, then `read16()` clears any
   pending interrupt.
3. GPIO1 is set to `INPUT_PULLUP` with a `FALLING` interrupt that just sets a
   flag.
4. `pin_expander_process_irq()` reads `read16()` and matches the exact
   single-key pattern (e.g. `0b111111111110` → '0', `0b101111111111` → 'Y',
   `0b011111111111` → 'N'). Chords and releases return `'x'`.

## cdc-badge-os driver

`references/cdc-badge-os/components/cdc_hal/src/TCA9535Keypad.cpp` implements
the `IKeypad` HAL with a dedicated FreeRTOS task:

- **Init:** gets I²C bus 0 from the HAL, adds device 0x20, and writes outputs high,
  polarity non-inverted and all pins as inputs.
- **Task:** `keypad` task (6144-byte stack, priority 5) created with
  `xTaskCreateWithCaps`. The GPIO1 negative-edge ISR notifies it. A 50 ms poll
  timeout is the fallback if an IRQ is missed, and a 10 ms software settle runs
  after each wake.
- **Decoding:** the 12-bit active-low state maps to `Key::KEY_0..KEY_9`,
  `KEY_YES`, `KEY_NO`. A failed I²C read returns the sentinel `0xFFFF`.
- **Buffering:** a 16-entry ring buffer queues key events.
- **Long press:** 800 ms default threshold, optional per consumer.
- **Key repeat:** configurable initial delay and period. It re-emits a held key
  and is mutually exclusive with long-press.
- **Chords:** an ambiguous multi-key press emits no single-key events. The only
  recognised chord is **N + Y**, the *panic / anti-block* chord. It fires once and
  triggers an instant lock that unloads plugins, closes views and returns to the
  lock screen.

OS-wide key conventions (from the user guide `start/keypad-navigation.md`): 2/8
move up/down, Y selects, N goes back, 3 opens a context menu, holding 5 forces a
full e-paper refresh, and T9 multi-tap is used for text entry.

## How key input reaches a plugin

A plugin has two ways to read keys, and **they use different encodings**:

| Mechanism | API | Key encoding |
|---|---|---|
| Polling | `host_key_pressed(key)`, `host_key_consume_next(&key)` | `KEY_0..KEY_9` = 0–9, `KEY_Y` = **10**, `KEY_N` = **11** |
| Events | `host_event_subscribe(EVENT_KEY_PRESSED \| EVENT_KEY_RELEASED \| EVENT_KEY_LONG_PRESS, action_id)` | `user_data` = **ASCII** `'0'..'9'`, `'Y'` (89), `'N'` (78) |

Most UI plugins never read raw keys at all. The OS view system (lists, menus,
T9 input) handles navigation and calls the plugin's actions. See
[Plugin lifecycle, events and UI](../plugin-runtime/lifecycle-events-and-ui.md).

### Security gate

Polling is allowed only while the calling plugin is in the **foreground and one of
its views has input focus** (`PluginUiState::hasInputFocus`). Otherwise
`host_key_pressed` returns false and `host_key_consume_next` returns
`HOST_ERR_NOT_FOUND`. The code says why: without this gate a background plugin
could watch keys typed on the lock-screen PIN pad. A Rust plugin therefore can't
build a keylogger or a global hotkey, and the panic chord is always reserved for
the OS.
