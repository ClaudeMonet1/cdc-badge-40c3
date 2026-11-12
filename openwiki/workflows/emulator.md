---
type: developer workflow
title: Off-device plugin emulator
description: The cdc-badge-development emulator that runs a plugin .wasm on a desktop by re-hosting the real cdc-badge-os WAMR runtime, host-API bodies, view stack and e-paper drawing code behind host backends — what is real versus stubbed, CLI and console, deterministic snapshot testing, the dev-only software secure element, and how to build it from this repository.
tags: [emulator, testing, wamr, snapshot, workflow, cmake, sdl2]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-5a81171e44b36925cf23a168
    resource: repo://references/cdc-badge-development/emulator/CMakeLists.txt
  - id: openwiki-source-db7ae95d89816d9814fded8b
    resource: repo://references/cdc-badge-development/emulator/README.md
  - id: openwiki-source-b83df52cadcf1e6acd4632ac
    resource: repo://references/cdc-badge-development/emulator/src/WamrImports64.cpp
  - id: openwiki-source-aaaae0d06618766285ac2706
    resource: repo://references/cdc-badge-development/emulator/tests/CMakeLists.txt
  - id: openwiki-source-102679e338db93cd4c4318e1
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/WamrImports.cpp
  - id: openwiki-source-b5862e9e95cace84643b81e7
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0013-offdevice-emulator-rehosting.md
  - id: openwiki-source-edf57d425cf4973bb79fe308
    resource: repo://references/SOURCES.md
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Off-device plugin emulator

`references/cdc-badge-development/emulator/` runs a plugin's `.wasm` on Linux,
macOS or Windows without badge hardware. It is the fastest loop for developing
our Rust plugin before flashing it to a badge.

## Design (ADR-0013)

The emulator is not a SoC emulator, and it doesn't reimplement the API. It is a
C++ CMake target that **re-hosts read-only cdc-badge-os sources**:

- WAMR with the device's interpreter flags (fast interpreter, AOT off), built
  for `X86_64` or `AARCH64`
- the firmware `WamrImports.cpp` and the in-scope `host_api_*.cpp` bodies
- the `Adafruit_GFX` / CalEPD `Gdey029T94` drawing core and the
  `cdc_ui` / `cdc_views` / `PluginUiState` view stack

Hardware is replaced at the **HAL factory boundary** (`getDisplayInstance()`
etc.) by host backends in `src/backends/`: `HostDisplay`, `HostKeypad`,
`HostNvs`, `HostSecureElement`, `HostNet`, `HostHttpClient`,
`HostMessageTransfer`, `HostPower`, `HostRtc`, `HostCpuStats`, a fake
`LockscreenView`, and a `VirtualClock`. About 15 shim headers in `shim/`
(FreeRTOS → std mutexes, `esp_timer` → virtual clock, NVS → file KV, no-op
drivers) close the gap. The `EpdSpiStub` captures the panel byte stream, so
**frames are pixel-identical to what the e-paper receives**.

One host-specific fix: `WamrImports64.cpp` overrides the 5 natives that read
structs with embedded pointers (`ui_item_t` in list push/replace/update/insert
and the context menu). The firmware casts plugin memory directly, which works
with 32-bit pointers on the ESP32 but breaks on a 64-bit host. WAMR resolves the
most recently registered table first, so these shadow the firmware wrappers.

## What is real and what is stubbed

| Real | Clean stubs ("unavailable" error) | Simulated |
|---|---|---|
| Drawing and view stack, host-API bodies, WAMR interpreter semantics, NVS and vFAT persistence (files under `--data`), crypto (mbedTLS P-256, Ed25519), HTTP and sockets over the real network (Wi-Fi always "connected") | BLE, GPIO/PWM/ADC/I²C/SAO, pixel strip, USB CDC | Badge-to-badge messages as JSON packets in `<data>/msg/out/`, injected with `--msg-in`. A fake lock screen (`L`, no PIN) tests background residency and quick actions. `--sim-light-sleep` / `--sim-deep-sleep`. Prerequisites run as on the device and can be forced to fail with `--fail-prereq`. |

