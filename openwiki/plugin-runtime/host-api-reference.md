---
type: api reference
title: Host API (ABI) reference
description: The C ABI that cdc-badge-os exposes to WASM plugins — 307 host_* functions imported from WAMR module "cdc", grouped by family with the capability each needs, calling conventions (pointers, wasm32 length-returning forms, UTF-8), return codes, API level 0.8 compatibility rules, and how the canonical header is mirrored into the SDK.
tags: [host-api, abi, wasm, imports, capabilities, wamr, sdk]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-3f00bf683fd77308725c121c
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_http.cpp
  - id: openwiki-source-1cf8e76e4af214efa7b3bd8f
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_wifi.cpp
  - id: openwiki-source-102679e338db93cd4c4318e1
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/WamrImports.cpp
  - id: openwiki-source-17168c8aab3c540d03e3bd13
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0007-host-api-canonical-sdk-mirror.md
  - id: openwiki-source-5f34a55d37e245b9e7153335
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/host-api.md
  - id: openwiki-source-72f34635573014fbc77b4d3d
    resource: repo://references/cdc-badge-plugins/.github/workflows/sync-host-api.yml
  - id: openwiki-source-bdc5587210a2ab529b3a8f33
    resource: repo://references/cdc-badge-plugins/docs/capabilities.md
  - id: openwiki-source-c34efb351320cfafb6bfad7b
    resource: repo://references/cdc-badge-plugins/docs/host_api_reference.md
  - id: openwiki-source-9f54a822157fbf6d890ebb6d
    resource: repo://references/cdc-badge-plugins/sdk/cdc-badge-plugin/src/ffi.rs
  - id: openwiki-source-73407625626e00182b5056c6
    resource: repo://references/cdc-badge-plugins/sdk/host_api.h
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Host API (ABI) reference

This is the contract between our Rust plugin and the badge. The plugin is a
`.wasm` module that **imports** host functions from the WAMR module `"cdc"` and
**exports** lifecycle entry points (see
[Plugin lifecycle, events and UI](lifecycle-events-and-ui.md)). Nothing else
crosses the sandbox boundary.

## Sources of truth

| Artifact | Role |
|---|---|
| `references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h` | **Canonical** declaration: 2743 lines, Doxygen groups, every function's `\brief`, parameters and return values |
| `references/cdc-badge-plugins/sdk/host_api.h` | SDK mirror. **Byte-identical** to the OS copy in our snapshots. |
| `components/plugin_manager/src/WamrImports.cpp` | `NativeSymbol` table registered under module `"cdc"` with WAMR signature strings. It registers exactly the functions the header declares (307 unique names). |
| `components/plugin_manager/src/host_api_<family>.cpp` | Implementations, including capability checks |
| `cdc-badge-plugins/sdk/cdc-badge-plugin/src/ffi.rs` | Rust `extern "C"` block with `#[link(wasm_import_module = "cdc")]`, binding the wasm32 forms |
| OS docs `website/src/content/docs/dev/host-api.md` | Curated family table, signature notes, UTF-8 rules |

**ADR-0007:** the OS header is canonical. The SDK copy is only ever copied over
from it, never hand-edited, and surface changes ship in both repos together. A
daily workflow in cdc-badge-plugins (`.github/workflows/sync-host-api.yml`)
downloads the OS header from the `release` branch, diffs it against
`sdk/host_api.h`, and opens an issue if they drift.

## API level and compatibility

`HOST_API_LEVEL_MAJOR 0`, `HOST_API_LEVEL_MINOR 8`, `HOST_API_LEVEL_STR "0.8"`,
and `HOST_API_LEVEL_PACKED = major<<16 | minor`. The Rust SDK mirrors these as
`HOST_API_LEVEL_MAJOR/MINOR` constants.

A plugin declares `"host_api_level_min": "0.8"` in `meta.json`. The host loads it
only if `plugin_major == host_major && plugin_minor <= host_minor`. Pre-1.0, a
minor bump can be breaking: 0.8 turned `background`/`autoload` into permissions
that need `host_set_resident`. ADR-0007 still says "currently 0.7"; that text
predates the bump.

