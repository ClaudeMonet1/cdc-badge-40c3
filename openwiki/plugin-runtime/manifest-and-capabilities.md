---
type: security model
title: Plugin manifest, capabilities and sandbox security
description: The meta.json manifest of a cdc-badge-os plugin (fields, i18n, capabilities, prerequisites), how capabilities are validated at load and enforced per host call, per-plugin storage isolation (NVS, vFAT, secure element), the GPIO policy, the absence of plugin signing, and the resulting threat model for our Rust WASM application.
tags: [manifest, capabilities, sandbox, security, nvs, vfat, gpio, prerequisites, threat-model]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-d036dc40c58b866b2d776e86
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/CapabilityChecker.cpp
  - id: openwiki-source-9143e6a77f299e9c60b3dcdc
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_fs.cpp
  - id: openwiki-source-51c459894bd85636fc99b8af
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_nvs.cpp
  - id: openwiki-source-84576151a1e5dc8e04fe8055
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginSerialCommands.cpp
  - id: openwiki-source-adf708a7e32b2e6b193cc52a
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginStorage.cpp
  - id: openwiki-source-609ee9ef8b3651ae376f6509
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/Prerequisites.cpp
  - id: openwiki-source-c801cf7787387736434f7d04
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0006-plugin-sandbox-capability-model.md
  - id: openwiki-source-bdc5587210a2ab529b3a8f33
    resource: repo://references/cdc-badge-plugins/docs/capabilities.md
  - id: openwiki-source-66c082681bd6e4e191f60ce2
    resource: repo://references/cdc-badge-plugins/docs/manifest_schema.md
  - id: openwiki-source-a9c75f12bd348edf3929a098
    resource: repo://references/cdc-badge-plugins/tools/validate_manifest.py
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Plugin manifest, capabilities and sandbox security

## The sandbox in one paragraph (ADR-0006)

A plugin is untrusted code on a hardware security key. It runs as **interpreted
WebAssembly** in WAMR. AOT native code is disabled by default
(`FEATURE_PLUGIN_AOT=0`) because it would bypass the bounds-checked interpreter.
Its linear memory lives in PSRAM (manifest range 16–4096 KB). Every `host_*`
call validates the full extent of each pointer argument and checks the
manifest's capabilities. Hardware access goes through a firmware hard-block list
plus a per-pin manifest whitelist. See [WAMR runtime](wamr-runtime.md) for the
execution side.

## `meta.json`

The manifest ships next to the `.wasm`. It is parsed by
`components/plugin_manager/src/PluginManifest.cpp` (cJSON), validated by
`CapabilityChecker.cpp` at load, and checked offline by
`cdc-badge-plugins/tools/validate_manifest.py`.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Filename stem (`/vfat/system/<id>.wasm`). By convention `[a-z][a-z0-9_]*`; the parser only requires non-empty. |
| `version` | yes | SemVer |
| `host_api_level_min` | yes | `"0.8"`; major must match and minor must be ≤ the host's ([host API](host-api-reference.md)) |
| `linear_memory_kb` | yes | See the range discrepancy below. The module's own memory declaration actually sizes the instance; this field is validated and displayed. |
| `author`, `icon` | no | `icon` is a built-in identifier (`info`, `battery`, `ha`, …) |
| `i18n` | no | `default_language`, `meta.name/description`, and `strings` per language. Looked up with `host_i18n_tr_key` / `host_i18n_tr_meta`. |
| `capabilities` | no | Flat map, below |
| `prerequisites` | no | Map of name → `{…, on_fail: abort\|warn\|callback}` |

**`linear_memory_kb` range disagreement:** the firmware accepts **16–4096**
(`CapabilityChecker.cpp` `LINEAR_MEMORY_MAX_KB = 4096`, ADR-0006, SDK
`capabilities.md`), but `manifest_schema.md` and `validate_manifest.py` allow
only **16–1024**. Stay ≤ 1024 so CI validation passes.

### Capabilities

| Capability | Type | Grants |
|---|---|---|
| `wifi`, `http`, `socket`, `net_listen` | bool | Wi-Fi request/scan, outbound HTTP(S), TCP/UDP client, inbound TCP listener |
| `ble` | bool | GATT server and central. GATT services also need `ble_service_uuids` (128-bit lowercase). |
| `message_types` | string[] | MIME types for badge-to-badge messages (also needs `ble`) |
| `display_lowlevel` | bool | Direct framebuffer + `host_display_flush` |
| `ui_exclusive` | bool | Exclusive view-stack ownership |
| `usb_cdc`, `vfat`, `vcard`, `pixel_strip` | bool | USB CDC writes, sandboxed files, vCard store, addressable LEDs |
| `gpio_pins`, `pwm_pins`, `adc_pins` | int[] | Individual pins from the allowed list ([pin map](../hardware/pin-map-and-buses.md)) |
| `grove`, `sao` | bool | Shortcuts: GPIO 2/3; GPIO 15/16 + SAO EEPROM at I²C1 0x50 |
| `i2c_bus` | int[] | Only `1` is usable; bus 0 is reserved |
| `rmem`, `ecc` | string[] | Named secure-element slots, 1–15 chars. `rmem` also requires `nvs_namespace`. |
| `nvs_namespace` | string | `plg_`/`plugin_` prefix, `[a-z0-9_]`, ≤ 15 chars, not `plg_ecc_map` |
| `provides` | string[] | ≤ 4 external feature names this plugin serves (`[a-z][a-z0-9_]*`, ≤ 32 chars) |
| `background`, `autoload` | bool | **Permission** to stay resident (also needs `host_set_resident(true)`) |
| `prevent_sleep` | bool | Holds a light-sleep inhibitor while loaded |

