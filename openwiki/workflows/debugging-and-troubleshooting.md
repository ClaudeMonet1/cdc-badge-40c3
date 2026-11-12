---
type: playbook
title: Debugging and troubleshooting plugins
description: Symptom-to-cause playbook for cdc-badge-os plugins — reading the serial log, plugin logging levels, PLUGIN INFO/DEBUG/LIST, the load sequence and its log messages, host error codes, Rust panics and WAMR traps, the 50-entry ERROR_LOG ring, MEMINFO/MEM/CPU, flash core dumps, and the most common e-paper, keypad and capability mistakes.
tags: [debugging, troubleshooting, serial, logging, traps, coredump, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-1891235328b68ffbc23a1094
    resource: repo://references/cdc-badge-os/components/cdc_log/include/cdc_log.h
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-d4b13a9a0f745bb69f4d87a3
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_log.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
  - id: openwiki-source-84576151a1e5dc8e04fe8055
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginSerialCommands.cpp
  - id: openwiki-source-ebcbc9781ed420f4f17c97e4
    resource: repo://references/cdc-badge-os/sdkconfig.defaults
  - id: openwiki-source-0d45e9b73698135032dff07d
    resource: repo://references/cdc-badge-os/tools/coredump.py
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Debugging and troubleshooting plugins

Upstream companions:
`cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/debugging.md`
and `pitfalls.md` (see [upstream skill](../reference/upstream-plugin-dev-skill.md)).
Off-device first: the [emulator](emulator.md) reproduces drawing and host-API
behaviour deterministically.

## 1. Get the log

- Open the USB serial port at 115200 baud: `badge monitor`, `pio device
  monitor`, or any terminal. Only one program can hold the port, so close the
  monitor before uploading.
- Standard builds gate commands behind **`AUTH <pin>`**. Logs stream regardless.
  See [serial console](../os/serial-console-and-auth.md).
- **Plugin logging:** `host_log(level, tag, msg)` / SDK `log::error|warn|info|debug|verbose`
  maps onto the firmware's `cdc_log` with your tag (`host_api_log.cpp:17-27`;
  levels `LOG_LEVEL_ERROR` 0 … `VERBOSE` 4). `host_log_hex` dumps bytes.
- **`PLUGIN DEBUG`** toggles verbose `host_*` logging for every call.
- **Don't log secrets.** The log is readable by anyone at the port, and
  `ERROR_LOG` needs no AUTH.

## 2. Does it load?

`PLUGIN LIST` (JSON) and `PLUGIN INFO <id>` show what the badge parsed:
capabilities, `linear_kb`, prerequisites. A failed start logs one of these
(`PluginManager.cpp`):

| Log line | Meaning / fix |
|---|---|
| `plugin <id> is disabled` | Enable it (`PLUGIN ENABLE <id>` or the plugin list) |
| `manifest missing/invalid` | `meta.json` didn't parse or lacks required fields. Run `validate_manifest.py`. |
| `capability check failed for <id>: …` | API level, memory range, names, UUIDs, blocked pins, or a resource collision with a loaded plugin ([manifest](../plugin-runtime/manifest-and-capabilities.md)) |
| `native AOT images are not accepted` | Only bytecode loads ([WAMR](../plugin-runtime/wamr-runtime.md)) |
| `wasm_runtime_load failed` / `instantiate failed` + WAMR text | Unknown import (only module `"cdc"` exists), invalid wasm, or not enough PSRAM |
| `plugin_on_enter missing` / `plugin: missing export '…'` | Required export not `#[no_mangle] pub extern "C"` |
| `plugin_init failed (rc=…)` | Your `plugin_init` returned non-zero |
| `prerequisite '…' aborted start` | e.g. Wi-Fi not connected, battery too low |

Check imports before uploading: `wasm-tools print x.wasm | grep import`.

## 3. Error codes from host calls

| Code | Usual cause |
|---|---|
| `-2 INVALID_ARG` | Bad pointer or length (WAMR bounds check), wrong bus, out-of-range id |
| `-3 NO_CAPABILITY` | Capability missing, or a name not declared (`rmem`/`ecc`), or a pin not allowed. Logged by the host. |
| `-4 NOT_FOUND` | Empty queue, missing key or file, no provider, no input focus for keypad reads |
| `-7 BUSY` | Resource held by another plugin (pin, BLE slot, ext-feature job, send in progress); msg handler registration (a known bug, [BLE review](../os/security/ble-message-transfer.md)) |
| `-6 NO_MEMORY` | Slot table full (event subscriptions, sockets, HTTP) or PSRAM exhausted |
| `-9 RMEM_FULL` | Plugin R-Memory pool (11 slots) exhausted |

Full table: [host API](../plugin-runtime/host-api-reference.md).

## 4. Panics and traps

- With the SDK `panic_handler` feature, a Rust panic logs `PANIC <message>` and
  then hits `unreachable`.
- Any trap prints a `PLUGIN TRAP` banner with the function, the WAMR reason and
  "force-unload". `plugin_deinit` is **not** run, and the host frees resources.
  See [lifecycle](../plugin-runtime/lifecycle-events-and-ui.md#failure-behaviour-traps).
- **Common reasons:**
  - `unreachable`: a panic, or a failed `memory.grow`. The allocator log reports
    the PSRAM state. Shrink the stack (`-z stack-size`) and the heap.
  - Instruction limit exceeded: more than 500 M instructions in one call, so
    split work across ticks.
  - Out-of-bounds memory access.
  - WAMR stack overflow: deep recursion with the 64 KiB exec stack.

## 5. System state

| Command | Shows |
|---|---|
| `ERROR_LOG [CLEAR]` | The last **50** WARN/ERROR lines (100 chars each) from a PSRAM ring (`cdc_log.h`), including plugin warnings |
| `MEM` / `MEMINFO` | Heap, internal DRAM, DMA, PSRAM, per-region detail, FreeRTOS task stack watermarks (`plg_tick` among them) |
| `CPU` | CPU load over about 250 ms |
| `VERSION` | Firmware version, host API level, build profile |
| `TR01 SLOTS` | Secure-element slot usage (AUTH) |

**Core dumps:** firmware crashes (not plugin traps) are written as ELF to the
`coredump` flash partition (`0xFF0000`; `sdkconfig.defaults:89-91`). Fetch and
analyse them with `tools/coredump.py [port]` (espcoredump + GDB).

## 6. Symptom → cause

| Symptom | Likely cause |
|---|---|
| Builds and tests pass, display garbled | Canvas layout: body coordinates, header offset, font height (`pick_font_that_fits` checks width only). Verify on the device or in the emulator. |
| Flicker or ghosting | Redrawing every tick. Redraw only on change and commit FAST after big changes ([canvas](../plugin-runtime/canvas-surfaces-and-animation.md)). |
| Keys do nothing / can't leave | A canvas key callback consumes all keys, including N. Handle back and `ui::pop()`. |
| Background plugin stops ticking | No `set_resident(true)`, or the badge went to light sleep (use `prevent_sleep` / `set_sleep_inhibit`) |
| HTTPS fails after deep sleep | Clock unset; wait for `time_synced` ([networking](../plugin-runtime/networking-wifi-http-sockets.md)) |
| Upload "busy" | The USB mass-storage drive is mounted on the host ([storage tools](../os/storage-tools.md)) |
| Data gone after a firmware update | Pre-1.0 no-migration wipe; plugin data isn't backed up ([backup](../os/backup-and-restore.md)) |
| Plugin missing from `PLUGIN LIST` after flash | Load rejected; read the log lines above |
