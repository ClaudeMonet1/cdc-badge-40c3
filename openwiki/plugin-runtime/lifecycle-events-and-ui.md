---
type: runtime contract
title: Plugin lifecycle, events and UI
description: The exports a cdc-badge-os WASM plugin must and may provide, the load→init→prerequisites→enter→exit→deinit sequence, foreground/background/autoload residency, the 50 ms plg_tick task, action-id callbacks and EventBus delivery, trap handling, and the three UI styles (prebuilt views, canvas, low-level GFX) plus lock-screen hooks.
tags: [plugin, lifecycle, exports, events, ui, canvas, background, tick, traps]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-e3d0e3a416e7e9decef6e4e9
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_event.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
  - id: openwiki-source-c561d477c3b54260e9f35fe3
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/ui-framework.md
  - id: openwiki-source-bdc5587210a2ab529b3a8f33
    resource: repo://references/cdc-badge-plugins/docs/capabilities.md
  - id: openwiki-source-f0a24920ad2a495ca6283d5e
    resource: repo://references/cdc-badge-plugins/docs/plugin_lifecycle.md
  - id: openwiki-source-50f6becdca203e7d479d053a
    resource: repo://references/cdc-badge-plugins/sdk/plugin_lifecycle.h
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Plugin lifecycle, events and UI

## Exports

`plugin_lifecycle.h` (OS copy identical to `cdc-badge-plugins/sdk/plugin_lifecycle.h`)
defines the WASM **exports** the host calls. A missing **required** export makes
the plugin fail to load.

| Export | Required | Called when |
|---|---|---|
| `plugin_required_api_major()` / `plugin_required_api_minor()` | yes | At load, for the API-level check. The Rust `plugin_main!()` macro generates them from the SDK constants. |
| `plugin_init()` | yes | Once, after the WASM instance is created |
| `plugin_deinit()` | yes | Once, before the instance is destroyed (**skipped after a trap**) |
| `plugin_on_enter()` | yes | The user opens the plugin (not for headless autoload) |
| `plugin_on_exit()` | yes | The user leaves the plugin |
| `plugin_on_action(action_id, selected_idx, user_data)` | no | Any asynchronous callback: UI views, canvas keys and widgets, **EventBus subscriptions**, HTTP/BLE/msg completions, animations, lock-screen actions |
| `plugin_on_button(button_code)` | no | A key press while no host view is in front |
| `plugin_on_event(event_type, event_value)` | no | Events delivered through the event path of `PluginManager` |
| `plugin_on_tick(uptime_ms)` | no | Every **~50 ms** (≈20 Hz) |
| `plugin_on_cmd(len)` | no | The host forwarded a command (e.g. serial `PLUGIN CMD <id> <args>`). Pull it with `host_cmd_consume`. |
| `plugin_on_prerequisite_failed(prereq_id, error_code)` | no | A manifest prerequisite with `on_fail: callback` failed |

All exports return `int`, where 0 means OK.

## Sequence

```
load (.wasm from /vfat/system/<id>.wasm, manifest checks, instantiate)
 → plugin_init
 → prerequisites (manifest order; on_fail = abort | warn | callback)
 → plugin_on_enter                     (skipped for headless autoload)
 → [running: on_tick / on_action / on_button / on_event / on_cmd]
 → plugin_on_exit
 → release prerequisites (reverse order; e.g. Wi-Fi the host brought up is dropped)
 → plugin_deinit
 → unload (sleep inhibitor, GPIO claims, subscriptions, views released)
```

Prerequisites ("what the host sets up before the plugin runs", such as Wi-Fi,
BLE, time sync or battery level) come from the manifest's `prerequisites`.
Capabilities, by contrast, are checked on every call. Both are covered in
[manifest and capabilities](manifest-and-capabilities.md).

### Residency: foreground, background, autoload

- At most **one foreground plugin** runs at a time.
- `background` and `autoload` are **permissions** (since host API 0.8). The
  plugin must also call `host_set_resident(true)`:
  - **background:** call it while running and the plugin keeps ticking after the
    user leaves its view. Without the call, it is torn down on leave.
  - **autoload:** loaded headless at boot (`plugin_init` and prerequisites, no
    `on_enter`). It must call `set_resident(true)` in `plugin_init`, or it is
    unloaded right after.
- A resident background plugin can be stopped from the plugin list's `[3]`
  context menu ("Stop background").
- The N+Y panic chord unloads all plugins (see [keypad](../hardware/keypad-and-io-expander.md)).

## Threading and scheduling

`PluginManager` (`components/plugin_manager/src/PluginManager.cpp`) runs a
dedicated FreeRTOS task, **`plg_tick`**: 12 KiB stack, priority 5, period
`TICK_INTERVAL_MS = 50`, scheduled with `vTaskDelayUntil`. On each wake it
refreshes the message index, handles a pending "stop", polls UI inactivity
timers and calls `plugin_on_tick` on the foreground plugin and every resident
background plugin.

Every call into WASM (tick, action, button, event) is made under a single
**recursive call mutex**, so plugin code is never re-entered concurrently and
runs one call at a time across all plugins. Consequences:

- A long-running export blocks every other plugin and every pending callback.
  Keep each call short and keep state machines across ticks. A blocking host
  call, such as `host_ui_wink` sleeping for `2 × count × period_ms`, stalls the
  whole runtime for that time.
- `plugin_on_tick` is **not a redraw signal**. The SDK docs say to redraw only
  when content changes. An e-paper refresh takes 0.4–2 s
  ([display](../hardware/display-and-graphics.md)).

