---
type: runtime subsystem
title: "Hardware I/O for plugins: GPIO, PWM, ADC, I2C, SAO, pixel strip"
description: Runtime semantics of plugin hardware access on cdc-badge-os — the three-layer check (manifest, pin lock, firmware block list), pin locks shared with the GPIO serial shell, LEDC PWM channels sharing one timer, ADC1 one-shot reads, I2C restricted to the expansion bus, the SAO EEPROM, the shared WS281x/SK6812 pixel strip, and release on unload.
tags: [gpio, pwm, adc, i2c, sao, pixel-strip, hardware, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-b799e30e4c8e626d9ad71c0c
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_gpio.cpp
  - id: openwiki-source-c06b6ecdc8ba4120dbd99a7e
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_pixel_strip.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Hardware I/O for plugins: GPIO, PWM, ADC, I2C, SAO, pixel strip

**Which pins exist** and which are allowed is on the
[pin map](../hardware/pin-map-and-buses.md). This page covers **how access
behaves at runtime**.

Sources: `components/plugin_manager/src/host_api_gpio.cpp`,
`host_api_pixel_strip.cpp`, `GpioSerialCommands.cpp`,
`include/plugin_manager/PluginGpioPolicy.h`, `components/mod_sao/src/sao.cpp`,
and the upstream skill reference `…/cdc-badge-plugin-dev/reference/hardware.md`.
Examples: `grove_blink`, `gpio_mqtt`, `grove_led`, `sdk_probe`.

## Three checks on every call

`host_api_gpio.cpp:1-12`. A call must pass all three:

1. **Manifest:** the pin is listed in `gpio_pins` / `pwm_pins` / `adc_pins`, or
   unlocked by `grove` (GPIO 2/3) or `sao` (GPIO 15/16).
2. **Pin lock:** no other plugin, and not the native `GPIO` serial shell, holds
   the pin. Otherwise `HOST_ERR_BUSY`.
3. **Firmware block list:** display SPI, TROPIC01 CS, charger I²C, USB, PSRAM
   lines and so on are refused regardless of the manifest
   (`PluginGpioPolicy.h`, shared with the serial shell). The load-time
   `CapabilityChecker` already rejects manifests naming blocked pins.

Locks are taken on first use and released by `host_gpio_release(pin)` or
automatically at unload. `teardownPlugin` calls `plg_gpio_on_unload`, along
with the BLE, msg, ext-feature, surface, net, HTTP and socket cleanup
(`PluginManager.cpp:451-459`). A trap-unload releases them too.

## GPIO

- `host_gpio_set_direction(pin, IN | OUT | OUT_OD)`
- `host_gpio_set_pull(NONE | UP | DOWN)`
- `host_gpio_write`, `host_gpio_read`

There are no GPIO interrupts in the plugin API. Poll from `plugin_on_tick`
(about 50 ms resolution).

## PWM

- `host_gpio_pwm_start(pin, freq_hz, duty_per_mille)`, `pwm_set_duty`,
  `pwm_stop`.
- Each PWM pin gets its **own LEDC low-speed channel** (independent duty), but
  **all channels share `LEDC_TIMER_0`, so they share one frequency**. Starting
  PWM at a new frequency affects every running PWM pin.
- The frontlight runs on the same LEDC peripheral but is handled by the display
  HAL. Use `host_display_set_backlight` for it (see
  [display](../hardware/display-and-graphics.md)).

## ADC

- `host_adc_read(pin, &raw, &millivolt)` does a one-shot read on **ADC1**
  (`host_api_gpio.cpp:271-300`), returning raw counts and calibrated mV.
- The allowed ADC-capable pins are header GPIO 4–7 (ADC1 ch3–6).
- GPIO14 is ADC2 on the ESP32-S3, and ADC2 conflicts with Wi-Fi. Prefer the
  ADC1 pins.

## I²C

- Only **bus 1** (the expansion bus: Raspberry Pi header pins 3/5 and SAO) is
  usable. Bus 0 (charger and keypad) returns `HOST_ERR_INVALID_ARG`.
- Needs `i2c_bus: [1]` in the manifest.
- Calls: `host_i2c_write`, `read`, `write_read` (repeated start), `scan`.
- The OS runs the bus at 100 kHz, although the hardware supports 400 kHz.

## SAO

- With `sao: true`, plugins get GPIO 15/16 plus `host_sao_eeprom_read/write`,
  which targets the add-on EEPROM at I²C1 `0x50` transparently.
- `mod_sao` identifies an add-on only if its EEPROM begins with `SAO1` (see
  [browser, vCard and SAO](../os/modules/browser-vcard-sao.md)).
- **Writing the EEPROM can make an add-on unrecognisable**, so treat writes as
  destructive.

## Pixel strip

- Supports WS2811/WS2812/WS2813/SK6812 through ESP-IDF `led_strip` (RMT)
  (`host_api_pixel_strip.cpp:1-30`). Needs `pixel_strip: true`.
- **One global strip handle is shared by all plugins.** It is identified by
  (gpio, pixel count, format) and holds at most **1024 pixels**.
- The data pin must be on the allowed list (typically Grove GPIO 2).
- Calls: `host_pixel_strip_init`, `set`, `fill`, `clear`, `refresh`, `length`,
  `ready`, `deinit`.
- Example: `grove_led`, an autoload service driving a WS2813 on Grove.

## Power and safety notes

- Grove VCC is 3.3 V or 5 V depending on solder jumper JP1. GPIO levels are
  always 3.3 V.
- Pins 3 (a strapping pin) and 40 (JTAG TDO) are allowed but have secondary
  roles.
- A plugin holding a pin keeps it until release or unload. A background
  resident plugin can therefore block another plugin's pins indefinitely; the
  user can stop it from the plugin list's `[3]` menu.
