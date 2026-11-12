---
type: reference implementation
title: Vendor nametag firmware (Arduino)
description: The riatlabs cdc-badge-nametag firmware — a minimal Arduino/PlatformIO program that brings up I²C, the BQ25895, SPI, the TCA9535 keypad, NVS settings, the GxEPD2 e-paper and a TROPIC01 session, then shows a static nametag with frontlight control; useful as a second source of truth for drivers and pins, with its known inaccuracies listed.
tags: [vendor, arduino, platformio, nametag, reference-implementation, drivers]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-22b27fa017c8baa103976611
    resource: repo://references/cdc-badge-nametag/boards/cdc-badge-usb.json
  - id: openwiki-source-2840460c499870e8a24f55c4
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/badge.cpp
  - id: openwiki-source-0061ecdd18abc7e2551b83ca
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/pin_expander.cpp
  - id: openwiki-source-520d6288a90d6d818c0d4160
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/settings.cpp
  - id: openwiki-source-7b75a99344101b9c2a7006d6
    resource: repo://references/cdc-badge-nametag/platformio.ini
  - id: openwiki-source-ba365a930a57263af22ad51c
    resource: repo://references/cdc-badge-nametag/README.md
  - id: openwiki-source-0013d9cd0341a310807fdaff
    resource: repo://references/cdc-badge-nametag/src/app.cpp
  - id: openwiki-source-6cd6ccd82ce11227089acb32
    resource: repo://references/cdc-badge-nametag/test/test_connected/test_main.cpp
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Vendor nametag firmware (Arduino)

`references/cdc-badge-nametag/` (upstream `riatlabs/cdc-badge-nametag`) is the
hardware vendor's minimal firmware. It is not an OS and has no sandbox, so we
won't build on it directly. Its value is as **the simplest independent working
driver code** for every on-board chip, written with the stock Arduino libraries
that are vendored next to it.

## Build

`platformio.ini` defines one environment, `cdc_badge_usb`:

- `platform = espressif32`, `framework = arduino`, **`board = esp32-s3-devkitc-1`**,
  `ARDUINO_USB_MODE=1`, `ARDUINO_USB_CDC_ON_BOOT=1` (serial over native USB,
  115200).
- `lib_deps`: libtropic-arduino (git), `robtillaart/TCA9555 ^0.4.3`,
  `zinggjm/GxEPD2 ^1.6.5`, `adafruit/Adafruit GFX Library ^1.12.4`. These are the
  four driver libraries vendored under `references/`.
- `boards/cdc-badge-usb.json` and `cdc-badge-uart.json` exist (8 MB QIO flash
  declarations) but **are not referenced** by `platformio.ini`, which uses the
  stock DevKitC-1 board. So the "8 MB" figure discussed on the
  [board overview](../hardware/board-overview.md) comes from unused board files.

## Structure

```
src/main.cpp        setup(): badge_init(); app_setup()   loop(): app_loop()
src/app.cpp         nametag behaviour (frontlight pulse, keys 1/2 brightness, power-off)
lib/cdc-badge/      hardware layer
  badge.h/.cpp      pin and address constants, init order
  i2c_bus.*         TwoWire(0) on 17/18, TwoWire(1) on 47/48
  power_management.*  BQ25895 setup, Flash-button IRQ, ship mode (REG09 BATFET_DIS)
  spi_bus.*         shared SPIClass (SCLK 12, MISO 11, MOSI 13)
  pin_expander.*    TCA9535 at 0x20 on I2C0, IRQ GPIO1, key decode
  display.*         GxEPD2_BW<GxEPD2_290_T94_V2> + FreeMonoBold fonts, LEDC frontlight on GPIO8
  tropic01.*        libtropic-arduino Tropic01(CS 10) + secure session with prod SH0 key
  settings.*        Arduino Preferences namespace "badge" (brightness)
  serial_port.*, timeout.*, keyboard.h (empty)
test/               Unity tests run on hardware: serial, LED, EPD light (test_connected, test_uart)
```

`main.cpp` still carries the header comment of libtropic's `hello_world.ino`
example, which shows where it was derived from.

### Init order (`badge_init`, actual code)

1. Serial
2. I²C buses
3. BQ25895 power management
4. SPI
5. TCA9535
6. Settings (Preferences)
7. Display (frontlight, init, rotation 1, partial window, home screen)
8. TROPIC01 (begin + secure session)

Failures are logged and boot continues. The README lists a different order
(TROPIC01 before the display) and says "white text on black". The code draws
black text on white and initialises the display first.

### Behaviour

- The home screen shows `DISPLAY_LINE_*` macros from `display.h`; you
  personalise the badge by editing them and reflashing.
- The frontlight pulses continuously (step 15 every 15 ms). Keys **1/2** raise or
  lower brightness with a quasi-logarithmic step and a 2 s on-screen display
  (`brightness_osd`). Other keys only log.
- The Flash button (GPIO0) interrupt triggers power-off through ship mode.
- **Flash-wear caveat:** `set_setting_brightness()` writes Preferences/NVS on
  every call, and the pulse loop calls it every 15 ms. If you reuse this code,
  keep animation state in RAM and persist only user changes.

## Used as a second source of truth

| Topic | Vendor code agrees with OS? | Notes |
|---|---|---|
| GPIO numbers (I²C, SPI, EPD, TROPIC01 CS, charger IRQ/DSEL) | yes | [pin map](../hardware/pin-map-and-buses.md) |
| Expander bus | yes, in code | The `badge.h` comments and the README table say "I2C1 (Expander)", which is wrong |
| Keypad bit order (0–9, Y = bit 10, N = bit 11) | yes | [keypad](../hardware/keypad-and-io-expander.md) |
| Display controller and geometry | same SSD1680 128×296 | Different driver class (GxEPD2 `T94_V2` vs CalEPD `Gdey029T94`) — [display](../hardware/display-and-graphics.md) |
| Frontlight PWM | 10-bit at 10 kHz on GPIO8 (the code comment says "5 kHz") | Same as the OS |
| BQ25895 setup | **partial** | No charge-current or SYS_MIN programming — [power](../hardware/power-and-charging.md) |
| TROPIC01 | Same production pairing key, slot 0 | [secure element](../hardware/secure-element.md) |

README inaccuracies to ignore: "keyboard matrix" (the keys are wired one per
pin), "TCA9535 on I2C1", and "Power ON: hold SW12 ~3 s" (the hardware README says
2 s on PW ON to leave ship mode).