**Security notice:** the secure element is a software mock that stores keys and
R-Memory in **plaintext** under `<data>/se/`, and HTTP TLS verification is
**disabled**. It implements no irreversible TROPIC01 operation, which the
`se_safety` CTest enforces. Never treat emulator results as security
evidence.

## Usage

```bash
python tools/badge.py emulate <plugin|path.wasm> [options]
```

| Option | Purpose |
|---|---|
| `--no-build` | Use the existing `dist/<name>.wasm` |
| `--headless` | No window; PNG/hash output only (CI) |
| `--keys 1,2,Y,N` | Scripted keys. `5!` = long press, `@battery_low` = EventBus event. |
| `--cmd <str\|@file>` | Feed `plugin_on_cmd` |
| `--fail-prereq <name>` | Exercise `on_fail` handling |
| `--frames <dir>` / `--snapshot <dir>` | PNG per committed frame / compare frame hashes (non-zero exit on mismatch) |
| `--data <dir>` | Persistent NVS, vFAT and SE store |
| `--offline` | HTTP/socket return the network error the plugin would see |
| `--seconds n` / `--ticks n` | Advance the virtual clock deterministically |
| `--serve n` | Wall-clock headless run so real TCP listeners stay reachable |

Window keys: `0`–`9`, `Y`/Enter, `N`/Esc/Backspace, arrows = 2/4/6/8, and hold
> 800 ms for a long press. From a terminal, a REPL accepts `key`, `keys`,
`paste`, `cmd`, `event`, `advance`, `screenshot`, `offline`, `status`, `lock`,
`msg-in` and `quit`.

### Determinism and tests

A single `VirtualClock` drives `esp_timer`, FreeRTOS ticks and
`plugin_on_tick` (50 ms, like the device), and the RNG is seeded, so scripted
runs produce byte-identical frames. CTest targets
(`emulator/tests/CMakeLists.txt`): `backends`, `se_safety`,
`canvas_demo_snapshot`, `mini_messenger_snapshot`, `lockscreen_residency`,
`msg_roundtrip`, `paste_encoding` and `webserver_http`. Snapshot fixtures are
frame hashes under `tests/snapshots/<plugin>/` driven by key scripts in
`tests/keyscripts/*.keys`. `tests/run_examples.py` runs every example for
crashes, and `tests/coverage_notes.md` maps each host-API family to its
emulation status.

## Version skew to be aware of

- The README and ADR say the emulator exposes a **225-symbol** `"cdc"` API. The
  OS snapshot we vendor registers **307**. The emulator compiles whatever
  `vendor/cdc-badge-os` is checked out, and the development repo pins an
  **older** OS commit (`7682dec…`) than ours (`181a24d…`). Newer host functions
  are missing until that pin moves, and a plugin importing one fails to
  instantiate in the emulator while working on the device.
- `emulator/CMakeLists.txt` hard-codes `VENDOR = ../vendor/cdc-badge-os/components`
  and stops with `FATAL_ERROR` if that submodule (plus its nested
  `wasm-micro-runtime`) is missing. In this repository those directories are
  empty.

### Building it here

Our Nix shell has cmake, pkg-config, SDL2 and gcc. Two ways to satisfy the
vendor path:

1. Clone upstream `krim404/cdc-badge-development` outside `references/` with
   `git submodule update --init --recursive` (this matches the emulator's
   pinned OS).
2. Or place a full checkout of the OS **at our pinned commit, with submodules**
   at `cdc-badge-development/vendor/cdc-badge-os` in a scratch copy. This is
   newer and closer to the device, but untested against this emulator revision.

Then run `cmake -S emulator -B emulator/build && cmake --build emulator/build`.
Prebuilt binaries (AppImage/.deb, Windows .exe, unsigned macOS) come from the
upstream `release-emulator` workflow.

Related: [plugin build and install](plugin-build-and-install.md),
[WAMR runtime](../plugin-runtime/wamr-runtime.md),
[host API](../plugin-runtime/host-api-reference.md).
