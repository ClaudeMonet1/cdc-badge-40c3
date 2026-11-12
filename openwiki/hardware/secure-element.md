---
type: hardware subsystem
title: TROPIC01 secure element, PIN and attestation
description: How the CDC Badge uses the TROPIC01 secure element — SPI and libtropic integration, pairing keys and secure sessions, the ECC and R-Memory slot map, PIN hashing, lockout, attestation-signed PIN record and duress PIN in cdc-badge-os, the libtropic-arduino API used by the vendor, and the named-slot secure-element host API offered to plugins.
tags: [tropic01, secure-element, libtropic, pin, attestation, slots, rmem, ecc, security]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-5e9bedad6c60b4dcd8d76a5a
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/tropic01.cpp
  - id: openwiki-source-9472b8f68db0bd379ce46075
    resource: repo://references/cdc-badge-os/components/cdc_hal/include/cdc_hal/pairing_key_config.h
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-4b33dc6fecf63df3facfa270
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_se.cpp
  - id: openwiki-source-b867d153675ba33ae714dd88
    resource: repo://references/cdc-badge-os/main/tropic_slot_map.h
  - id: openwiki-source-cc422b0007a641930b4dfa5a
    resource: repo://references/cdc-badge-os/platformio.ini
  - id: openwiki-source-967ad52dfb083c049aeee6cb
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0004-two-kdf-pin-hashing.md
  - id: openwiki-source-3a9296d800ac25eff7db8b38
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0011-attestation-signed-pin-record.md
  - id: openwiki-source-35a1e3ccecf4b500f9c41890
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/secure-element.md
  - id: openwiki-source-1d11e6ceb8199a502217f7a4
    resource: repo://references/cdc-badge-os/website/src/content/docs/security/pin-lockout.md
  - id: openwiki-source-7750baf6065749c0d8f8fb55
    resource: repo://references/libtropic-arduino/src/LibtropicArduino.h
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# TROPIC01 secure element, PIN and attestation

## Chip and connection

The **TROPIC01** (Tropic Square, open-architecture secure element; TR01-C2P-T301
in the schematic) sits on the badge's shared SPI bus (SCLK 12 / MISO 11 / MOSI
13) with chip select **GPIO10**. Its interrupt line goes to GPIO38. It provides:

- **32 ECC key slots** — P-256 and Ed25519 keys generated or imported on-chip.
  Private keys can't be read back.
- **512 R-Memory ("retained memory") slots** — 444 bytes guaranteed per slot,
  up to 475 bytes depending on the chip firmware.
- A hardware TRNG, MAC-and-destroy slots (used for PIN-attempt schemes), and
  chip ID and firmware version queries.

The ESP32 can only talk to it inside an **encrypted, authenticated secure
session**, opened with an X25519 "pairing key" (SH0 private/public plus a
pairing slot index).

The hardware lets a Raspberry Pi header device share the TROPIC01 chip select via
slide switch SW15 (see [pin map](pin-map-and-buses.md)). In sleep the chip draws
~945 µA, which dominates standby power (see [power](power-and-charging.md)).

## Software stacks

| Stack | Library | Where |
|---|---|---|
| Vendor firmware | **libtropic-arduino** (`references/libtropic-arduino/`, wraps the libtropic C library as an Arduino `Tropic01` class) | `references/cdc-badge-nametag/lib/cdc-badge/tropic01.cpp` |
| cdc-badge-os | **libtropic** C library (submodule `third_party/libtropic`, not vendored) with an ESP-IDF SPI port | `components/cdc_hal/src/libtropic_port_esp32.cpp`, `Tropic01Element.cpp` |

### libtropic-arduino API surface

`Tropic01(csPin, spiBus)` is non-copyable and non-movable. Its methods return
`lt_ret_t`:

