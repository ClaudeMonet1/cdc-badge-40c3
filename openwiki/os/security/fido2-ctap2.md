---
type: security review
title: FIDO2 / CTAP2 module review
description: Code-level review of cdc-badge-os's mod_fido2 — USB-only CTAP2 (advertised as 2.1) plus U2F, the getInfo it advertises, which commands are implemented, one-TROPIC01-slot-per-credential storage and sign counters, user presence and the badge-PIN-as-ClientPIN semantics, per-device attestation, and spec deviations including raw (non-DER) ES256 assertion signatures and the absence of hmac-secret.
tags: [fido2, ctap2, webauthn, u2f, security-review, tropic01, attestation]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T20:57:16.971Z
sources:
  - id: openwiki-source-ea1f45c2ab6ed4cd0d8a0cf1
    resource: repo://references/cdc-badge-os/components/mod_fido2/src/ctap2.cpp
  - id: openwiki-source-e32260f9e28a7fecafaadae0
    resource: repo://references/cdc-badge-os/components/mod_fido2/src/fido2_storage.cpp
  - id: openwiki-source-2657051cbbbf61913a50bf54
    resource: repo://references/cdc-badge-os/components/mod_fido2/src/u2f.cpp
  - id: openwiki-source-b867d153675ba33ae714dd88
    resource: repo://references/cdc-badge-os/main/tropic_slot_map.h
generated: { by: "claude-code", at: "2026-11-12T20:57:16.971Z" }
---

# FIDO2 / CTAP2 module review

Scope: `references/cdc-badge-os/components/mod_fido2/` (`ctap2.cpp`,
`ctaphid.cpp`, `u2f.cpp`, `fido2_storage.cpp`, `Fido2Ui.cpp`) and the PIN
plumbing in `cdc_core/src/PinManager.cpp`.

**Method:** static reading of the vendored snapshot, OS commit `181a24d`. The
headline items were re-read in source. Nothing was tested against a real
browser or relying party.

**Short answer:** yes, it implements CTAP2 and advertises 2.1, with broad
command coverage. It also has real interoperability bugs, notably **P-256
assertions are not DER-encoded**, and **no `hmac-secret`**.

## Transports

- **USB HID (CTAPHID) only**: getInfo lists `transports = ["usb"]` (`ctap2.cpp:55`).
  There is no BLE or NFC authenticator.
- CTAPHID handles INIT, PING, WINK, CANCEL, CBOR and MSG. `CTAPHID_LOCK` is
  defined but never dispatched.
- **U2F / CTAP1** via MSG: `U2F_V2` VERSION, REGISTER, AUTHENTICATE.

## authenticatorGetInfo

| Field | Value |
|---|---|
| versions | `FIDO_2_0`, `FIDO_2_1`, `U2F_V2` (`ctap2.cpp:560-565`) |
| extensions | `appid`, `credProtect`, `appidExclude` (`ctap2.cpp:568-575`) |
| AAGUID | `CDCBAD6E-39C3-0001-BAD6-E00100000001` (`ctap2.cpp:46-52`) |
| options | `rk`, `up`, `clientPin`, `credMgmt`, `authnrCfg`, `largeBlobs`, `pinUvAuthToken`, `setMinPINLength`, `makeCredUvNotRqd` = true; `uv` = false (no built-in UV); `alwaysUv` per state |
| pinUvAuthProtocols | `[2]` |
| algorithms | ES256, EdDSA |

## Commands

- **Implemented:**
  - makeCredential, getAssertion, getNextAssertion, getInfo, reset, selection,
    largeBlobs, config (toggleAlwaysUv, setMinPINLength);
  - clientPIN: getPINRetries, getKeyAgreement, getPinToken,
    getPinUvAuthTokenUsingPinWithPermissions;
  - credentialManagement: metadata, enumerate RPs and credentials, delete.
- **Not implemented:**
  - clientPIN `setPIN` / `changePIN` return `UNSUPPORTED_OPTION`, because the PIN
    is the badge PIN, set on-device (`ctap2.cpp:2995-3000`);
  - credMgmt `updateUserInformation`;
  - bioEnrollment.
- **Advertised but incomplete:**
  - `largeBlobs` is offered without the `largeBlobKey` extension;
  - makeCredential doesn't parse `excludeList`, so excluded credentials are
    ignored.

## Credential storage and counters

