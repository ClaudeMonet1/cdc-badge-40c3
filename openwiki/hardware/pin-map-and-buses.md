---
type: hardware reference
title: Pin map, I2C and SPI buses
description: Consolidated ESP32-S3 GPIO map of the CDC Badge traced from the KiCad schematic and cross-checked against cdc-badge-os hw_config.h, the plugin GPIO policy and the vendor nametag firmware, including bus topology, Raspberry Pi header routing and known disagreements.
tags: [pinout, gpio, i2c, spi, schematic, raspberry-pi-header, sao, grove]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-74b275fa9c10858379ce54d3
    resource: repo://references/cdc-badge-hardware/cdc-badge/cdc-badge.kicad_sch
  - id: openwiki-source-72c9ac63f5e59b7aed1a202e
    resource: repo://references/cdc-badge-hardware/docs/design-choices.md
  - id: openwiki-source-bca213cdd2263add6212a0e4
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/badge.h
  - id: openwiki-source-2410dd9cb6ec516492676702
    resource: repo://references/cdc-badge-os/components/cdc_hal/include/cdc_hal/hw_config.h
  - id: openwiki-source-d071ab330bd7e24b7009d4d3
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/I2cBus.cpp
  - id: openwiki-source-d9acbe0ae72e95e3518f3e17
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/SpiBus.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-d0fa148cbee192b01dd77c36
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/PluginGpioPolicy.h
  - id: openwiki-source-b799e30e4c8e626d9ad71c0c
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_gpio.cpp
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Pin map, I2C and SPI buses

This page has three sources for every pin. They are listed below in order of
authority:

1. **Schematic** — the nets on each pin of U1 (ESP32-S3-WROOM-1), traced from
   `references/cdc-badge-hardware/cdc-badge/cdc-badge.kicad_sch` (upstream
   `riatlabs/cdc-badge`, v1.1).
2. **cdc-badge-os** — `components/cdc_hal/include/cdc_hal/hw_config.h`, plus the
   plugin allow/block list in
   `components/plugin_manager/include/plugin_manager/PluginGpioPolicy.h`.
3. **Vendor firmware** — `references/cdc-badge-nametag/lib/cdc-badge/badge.h`.