## Calling convention

- **Integers and pointers** are wasm32 `i32`/`i64`. Pointers are offsets into
  the plugin's linear memory. WAMR validates `$` (NUL-terminated string) and
  `*~` (buffer + length) parameters. For a bare `*` it only checks 1 byte, so
  every wrapper that reads or writes more re-validates the full range with
  `wasm_runtime_validate_native_addr` (`wbuf_ok`) and returns
  `HOST_ERR_INVALID_ARG` when the check fails.
- **wasm32-specific forms.** Six functions whose native form takes a `size_t*`
  in/out length with no separate capacity are imported differently: they take the
  capacity by value and **return the byte count (≥ 0) or a negative error**.
  These are `host_rmem_read_named`, `host_http_read_chunk`, `host_nvs_get_blob`,
  `host_fs_read`, `host_fs_size` and `host_fs_list`. The header declares that
  form under `#if defined(__wasm__)`.
- **Lists.** `host_nvs_list_keys` and `host_fs_list` end each entry with `\n`,
  write only whole entries, and report the full length needed so the caller can
  retry with a bigger buffer.
- **Text is UTF-8 everywhere.** The host converts to the display's CP437
  internally, and text it reads back is returned as UTF-8.
  `host_str_to_display` / `host_str_to_utf8` exist for special cases; never feed
  their output back into UI calls.
- **Callbacks are action IDs.** Asynchronous APIs (events, UI results, HTTP,
  BLE, timers, animations) take a `uint32_t action_id`. The host later calls the
  plugin's `plugin_on_action(action_id)` export. There are no function-pointer
  callbacks.

### Return codes

| Code | Value | Meaning |
|---|---|---|
| `HOST_OK` | 0 | Success |
| `HOST_ERR_GENERIC` | -1 | Unspecified failure |
| `HOST_ERR_INVALID_ARG` | -2 | Bad argument or out-of-bounds pointer |
| `HOST_ERR_NO_CAPABILITY` | -3 | The manifest lacks the needed capability. Logged; the plugin keeps running. |
| `HOST_ERR_NOT_FOUND` | -4 | Missing key/file/slot/provider, or empty queue |
| `HOST_ERR_TIMEOUT` | -5 | Timed out |
| `HOST_ERR_NO_MEMORY` | -6 | Allocation failed |
| `HOST_ERR_BUSY` | -7 | Resource held by another plugin (pin, panel, …) |
| `HOST_ERR_NOT_SUPPORTED` | -8 | Not available in this build or hardware |
| `HOST_ERR_RMEM_FULL` | -9 | The plugin R-Memory pool is exhausted |

## Function families

Every `\defgroup` in `host_api.h`, with its functions (prefix `host_` omitted)
and the capability checked at call time. Capabilities are explained in
[manifest and capabilities](manifest-and-capabilities.md).

