---
type: research findings
title: What a plugin can build on the TROPIC01
description: Findings on how far a sandboxed cdc-badge-os plugin can exploit the TROPIC01 secure element — the plugin-visible primitives (one non-exportable Ed25519/P-256 key, hardware RNG, 11 R-Memory slots), what the chip and the plugin API cannot do (vendor-signed firmware only, no HMAC/SHA-512 or secp256k1 or ECDH, no MAC-and-Destroy or counters for plugins), BIP85/HMAC-SHA512 options, a ranked catalogue of plugin ideas, and Alephium compatibility via ED25519 and WebAuthn groupless addresses, with the items still to verify.
tags: [tropic01, secure-element, research, ideas, ed25519, alephium, bip85, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:38:30.389Z
sources:
  - id: openwiki-source-a893e42b7081dbabd7efc3d8
    resource: repo://references/cdc-badge-hardware/README.md
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-b867d153675ba33ae714dd88
    resource: repo://references/cdc-badge-os/main/tropic_slot_map.h
  - id: openwiki-source-35a1e3ccecf4b500f9c41890
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/secure-element.md
  - id: openwiki-source-7750baf6065749c0d8f8fb55
    resource: repo://references/libtropic-arduino/src/LibtropicArduino.h
generated: { by: "claude-code", at: "2026-11-12T21:38:30.389Z" }
---

# What a plugin can build on the TROPIC01

These findings come from the 2026-11-12 design discussion. Repository facts
are cited from `references/`. Vendor and Alephium facts come from public
documentation and source, linked inline, and are **not** part of the vendored
tree. Mechanics live in [secure element](../hardware/secure-element.md); this
page is about what to build with them.

## 1. What a plugin actually gets

From the secure-element and crypto groups of `host_api.h`, implemented in
`plugin_manager/src/host_api_se.cpp`:

| Primitive | Detail | Use it for |
|---|---|---|
| **One ECC key per badge** | The plugin pool is a single TROPIC01 ECC slot (31), shared by name across all plugins. Ed25519 or P-256. Generated on-chip, or imported from a 32-byte private key. **Never exportable**; only the public key reads back. | Identity, signing, and a deterministic PRF root (below) |
| Ed25519 signing | `host_eddsa_sign`: standard Ed25519, 64-byte signature, **deterministic** | OpenPGP EdDSA, minisign/signify, SSB, Ed25519 blockchains, Alephium ED25519 addresses |
| P-256 signing | `host_ecdsa_sign`: the chip **SHA-256-hashes the message itself**; raw r‖s, 64 bytes | Protocols that sign `SHA-256(message)` (WebAuthn-style) |
| Hardware RNG | `host_random_strict` (SE only) / `host_random` (SE, falls back to the ESP32 TRNG) | Keys, nonces, seeds |
| R-Memory | 11 named slots, ≥ 444 B each, shared by name | Small records. **Not confidential** on stock badges. |
| Software crypto (ESP32) | `host_sha256`, `host_hmac_sha256`, `host_aes_gcm_*` | Glue around the SE |

Properties to design around:

- **Non-exportable doesn't mean unusable by an attacker.** On a stock badge the
  TROPIC01 pairing key is the public libtropic production key. Anyone with
  physical SPI access (for example through the Raspberry Pi header switch) can
  open a session, *use* the key and read R-Memory, though they can't extract the
  private key. Only a [hardened](../os/production-hardening.md) badge with a
  rotated pairing key closes this.
- **Isolation is by name.** Another installed plugin that declares the same
  `ecc` name can sign with the same key (see
  [manifest](../plugin-runtime/manifest-and-capabilities.md)).
- **Plugins don't get** MAC-and-Destroy (attempt-limited PIN secrets),
  monotonic counters, or pairing-key management. The chip has them (see the
  libtropic-arduino API), but the plugin host API exposes none. They are the
  OS's.

### The deterministic-signature PRF

Ed25519 signatures are deterministic (RFC 8032). Therefore
`H(eddsa_sign(label))` is a stable secret that only this chip can compute:
a key-derivation root whose secret never leaves the TROPIC01.

- **Recoverable variant.** Import an Ed25519 private key derived from your own
  seed (`host_ecc_import`). The chip then holds the root, and the paper seed can
  reproduce every output on a computer.
- **Non-recoverable variant.** Generate the key on-chip. Then everything dies
  with the badge.
- **To verify on hardware:** that the TROPIC01 EdDSA implementation is the pure,
  deterministic RFC 8032 variant (expected, not yet tested).

## 2. Chip limits (TROPIC01 architecture)

- **Two processors.**
  - A **RISC-V CPU** runs the updatable application firmware: the secure-channel
    protocol, command handling, R-Memory, pairing keys, counters and
    MAC-and-Destroy.
  - A **SPECT** coprocessor does the elliptic-curve math.
  - The OS reports both firmware versions (`dev/secure-element.md`,
    `getFwVersion`).
- **Firmware must be vendor-signed.** The ROM bootloader accepts only firmware
  signed by Tropic Square (an EdDSA signature over a SHA-256 hash chain), with
  downgrade protection.
  - **There are no user applets**, so nobody but the vendor can add commands
    such as HMAC-SHA512.
  - "Open architecture" means auditable, not user-programmable.
  - Ledger's Donjon team has shown a laser fault-injection bypass of the
    signature check. That is an attack, not a development path.
  - Sources: [libtropic: TROPIC01 firmware](https://tropicsquare.github.io/libtropic/latest/reference/tropic01_fw),
    [Tropic Square notice](https://www.tropicsquare.com/blogs/potential-bypass-of-firmware-verification-by-laser-fault-injection),
    [Ledger Donjon](https://donjon.ledger.com/blog/tropic01-laser-fault-injection/).
- **Primitives the chip lacks** for our purposes:
  - no exposed general hash, HMAC or AES command (SHA-512 exists internally
    for Ed25519, but can't be called);
  - **no secp256k1**;
  - **no ECDH or X25519**. The OS works around this with software keys for
    GPG DEC and PIV 9D.

## 3. HMAC-SHA512 and BIP85

- **HMAC-SHA512 can't run on the TROPIC01.** Do it in Rust inside the plugin
  (`hmac` + `sha2`, no_std). The key is in ESP32 RAM while in use.
- **BIP85** (BIP32 hardened derivation plus
  `HMAC-SHA512("bip-entropy-from-k", k)`) needs only HMAC-SHA512 and arithmetic
  modulo the secp256k1 group order, with no EC point math. It therefore runs
  entirely in the plugin.
- **Protecting the seed at rest.** Encrypt it with a key derived from the
  deterministic-signature PRF plus a PIN typed on the badge. Don't store it
  plain in R-Memory.
- **Prior art:** [xmr-cdc-badge](https://codeberg.org/telliandev/xmr-cdc-badge),
  a Monero wallet on this badge (listed in `cdc-badge-hardware/README.md`).
- **Keep a real BIP39 seed as the root** so that standard BIP85 outputs stay
  recoverable elsewhere. A chip-signature-rooted "BIP85-like" scheme is
  non-standard and dies with the chip.

## 4. Ranked plugin ideas

| # | Idea | Why the TROPIC01 matters | Main blockers |
|---|---|---|---|
| 1 | **Keysigning party with a hardware certification key.** An Ed25519 OpenPGP key that lives only in the chip; a real verification ritual (high-entropy SAS words, ID checklist, cert levels 0x12/0x13, expiry); OpenPGP certifications exported by QR, USB or serial; your main key certifies the badge key once. Exchange over the plugin's own GATT service. Event key list with checksum, who-signed-whom graph. | Non-exportable certifying key | Plugin message receive is broken, so use raw GATT ([BLE GATT](../plugin-runtime/ble-gatt-for-plugins.md)). Can't use the OS GPG key ([GPG review](../os/security/gpg-openpgp-module.md)). |
| 2 | **Seed-recoverable secret generator.** Passwords, TOTP seeds, BIP85-style mnemonics = `H(sig(label))` | Root stays in the chip | Ed25519 determinism to verify |
| 3 | **Ed25519 signing device.** minisign/signify, git/SSH signature payloads, SSB, Ed25519 chains (Solana, Stellar, Algorand, NEAR, Aptos/Sui, Tezos tz1): data in over serial or USB, summary on screen, Y to sign, signature out by QR or serial | Hardware-held signing key | No secp256k1 chains (Bitcoin, Ethereum, Nostr); no age (needs X25519) |
| 4 | **Signed proof-of-meeting receipts** between badges | Per-badge hardware identity | Raw GATT exchange |
| 5 | **Signed warrant canary / dead-man's switch** over HTTPS | Hardware signature | Residency and power ([networking](../plugin-runtime/networking-wifi-http-sockets.md)) |

Upstream OS changes that would unlock more:

- host-API access to MAC-and-Destroy and the monotonic counters;
- a confirm-and-sign hook into mod_gpg;
- a fix for plugin message receiving.

## 5. Alephium compatibility

Alephium's Danube upgrade added **groupless P2PK addresses**. Their key-type
prefixes are `0x00` SecP256K1, `0x01` SecP256R1, `0x02` ED25519 and `0x03`
WebAuthn ([address docs](https://docs.alephium.org/dapps/concepts/address)).

| Key type | Badge can sign? | Reason |
|---|---|---|
| SecP256K1 (classic P2PKH) | **No** | The TROPIC01 has no secp256k1 |
| **ED25519** | **Yes** | Alephium verifies pure RFC 8032 Ed25519 over the raw message ([ED25519.scala](https://github.com/alephium/alephium/blob/master/crypto/src/main/scala/org/alephium/crypto/ED25519.scala)). The chip signs the 32-byte tx id directly. |
| SecP256R1 | **No (for transactions)** | Alephium uses the 32-byte data as the ECDSA digest, with no extra hash, and enforces low-S ([SecP256R1.scala](https://github.com/alephium/alephium/blob/master/crypto/src/main/scala/org/alephium/crypto/SecP256R1.scala)). The chip always SHA-256-hashes first, so the signatures can't match. |
| WebAuthn | **Very likely yes** | WebAuthn ES256 signs `SHA-256(authenticatorData ‖ SHA-256(clientDataJSON))`, which matches the chip's hash-then-sign. The plugin builds both blobs (challenge = tx id) and normalises `s` to low-S. **Alephium's WebAuthn verifier not yet checked.** |

The Ralph cryptography built-ins include `verifyED25519!`, `verifySecP256R1!`,
`verifyWebAuthn!`, `verifySecP256K1!`, `verifyBIP340Schnorr!`, `sha256!` and
`blake2b!` ([built-ins](https://docs.alephium.org/ralph/built-in-functions)).
Contracts can verify badge P-256 signatures with
`verifySecP256R1!(sha256!(msg), pk, sig)`.

Alephium ideas:

1. **Hardware signer for an ED25519 address.**
   - An unsigned transaction comes in over USB serial, or from your own node
     over Wi-Fi.
   - The plugin decodes it and shows recipients, amounts and tokens.
   - Y makes the chip sign the tx id, and the signature goes out by serial, QR
     or straight to your node.
2. **Recovery without key export.** Use a multisig groupless type (P2HMPK), for
   example badge Ed25519 + phone passkey + paper secp256k1. **The P2HMPK rules
   are not yet checked.**
3. **On-chain web of trust.** Badge keys register in a Ralph contract, and
   in-person verifications are double-signed and checked with `verifyED25519!`.
   This combines with idea #1 in section 4.
4. **Watch-only monitor.** Balances and transfers from a node or explorer API,
   shown on the e-paper, with no key.

Limits: one plugin key per badge; physical-access risk on unhardened badges;
the plugin must parse Alephium's tx format in Rust/WASM; wallet and SDK support
for ED25519/WebAuthn P2PK transaction building is unchecked.

## 6. Open verification items

| Item | How to check |
|---|---|
| TROPIC01 Ed25519 is deterministic RFC 8032 | Sign the same message twice on a badge and compare; check against a reference implementation using the same key |
| Alephium WebAuthn verification details (signed data, low-S, payload layout) | Read Alephium's WebAuthn verification source; testnet transaction |
| P2HMPK multisig rules | Alephium docs and source |
| SDK and wallet support for ED25519 / WebAuthn P2PK transaction building | `@alephium/web3` source and testnet |
| Plugin message receive bug | Device test ([BLE review](../os/security/ble-message-transfer.md)) |