All three agree on every on-board peripheral pin. The differences are in comments
and in documentation, listed under [Disagreements](#disagreements).

## ESP32-S3 GPIO map

| GPIO | Schematic net | Function | OS constant | Plugin access |
|---|---|---|---|---|
| 0 | (Flash button SW14) | BOOT strap / Flash button; power-off trigger | `FLASH_BTN_PIN` | blocked |
| 1 | `EXP_IRQ` | TCA9535 interrupt (active low) | `EXP_IRQ_PIN` | blocked |
| 2 | `GROVE0` | Grove signal 0, also RPi header pin 32 | `GROVE_0_PIN` | **allowed** |
| 3 | `GROVE1` | Grove signal 1, also RPi header pin 33 (strapping pin) | `GROVE_1_PIN` | **allowed** |
| 4–7 | `PCM_CLK`, `PCM_FS`, `PCM_DIN`, `PCM_DOUT` | RPi header PCM/I²S pins 12/35/38/40 | — | **allowed** (ADC1 ch3–6) |
| 8 | `EPD_LED` | Frontlight PWM (via MOSFET) | `EPD_LED_PIN` | blocked |
| 9 | `SPI_CS0` | Header SPI CE0 (through switch SW16) | — | **allowed** |
| 10 | `SPI_CS_TR01` | TROPIC01 chip select | `TR01_CS_PIN` | blocked |
| 11 | `SPI_MISO` | Shared SPI MISO (also header pin 21) | `SPI_MISO_PIN` | blocked |
| 12 | `SPI_SCLK` | Shared SPI clock (also header pin 23) | `SPI_SCLK_PIN` | blocked |
| 13 | `SPI_MOSI` | Shared SPI MOSI (also header pin 19) | `SPI_MOSI_PIN` | blocked |
| 14 | `SPI_CS1` | Header SPI CE1 (through switch SW15) | — | **allowed** (ADC2) |
| 15 | `SAO_GPIO1` | SAO GPIO1, also RPi header pin 18 | `SAO_GPIO1_PIN` | **allowed** |
| 16 | `SAO_GPIO2` | SAO GPIO2, also RPi header pin 22 | `SAO_GPIO2_PIN` | **allowed** |
| 17 | `I2C0_SDA` | I²C bus 0 SDA (also header pin 27) | `I2C0_SDA_PIN` | blocked |
| 18 | `I2C0_SCL` | I²C bus 0 SCL (also header pin 28) | `I2C0_SCL_PIN` | blocked |
| 19 / 20 | `USB_D-` / `USB_D+` | Native USB (also to BQ25895 D-/D+) | — | blocked |
| 21 | `CHG_DSEL` | BQ25895 DSEL (USB detection in progress) | `CHG_DSEL_PIN` | blocked |
| 35–37 | (not connected) | Used internally by the Octal PSRAM | — | blocked |
| 38 | `TR01_IRQ` | TROPIC01 interrupt, also RPi header pin 37 | — | **allowed** (listed as "Header") |
| 39 | `CHG_IRQ` | BQ25895 interrupt (active low) | `CHG_IRQ_PIN` | blocked |
| 40 | `GPCLK0` | RPi header pin 7 | — | **allowed** (JTAG TDO) |
| 41 | `SPI_CS_EPD` | E-paper chip select | `EPD_CS_PIN` | blocked |
| 42 | `SPI_BUSY_EPD` | E-paper BUSY (also header pin 36) | `EPD_BUSY_PIN` | blocked |
| 43 / 44 | `TXD` / `RXD` (module TXD0/RXD0) | UART0, RPi header pins 8 / 10 | — | **allowed** |
| 45 | `SPI_DC_EPD` | E-paper data/command (also header pin 29) | `EPD_DC_PIN` | blocked |
| 46 | `SPI_RST_EPD` | E-paper reset (also header pin 31) | `EPD_RST_PIN` | blocked |
| 47 | (via R4 pull-up) `I2C1_SDA` | I²C bus 1 SDA | `I2C1_SDA_PIN` | blocked as GPIO, reachable via `host_i2c_*` |
| 48 | (via R6 pull-up) `I2C1_SCL` | I²C bus 1 SCL | `I2C1_SCL_PIN` | blocked as GPIO, reachable via `host_i2c_*` |

"Plugin access" is the `PluginGpioPolicy` allow/block list. The OS uses this one
list both for manifest validation and for the raw GPIO serial shell, so no
software path can drive a blocked pin. A pin on the allowed list must still be
declared in the plugin manifest (`capabilities.gpio_pins` / `pwm_pins` /
`adc_pins`). Two plugins claiming the same pin get `HOST_ERR_BUSY`. See
[manifest and capabilities](../plugin-runtime/manifest-and-capabilities.md).

## Buses

### I²C bus 0 — on-board (internal)

| Device | Address | Notes |
|---|---|---|
| BQ25895 charger | `0x6A` | INT → GPIO39, DSEL → GPIO21 |
| TCA9535 keypad expander | `0x20` | INT → GPIO1 |

GPIO17 (SDA) and GPIO18 (SCL) carry 10 kΩ pull-ups. The design doc calls for
standard mode (100 kHz), and the OS `I2cBus.cpp` runs both buses at 100 kHz. Bus 0
is also routed to Raspberry Pi header pins 27/28, where HAT ID EEPROMs normally
sit. **Plugins cannot use bus 0**: `host_i2c_*` rejects any bus other than 1
with `HOST_ERR_INVALID_ARG`, because bus 0 carries the charger and the keypad.

### I²C bus 1 — expansion

GPIO47 (SDA) and GPIO48 (SCL) carry 10 kΩ pull-ups (R4/R6). This bus is broken
out to Raspberry Pi header pins 3/5 and SAO pins 3/4. The hardware is designed for
fast mode (400 kHz), but the OS currently uses 100 kHz. The OS reserves the SAO
add-on EEPROM at `0x50` (`SAO_EEPROM_ADDR`), which plugins reach through
`host_sao_eeprom_read/write`. Other plugin access requires the `i2c_bus`
capability to list bus 1.

### SPI — shared by the display and the secure element

| Signal | GPIO |
|---|---|
| SCLK | 12 |
| MISO | 11 |
| MOSI | 13 |
| CS e-paper | 41 |
| CS TROPIC01 | 10 |
| Header CE0 / CE1 | 9 / 14 |

The OS runs a single `SPI2_HOST` with DMA (`max_transfer_sz` 4096) and drives the
chip selects manually (`SpiBus.cpp`). The display and TROPIC01 accesses are
therefore serialised by the HAL. This is one reason plugins get high-level
display and secure-element calls rather than raw SPI. The vendor firmware drives
the same pins through Arduino `SPIClass`, with the display at 4 MHz.

### Raspberry Pi header slide switches

Two SPDT slide switches decide where the header's SPI chip-select pins go:

| Switch | Header pin | Position A (to the ESP32) | Position C (to an internal device) |
|---|---|---|---|
| SW16 | 24 (CE0) | `SPI_CS0` = GPIO9 | `SPI_CS_EPD` (display CS) |
| SW15 | 26 (CE1) | `SPI_CS1` = GPIO14 | `SPI_CS_TR01` (TROPIC01 CS) |

In position C, an external board on the header shares the display or TROPIC01 chip
select with the ESP32. Firmware cannot see the switch position.

### TCA9535 spare pins on the header

The expander's P0.0–P1.3 carry the 12 keys (`BTN_0`..`BTN_9`, P1.2 = `BTN_YES`,
P1.3 = `BTN_NO`). The four spare pins **P1.4–P1.7** (`EXP_P14`..`EXP_P17`) are
routed to Raspberry Pi header pins **11, 13, 15, 16**. Neither the OS nor the
plugin API exposes them: the keypad driver configures all 16 pins as inputs, and
bus 0 is closed to plugins.

