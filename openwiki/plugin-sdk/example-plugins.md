---
type: "Reference"
title: "Example and production plugins"
openwiki_generated: true
verified:
  - by: openwiki/0.5.2
    at: 2026-11-14T16:21:12.965Z
sources:
  - id: openwiki-source-651d1fb6c9e49916a916ab51
    resource: repo://Cargo.toml
  - id: openwiki-source-04a51e7c865423d871bbe1b5
    resource: repo://docs/runbooks/badge-device.md
  - id: openwiki-source-1297ec01979fd634d1962794
    resource: repo://plugins/snake/Cargo.toml
  - id: openwiki-source-4c340b7a731b439c6a33f78f
    resource: repo://plugins/snake/meta.json
  - id: openwiki-source-3c9b84a70c642739fffc76f3
    resource: repo://plugins/snake/src/game.rs
  - id: openwiki-source-caf818c738c97140995ce83e
    resource: repo://references/cdc-badge-development/plugins/starter/Cargo.toml
  - id: openwiki-source-e6837e378cfce0baeec36e03
    resource: repo://references/cdc-badge-development/plugins/starter/src/lib.rs
  - id: openwiki-source-a92c04f819bba26dcc8b09b9
    resource: repo://references/cdc-badge-plugins/examples/canvas_demo/meta.json
  - id: openwiki-source-bebc132e54162e83bf6453b1
    resource: repo://references/cdc-badge-plugins/examples/gpio_mqtt/meta.json
  - id: openwiki-source-0f4584ce2b6fab448244648e
    resource: repo://references/cdc-badge-plugins/plugins/grove_led/meta.json
  - id: openwiki-source-68afe990c74fb4d77b202539
    resource: repo://references/cdc-badge-plugins/plugins/matrix/meta.json
  - id: openwiki-source-5ded9d277397a439fbba8003
    resource: repo://references/cdc-badge-plugins/plugins/sdk_probe/meta.json
  - id: openwiki-source-372858cc68b7890bcb9cebec
    resource: repo://references/cdc-badge-plugins/plugins/thermo_printer/meta.json
  - id: openwiki-source-b36d406c78376a45c09e9b2b
    resource: repo://references/cdc-badge-plugins/plugins/webserver/meta.json
  - id: openwiki-source-edf57d425cf4973bb79fe308
    resource: repo://references/SOURCES.md
generated: { by: "opencode", at: "2026-11-14T16:21:12.965Z" }
---


# Example and production plugins

All of these are Rust crates built against the `cdc-badge-plugin` SDK (see
[Rust SDK](rust-sdk.md)). The table below is generated from each `meta.json`
plus a line count of `src/**/*.rs` in our snapshot. "API" is
`host_api_level_min`. Plugins declaring 0.7 still load on a 0.8 host (same major,
lower minor).

## In-repo: `plugins/snake` (first workspace member)

The repository's own first plugin is a **verbatim copy of the upstream
production `snake`** (`references/cdc-badge-plugins/plugins/snake`) — the only
change is that `Cargo.toml` points the SDK dependency at the vendored path
`../../references/cdc-badge-plugins/sdk/cdc-badge-plugin` (feature
`panic_handler`). It is the first member of the root `Cargo.toml` workspace, so
it builds and tests directly:

- `cargo test -p snake` — **18 host unit tests** on the pure game logic
  (`src/game.rs`); `lib.rs`, `game.rs`, `render.rs`, `sprites.rs`.
- `crate-type = ["cdylib", "rlib"]` so the same crate produces the badge
  `cdylib` and a host-testable `rlib`.
- `meta.json`: API 0.8, 64 KB linear memory, `ui_exclusive`,
  `nvs_namespace plg_snake` — matches the upstream row in the production table.
- `scripts/plugin-build.sh` compiles it to a **~30 KB wasm** that passed the
  contract checks (cdc-only imports, size limit, manifest) and was **flashed
  and run on a real badge** (see [plugin build and install](../workflows/plugin-build-and-install.md)
  and `docs/runbooks/badge-device.md`).

Copy it for new in-repo plugins: create `plugins/<id>/`, keep the path-dep on
the vendored SDK, and add the directory to the workspace `members`.

## Templates and starters

| Plugin | Where | API | What it shows |
|---|---|---|---|
| `starter` | `cdc-badge-development/plugins/starter` | 0.7 | Heavily commented hello-world, built for **test-driven development**: pure logic at the top, unit-tested with `cargo test` on the host; the plugin glue is compiled only under `cfg(target_arch = "wasm32")`; `#![cfg_attr(target_arch="wasm32", no_std)]`; the SDK is a wasm-only dependency with the `panic_handler` feature; release profile `opt-level="z"`, LTO, one codegen unit, `panic="abort"`, strip. |
| `plugin_template_rust` (`my_plugin`) | `cdc-badge-plugins/sdk/plugin_template_rust` | 0.8 | Minimal 42-line skeleton for `cargo generate`-style copying |
| `plugin_template_c` | `cdc-badge-plugins/sdk/plugin_template_c` | — | The same contract in C (CMake, includes `host_api.h` directly) |

**Starter path caveat:** `starter/Cargo.toml` points at
`../../vendor/cdc-badge-plugins/sdk/cdc-badge-plugin`, a submodule path that is
empty in our snapshot. To build it here, point the path at
`references/cdc-badge-plugins/sdk/cdc-badge-plugin`.

## Examples (`cdc-badge-plugins/examples/`)

