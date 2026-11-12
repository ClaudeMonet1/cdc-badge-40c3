---
type: security review
title: Badge-to-badge BLE message transfer review
description: Code-level security and design review of cdc-badge-os's cdc_msg framework (used by GPG key exchange, vCard and plugins) — discovery and trackability, what the 6-digit pairing does and does not guarantee, the OFFER/chunk wire protocol, delivery to modules and plugins, MIME-handler registry semantics, limits, and a bug that appears to stop plugins from registering receive handlers.
tags: [ble, security-review, cdc_msg, pairing, privacy, plugins, message-transfer]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T20:57:16.971Z
sources:
  - id: openwiki-source-83deb14d7252b0a7ada88fde
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/BluetoothController.cpp
  - id: openwiki-source-3a2d40176a0fcea7528c4b01
    resource: repo://references/cdc-badge-os/components/cdc_msg/include/cdc_msg/MessageTypes.h
  - id: openwiki-source-01d6fb60639d380068227ed4
    resource: repo://references/cdc-badge-os/components/cdc_msg/src/BeaconManager.cpp
  - id: openwiki-source-61b998c0f8cbbd5b9d104be0
    resource: repo://references/cdc-badge-os/components/cdc_msg/src/MessageHandlerRegistry.cpp
  - id: openwiki-source-dc6ca5600c665b4510239dec
    resource: repo://references/cdc-badge-os/components/cdc_msg/src/MessageTransfer.cpp
  - id: openwiki-source-5b74450674d6cc34f06768f8
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_msg.cpp
  - id: openwiki-source-b1d4e37214aad4d22b28c154
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginManager.cpp
  - id: openwiki-source-a9baa65a2e0f48fed1b02f5d
    resource: repo://references/cdc-badge-os/sdkconfig.cdc_badge_usb
  - id: openwiki-source-e9da9d444ef0e89f19d65183
    resource: repo://references/cdc-badge-plugins/examples/mini_messenger/src/lib.rs
generated: { by: "claude-code", at: "2026-11-12T20:57:16.971Z" }
---

# Badge-to-badge BLE message transfer review

Scope: `references/cdc-badge-os/components/cdc_msg/` plus its host-API surface
(`plugin_manager/src/host_api_msg.cpp`). Both GPG key exchange
([GPG review](gpg-openpgp-module.md)), vCard sharing and plugin messaging run on
this framework.

**Method:** static reading of the vendored snapshot (OS commit `181a24d`). Nothing
was tested on hardware. The key claims below were re-read in source; items
marked *(inference)* follow from the code but need a device test.

## Summary for a plugin author

- Treat every received payload as **anonymous and unauthenticated**. Verify
  identity at the application layer (for example, OpenPGP fingerprints compared
  out-of-band).