| Method | Purpose |
|---|---|
| `begin()` / `end()` | Initialise and release resources. `SPI.begin()` must already have been called. |
| `secureSessionStart(shiPriv, shiPub, pkeyIndex)` / `secureSessionEnd()` | Encrypted session using a pairing key |
| `ping(msgOut, msgIn, len)` | Echo test over the session |
| `eccKeyGenerate(slot, curve)`, `eccKeyStore(...)`, `eccKeyRead(...)`, `eccKeyErase(slot)` | ECC slot management (`eccKeyRead` returns the **public** key) |
| `ecdsaSign(slot, msg, len, rs)`, `eddsaSign(slot, msg, len, rs)` | Signing |
| `rMemWrite/rMemRead/rMemErase(udataSlot, ...)` | R-Memory |
| `macAndDestroy(slot, dataOut, dataIn)` | MAC-and-destroy primitive |

The vendor firmware only calls `begin()` and then `secureSessionStart()` with the
libtropic **production SH0 key in slot 0**, as a bring-up check. The libtropic-arduino
examples (`hello_world`, `ECDSA_P256`, `EdDSA_Ed25519`, `r_memory`,
`MAC_and_destroy`) show the rest of the API.

### cdc-badge-os `ISecureElement`

`Tropic01Element.cpp` implements the HAL interface `ISecureElement`. It is
documented in detail in `website/src/content/docs/dev/secure-element.md`, which is
the authoritative developer reference:

- **Session:** `sessionStart`, `sessionEnd`, `isSessionActive`, `sleep`.
  Operations without a session return `SeResult::SESSION_REQUIRED`. Other results
  include `SLOT_EMPTY`, `SLOT_OCCUPIED`, `INVALID_PARAM`, `NOT_SUPPORTED` and
  `ALARM_MODE` (tamper detected).
- **ECC:** `eccGenerate`, `eccImport` (32-byte private key), `eccGetPublicKey`
  (65 bytes for P-256, 32 for Ed25519), `eccDelete`, `eccSlotUsed`. There is **no
  private key export**.
- **Signing:** `ecdsaSign` (P-256; the chip hashes with SHA-256 internally, so
  **don't pre-hash**; output is raw r‖s, 64 bytes) and `eddsaSign` (Ed25519,
  64 bytes).
- **R-Memory:** raw read/write/erase plus `rmemWriteWithHeader` /
  `rmemReadWithHeader`. The packed header holds magic, checksum, module id,
  flags, a 16-byte name and the payload length.
- **RNG:** `getRandom` falls back to the ESP32 TRNG if no session is available
  (and logs a warning). `getRandomStrict` uses the SE only, and is the one to use
  for keys and seeds.

**Pairing key selection** is a build flag (`platformio.ini`,
`cdc_hal/pairing_key_config.h`): `CDC_PAIRING_KEY_PROD0` (default, libtropic
production key in slot 0), `CDC_PAIRING_KEY_ENG_SAMPLE`, or
`CDC_PAIRING_KEY_CUSTOM` from a git-ignored `pairing_key_custom.h`. The default
key is public in libtropic, so anyone with physical SPI access (for example
through the header switch) can open a session. That is why the OS signs its own
records (see below).

## Slot allocation (ADR-0003)

The compile-time map in `references/cdc-badge-os/main/tropic_slot_map.h` gives
each module disjoint ranges. Module IDs are permanent on-device identifiers and
are never reused. The table below follows the **source header**. The developer
doc `dev/secure-element.md` still shows FIDO2 at 5–30 and leaves out the PIV
module that now occupies 5–8, so on this point the doc is stale.

| Module (ID) | ECC slots | R-Memory slots |
|---|---|---|
| System / attestation (0) | **0** (attestation key) | **0** (signed PIN record) |
| GPG (2) | 1–3 | 1–3 |
| CA (3) | 4 | 4 |
| PIV (9) | 5–8 (9A, 9C, reserved, 9E; 9D is a software key, because TROPIC01 has no ECDH) | 5–8 |
| FIDO2 (4) | 9–30 | 9–30 |
| 2FA / TOTP (5) | — | 31–130 |
| GPG RSA (8) | — | 131–136 |
| Password vault (6) | — | 137–500 |
| **Plugin pool (7)** | **31** (one slot) | **501–511** (11 slots) |

`TropicSlotMap.cpp` is the central validator of these ranges at runtime.

## PIN, lockout, attestation and duress

