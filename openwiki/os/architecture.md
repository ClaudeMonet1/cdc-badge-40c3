---
type: system architecture
title: cdc-badge-os architecture
description: Layered structure of the cdc-badge-os reference firmware (ESP-IDF on ESP32-S3) — components, the staged boot in main.cpp, the cooperative main loop, service and module registries, EventBus, UI stack, feature modules, the PSRAM-first memory rule and the no-migration policy — and where the WASM plugin system fits.
tags: [os, architecture, esp-idf, boot, modules, eventbus, psram, adr]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-1d60007d1922bf727b062030
    resource: repo://references/cdc-badge-os/components/cdc_core/include/cdc_core/EventBus.h
  - id: openwiki-source-e3d0e3a416e7e9decef6e4e9
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_event.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
  - id: openwiki-source-91a63a3beacec1226cac4b20
    resource: repo://references/cdc-badge-os/main/CMakeLists.txt
  - id: openwiki-source-c460c05c339937e9287921df
    resource: repo://references/cdc-badge-os/main/main.cpp
  - id: openwiki-source-961bfad743ca64463e3cf273
    resource: repo://references/cdc-badge-os/main/module_defaults.h
  - id: openwiki-source-3de2850a4dafb312a8e71d16
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0001-psram-first-memory.md
  - id: openwiki-source-95558c28fa5a9d1777694b21
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0002-module-isolation-registration.md
  - id: openwiki-source-6a84ea21f8e96b933d36dada
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0005-no-migration-build-profile-wipe.md
  - id: openwiki-source-57c6933d6876e2553ddd88dc
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/architecture.md
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# cdc-badge-os architecture

`references/cdc-badge-os` (upstream `krim404/cdc-badge-os`, branch `release`) is
the reference firmware for the CDC Badge. It is a pre-1.0, GPL-3.0 C++ firmware
built with PlatformIO and ESP-IDF. It turns the badge into a hardware security key
(FIDO2/WebAuthn, OpenPGP card, PIV, TOTP, password vault) with BLE features and a
**sandboxed WASM plugin runtime**. Our Rust application will run as one of those
plugins, so this page describes the host it runs inside.

The authoritative design narrative is the OS's own developer docs under
`website/src/content/docs/dev/` (`architecture.md`, `module-development.md`, ADRs
0001–0014).

## Layering

```
┌────────────────────────────────────────────────────────────────────┐
│ WASM plugins (Rust/C → .wasm)  ── host API ──►  plugin_manager     │
├────────────────────────────────────────────────────────────────────┤
│ Feature modules  mod_fido2  mod_gpg  mod_piv  mod_2fa  mod_password│
│ (IModule)        mod_vcard  mod_sao  mod_blehid  mod_usbhid  ...   │
├────────────────────────────────────────────────────────────────────┤
│ OS UI  cdc_os_ui (lock screen, settings, AppUi loop)               │
│ Views  cdc_views (list, T9, PIN, slider, QR, toast...)  cdc_ui     │
├────────────────────────────────────────────────────────────────────┤
│ Services  cdc_core (ServiceRegistry, ModuleRegistry, EventBus,     │
│           PinManager, TropicStorage, UsbServiceManager, SystemLock)│
│           cdc_msg (BLE message transfer)  serial_cmd  usb_badge    │
├────────────────────────────────────────────────────────────────────┤
│ HAL  cdc_hal (IDisplay, IKeypad, IPowerManager, ISecureElement,    │
│      IBluetoothController, IWifiController, ISleepController,      │
│      IRtc, II2cBus, ISpiBus)                                        │
├────────────────────────────────────────────────────────────────────┤
│ ESP-IDF / FreeRTOS, CalEPD, Adafruit-GFX, libtropic, WAMR, libjpeg │
└────────────────────────────────────────────────────────────────────┘
```

Rules:

- **HAL by interface only.** Every hardware driver implements a pure-virtual
  `cdc_hal` interface that extends `core::IService` (`init/start/stop/getState`).
  The rest of the firmware depends on the interface, not the driver. The
  [emulator](../workflows/emulator.md) relies on this to substitute host backends.
- **Module isolation (ADR-0002).** `cdc_core` never references a `mod_*`
  component, so modules can be removed independently. The only registration point
  is the `MODULES` list in `main/CMakeLists.txt`. CMake generates
  `modules_init.gen.h` from it with one `<module>_register()` call per module.

## Components

| Component | Role |
|---|---|
| `cdc_hal` | Drivers: e-paper (CalEPD), TCA9535 keypad, BQ25895 power, TROPIC01, BLE, Wi-Fi, sleep, RTC, I²C/SPI buses. See the hardware pages. |
| `cdc_core` | `ServiceRegistry` (static service locator, max 24), `ModuleRegistry` (max 16 modules; enable/disable persisted in NVS; menus; lifecycle fan-out), `EventBus`, `PinManager`, `TropicStorage`, `TropicSlotMap`, `AttestationKeyService`, `UsbManager`/`UsbServiceManager`, `SystemLock`, `FactoryReset`, CP437 helpers, `feature_flags.h` |
| `cdc_ui`, `cdc_views`, `cdc_os_ui` | `IView` and `ViewStack` (depth 20, modals), I18n (English in rodata, other languages from `/vfat/system/i18n/lang_<code>.json` into PSRAM), reusable views, lock screen, settings and the top-level `AppUi` loop |
| `serial_cmd` | Line-oriented serial console with optional `AUTH <pin>`, over USB CDC, UART or BLE UART |
| `usb_badge` | TinyUSB CDC plus a composite device that modules add HID/CCID interfaces to |
| `cdc_msg` | Badge-to-badge BLE transfer of MIME-typed payloads, with ephemeral numeric-comparison pairing and a handler registry |
| `cdc_scard`, `cdc_keyboard`, `cdc_image`, `cdc_spi_lock`, `cdc_log` | Smartcard (CCID) plumbing, keyboard providers, image decoding (with `libjpeg`), SPI locking, logging |
| `mod_*` | Feature modules (below) |
| `wamr_runtime`, `plugin_manager` | The WASM sandbox. See [WAMR plugin runtime](../plugin-runtime/wamr-runtime.md). |

