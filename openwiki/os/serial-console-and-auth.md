---
type: os subsystem
title: Serial console and authentication
description: The cdc-badge-os serial console (serial_cmd) over USB CDC, UART and BLE UART — per-transport AUTH sessions with a 5-minute timeout, the effective secure-serial default (on in the shipped sdkconfig despite the header fallback), which commands need no PIN, and a catalogue of the command groups relevant to plugin development and security.
tags: [serial, console, authentication, commands, security, ble-uart, tooling]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-9b1eaa02194157f882b92ba1
    resource: repo://references/cdc-badge-os/components/cdc_core/include/cdc_core/feature_flags.h
  - id: openwiki-source-e6022592cb5ab3edb7e38141
    resource: repo://references/cdc-badge-os/components/serial_cmd/include/serial_cmd/SerialCmd.h
  - id: openwiki-source-8fa683c758e54bfc4fbb69e2
    resource: repo://references/cdc-badge-os/components/serial_cmd/src/SerialCmd.cpp
  - id: openwiki-source-a9baa65a2e0f48fed1b02f5d
    resource: repo://references/cdc-badge-os/sdkconfig.cdc_badge_usb
  - id: openwiki-source-ebcbc9781ed420f4f17c97e4
    resource: repo://references/cdc-badge-os/sdkconfig.defaults
  - id: openwiki-source-2d0fd9ea77dd856ad370eec2
    resource: repo://references/cdc-badge-os/sdkconfig.release
  - id: openwiki-source-9f006ce9ef5060664aff953e
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0012-build-profiles-and-defaults.md
  - id: openwiki-source-6feb07b52d0a717e123c2066
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/proto/serial-commands.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Serial console and authentication

Sources: `components/serial_cmd/` (`SerialCmd.cpp`, `CommandRegistry.cpp`),
`website/src/content/docs/dev/proto/serial-commands.md` (the full verified
catalogue) and `power/serial-console.md`.

The console drives almost all host tooling: `upload.py`, `backup.py`, `2fa.py`,
the browser plugin installer and the `badge` CLI. It is the main way to debug a
plugin (see [debugging](../workflows/debugging-and-troubleshooting.md)).

## Transports

| Transport | Notes |
|---|---|
| USB CDC (TinyUSB) | Primary; 115200 baud setting for monitors |
| UART0 | Raspberry Pi header pins 8/10, shares the USB/UART auth slot |
| BLE UART (`mod_ble_serial`, Nordic UART Service) | Characteristics require an encrypted link (`BleUartService.cpp`); `tools/ble_serial.py` on the host |

## Authentication model

- **Is the gate on by default?** `FEATURE_SECURE_SERIAL` maps from Kconfig
  `CONFIG_SECURE_SERIAL`. The header falls back to `0`
  (`cdc_core/feature_flags.h:16-23`), and ADR-0012 calls that the default.
  **But the shipped build sets `CONFIG_SECURE_SERIAL=y`** in
  `sdkconfig.defaults:94`, `sdkconfig.cdc_badge_usb:654` and
  `sdkconfig.release:35`. So **normal builds have the gate on**, which is what
  `serial-commands.md` states.
- **With the gate on**, every command except `PING` and `AUTH` needs a prior
  `AUTH <pin>` (the badge PIN, factory default `123456`). Without the gate, only
  commands whose descriptor sets `requiresAuth` are gated.
- **Group-level checks.** Authentication is checked per group, so read-only
  subcommands of a gated group also need it.
- **Per-transport sessions.** USB/UART and BLE each have their own AUTH state
  (`SerialCmd.cpp:88-102`). Sessions expire after **5 minutes**
  (`SerialCmd.h:26`). `LOGOUT` (or `AUTH` with no argument) ends one.
- **Isolation.** Output goes only to the originating transport. Lines and binary
  uploads are assembled from one transport only. The `AUTH` argument echoes as
  `*` and is never kept in history.
- **PIN guessing** over serial counts against the badge-PIN lockout (see
  [secure element](../hardware/secure-element.md)).

## Command catalogue (highlights)

| Group | AUTH | Highlights |
|---|---|---|
| System | mostly no | `HELP`, `PING`, `VERSION` (firmware, host API level, profile), `STATUS`, `MEM`, `MEMINFO` (per-region heap + task watermarks), `CPU`, `ERROR_LOG [CLEAR]`. Gated: `REBOOT`, `BOOTLOADER`, `SHIPMODE`, `PASTE <text>` (types into the open T9 field) |
| Time | **no** | `GET_TIME/DATE`, `SET_TIME HH:MM:SS`, `SET_DATE DD.MM.YYYY\|<unix>` |
| Display | no | `SET_NAME`, `SET_INFO`, `SET_INFO2` (lock-screen text) |
| `NVS` | yes | `LIST [ns]`, `READ <ns> <key>`, `DEL`, `CLEAR YES` |
| `PIN` | yes | `STATUS`, `RESET`, `CHANGE`, `DURESS <pin>`, `DURESS_CLEAR` |
| `TR01` | yes | `INFO`, `SESSION`, `SLOTS`, `RMEM_READ <slot>` (hex dump), `ECC_DEL`, `RMEM_DEL`, `WIPE CONFIRM` |
| `WIFI` | yes | `SCAN`, `STATUS`, `ON/OFF`, `CONNECT <ssid> <pw>`, `TIMEOUT`, `FORGET` |
| `MODULE` | yes | `LIST`, `ENABLE`, `DISABLE` |
| `PLUGIN` | yes | `LIST`, `INFO`, `START`, `STOP`, `CMD <id> <args>`, `ENABLE/DISABLE`, `DELETE`, `UPLOAD*`, `ABORT`, `DEBUG`, `FEATURES` (see [build and install](../workflows/plugin-build-and-install.md)) |
| `GPIO` | yes | Raw pin access under the same policy as plugins ([hardware I/O](../plugin-runtime/hardware-io-for-plugins.md)) |
| Module groups | yes | `GPG …` (incl. `RECV_CROSS_SIGN`, which signs with **no on-device confirmation**), `2FA`, `PWD`, `VCARD`, `BACKUP EXPORT/IMPORT`, `VFAT`, `LANG` |

## Security observations

- **Unauthenticated clock setting.** `SET_TIME` / `SET_DATE` need no AUTH.
  Anyone with USB or BLE-console access can move the clock. That affects TOTP
  codes, TLS certificate validity checks and any plugin logic based on time.
  *(Inference on impact.)*
- **An authenticated session is powerful.** `TR01 RMEM_READ` dumps R-Memory
  slots, which hold vault entries and 2FA secrets, stored without
  application-level encryption (see
  [credential modules](modules/credential-modules.md)). `GPG RECV_CROSS_SIGN`
  certifies keys without on-screen confirmation.
- **Plugin install** (`PLUGIN UPLOAD`) requires AUTH on standard builds. USB mass
  storage is a separate, unauthenticated-while-unlocked install path (see
  [storage tools](storage-tools.md)).
- **Logs.** `ERROR_LOG` / `MEMINFO` / `CPU` need no AUTH, so plugin log messages
  may be readable by anyone on the port. Don't log secrets.
