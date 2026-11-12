---
type: reference
title: Open questions, discrepancies and constraints
description: Cross-cutting checklist for building our sandboxed Rust WASM application on the CDC Badge — hard constraints (memory, stack, instruction budget, storage, refresh, power), every disagreement found between the vendored sources with the resolution we adopted, missing or non-vendored upstream material, and open design decisions.
tags: [constraints, discrepancies, open-questions, risks, planning]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T20:57:16.971Z
sources:
  - id: openwiki-source-782754752a7fccf1126740d6
    resource: repo://references/cdc-badge-development/.gitmodules
  - id: openwiki-source-dc6ca5600c665b4510239dec
    resource: repo://references/cdc-badge-os/components/cdc_msg/src/MessageTransfer.cpp
  - id: openwiki-source-ea1f45c2ab6ed4cd0d8a0cf1
    resource: repo://references/cdc-badge-os/components/mod_fido2/src/ctap2.cpp
  - id: openwiki-source-e32260f9e28a7fecafaadae0
    resource: repo://references/cdc-badge-os/components/mod_fido2/src/fido2_storage.cpp
  - id: openwiki-source-fd3fffd2204a12cca83d152c
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgRecvStore.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-5b74450674d6cc34f06768f8
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_msg.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
  - id: openwiki-source-bd7bb9940ccb3a24ccdc6345
    resource: repo://references/cdc-badge-os/partitions.csv
  - id: openwiki-source-a9baa65a2e0f48fed1b02f5d
    resource: repo://references/cdc-badge-os/sdkconfig.cdc_badge_usb
  - id: openwiki-source-b1ff795d15ce0723bf319255
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/production-hardening.md
  - id: openwiki-source-6eef1d3f209c09f14ca3056f
    resource: repo://references/cdc-badge-os/website/src/content/docs/security/caveats.md
  - id: openwiki-source-73407625626e00182b5056c6
    resource: repo://references/cdc-badge-plugins/sdk/host_api.h
  - id: openwiki-source-edf57d425cf4973bb79fe308
    resource: repo://references/SOURCES.md
generated: { by: "claude-code", at: "2026-11-12T20:57:16.971Z" }
---

# Open questions, discrepancies and constraints

This page collects findings from the rest of the wiki. Each row links back to
the page with the evidence. Update it whenever references are refreshed
(`scripts/fetch-references.sh`) or a question is settled.

## Hard constraints for our plugin

| Constraint | Value | Source page |
|---|---|---|
| Target / imports | `wasm32-unknown-unknown`; only the `"cdc"` import module; no WASI | [WAMR runtime](../plugin-runtime/wamr-runtime.md) |
| Execution | Interpreted (fast-interp). AOT is rejected. | [WAMR runtime](../plugin-runtime/wamr-runtime.md) |
| Per-call budget | 500 M WASM instructions, then a trap and force-unload | [WAMR runtime](../plugin-runtime/wamr-runtime.md) |
| Stacks | 64 KiB WAMR stack; wasm-ld shadow stack defaults to 1 MiB (shrink it with `-z stack-size`) | [WAMR runtime](../plugin-runtime/wamr-runtime.md) |
| Linear memory | PSRAM, grown by `memory.grow` (dlmalloc). Manifest 16–4096 KB on device, 16–1024 KB in the SDK validator. | [manifest](../plugin-runtime/manifest-and-capabilities.md) |
| Concurrency | Single-threaded. One recursive mutex serialises all plugin calls. Tick every 50 ms. | [lifecycle](../plugin-runtime/lifecycle-events-and-ui.md) |
| Event subscriptions | 16 slots shared by all plugins | [lifecycle](../plugin-runtime/lifecycle-events-and-ui.md) |
| Secure element | 1 ECC slot and 11 R-Memory slots (444 B guaranteed) for **all** plugins | [secure element](../hardware/secure-element.md) |
| Flash storage | 2 MB `vfat` partition shared by every `.wasm`, the language overlay and user files | [build and flashing](../os/build-flash-and-partitions.md) |
| NVS namespace | ≤ 15 chars with a `plg_`/`plugin_` prefix. **Declare it explicitly**, since the default `plugin_<id>` breaks for ids > 8 chars. | [manifest](../plugin-runtime/manifest-and-capabilities.md) |
| Display | 296×128 1-bit e-paper; ~0.4 s partial, ~1–2 s fast/full; ghosting escalation | [display](../hardware/display-and-graphics.md) |
| Input | 12 keys. Polling and key events need input focus. N+Y is reserved. | [keypad](../hardware/keypad-and-io-expander.md) |
| Power | Light sleep only from the lock screen; background work needs `set_sleep_inhibit` / `prevent_sleep` | [power](../hardware/power-and-charging.md) |
| Data durability | Pre-1.0: any firmware flash (or build-profile change) may wipe NVS, files and the TROPIC01 | [OS architecture](../os/architecture.md) |
| Badge-to-badge receive | A plugin can't register a handler for its own declared MIME type: `HOST_ERR_BUSY`, so payloads are dropped while the sender sees "Done". Sending works. 4 KB per message, 1:1 only, no authenticated sender identity. | [BLE review](../os/security/ble-message-transfer.md) |

