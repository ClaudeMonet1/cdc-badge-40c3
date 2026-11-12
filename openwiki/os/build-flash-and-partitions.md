---
type: build and operations
title: OS build, partitions and flashing
description: How cdc-badge-os is built with PlatformIO/ESP-IDF, its build environments and security profiles, the 16 MB partition table (including the 2 MB FAT partition that holds plugins), and the ways to flash it — PlatformIO, flash_firmware.py, and the esp-web-tools browser flasher with its Update vs Factory Setup manifests.
tags: [build, platformio, esp-idf, partitions, flashing, web-flasher, esptool, build-profile]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:23:11.133Z
sources:
  - id: openwiki-source-90130bdbc6cccafd51d570a5
    resource: repo://references/cdc-badge-os/.github/workflows/deploy-pages.yml
  - id: openwiki-source-9b1eaa02194157f882b92ba1
    resource: repo://references/cdc-badge-os/components/cdc_core/include/cdc_core/feature_flags.h
  - id: openwiki-source-bd7bb9940ccb3a24ccdc6345
    resource: repo://references/cdc-badge-os/partitions.csv
  - id: openwiki-source-2a97049eb475edb4a2987a71
    resource: repo://references/cdc-badge-os/partitions.release.csv
  - id: openwiki-source-cc422b0007a641930b4dfa5a
    resource: repo://references/cdc-badge-os/platformio.ini
  - id: openwiki-source-ebcbc9781ed420f4f17c97e4
    resource: repo://references/cdc-badge-os/sdkconfig.defaults
  - id: openwiki-source-d731567fb19f6498d74fe6d0
    resource: repo://references/cdc-badge-os/tools/flash_firmware.py
  - id: openwiki-source-37d0e1055dc8aed9deddacc2
    resource: repo://references/cdc-badge-os/web-flasher/index.html
  - id: openwiki-source-3a6c5840cc6f224243bab769
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/build-system.md
generated: { by: "claude-code", at: "2026-11-12T21:23:11.133Z" }
---

# OS build, partitions and flashing

We will normally run a released cdc-badge-os image and install our Rust plugin on
top of it. Building the OS ourselves is only needed to change host functions or
debug the runtime. This page covers both cases.

## Build

| Item | Value (`references/cdc-badge-os/platformio.ini`) |
|---|---|
| Platform | `espressif32@6.12.0`, `framework-espidf ~3.50500.0` (ESP-IDF 5.5), Xtensa toolchain 12.2.0 |
| Default env | `cdc_badge_usb`: board `cdc-badge-usb`, 16 MB flash, PSRAM enabled, `partitions.csv`, `sdkconfig.defaults` |
| Version | `APP_VERSION="0.8.2"` (pre-1.0 beta) |
| Language | `-std=gnu++17` (gnu++2b/23 explicitly unflagged) |
| Pre-scripts | `tools/pio_python_deps.py`, `tools/pio_submodules.py` (runs `git submodule update`), `tools/pio_component_manager.py` |
| Release env | `cdc_badge_release`: `partitions.release.csv`, `DEBUG_MODE=0`, guarded by `tools/pio_release_guard.py` |
| Host tests | `native` env with Unity, `test/host/*` |

```bash
git submodule update --init --recursive   # WAMR, libtropic, CalEPD, Adafruit-GFX (ESP-IDF port)
~/.platformio/penv/bin/pio run            # build
~/.platformio/penv/bin/pio run -t upload  # flash
~/.platformio/penv/bin/pio device monitor # 115200 baud
```

The four submodules are **not vendored** in this repository (see
[repository and references](../overview/repository-and-references.md)), so an
OS build has to fetch them from upstream.

Our Nix dev shell provides esptool, espflash and Python, but not PlatformIO.
Building the OS needs a PlatformIO install or the
`cdc-badge-development` container (see
[plugin build and install](../workflows/plugin-build-and-install.md)).

### Build profiles and security flags (ADR-0005, ADR-0012)

`components/cdc_core/include/cdc_core/feature_flags.h` holds `#ifndef`-guarded
switches that can be overridden with `-D`:

| Flag | Default | Effect |
|---|---|---|
| `DEBUG_MODE` | 1 | Verbose logs, development lockouts off (the PIN rate limit stays on) |
| `FEATURE_SECURE_SERIAL` | 1 in shipped builds | Serial `AUTH <pin>` gate. The header falls back to 0 and ADR-0012 says "off", but `sdkconfig.defaults` sets `CONFIG_SECURE_SERIAL=y`, so it is **on** ([serial console](serial-console-and-auth.md)). |
| `FEATURE_PLUGIN_AOT` | 0 | Interpreted WASM only; AOT native code disabled |
| `FEATURE_NVS_EDIT` | 0 | Destructive NVS-editor actions |
| `FEATURE_EPD_*` | 50 / 10 / 1 / 1 | E-paper refresh escalation (see [display](../hardware/display-and-graphics.md)) |