### Prerequisites

`Prerequisites.cpp` implements `wifi_connected` (with `timeout_ms`),
`time_synced`, `battery_min` (`min_pct`), `usb_connected`, `not_charging`,
`min_free_psram`, `min_free_dram` and `unlocked`. They are checked in manifest
order before `plugin_on_enter` and released in reverse order on exit. For
example, Wi-Fi that the host brought up is dropped again.

## Enforcement points

| When | What is checked | Failure |
|---|---|---|
| Install (offline) | `validate_manifest.py` in plugin CI | Build fails |
| Load (`CapabilityChecker`) | API level, memory range, name lengths, UUID format, NVS namespace rules, `provides` names, GPIO pins against `PluginGpioPolicy` (blocked or not allowed), pin conflicts with already-loaded plugins | Plugin not started ("GPIO N already held by `<id>`" etc.) |
| Each host call (`host_api_*.cpp`) | Capability flag or name/pin membership; full-extent pointer validation (`wbuf_ok`) | `HOST_ERR_NO_CAPABILITY` / `HOST_ERR_INVALID_ARG`. Logged; the plugin continues. |
| Runtime UI state | Keypad reads and key events need input focus; `host_lockscreen_alert` needs no other modal | `HOST_ERR_NOT_FOUND` / `HOST_ERR_BUSY` |

## Storage isolation

| Store | Scope | Notes |
|---|---|---|
| **NVS** (`host_nvs_*`, no capability) | The declared `nvs_namespace`, else `plugin_<id>` | The host selects the namespace, never the plugin. The prefix rule keeps plugins away from system namespaces (`nvs.net80211` Wi-Fi credentials, `display`, `mod_*`). **Pitfall:** with no declared namespace, an `id` longer than 8 characters gives `plugin_<id>` > 15 chars, and every NVS call returns `HOST_ERR_NO_CAPABILITY`. Always declare `nvs_namespace`. |
| **vFAT files** (`host_fs_*`, `vfat`) | `/vfat/data/<id>/` | Only bare filenames (`[A-Za-z0-9._-]`, no separators, no leading dot), so escaping the directory is impossible |
| **Secure element** (`host_rmem_*`, `host_ecc_*`) | Names declared in `rmem`/`ecc` | Names are a **shared** namespace across plugins (see [secure element](../hardware/secure-element.md)). The pools hold 11 R-Memory slots and 1 ECC slot. |
| `.wasm` + manifest | `/vfat/system/<id>.*` | Written by the installer (see [plugin build and install](../workflows/plugin-build-and-install.md)) |

**Isolation is by declaration, not by identity.** Two plugins that declare the
same `nvs_namespace`, `rmem` name or `ecc` name share that storage. The docs
call this intentional ("common scope"). Nothing binds a namespace to an
author or signing key, so a malicious plugin can declare another plugin's
namespace or slot names and read its data. Treat on-device plugin storage as
shared with every other installed plugin.

## Trust and distribution

- **No plugin signing.** Serial upload verifies only a CRC32 of the transferred
  bytes (`PluginSerialCommands.cpp`), and the manifest has no signature field.
  Anyone who can talk to the serial console can install code. With the default
  beta profile, `FEATURE_SECURE_SERIAL=0`, so no PIN is needed for the console.
- **No install-time consent screen** is described in the OS user docs. The
  capability list can be inspected with the serial `PLUGIN INFO <id>` command
  and in the plugin info view.
- What protects the security functions is therefore the **sandbox boundary**,
  not plugin provenance. Plugins can't reach PIN/lock-screen state, FIDO2/GPG/PIV
  keys, reserved TROPIC01 slots, charger control, bus 0, the display or SE SPI
  lines, or raw HID.

## Threat model for our Rust plugin

| Asset | Exposure |
|---|---|
| Our NVS, files and R-Memory | Readable by any plugin that declares the same names. Encrypt sensitive blobs with a key derived from `host_ecc_*` signatures or user input, not from a stored secret. |
| Our ECC key | Non-exportable, but any plugin declaring the same `ecc` name can sign with it. Choose a unique name and verify `host_ecc_pubkey` against a pinned value. |
| User input | The keypad is only visible while our view has focus, which protects the PIN. Other plugins can't sniff it either. |
| Network | Plain HTTP(S) via the host stack; certificate handling lives in the firmware (`esp_crt_bundle`). |
| Availability | One trapping or slow plugin stalls all plugin calls (shared call mutex), but not the OS. |