### Feature modules

`main/module_defaults.h` sets each module's factory default. User toggles then
persist in NVS.

| Enabled by default | Disabled by default |
|---|---|
| `mod_2fa` (TOTP), `mod_fido2`, `mod_password`, `mod_gpg`, `mod_piv`, `mod_sao`, `mod_vcard`, `mod_ble_serial`, `mod_nvsedit`, `mod_blehid`, `mod_vfat` | `mod_usbhid`, `mod_otphid`, `mod_msc` |

`mod_browser` is built (it appears in `MODULES`) but has no entry in the defaults
map.

A module implements `IModule` (usually via `ModuleBase`):

- lifecycle hooks: `onUnlock`, `onLock`, `onUsbConnect/Disconnect`, `onTick(nowMs)`
- menu contributions per `MenuLocation`, an entry view and lock-screen context
  items
- semantic backup export/import via cJSON
- secure-element slot requests validated against the
  [slot map](../hardware/secure-element.md)

Module NVS namespaces use the prefix `mod_`.

## Boot sequence (`main/main.cpp`, `app_main`)

| Stage | Work |
|---|---|
| 0 | `nvs_flash_init` (erases and retries on a version mismatch). `checkBuildProfileAndWipeNvs()` compares `BUILD_PROFILE_BYTE` with NVS. |
| 1 | Core services: `EventBus`, USB CDC, logging. If this fails, reboot after 5 s. |
| 2 | RTC |
| 3 | Hardware: I²C bus → power manager (BQ25895) → sleep controller → Wi-Fi → BLE → keypad → secure element (session start). A **factory wipe of TROPIC01 data** runs here if the build profile changed. |
| 4 | System services: attestation key, `TropicStorage` cache, serial command interface, message transfer, USB service manager (CCID etc.) |
| 5 | Display init + splash, then UI init (`ui_init(UiDeps)`) |
| 6 | Modules (`initModules`), then restore the Wi-Fi state |
| 6b | **Plugin system:** `PluginManager::init()` (WAMR, mounts the plugins FAT partition, discovers plugins), plugin and GPIO serial commands, language-file scan |
| — | Release the BLE boot barrier, so every module/plugin GATT service is committed at once |
| 7 | `startApp()`, then the infinite main loop |

## Execution model

The main task runs a **cooperative loop** every 10 ms (`runMainLoopIteration`):

1. `SystemLock::enforceIfLocked()`: hard lockdown gate (halt screen, then deep
   sleep).
2. `EventBus::process()`: drain queued events to subscribers.
3. PIN lockout timer, serial console, power-manager update.
4. `ui_process(nowMs)`: input, timers, rendering.
5. Attestation service tick, BLE message-transfer tick.
6. `ModuleRegistry::dispatchTick(nowMs)`.

Several dedicated FreeRTOS tasks run beside it: the keypad task, the display
render task, TinyUSB, the BLE/Wi-Fi stacks, and the plugin tick task (`plg_tick`)
that drives WASM plugins outside the main loop. Shared hardware is protected by
mutexes (panel mutex, SPI lock), which is why a plugin's display flush can
contend with the UI.

### EventBus

A publish/subscribe bus on a FreeRTOS queue: no heap, up to 16 handlers, queue
depth 32. Publishing is ISR-safe, and handlers run later from the main loop.
Subscriptions are `EventType` bitmasks. The plugin-visible `EVENT_*` bits in
`host_api.h` equal `1 << EventType ordinal`, and a `static_assert` keeps the two
in sync. See [plugin lifecycle and events](../plugin-runtime/lifecycle-events-and-ui.md).

## Cross-cutting policies (ADRs)

| ADR | Rule | Consequence for a plugin author |
|---|---|---|
| 0001 PSRAM-first | Internal SRAM is the binding constraint; PSRAM (8 MB Octal, 80 MHz) is the default pool. Internal RAM is only for stacks, ISR data, radio buffers and small statics. | Plugin linear memory is allocated from PSRAM. It is plentiful but slower than SRAM. |
| 0002 Module isolation | Core never references modules. | Plugins likewise talk to modules only through host APIs and events. |
| 0005 No migration | Pre-1.0: on-device formats are replaced, not migrated. A changed build profile wipes NVS and TROPIC01 data. | Any flash may erase plugin storage. Keep exportable state. |
| 0006 Capability sandbox | See [manifest and capabilities](../plugin-runtime/manifest-and-capabilities.md). | |
| 0007 Canonical host API | `host_api.h` in the OS is canonical, and the SDK mirrors it. | See [host API reference](../plugin-runtime/host-api-reference.md). |
| 0008 Single BLE controller | One shared NimBLE controller; services are committed after boot. | Plugin BLE use goes through the shared controller. |
| 0009/0014 E-paper refresh | PARTIAL → FAST → FULL escalation. | See [display](../hardware/display-and-graphics.md). |
| 0012 Build profiles | Dev and release build profiles with different defaults. | See [build and flashing](build-flash-and-partitions.md). |
| 0013 Emulator rehosting | The real plugin_manager is compiled for the host. | See [emulator](../workflows/emulator.md). |
