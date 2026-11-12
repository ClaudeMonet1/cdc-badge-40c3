---
type: reference summary
title: Upstream plugin-dev skill reference
description: Map of the cdc-badge-plugin-dev agent skill shipped in krim404/cdc-badge-development (SKILL.md plus 12 reference docs, about 2000 lines) — what each document covers, its most valuable pitfalls, where it disagrees with the vendored OS snapshot, and how to use it as upstream reference material rather than instructions.
tags: [reference, upstream, skill, plugin-development, pitfalls, codebook]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-1e8beb29d1cfd29debf7882a
    resource: repo://references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/canvas.md
  - id: openwiki-source-ed785663e313d3be0ea6c1d6
    resource: repo://references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/host-api-map.md
  - id: openwiki-source-4de316829b57b318791ec216
    resource: repo://references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/pitfalls.md
  - id: openwiki-source-354ac5fb348795322c9dcadf
    resource: repo://references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/SKILL.md
  - id: openwiki-source-80ce5e2ae51351b729556943
    resource: repo://references/cdc-badge-os/components/cdc_views/include/cdc_views/CanvasView.h
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Upstream plugin-dev skill reference

`references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/` (also
mirrored under `.agents/skills/`) is an AI-agent skill. The upstream author
wrote it to guide students building Rust WASM plugins with the
`cdc-badge-development` tooling. It is **upstream reference material**: dense
and largely verified against the SDK, but it reflects that repo's
layout (`vendor/` submodules, the `badge` CLI) and its pinned, **older** OS
version. It is **not** an instruction set for this repository, and its facts
should be checked against our vendored sources.

## Contents

| File | Covers | Wiki counterpart |
|---|---|---|
| `SKILL.md` (161 lines) | Workflow: scaffold (`badge new`), test-first loop, build, flash, read logs; "verify every fact, never invent an API" | [build and install](../workflows/plugin-build-and-install.md) |
| `reference/host-api-map.md` | Module-to-page map, rough surface counts, the **forbidden list** (lock screen/PIN, BLE bonds, charger, deep sleep, raw HID) | [host API](../plugin-runtime/host-api-reference.md) |
| `reference/capabilities-and-lifecycle.md` | `meta.json` skeleton, runtime gating, behavioural capabilities, load checks, lifecycle, cleanup, prerequisites | [manifest](../plugin-runtime/manifest-and-capabilities.md), [lifecycle](../plugin-runtime/lifecycle-events-and-ui.md) |
| `reference/codebook.md` (284 lines) | Copy-ready Rust recipes: state across hooks, dynamic strings, toasts, list menus, a "perfect" canvas view, keypad, NVS settings, sending badge-to-badge text | [Rust SDK](../plugin-sdk/rust-sdk.md) |
| `reference/ui-views.md` | Choosing a view; keypad conventions; dialogs, `ListBuilder`, `ContextMenuBuilder`, `SliderBuilder`, text/PIN entry, pickers | [lifecycle and UI](../plugin-runtime/lifecycle-events-and-ui.md) |
| `reference/canvas.md` | Canvas lifecycle, fonts, shapes, elements, widgets, event flow | [canvas](../plugin-runtime/canvas-surfaces-and-animation.md) |
| `reference/connectivity.md` | wifi, http, socket, ble, msg modules | [networking](../plugin-runtime/networking-wifi-http-sockets.md), [BLE GATT](../plugin-runtime/ble-gatt-for-plugins.md) |
| `reference/crypto.md` | crypto helpers, secure element (`ecc`), random | [secure element](../hardware/secure-element.md) |
| `reference/storage.md` | NVS, vFAT, R-Memory | [manifest: storage isolation](../plugin-runtime/manifest-and-capabilities.md) |
| `reference/system.md` | time, power, event, i18n, keypad, cmd, sysinfo, usb | [power](../hardware/power-and-charging.md), [i18n](../os/i18n-and-language-overlays.md) |
| `reference/hardware.md` | GPIO, PWM, ADC, I²C, SAO EEPROM, pixel strip, low-level display, pins | [hardware I/O](../plugin-runtime/hardware-io-for-plugins.md) |
| `reference/debugging.md` | Serial log, load and start checks, error codes, panics and traps, bisecting, symptom→cause table | [debugging](../workflows/debugging-and-troubleshooting.md) |
| `reference/pitfalls.md` | ~25 hard-won rules (below) | spread across the wiki |

## Pitfalls worth knowing

Paraphrased from `reference/pitfalls.md`; the original wording is in the file.

- **`host_api.h` is canonical.** Verify every call and capability name against it.
- **Don't `unwrap()` host calls**; `NoCapability` can come back unexpectedly.
- **Declare every capability.** A missing one is a runtime error, not a load error.
- `rmem` requires `nvs_namespace`. Names are 1–15 chars, with the
  `plg_`/`plugin_` prefix, ≤ 15 chars.
- `pick_font_that_fits` checks **width only, not height**. On the 128 px-tall
  panel, check height yourself.
- Canvas coordinates are relative to the **body**, and a title adds a header bar.
- **A canvas key callback consumes all keys, including N (back).** Handle exit
  yourself.
- **Pop your own modals and views on exit, and never double-pop host dialogs**
  (confirm, slider, T9 and password pop themselves).
- **Never push a view per animation frame.** Use one canvas with elements.
- **Verify canvas plugins on the device.** Layout and refresh bugs don't show
  in unit tests.
- `background` vs `autoload` semantics changed at host API 0.8; both need
  `set_resident(true)`.
- **Don't flood the serial log**, and keep pure logic host-testable.

## Known disagreements with our snapshot

| Topic | Skill says | Vendored OS says |
|---|---|---|
| Canvas display list | 96 commands | 128 (`CanvasView.h`) |
| Paths and tooling | `vendor/cdc-badge-os`, `vendor/cdc-badge-plugins` | Our copies are under `references/` and newer; the `vendor/` directories are empty |
| OS version | the development repo's pinned commit `7682dec…` | our snapshot `181a24d…` (more host functions) |

Treat any count or limit in the skill as a hint, and confirm it in
`references/cdc-badge-os/`.