`BUILD_PROFILE_BYTE = (SECURE_SERIAL ? 2 : 0) | (DEBUG_MODE ? 1 : 0)` is stored in
NVS. If a newly flashed firmware has a different byte, the next boot does a
**full factory wipe**: NVS plus every used TROPIC01 slot. There is no migration
code (ADR-0005). The release gate for builds ≥ 1.0 requires `DEBUG_MODE=0`,
`SECURE_SERIAL=1`, `PLUGIN_AOT=0` and `NVS_EDIT=0`.

The `cdc_badge_release` environment layers `sdkconfig.release` on top (secure
boot, flash encryption, NVS encryption). Its bootloader **burns eFuses** on first
boot, so it can only be flashed through `tools/provision.py`. The full lockdown
flow is described in [production hardening](production-hardening.md).

## Partition table

`partitions.csv` (dev) has no OTA slots:

| Name | Type/Subtype | Offset | Size | Contents |
|---|---|---|---|---|
| (bootloader) | — | `0x0` | — | |
| (partition table) | — | `0x8000` | — | |
| `nvs` | data/nvs | `0x9000` | `0x47000` (284 KB) | Settings, module NVS (`mod_*`), plugin NVS, ECC name map |
| `app0` | app/factory | `0x50000` | `0xDA0000` (~13.6 MB) | Firmware |
| `vfat` | data/fat | `0xDF0000` | `0x200000` (**2 MB**) | Mounted at `/vfat`. Plugins live at `/vfat/system/<id>.wasm`, the i18n overlay at `/vfat/system/i18n/lang_<code>.json`. The root is the user file area. |
| `coredump` | data/coredump | `0xFF0000` | `0x10000` | Crash dumps (`tools/coredump.py`) |

`partitions.release.csv` keeps every offset but shrinks `nvs` by 4 KB to add an
encrypted `nvs_keys` partition at `0x4F000`.

Discrepancies to be aware of:

- The OS docs (`dev/build-system.md`, `dev/architecture.md`) call the FAT
  partition `plugins`, but the CSV names it **`vfat`**. Offset and size match.
- `boards/cdc-badge-usb.json` names `default_16MB.csv` (an OTA layout with
  `spiffs`), but `platformio.ini` overrides it with `partitions.csv`. The OTA
  table is unused.

All installed plugins together share the 2 MB `vfat` partition with language
files and user files. Keep `.wasm` binaries small: `wasm-opt -Oz`, no `std`
formatting machinery (see [Rust SDK](../plugin-sdk/rust-sdk.md)).

## Flashing options

| Method | What it writes | Notes |
|---|---|---|
| `pio run -t upload` | Bootloader, partitions, app | From a source build |
| `tools/flash_firmware.py --release latest \| --dir <bins>` | `0x0` bootloader, `0x8000` partitions, `0x50000` firmware | Pure Python (esptool + requests); esp32s3, 460800 baud, DIO, 80 MHz, 16 MB |
| **Web flasher** (`web-flasher/index.html`, published at `https://krim404.github.io/cdc-badge-os/flasher/`) | See the two manifests below | `esp-web-tools@10` install buttons over Web Serial (Chrome/Edge desktop) |

The web flasher offers two manifests, both generated by
`.github/workflows/deploy-pages.yml`:

- **Firmware Update** (`manifest.json`): bootloader at 0, partitions at
  `0x8000`, firmware at `0x50000`. Plugins, language overlay, settings and PINs
  are kept. The optional "Erase device" checkbox wipes everything but doesn't
  reinstall the language overlay.
- **Factory Setup** (`manifest_factory.json`): the same three images plus
  `plugins_initial.bin` at `0xDF0000` (14614528). That FAT image, built by
  `tools/build_lang_image.py`, contains the language overlay, so writing it wipes
  every installed plugin. The first boot afterwards takes 10–20 s while TROPIC01
  slots are wiped and NVS is reinitialised.

Entering download mode: hold Flash (BOOT) and tap Reset, then press Reset again
after flashing. Or, on a running badge, send `AUTH <pin>` followed by
`BOOTLOADER` over the CDC serial port, which also reboots automatically after
esptool finishes. The device enumerates as `BadgeV1`. In bootloader mode the
e-paper doesn't change and the badge looks dead.

## Serial console

`serial_cmd` provides a line console at 115200 baud over USB CDC (and BLE UART
via `mod_ble_serial`). Commands include `AUTH`, `BOOTLOADER`, `SHIPMODE`, and
plugin and GPIO commands registered by `plugin_manager`
(`PluginSerialCommands.cpp`, `GpioSerialCommands.cpp`). The plugin upload path
used by the `badge` CLI and the browser plugin installer runs over this console.
See [plugin build and install](../workflows/plugin-build-and-install.md) and
`website/src/content/docs/dev/proto/serial-commands.md`. The command catalogue,
per-transport authentication and timeouts are in
[serial console and authentication](serial-console-and-auth.md).

## Pre-1.0 warning

The OS README warns that **every flash can wipe all stored data**: FIDO2
credentials, TOTP seeds, vault entries, GPG keys, the PIN and plugin storage. A
plugin must assume its NVS, files and R-Memory can disappear after any firmware
update, and should offer export or re-provisioning.
