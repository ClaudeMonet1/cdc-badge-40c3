---
type: quickstart
title: Quickstart
description: Entry point to the badge-cdc wiki — what this project is (a sandboxed Rust WebAssembly application for the CDC Badge running on cdc-badge-os), the ten facts to know before writing code, and a task-routing table pointing to the right page for pins, host functions, capabilities, building, installing and emulating.
tags: [quickstart, index, routing, overview]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T20:57:16.971Z
sources:
  - id: openwiki-source-3eda5d2b85501c78fc0ba02d
    resource: repo://flake.nix
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-dc6ca5600c665b4510239dec
    resource: repo://references/cdc-badge-os/components/cdc_msg/src/MessageTransfer.cpp
  - id: openwiki-source-91a63a3beacec1226cac4b20
    resource: repo://references/cdc-badge-os/main/CMakeLists.txt
  - id: openwiki-source-85b872e7a3df64ece24c87d8
    resource: repo://references/cdc-badge-os/README.md
  - id: openwiki-source-50f6becdca203e7d479d053a
    resource: repo://references/cdc-badge-plugins/sdk/plugin_lifecycle.h
generated: { by: "claude-code", at: "2026-11-12T20:57:16.971Z" }
---

# Quickstart

**badge-cdc** will be a **sandboxed WebAssembly application written in Rust**
for the **CDC Badge** (ESP32-S3, 2.9" e-paper, TROPIC01 secure element, 12-key
keypad). It runs as a **plugin** inside the reference firmware
**cdc-badge-os**, which hosts plugins in a WAMR interpreter and exposes a
capability-gated C ABI. Today the repository holds only the vendored reference
material (`references/`, see `references/SOURCES.md`) and this wiki.

## Ten things to know before writing code

1. Build for **`wasm32-unknown-unknown`** as a `cdylib`. The only allowed
   import module is **`"cdc"`**: no WASI, no threads. Plugins are **interpreted**,
   never AOT. → [WAMR runtime](plugin-runtime/wamr-runtime.md)
2. Use the **`cdc-badge-plugin`** Rust crate (v0.8.0, **GPL-3.0**), which wraps
   307 host functions, host API level **0.8**. → [Rust SDK](plugin-sdk/rust-sdk.md),
   [Host API](plugin-runtime/host-api-reference.md)
3. Required exports: `plugin_required_api_major/minor` (from `plugin_main!()`),
   `plugin_init`, `plugin_deinit`, `plugin_on_enter`, `plugin_on_exit`. Every
   async result comes back via **`plugin_on_action(action_id, idx, data)`**.
   → [Lifecycle](plugin-runtime/lifecycle-events-and-ui.md)
4. Everything you may do is declared in **`meta.json` capabilities**. A missing
   capability returns `HOST_ERR_NO_CAPABILITY`, so never `unwrap()`.
   **Always declare `nvs_namespace`.** → [Manifest and capabilities](plugin-runtime/manifest-and-capabilities.md)
5. Ticks arrive every **50 ms** on one shared task, and all plugin calls are
   serialised. Each call has a 500 M-instruction budget, and a trap force-unloads
   the plugin.
6. The screen is **296×128, 1-bit e-paper**: about 0.4 s for a partial refresh
   and 1–2 s for a fast or full one. Redraw only on change.
   → [Display](hardware/display-and-graphics.md)
7. Input is **12 keys** (0–9, Y, N). Prefer the OS views (lists, T9, confirm) or
   the canvas; raw key reads need focus. → [Keypad](hardware/keypad-and-io-expander.md)
8. Storage: NVS, a vFAT folder and named secure-element slots. All are isolated
   **by declared name only**, and **pre-1.0 firmware flashes can wipe them**.
   → [Secure element](hardware/secure-element.md)
9. Keep the `.wasm` small: ≤ 768 KB enforced by upstream CI, inside a 2 MB
   partition shared by all plugins. → [Build and install](workflows/plugin-build-and-install.md)
10. Iterate in the **emulator** (pixel-identical frames, deterministic) before
    flashing, but it pins an older host API. → [Emulator](workflows/emulator.md)

## Where to look

| I want to… | Read |
|---|---|
| Understand the repo, references and dev shell | [Repository and references](overview/repository-and-references.md) |
| Know what's on the board | [Hardware overview](hardware/board-overview.md) |
| Find a GPIO, bus or header pin, or know whether a plugin may use it | [Pin map, I²C and SPI](hardware/pin-map-and-buses.md) |
| Draw on screen, pick a refresh mode or font | [Display and graphics](hardware/display-and-graphics.md) |
| Handle keys, long presses or the panic chord | [Keypad and I/O expander](hardware/keypad-and-io-expander.md) |
| Read the battery, keep the badge awake, or understand sleep | [Power, charging and sleep](hardware/power-and-charging.md) |
| Store secrets or sign with the TROPIC01 | [Secure element](hardware/secure-element.md) |
| Understand how the OS is put together | [OS architecture](os/architecture.md) |
| Build or flash the OS, or understand partitions | [OS build, partitions and flashing](os/build-flash-and-partitions.md) |
| Know what the OS's GPG / OpenPGP card and cross-signing really check | [GPG module review](os/security/gpg-openpgp-module.md) |
| Know what badge-to-badge Bluetooth transfer guarantees, and why plugin receive is broken | [BLE message transfer review](os/security/ble-message-transfer.md) |
| Check FIDO2 / CTAP2 support and its bugs | [FIDO2 / CTAP2 review](os/security/fido2-ctap2.md) |
| Know memory, stack and instruction limits | [WAMR runtime](plugin-runtime/wamr-runtime.md) |
| Write `meta.json` and choose capabilities; understand the threat model | [Manifest and capabilities](plugin-runtime/manifest-and-capabilities.md) |
| Look up a host function, error code or calling convention | [Host API reference](plugin-runtime/host-api-reference.md) |
| Structure exports, events and UI | [Lifecycle, events and UI](plugin-runtime/lifecycle-events-and-ui.md) |
| Set up the Rust crate | [Rust SDK](plugin-sdk/rust-sdk.md) |
| Find a plugin to copy from | [Example plugins](plugin-sdk/example-plugins.md) |
| Build, upload and run on a badge | [Build and install](workflows/plugin-build-and-install.md) |
| Test without hardware | [Emulator](workflows/emulator.md) |
| Compare with the vendor's Arduino firmware | [Vendor nametag firmware](vendor/nametag-firmware.md) |
| See known contradictions, constraints and open decisions | [Open questions and discrepancies](reference/open-questions-and-discrepancies.md) |

## Getting a shell

```bash
nix develop            # or: direnv allow  — Rust + wasm32, binaryen, wabt, wasm-tools,
                       #   wasmtime, esptool/espflash, pyserial, cmake/SDL2, node 22
openwiki visualize     # browse the wiki graph
```

The official user and developer documentation for the OS is
`references/cdc-badge-os/website/` (published at
https://krim404.github.io/cdc-badge-os/). Treat it as the authority for user-facing
behaviour, but check implementation details against the source. This wiki
records the places where the two disagree.