| Family | Capability | Functions |
|---|---|---|
| Logging | — | `log`, `log_hex` |
| Time / RTC | — | `uptime_ms`, `unix_time`, `local_time`, `timezone_offset`, `is_time_set` |
| Power | — | `battery_mv`, `battery_pct`, `is_usb_connected`, `power_source`, `charge_status`, `is_battery_low`, `is_battery_critical`, `set_sleep_inhibit` |
| Crypto | — | `random`, `random_strict`, `sha256`, `hmac_sha256`, `aes_gcm_encrypt/decrypt`, `base32_*`, `base64_*`, `hex_*` |
| Secure element | name in `rmem` / `ecc` | `rmem_read_named`, `rmem_write_named`, `rmem_erase_named`, `rmem_name_used`, `rmem_slot_size`, `ecc_generate/import/pubkey/delete/exists`, `ecdsa_sign`, `eddsa_sign`, `se_chip_id`, `se_fw_version`. See [secure element](../hardware/secure-element.md). |
| HTTP (streamed) | `http` | `http_open`, `http_set_header`, `http_set_body`, `http_perform`, `http_status`, `http_read_chunk`, `http_content_length`, `http_close` |
| Socket (TCP/UDP client) | `socket` | `socket_open`, `socket_write`, `socket_read`, `socket_close` |
| Net listener | `net_listen` | `net_listen`, `net_accept`, `net_close` (accepted connections use the socket calls) |
| Lifecycle | `background`/`autoload` permission | `set_resident` |
| Wi-Fi | `wifi` | `wifi_request`, `wifi_release`, `wifi_is_connected`, `wifi_ssid`, `wifi_ip`, `wifi_rssi`, `wifi_mac`, `wifi_start_scan`, `wifi_scan_done`, `wifi_scan_results` |
| BLE | `ble` (+ `ble_service_uuids` for a GATT server) | Server: `ble_register_service`, `ble_unregister_service`, `ble_send_notification`, `ble_send_indication`, `ble_consume_write`. Central: `ble_scan_start/done/results`, `ble_connect`, `ble_disconnect`, `ble_conn_handle`, `ble_conn_peer`, `ble_discover`, `ble_consume_discovery`, `ble_read_char`, `ble_consume_read`, `ble_write_char`, `ble_on_write_complete`, `ble_subscribe`, `ble_subscribe_char`, `ble_consume_notification`, `ble_get_mtu`. Info: `ble_is_enabled`, `ble_mac`, `ble_device_name`, `ble_rssi` |
| NVS | — (confined to the declared `nvs_namespace`) | `nvs_get/set_blob`, `nvs_get/set_u32`, `nvs_get/set_str`, `nvs_erase`, `nvs_erase_all`, `nvs_list_keys` |
| vFAT files | `vfat` | `fs_write`, `fs_read`, `fs_remove`, `fs_size`, `fs_list`, `fs_view`, `fs_view_image`, `fs_view_markdown` |
| UI views | — | `ui_push_toast/message/info/confirm`, `ui_push_list`, `ui_replace_list`, `ui_update/insert/remove_list_item`, `ui_push_context_menu`, `ui_push_t9_input`, `ui_push_password`, `ui_push_pin_entry`, `ui_push_slider`, `ui_push_color_picker`, `ui_push_date`, `ui_push_time`, `ui_consume_input_int/text`, `ui_set_view_footer/empty/lifecycle`, `ui_pop`, `ui_pop_to_plugin`, `ui_repaint`, `ui_acquire/release_exclusive`, `ui_set_inactivity`, `ui_wink`, `ui_view_image`, `ui_view_markdown`, `browser_open` |
| Canvas view | — | `view_canvas_push`, `view_canvas_commit`, `view_canvas_clear(_ex)`, `view_canvas_get_body_size`, `view_canvas_set_footer/font/text_size/text_color/shade/ink`, `text_pick_font_that_fits`, `view_canvas_draw_text(_aligned)/rect/pixel/line/circle/triangle/round_rect/bitmap/sprite`, `view_canvas_hline/vline`, `view_canvas_marquee`, elements (`view_canvas_elem_begin/end/set_offset/move/show/remove/clear/set_z/get_offset/get_bounds`), widgets (`view_canvas_add_slider/text/button`, `remove_widget`, `set/get_value`, `set/get_text`, `set/get_focus`), `view_canvas_set_key_repeat`, `view_canvas_set_long_press_action`, `view_canvas_set_anim_policy` |
| Canvas animation | — | `anim_start`, `anim_cancel`, `anim_pause`, `anim_state`, `anim_active_count`, `anim_blink` (eased tweens on canvas elements) |
| Low-level GFX | `display_lowlevel` (except the backlight calls) | `display_width/height`, `display_clear`, `display_draw_pixel/line/rect/text`, `display_fill_rect`, `display_flush(mode)`, `display_is_busy`, `display_set/get_backlight` |
| I18n | — | `i18n_tr_key`, `i18n_tr_meta`, `i18n_tr_core`, `i18n_current_language` |
| EventBus | — | `event_subscribe(mask, action)`, `event_unsubscribe`, `event_publish` |
| Keypad | — (needs input focus) | `key_pressed`, `key_consume_next` |
| USB CDC | `usb_cdc` | `usb_cdc_write` |
| System info | — | `feature_enabled`, `get_firmware_version`, `get_build_profile`, `cpu_load` |
| Command channel | — | `cmd_consume` (pairs with the optional `plugin_on_cmd` export) |
| Message transfer | `ble` + non-empty `message_types` | `msg_register_handler`, `msg_unregister_handler`, `msg_consume`, `msg_send_interactive`, `msg_send` (`HOST_MSG_FLAG_PERSIST` keeps the pairing for the session) |
| External features | none to call; `provides` to serve | `ext_feature_available`, `ext_feature_use`, `ext_feature_register_handler`, `ext_feature_consume`, `ext_feature_result` (payload ≤ 32 KiB, "Open with" semantics) |
| vCard store | `vcard` | `vcard_get_own`, `vcard_set_own`, `vcard_received_count/get/display/add/update/delete` |
| QR | — | `qr_measure`, `qr_render_bitmap` (1 bpp, MSB-first, set = black) |
| Image | — | `image_info`, `image_render` (PNG/JPEG → scaled, dithered 1 bpp) |
| Surfaces | — | `surface_create` (≤ 64 KiB pixels, 2 per plugin), `surface_destroy/clear`, `surface_set_font/text_size/text_color/shade`, `surface_draw_*`, `surface_measure_text`, `surface_export`, `surface_export_jpg` |
| Sprites | — | `sprite_create(_from_surface/_from_image)`, `sprite_set_mask/flags/scale/frame/frame_durations`, `sprite_get_frame`, `sprite_play/stop/destroy` |
| Strings | — | `str_to_display`, `str_to_utf8` |
| GPIO / PWM / ADC / I²C / SAO | pin in `gpio_pins`/`pwm_pins`/`adc_pins`, `grove`, `sao`, bus in `i2c_bus` | `gpio_set_direction/pull`, `gpio_write/read/release`, `gpio_pwm_start/set_duty/stop`, `adc_read`, `i2c_write/read/write_read/scan` (bus 1 only), `sao_eeprom_read/write` |
| Pixel strip | `pixel_strip` | `pixel_strip_init/deinit/set/fill/clear/refresh/length/ready` (RMT-driven addressable LEDs) |
| Lockscreen quick action | — (active plugin) | `lockscreen_register_action`, `lockscreen_unregister_action`, `lockscreen_alert` |