## Callbacks are action IDs

APIs that complete later take a `uint32_t action_id` chosen by the plugin. The
host later calls `plugin_on_action(action_id, idx, user_data)`.

| Source | `idx` | `user_data` |
|---|---|---|
| `host_ui_push_confirm` / `host_lockscreen_alert` | unused | 1 = Y, 0 = N |
| List views | selected index | item id or context |
| Canvas `key_action_id` | focused widget id | ASCII key code |
| Canvas `widget_action_id` | widget id | `CANVAS_WIDGET_CHANGED` 1 / `COMMITTED` 2 / `CANCELLED` 3 |
| `host_event_subscribe(mask, action_id)` | `EventType` ordinal | event value (ASCII key code for key events) |
| Lock-screen quick action | 0 | 0 |

Text and number results are fetched afterwards with
`host_ui_consume_input_text` / `host_ui_consume_input_int`.

## EventBus delivery

`host_event_subscribe(event_mask, action_id)` returns a subscription id
(`host_api_event.cpp`):

- One core EventBus handler fans out to all plugin subscriptions. The table holds
  **16 subscriptions shared by all plugins**. When it is full the call returns
  `HOST_ERR_NO_MEMORY`.
- Each matching event is delivered as `plugin_on_action(action_id, event_type, value)`.
- **Key events are delivered only to a plugin whose view has input focus.**
- If any plugin subscribes to `EVENT_KEY_LONG_PRESS`, the keypad switches to
  deferred short-press mode, so a held key yields only the long press.
- Event bits (`EVENT_KEY_*`, `EVENT_POWER_*`, `EVENT_SYSTEM_LOCK/UNLOCK/SLEEP/WAKE`,
  `EVENT_BLE_*`, `EVENT_TIMER_TICK`, `EVENT_MODULE_EVENT`, `EVENT_DISPLAY_REFRESH`)
  are statically asserted to equal the core `EventType` masks.
  `EVENT_DISPLAY_REFRESH` fires with 1 when a FAST/FULL refresh starts and 0
  when it ends, so a game can pause while the panel is unreadable.
- `host_event_publish(subtype, value)` raises `EVENT_MODULE_EVENT` for
  plugin-to-plugin or plugin-to-module signalling.

## Failure behaviour: traps

If any export traps (WASM `unreachable`, out-of-bounds access, stack overflow,
Rust panic → abort), `PluginManager::handleTrap` logs a `PLUGIN TRAP` banner
with the reason and **force-unloads** the plugin. For the foreground plugin it
also pops the plugin's views and resets UI state. `plugin_deinit` is **not**
run, and held resources are released by the host. Nothing else is affected:
the OS, the other plugins and the badge keep running. See
[WAMR runtime](wamr-runtime.md) for memory and stack limits.

## UI options

All plugin UI lives on the OS `ViewStack` (`cdc_ui`), so the standard chrome
(header, footer hints, N = back) and refresh handling apply.

| Style | Capability | Use for |
|---|---|---|
| **Prebuilt views** (`host_ui_push_*`): toast, message, info, confirm, list (with icons, live insert/update/remove), context menu, T9 text, password, PIN, slider, color picker, date, time, image and markdown viewers, file browser | none | Menus, settings, forms. Consistent UX for little code. |
| **Canvas view** (`host_view_canvas_*`): draw primitives, five fonts, inline widgets (slider, text, button), named elements that can be moved, hidden or z-ordered, sprites, eased tweens (`host_anim_*`), marquee | none | Custom screens, dashboards, games. Draw, then `host_view_canvas_commit` to refresh. |
| **Low-level GFX** (`host_display_*`) | `display_lowlevel` | Full-screen rendering that bypasses the view system. The plugin chooses FULL / PARTIAL / FAST on flush. |

Supporting pieces: off-screen **surfaces** (≤ 64 KiB, 2 per plugin, exportable
to PNG-like rows or JPEG), **QR** and **image** decoding to 1-bpp bitmaps,
`UI_ICON_*` glyphs (CP437 codes with semantic aliases), `host_ui_set_inactivity`
idle timers, and `host_ui_acquire_exclusive` / `release_exclusive` to take
exclusive ownership of the view stack, which the OS uses for FIDO2 prompts.

### Lock-screen hooks for background plugins

- `host_lockscreen_register_action(label_key, action_id)` adds **one** item to
  the lock-screen context menu (label resolved through i18n).
- `host_lockscreen_alert(text, icon, action_id)` raises a persistent Y/N modal
  over any screen, including the lock screen. Only one alert can be pending
  (`HOST_ERR_BUSY` otherwise), and the answer is routed back even to a
  background plugin.

### Minimal Rust shape

See [Rust SDK](../plugin-sdk/rust-sdk.md) for the real API. Conceptually:

```rust
plugin_main!();                       // api-level exports
#[no_mangle] extern "C" fn plugin_init() -> i32 { /* subscribe events, set_resident */ 0 }
#[no_mangle] extern "C" fn plugin_on_enter() -> i32 { /* push list or canvas */ 0 }
#[no_mangle] extern "C" fn plugin_on_action(id: u32, idx: u32, data: u32) -> i32 { /* dispatch */ 0 }
#[no_mangle] extern "C" fn plugin_on_exit() -> i32 { 0 }
#[no_mangle] extern "C" fn plugin_deinit() -> i32 { 0 }
```