| Plugin | API | Mem KB | Rust lines | Capabilities / prerequisites | Demonstrates |
|---|---|---|---|---|---|
| `hello_world` | 0.7 | 64 | 135 | — | Toast, i18n (`*.lang.json`) |
| `battery_widget` | 0.7 | 64 | 123 | — | Power API, live updates |
| `canvas_demo` | 0.8 | 64 | 877 | — | Every canvas feature: primitives, bitmaps, CP437 symbols, shades, elements, tweens, sprites, z-order. It is also the emulator's snapshot-test fixture. |
| `grove_blink` | 0.7 | 64 | 192 | `grove` | GPIO output on Grove pin 0 |
| `gpio_mqtt` | 0.7 | 96 | 718 | `wifi`, `socket`, `grove`, `sao`, `ui_exclusive`, `prevent_sleep`, `gpio_pins` [4,5,6,7,9,14,38,40,43,44], `rmem` [`mqtt_pass`], ns `plg_gpio_mqtt`; prereq `wifi_connected` | Raw TCP MQTT client, secret kept in SE R-Memory, the full allowed pin list |
| `mini_messenger` | 0.7 | 64 | 116 | `ble`, `message_types` [`text/plain`] | Badge-to-badge message transfer |
| `news_feed` | 0.7 | 128 | 547 | `wifi`, `http`, `ui_exclusive`; prereq `wifi_connected` | Streamed HTTP, XML (Atom) parsing, list views |
| `print_counter` | 0.8 | 128 | 210 | `wifi`, `http`, `background` | Background residency (`set_resident`), HTTP |
| `sci_calc` | 0.7 | 96 | 1110 | `vfat` | Long-press quick keys, function menu, file storage |

## Production plugins (`cdc-badge-plugins/plugins/`)

| Plugin | API | Mem KB | Rust lines | Capabilities | Demonstrates |
|---|---|---|---|---|---|
| `name_badge` | 0.8 | 128 | 1928 | `prevent_sleep`, `ui_exclusive` | Animated name tag with eight e-paper effects (`fx/`: bounce, glitch, typewriter, wipe…), dithering, text fitting. Relevant to e-paper animation budgets. |
| `snake` | 0.8 | 64 | 1637 | `ui_exclusive` | Game loop on e-paper with animated sprites, high scores in NVS. **Copied in-repo as `plugins/snake`** — the copy source for new plugins. |
| `home_assistant` | 0.7 | 1024 | 1807 | `wifi`, `http`, `ui_exclusive`, `rmem` [`ha_token`], ns `plugin_ha` | REST client, token in SE, browse/favorites UI |
| `matrix` | 0.7 | 1024 | 5027 | `wifi`, `http`, `ui_exclusive`, `prevent_sleep`, `rmem` ×4, ns `plg_matrix` | The largest plugin: Matrix chat with Olm/Megolm E2EE (vodozemac), custom getrandom backend, 256 KiB shadow stack (`build.rs`), host-test stubs. It shows the upper bound of what fits. |
| `ble_scanner` | 0.7 | 64 | 444 | `ble`, `prevent_sleep`, `vfat` | BLE central scanning, RSSI sorting, CSV export (`EXPORT.md`) |
| `grove_led` | 0.8 | 64 | 641 | `background`, `autoload`, `pixel_strip` | Autoload service driving a WS2813 strip on Grove |
| `thermo_printer` | 0.8 | 256 | 2799 | `ble`, `vcard`, `vfat`, `wifi`, `net_listen`, `background`, `autoload`, `message_types` [`image/jpeg`], `provides` [`thermo_print`] | BLE central printer protocol, raster/QR layout, the **external-feature provider** pattern, and inbound jobs over BLE messaging or TCP |
| `webserver` | 0.8 | 128 | 439 | `net_listen`, `wifi`, `vfat`, `background`, `autoload` | Inbound TCP listener serving vFAT files on port 80 |
| `sdk_probe` | 0.8 | 128 | 1448 | Nearly everything, including `ecc` [`probe`], `rmem` [`probe`], `display_lowlevel`, `i2c_bus` [1], PWM/ADC pins, `provides` [`probe_echo`] | Serial diagnostic that calls **every SDK binding once**. The best reference for exact call shapes, and a smoke test for a new firmware. |

## Which one to start from

| Our application needs… | Copy from |
|---|---|
| An in-tree plugin that builds and runs today | `plugins/snake` (first workspace member — the copy source for new plugins) |
| A testable skeleton | `starter` (TDD layout) + `plugin_template_rust` |
| Menus and settings with no custom drawing | `hello_world`, `news_feed` (lists) |
| Custom screens or animation | `canvas_demo`, then `name_badge` / `snake` |
| Networking | `news_feed` (HTTP), `gpio_mqtt` (raw socket), `webserver` (listener) |
| Secrets | `home_assistant` / `gpio_mqtt` (`rmem`), `sdk_probe` (`ecc`) |
| Background service | `print_counter`, `grove_led` (autoload) |
| Badge-to-badge | `mini_messenger` |
| Calling other plugins | `thermo_printer` (provider) and `ext_feature_use` callers |
| A large dependency tree (crypto, serde) | `matrix` (stack size, getrandom shim, host-test stubs) |

Watch the shared limits when combining ideas from these plugins. `matrix`
alone declares 4 of the 11 plugin R-Memory slots, and several plugins request
`ui_exclusive` (see [manifest and capabilities](../plugin-runtime/manifest-and-capabilities.md)).