All PIN state lives in `cdc_core/src/PinManager.cpp`, persisted in **R-Memory
slot 0**.

- **Two hash schemes (ADR-0004).** The protocols that consume the PINs dictate
  the hashes:
  - The badge PIN doubles as the FIDO2 CTAP2 ClientPIN, so it is stored as
    `LEFT(SHA-256(PIN), 16)`, unsalted.
  - OpenPGP PW1/PW3 and the duress PIN use Iterated+Salted S2K over SHA-256
    with a per-PIN salt.
- **Attestation-signed record (ADR-0011).** On save, the PIN record is signed
  with ECDSA P-256 by the chip-bound attestation key in **ECC slot 0**. On load,
  a bad magic, bad length or bad signature triggers a silent reinit to defaults,
  never a migration. Rewriting slot 0 with the public pairing key therefore
  wipes PIN state rather than letting an attacker substitute it.
- **Badge PIN rules.** 4–8 digits, default `123456`, 3 attempts. The lockout is
  a self-recovering rate limit: the retry counter lives in RAM and only the
  consecutive-lockout count is persisted. The recovery window is
  `60 s × 2^(lockouts−1)`, capped at ~17 h. The badge PIN can't be bricked. The
  OpenPGP PW1/PW3 counters follow persistent smartcard semantics.
- **Duress PIN** (off by default, set from Expert menu). It is checked before
  the real PIN at unlock. A match wipes the badge and reboots, with no visible
  difference from a normal attempt.

User-facing explanations are in `website/src/content/docs/security/`
(`pin-lockout.md`, `duress.md`, `attestation.md`, `secure-element-keys.md`).

## What plugins can do with the secure element

Plugins never see slot numbers. The crypto and secure-element section of the
host API (`host_api.h`, implemented in
`plugin_manager/src/host_api_se.cpp`) is **name-based and capability-gated**:

| API | Gate | Behaviour |
|---|---|---|
| `host_ecc_generate/import/pubkey/delete/exists(name, ...)`, `host_ecdsa_sign`, `host_eddsa_sign` | Name must appear in manifest `capabilities.ecc` (≤15 bytes) | Maps the name to a slot in the plugin ECC pool. The name→slot mapping is persisted in NVS namespace `plg_ecc_map`. A slot whose name no installed plugin declares can be reclaimed, and its stale key is wiped. |
| `host_rmem_read_named/write_named/erase_named/name_used(name, ...)`, `host_rmem_slot_size()` | Name must appear in manifest `capabilities.rmem` (≤15 bytes) | Allocates a slot from R-Memory 501–511 tagged with header magic `0xCD` and the name. The data **survives reboot, uninstall and reinstall** as long as some installed plugin still declares the name. **Plugins declaring the same name share the slot**, intentionally. |
| `host_se_chip_id`, `host_se_fw_version` | — | Diagnostics |
| `host_random`, `host_random_strict`, `host_sha256`, `host_hmac_sha256`, `host_aes_gcm_*`, hex helpers | — | Software and TRNG helpers (see [host API](../plugin-runtime/host-api-reference.md)) |

There is no plugin path to reserved slots, the attestation key, FIDO2/GPG keys,
or raw SPI.

### Pitfalls for a Rust plugin

- **Curve constants differ by layer.** The plugin ABI uses `ECC_CURVE_P256 = 0`,
  `ECC_CURVE_ED25519 = 1`. Internally `curveByte()` uses Ed25519 = 0 and P-256 = 1.
  Always use the `host_api.h` / SDK constants.
- **Pool capacity.** The plugin ECC pool is a **single slot (31)** for the
  entire badge. Two plugins that each want their own ECC key compete for it;
  the second gets an error. Design for at most one hardware-backed key, or fall
  back to software keys sealed with R-Memory.
- **R-Memory sharing.** The R-Memory pool is 11 slots shared by every plugin.
  Names are a shared namespace, not a per-plugin one, so use a distinctive
  prefix to avoid accidental sharing. See
  [manifest and capabilities](../plugin-runtime/manifest-and-capabilities.md).
- **Signing input.** `host_ecdsa_sign` takes the message, not its hash.