Capability enforcement lives in the `host_api_*.cpp` files. For example,
`host_api_wifi.cpp` and `host_api_http.cpp` return `HOST_ERR_NO_CAPABILITY` when
the manifest lacks `wifi` or `http`. The OS doc's "manifest only" note for those
two families doesn't match the code.

### Deliberately absent

The SDK's `docs/capabilities.md` says no host function exists, under any
capability, for the lock screen and PIN system, BLE bond management, charger
control, deep sleep, or raw HID report emission. Raw SPI, I²C bus 0, the
TROPIC01's reserved slots and arbitrary GPIOs are also out of reach (see
[pin map](../hardware/pin-map-and-buses.md)).

## Adding or changing a host function (upstream process)

1. Declare it in the OS `host_api.h` and copy the header into the SDK.
2. Implement it in `host_api_<family>.cpp`.
3. Register the wrapper and signature in `WamrImports.cpp`. If it needs a
   native-side 64-bit build, the emulator has a parallel `WamrImports64.cpp`
   (see [emulator](../workflows/emulator.md)).
4. Add the Rust binding in `ffi.rs` and a safe wrapper module.
5. Ship both repos together. Level constants change only with an explicit decision.

Our own application can't add host functions without forking the OS. Anything it
needs that isn't listed above is a gap; record it in
[open questions](../reference/open-questions-and-discrepancies.md).
