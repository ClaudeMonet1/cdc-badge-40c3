---
type: runtime subsystem
title: Inter-plugin external features
description: The cdc-badge-os "Open with" mechanism that lets one plugin hand a job to another — providers declaring `provides` and registering handlers in plugin_init, callers using host_ext_feature_use with a ≤32 KiB payload, the single job slot, foreground switch on the tick task, consume-once payloads, result routing back to the caller, and the limits and pitfalls.
tags: [plugins, ipc, external-features, open-with, host-api]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-e0b6e038938510b69ae91175
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_ext_feature.cpp
  - id: openwiki-source-bdc5587210a2ab529b3a8f33
    resource: repo://references/cdc-badge-plugins/docs/capabilities.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Inter-plugin external features

Sources: `components/plugin_manager/src/host_api_ext_feature.cpp`,
`include/plugin_manager/ExtFeatureName.h`, the "External features" group in
`host_api.h`, the SDK's `docs/capabilities.md`, and the SDK module `feature`.
Reference implementations: `plugins/thermo_printer` (provider of
`thermo_print`) and `plugins/sdk_probe` (provider `probe_echo`).

This is the **only** way for plugins to talk to each other directly, apart from
`host_event_publish(EVENT_MODULE_EVENT, …)`, which carries just a subtype and a
value, and shared storage names.

## Roles

| Role | Requirements | Calls |
|---|---|---|
| **Provider** | Manifest `provides: [name, …]`: `[a-z][a-z0-9_]*`, ≤ 32 chars, ≤ 4 entries. A duplicate provider of the same name is ignored at index time. | In **`plugin_init`**: `host_ext_feature_register_handler(name, action_id)`. In that action: `host_ext_feature_consume(buf, cap)`, do the work, then call `host_ext_feature_result(status)` **exactly once**. |
| **Caller** | No capability needed. `background: true` if the result matters. | `host_ext_feature_available(name)`, `host_ext_feature_use(name, payload, len, status_action_id)` |

Status codes: `HOST_EXT_FEATURE_STATUS_DONE` (0), `…_ERROR` (1), or
provider-defined values ≥ 1. They arrive as `user_data` of the caller's status
action.

## Flow

```
caller (WASM frame) ── host_ext_feature_use ──► copy payload to PSRAM, stash job   (never starts provider inline)
plugin tick task    ── plg_ext_feature_pump ──► start provider in FOREGROUND (plugin_init already ran → handler registered)
                                              ► fire provider's handler action; payload consumable during this dispatch only
provider            ── host_ext_feature_result(status) ──► caller's status action, if the caller is still loaded
```

`host_api_ext_feature.cpp:1-17`: `use` runs inside the caller's WASM frame, so
starting the provider inline would tear down the instance that is currently
executing. Hence the stash-and-pump design.

## Limits and failure modes

- **One job slot** badge-wide. A second `use` while a job is pending returns
  `HOST_ERR_BUSY` (`host_api_ext_feature.cpp:159-164`).
- **At most 4 handler registrations** badge-wide (`:41`).
- **Payload ≤ 32 KiB** (`HOST_EXT_FEATURE_PAYLOAD_MAX`), copied into PSRAM.
- **No provider installed:** the firmware shows a "no plugin for this feature"
  modal and `use` returns `HOST_ERR_NOT_FOUND`.
- **A plugin can't call its own feature** (`HOST_ERR_INVALID_ARG`, `:150`).
- `HOST_OK` from `use` means *job accepted*, not *done*.
- **The foreground switch unloads a non-background caller.** Its status action
  is then silently dropped. Declare `background` and call `set_resident(true)`
  to receive results.
- The payload must be consumed during the handler dispatch. Afterwards it's
  gone.

## Uses for badge-cdc

- Hand data to existing plugins without reimplementing them. For example,
  `thermo_print` prints a raster or QR job on a BLE thermal printer (format
  documented in `plugins/thermo_printer/README.md`). A keysigning party could
  print fingerprint slips this way.
- Expose our own capability as a provider (for example "verify an OpenPGP
  fingerprint" or "sign with the party key") for other plugins.
- **Security:** any installed plugin can call a provider, and the provider
  learns only the caller's payload, not an authenticated caller identity.
  Validate payloads as untrusted input, and require on-screen user confirmation
  for anything sensitive.
