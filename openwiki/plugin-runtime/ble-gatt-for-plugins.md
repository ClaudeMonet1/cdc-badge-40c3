---
type: runtime subsystem
title: BLE GATT for plugins
description: The plugin-facing Bluetooth LE API of cdc-badge-os — one reserved GATT server service (up to 6 characteristics) plus the central/client role, single connection, 244-byte payloads, 4-deep write/notify rings drained on the plugin tick task, reserved-UUID refusal, and the single-controller constraints (service registration restarts NimBLE) from ADR-0008.
tags: [ble, gatt, plugins, nimble, central, peripheral, host-api]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-3c15593f946798e0d377c1cd
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_ble.cpp
  - id: openwiki-source-fa86607201426a5c9fb70564
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0008-single-ble-controller.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# BLE GATT for plugins

Sources: `components/plugin_manager/src/host_api_ble.cpp`,
`website/src/content/docs/dev/adr/0008-single-ble-controller.md`,
`components/cdc_hal/src/BluetoothController.cpp`, and the upstream skill
reference `cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/connectivity.md`.
Example plugins: `ble_scanner` (central scanning), `thermo_printer` (central
GATT client to BLE printers).

This page is about **raw GATT**. Badge-to-badge payloads use the separate
message framework; see the [BLE message transfer review](../os/security/ble-message-transfer.md).
Everything here requires the `ble` capability. A GATT server also needs
`ble_service_uuids` in the manifest.

## Model

```
NimBLE host task ──(callback)──► copy into mutex-protected ring, set pending flag
plugin tick task ──plg_ble_pump()──► plugin_on_action(action_id, …)
plugin ──host_ble_consume_write / _read / _discovery / _notification──► pulls payload
```

- NimBLE callbacks **never call into WASM**. They copy the payload into a ring
  that the plugin tick task drains (the same deferred pattern as the command
  channel; `host_api_ble.cpp:1-15`).
- So events arrive with up to one tick (about 50 ms) of latency, and
  serialised with all other plugin calls (see [lifecycle](lifecycle-events-and-ui.md)).

## Limits

| Limit | Value | Source |
|---|---|---|
| Plugin GATT services | **1**, shared by all plugins (a reserved controller slot) | `host_api_ble.cpp:13-15`, `:36` |
| Characteristics per service | ≤ `MAX_CHARS_PER_SERVICE` (6) | ADR-0008 |
| Payload per write/notify | **244 B** (default-MTU budget) | `host_api_ble.cpp:35` |
| Write ring / notify ring | 4 entries each | `:38-39` |
| Discovered characteristics | ≤ 8 | `:40` |
| Connections | one BLE connection at a time for the plugin API | `:13-15` |
| Whole-system GATT registry | 7 services (OS modules use most) | ADR-0008 |

## Peripheral (GATT server)

- `host_ble_register_service(def, chars, n)` checks the capability, a
  characteristic count ≤ the limit, and that the UUID is **not reserved**. It
  refuses OS UUIDs such as the message-transfer, NUS and 2FA services with
  `HOST_ERR_NO_CAPABILITY` (`host_api_ble.cpp:258-272`).
- If another plugin already holds the slot, the call returns `HOST_ERR_BUSY`.
- Re-registering by the same plugin replaces its service.
- `host_ble_send_notification` / `send_indication` push data to the peer, and
  `host_ble_consume_write` pulls incoming writes.
- Service UUIDs are 128-bit lowercase, declared in the manifest.

## Central (GATT client)

| Step | Calls |
|---|---|
| Scan | `host_ble_scan_start`, `host_ble_scan_done`, `host_ble_scan_results` |
| Connect | `host_ble_connect`, `host_ble_conn_handle`, `host_ble_conn_peer` |
| Discover | `host_ble_discover` → `host_ble_consume_discovery` |
| Read / write | `host_ble_read_char` → `host_ble_consume_read`; `host_ble_write_char` + `host_ble_on_write_complete` for chunk pacing; `host_ble_get_mtu` |
| Notify | `host_ble_subscribe` / `host_ble_subscribe_char` (CCCD resolved by the host) → `host_ble_consume_notification` |
| Info | `host_ble_is_enabled`, `host_ble_mac`, `host_ble_device_name`, `host_ble_rssi` |

## Single-controller consequences (ADR-0008)

- `BluetoothController` is the **only** GAP handler. Everything goes through
  `IBluetoothController`.
- **Registering a GATT service while the stack is running forces a NimBLE
  restart** to commit it. *(Inference)* That briefly drops other BLE users: the
  BLE keyboard, BLE serial console and any message transfer.
- At boot, services registered during init are committed together when
  `notifySystemReady()` releases the startup barrier. An `autoload` plugin that
  registers in `plugin_init` therefore avoids the restart.
- **Privacy:** the badge advertises with a static address and the owner's name
  (see the [BLE review](../os/security/ble-message-transfer.md)). Plugins can't
  change this.

## Design notes for badge-cdc

- With one plugin service slot and one connection, BLE is a **scarce, shared
  resource**. Expect `HOST_ERR_BUSY` and handle it.
- Raw GATT has no badge-OS pairing UX. Apply your own end-to-end authentication
  and encryption (e.g. a Noise handshake over GATT using `host_random_strict` and
  the plugin's [secure element](../hardware/secure-element.md) key) if peer
  identity matters.
- Keep messages ≤ 244 B, or chunk them with `on_write_complete` pacing.