## Other connectors

| Connector | Pins |
|---|---|
| SAO (J5, 2×3) | 1–2 power, 3 `I2C1_SDA`, 4 `I2C1_SCL`, 5 `SAO_GPIO1` (GPIO15), 6 `SAO_GPIO2` (GPIO16) |
| Grove (J4) | GND, VCC (3.3 V / 5 V via solder jumper JP1), Grove "IO1" = `GROVE0` (GPIO2), Grove "IO2" = `GROVE1` (GPIO3), with optional pull-up pads R42/R43 |
| USB-C (J1) | D+/D- to GPIO20/19 and to BQ25895 D+/D- (for charger detection) |
| Display FPC (J7, 24-pin) | GDEY029T94 |

## Disagreements

| Topic | Source A | Source B | Resolution |
|---|---|---|---|
| Grove GPIOs | design-choices.md: "wired to the ESP32-S3 IO1 and IO2" | Schematic and OS: GPIO2/GPIO3 (GPIO1 is `EXP_IRQ`) | The doc means the **Grove connector's** pin names "IO1/IO2". Use GPIO2/3. |
| Expander bus | nametag `badge.h` comments: "I2C0 (Charging IC)" on 17/18, "I2C1 (Expander)" on 47/48 | nametag code, OS and schematic: expander on bus 0 (17/18) | The comments are wrong; the code is right. |
| I²C bus 1 speed | Design: fast mode 400 kHz | OS `I2cBus.cpp`: 100 kHz for both buses | The OS runs below the hardware's capability. |
| Board revision label | `hw_config.h`: "CDC Badge v1.0" | The vendored schematic is v1.1 | The changelog lists no pin changes between v1.0 and v1.1. |

For broader cross-source issues, see
[Open questions, discrepancies and constraints](../reference/open-questions-and-discrepancies.md).