## Discrepancies between sources

| # | Topic | What disagrees | Adopted resolution |
|---|---|---|---|
| D1 | Grove GPIOs | Hardware `design-choices.md` says ESP32 IO1/IO2; schematic and OS say GPIO2/3 | GPIO2/3 (the doc names the Grove pins) — [pin map](../hardware/pin-map-and-buses.md) |
| D2 | Expander bus | Vendor `badge.h` comments put the expander on 47/48; its code, the OS and the schematic put it on bus 0 (17/18) | Bus 0 |
| D3 | I²C1 speed | Hardware is designed for 400 kHz; the OS runs 100 kHz | The OS limits it; affects `host_i2c_*` throughput |
| D4 | Flash size | OS 16 MB vs vendor board JSON 8 MB; the schematic symbol doesn't specify | Assume 16 MB + 8 MB Octal PSRAM — [board overview](../hardware/board-overview.md) |
| D5 | Display driver | Vendor uses GxEPD2 `GxEPD2_290_T94_V2` (GDEM029T94 class); GxEPD2 has a dedicated `GDEY029T94` class; the OS uses CalEPD `Gdey029T94` | Panel is GDEY029T94 / SSD1680 — [display](../hardware/display-and-graphics.md) |
| D6 | TROPIC01 slot map | OS `dev/secure-element.md` shows FIDO2 5–30 and no PIV; `tropic_slot_map.h` has PIV 5–8 and FIDO2 9–30 | Header is authoritative — [secure element](../hardware/secure-element.md) |
| D7 | Curve IDs | Plugin ABI P-256 = 0 / Ed25519 = 1; OS internal byte Ed25519 = 0 / P-256 = 1 | Use ABI constants only |
| D8 | Key codes | Polling `KEY_Y` = 10 / `KEY_N` = 11; events deliver ASCII `'Y'`/`'N'` | Handle both explicitly |
| D9 | `linear_memory_kb` max | Firmware/ADR 4096 vs SDK schema/validator 1024 | Stay ≤ 1024 |
| D10 | API level | ADR-0007 says 0.7; header and SDK say 0.8 | 0.8 |
| D11 | FAT partition name | OS docs say `plugins`; `partitions.csv` says `vfat` | Same partition (0xDF0000, 2 MB) |
| D12 | HTTP/Wi-Fi capability | OS `host-api.md` calls them "manifest only"; the code enforces both per call | Enforced |
| D13 | WAMR Kconfig | `WAMR_PSRAM_*` Kconfig options exist; the code hard-codes 64 KiB stacks and ignores them | Code wins |
| D14 | Vendor charger setup | Firmware checklist requires charge current and SYS_MIN on every boot; the vendor nametag firmware sets neither | The OS does it; don't copy the vendor's charger setup |
| D15 | `host_api.h` copies | OS and SDK copies are byte-identical in our snapshot (no drift) | Watch `sync-host-api.yml` upstream |
| D16 | Dev repo pins | `cdc-badge-development/.gitmodules` pins older OS/plugins commits than our vendored snapshots | Use our snapshots; the starter's SDK path must be redirected — [example plugins](../plugin-sdk/example-plugins.md) |

## Missing or partial material

- **`krim404/cdc-badge`** (from the original request) isn't publicly accessible;
  `cdc-badge-development` stands in for it — [repository](../overview/repository-and-references.md).
- **Not vendored submodules:** WAMR, libtropic (C), CalEPD,
  Adafruit-GFX-Library-ESP-IDF. Their behaviour is documented here only as the
  OS uses it. Building the OS or emulator requires fetching them.