- **Every credential, resident or not, occupies its own TROPIC01 ECC slot.**
  There is no key wrapping.
- The slot map gives FIDO2 ECC and R-Memory slots **9–30, so 22 credentials**.
  The OS docs still say 26 (slots 5–30). See [secure element](../../hardware/secure-element.md).
- **Credential ID** = slot byte ‖ 16-byte random nonce ‖ zero padding. It isn't
  MAC'd; the code comments "In production, use HMAC for binding"
  (`fido2_storage.cpp:948-955`). Lookups compare against the stored ID.
- **Sign counter:**
  - one per credential, persisted by erasing and rewriting the credential's
    R-Memory record;
  - not atomic: a power loss between the two can lose the record;
  - not backed by TROPIC01's monotonic counters.

## User presence, PIN and UV

- **User presence** is an on-device Y/N prompt with a 30 s timeout
  (`ctap2.cpp:58`). On a locked badge, approving also asks for the badge PIN.
- **`up = false` requests are honoured without any prompt**, even on a locked
  badge (`ctap2.cpp:1955-1966`).
- **No built-in UV.** UV comes from ClientPIN protocol 2: ECDH, then HKDF, then
  AES-CBC. The decrypted `LEFT(SHA-256(PIN),16)` is compared with the badge PIN
  hash ([ADR-0004](../../hardware/secure-element.md)).
- **The badge PIN is the FIDO PIN.**
  - FIDO is always reported as having a PIN set, so the factory default
    `123456` works until the user changes it.
  - authenticatorReset erases credentials but cannot clear the PIN.
- **Two layers of retries, both differing from the spec:**
  - The CTAP retry counter (8) is RAM-only and resets every boot.
  - The real limit is the badge PIN's: 3 tries, then a timed lockout doubling
    from 60 s up to about 17 h.
  - So getPINRetries over-reports, and there is no permanent block.
- **PIN tokens and resident keys:**
  - Legacy `getPinToken` tokens get all permissions, not just mc/ga.
  - A discoverable credential can be created without pinUvAuth even when a PIN
    is set.

## Attestation

- `packed` format with an x5c chain, signed by the attestation key in ECC slot 0.
  The attestation signature *is* DER-encoded.
- The certificate is self-signed and generated per device. A CA-signed
  certificate can be imported.
- **Privacy:** one unique attestation key per badge links the device across
  relying parties. FIDO expects batches of at least 100k devices to share one.

## Spec deviations and bugs

| Issue | Evidence | Impact |
|---|---|---|
| **ES256 assertion signatures are raw r‖s (64 B), not DER.** getAssertion, getNextAssertion and U2F AUTHENTICATE all call `fido2_storage_sign_raw`; `fido2_storage_sign_der` exists but has no caller | `ctap2.cpp:1819`, `ctap2.cpp:2114`, `u2f.cpp:821`, `fido2_storage.cpp:1089-1125` | WebAuthn and U2F verifiers expect DER, so P-256 sign-ins should fail at standard RPs (EdDSA unaffected). Contradicts the OS doc `fido2-ctap.md`. |
| No `hmac-secret`, `credBlob` or `largeBlobKey` | no references in `mod_fido2/src` | No FIDO PRF. Even added, hmac-secret is HMAC-SHA-256, not SHA-512. |
| allowList with no matching ID falls back to discoverable credentials | `ctap2.cpp` getAssertion | Should return NO_CREDENTIALS |
| getNextAssertion omits the `user` map | `ctap2.cpp` | Account pickers lose user info |
| Non-constant-time `memcmp` on pinUvAuthParam; 16-byte (protocol 1) params accepted while only protocol 2 is advertised | `ctap2.cpp` | Hardening / spec |
| RP IDs ≥ 64 chars truncated before hashing | `cbor_helpers.cpp` | Edge-case collisions |

## Relevance to badge-cdc

- Plugins have **no host API into FIDO2**, and FIDO2 owns ECC slots 9–30. A
  plugin can't use WebAuthn credentials or attestation.
- Anyone wanting FIDO-based key derivation (hmac-secret) or HMAC-SHA512 must
  build it elsewhere: inside a plugin
  ([secure element](../../hardware/secure-element.md)) or as an upstream OS
  change.
- The DER bug and the silent `up=false` behaviour are worth reporting upstream;
  see [open questions](../../reference/open-questions-and-discrepancies.md).