- Never set `HOST_MSG_FLAG_PERSIST` for anything security-relevant.
- Use a **private MIME type**, not `application/pgp-keys`.
- **Before you rely on plugin receive at all**, check the registration bug in
  [MIME handlers](#mime-handlers-and-the-plugin-registration-bug).

## Discovery and privacy

- Badges advertise the 128-bit service UUID `CDC50001-…`, a complete local
  name, TX power and flags (`MessageProfile.h`, `BluetoothController.cpp`).
- **The advertised name** comes from NVS `msg/bname`, then the badge display
  name, then `"Badge"` (`BeaconManager.cpp:52-58`). By default it is the
  owner's on-badge name.
- **The address is public/static.** It comes from `ble_hs_id_infer_auto(0, …)`
  with privacy off (`BluetoothController.cpp:1083-1087`). Combined with the
  broadcast name, the badge is **trackable**.
- **The beacon is on by default.** The peer picker lists anything that
  advertises the UUID under whatever name it claims. Nothing proves a peer's
  identity.

## Pairing: what the 6 digits really mean

- **NimBLE is set up for numeric comparison** (`BluetoothController.cpp:733-739`):
  `sm_io_cap = DISP_YES_NO`, bonding, `sm_mitm = 1`, `sm_sc = 1`.
- **Authenticated pairing is not enforced.**
  - The Data characteristic requires only `GattPerm::WRITE_ENC` (encrypted), not
    an authenticated link (`MessageTransfer.cpp:165-168`).
  - The build sets `CONFIG_BT_NIMBLE_SM_LVL=0`, `SM_SC_ONLY=0`,
    `SM_LEGACY=y` (`sdkconfig.cdc_badge_usb:754-759`).
  - *(Inference)* A peer that claims NoInputNoOutput gets an unauthenticated
    "Just Works" pairing, with no number shown, and the transfer still proceeds.
- **Plaintext before pairing.** The OFFER (MIME type, size, sender name) and
  status frames cross the link before encryption.
- **Bonds are deleted after each transfer.** The bond table holds 2 entries.
  *(Inference)* A missed 50 ms lock in `onDisconnect` can leave a bond behind,
  though a boot-time cleanup erases leftovers.
- **`HOST_MSG_FLAG_PERSIST`**, set by the **sender** alone:
  - Both sides keep the peer as trusted for the session.
  - Any later persistent OFFER from that peer is **auto-accepted without a
    consent prompt or prompt budget, regardless of MIME type**
    (`MessageTransfer.cpp:932-946`).
  - The trust check uses the peer's claimed identity address.
  - *(Inference)* A device that spoofs a trusted badge's public address could
    skip consent.
- **The receiver gets no authenticated sender identity.** The name is
  self-declared in the OFFER, and the plugin delivery callback receives no peer
  information at all.

## Wire protocol and delivery

```
receiver ◄─ OFFER [01][ver=1][u32 len][mimeLen][nameLen|0x80 persist][mime][name]   (plaintext)
         ── consent prompt (claimed name, description, size; PIN if locked)
         ─► Accept ; sender initiates pairing ; encrypted link
receiver ◄─ CHUNK [10][00][≤254 bytes] … (write-without-response)
receiver ◄─ COMPLETE [11][00][crc32]
         ─► Progress every 512 B, then Done
```

- CRC32 detects corruption only. Tamper resistance comes entirely from link
  encryption.
- **Delivery order:** a live registry handler first; otherwise the deferred
  path, which stashes the payload and loads the handler plugin in the background
  (`MessageTransfer.cpp:1005-1020`).
- **Done is sent once the hand-off is queued, not when the plugin has the
  payload.** If the plugin never gets a handler, the payload is silently
  dropped while both badges report success.

## MIME handlers and the plugin registration bug

- **Registry semantics.** `MessageHandlerRegistry::registerHandler` replaces any
  existing entry for the same MIME type (`MessageHandlerRegistry.cpp:35-55`).
  `unregisterHandler` has no owner check.
- **Plugins can't take over a live OS handler.**
  - `host_msg_register_handler` requires the MIME type to be declared in the
    manifest's `message_types`.
  - It returns `HOST_ERR_BUSY` when `MessageTransfer::hasHandler(mime)` is true
    (`host_api_msg.cpp:188-201`).
  - But if an OS module is absent or stopped (mod_gpg unregisters on `stop()`),
    its type is free to claim. Load-time capability checks don't validate
    `message_types` at all.
- **Bug (checked in source): plugins can't register their own types.**
  - `hasHandler` also asks the deferred resolver (`MessageTransfer.cpp:240-252`).
  - That resolver is `PluginManager::messageTypeInstalled(mime)`
    (`host_api_msg.cpp:274-280`). It returns true for any installed, enabled
    plugin declaring the type, **including the caller itself**
    (`PluginManager.cpp:585-647`).
  - So a plugin's registration of its own declared MIME type returns
    `HOST_ERR_BUSY`. It only succeeds if the 20 ms index lock times out.
  - The deferred path then finds no handler (`find_handler_by_mime`) and drops
    the payload.
  - The bundled `mini_messenger` example ignores the return value
    (`let _ = msg::register_handler(...)`).
  - The emulator builds against an older OS pin (see [emulator](../../workflows/emulator.md)),
    so its passing `msg_roundtrip` test doesn't prove the current OS works.
  - **Needs a device test, and an upstream report.**

## Limits

| Limit | Value |
|---|---|
| Payload | ≤ 4096 B (`MessageTypes.h:74-76`) |
| MIME string | ≤ 63 chars |
| Chunk | ≤ 254 B |
| Outbound | one send at a time, shared with OS modules (`HOST_ERR_BUSY` otherwise) |
| Inbound | one active session + queue of 4 (`MessageTypes.h:108`), 2 BLE connections |
| Rate limits | 3 offers / 10 s per connection; **5 consent prompts / 30 s globally**; 20 s quiet period after a decline (`MessageTypes.h:117-125`) |
| Plugin hand-off | one pending delivery slot. A second delivery before the first is consumed fails. |
| Topology | strictly 1:1 (connect → offer → pair → send). **No broadcast.** |
| Handler table | 8 slots shared by OS modules and plugins |

The global prompt budget lets a nearby device **crowd out real offers**: anyone
can write the plaintext control characteristic.

## Documentation vs code

- The docs call the pairing "numeric comparison", but authentication isn't
  enforced.
- The docs say the bond table is "sized to connection capacity"; the code
  hard-codes 2.
- A `Delivering` receiver state is documented but never used. `Abort` is handled
  on receive but never sent.
- `host_api.h` doesn't list `HOST_ERR_BUSY` for `host_msg_register_handler`.

## Implications for a keysigning-party plugin

1. The transport gives confidentiality against passive listeners only when
   pairing happens to be authenticated. Design for an unauthenticated channel.
   Bind identities with fingerprints the humans compare on screen.
2. Group exchange has to be built from repeated 1:1 transfers within the
   prompt-rate limits.
3. Until the registration bug is fixed upstream, a plugin can **send** but most
   likely can't **receive**. Alternatives:
   - QR codes for display-to-camera exchange (the badge has no camera, so this
     only works badge → phone);
   - serial `PLUGIN CMD` input via `plugin_on_cmd`;
   - a patched OS build.