- **`krim404/cdc-badge-updater`** (TROPIC01 firmware updater) isn't vendored.
- The hardware schematic **PDF** and the datasheets are external (archive.org
  mirror listed in `docs/datasheets.md`).

## Security observations

- **No plugin signing.** Serial upload is CRC-checked only, and the beta profile
  ships with `FEATURE_SECURE_SERIAL=0` (console open without PIN) —
  [manifest](../plugin-runtime/manifest-and-capabilities.md).
- **Storage isolation is by declared name.** Any plugin can declare another
  plugin's `nvs_namespace`, `rmem` or `ecc` names and access them.
- **Default TROPIC01 pairing key is public** (libtropic prod0). The OS
  compensates with attestation-signed records, and the production-hardening flow
  (`dev/production-hardening.md`) rotates the key and burns eFuses. Stock badges
  also have no secure boot, no flash encryption and an open ROM download mode.
- **External header access.** Slide switches let a Raspberry Pi header device
  drive the display and TROPIC01 directly, bypassing the OS and the sandbox
  — [pin map](../hardware/pin-map-and-buses.md).
- **No OTA:** a single factory app partition means updates are serial-only.

### OS security review findings (2026-11-12, static code reading)

Full detail, with file and line evidence, is in the three review pages. Nothing
below has been tested on a device yet.

| Area | Most important findings | Page |
|---|---|---|
| GPG / OpenPGP | Cross-sign is a single yes/no, with no fingerprint comparison and no PIN. Peer self-signatures and incoming certifications are never verified. Received-key and self-cert stores are keyed on 32-bit fingerprint prefixes, so entries can be overwritten. The DEC/RSA software keys are wrapped without the PIN. There is no touch-to-sign. The word fingerprint is only 25 bits. | [GPG review](../os/security/gpg-openpgp-module.md) |
| BLE message transfer | Authenticated (numeric-comparison) pairing is requested but not enforced: data needs only an encrypted link, SM level 0, legacy allowed. Offers are plaintext. The address is static and the owner's name is broadcast. `PERSIST` auto-accepts later offers of any type. Plugin receive appears broken (see constraints above). | [BLE review](../os/security/ble-message-transfer.md) |
| FIDO2 / CTAP2 | Implements CTAP2 (2.1) over USB plus U2F. **ES256 assertions are raw r‖s, not DER**, so P-256 logins likely fail at standard sites. `up=false` signs silently even when locked. No `hmac-secret`. 22 credentials, one TROPIC01 slot each. Credential IDs aren't MAC'd. The attestation key is unique per device. | [FIDO2 review](../os/security/fido2-ctap2.md) |

Candidates to report upstream: the FIDO2 DER encoding, the plugin message
registration bug, enforcing authenticated BLE pairing, keying the GPG stores on
full fingerprints, and verifying signatures on receipt.

## Open design questions for badge-cdc

1. **License.** The SDK and OS are GPL-3.0. Linking `cdc-badge-plugin` makes our
   plugin GPL. Is that acceptable, or do we bind `host_api.h` ourselves
   (a clean-room FFI) — and does the ABI-only boundary even avoid it?
2. **SDK dependency.** Path-depend on `references/cdc-badge-plugins` (frozen,
   offline), or git-pin upstream? Do we fork `ffi.rs` to own the ABI?
3. **`no_std` vs `std`.** `matrix` shows `std` works on this target. Pick based on
   dependency needs vs binary size.
4. **Secret storage.** With only one plugin ECC slot badge-wide and shared names,
   do we rely on the SE at all, or derive keys from user PIN input
   (`host_ui_push_pin_entry`) plus `host_hmac_sha256`?
5. **UI style.** Prebuilt views (cheap, consistent) vs canvas (custom) vs
   `display_lowlevel` (full control, needs capability).
6. **Residency.** Foreground-only, or a `background` / `autoload` service with
   `set_resident`, and what power cost is acceptable?
7. **Testing.** Which logic goes in host-side `cargo test`, and which goes
   through the [emulator](../workflows/emulator.md) and on-device runs?
8. **Target firmware version.** Pin to OS release `0.8.2` / host API 0.8 and
   re-validate on each upstream minor bump (pre-1.0 minors can break).
9. **Missing host functions.** Anything our application needs that isn't in the
   [host API](../plugin-runtime/host-api-reference.md) needs an upstream
   contribution or an OS fork. List them here once requirements are known.
