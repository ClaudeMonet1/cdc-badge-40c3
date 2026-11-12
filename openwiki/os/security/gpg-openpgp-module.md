---
type: security review
title: GPG / OpenPGP module review
description: Code-level review of cdc-badge-os's mod_gpg — which keys live in the TROPIC01 versus software, OpenPGP card v3.4 compliance and deviations, the badge-to-badge cross-signing flow and what it does not verify, weaknesses in the received-key and self-certification stores, the 25-bit alchemical word fingerprint, and what this means for a web-of-trust keysigning-party plugin.
tags: [gpg, openpgp, security-review, web-of-trust, cross-signing, tropic01, smartcard]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T20:57:16.971Z
sources:
  - id: openwiki-source-c6b3825f0fb7ee76be0310f3
    resource: repo://references/cdc-badge-os/components/cdc_core/src/KeyFingerprint.cpp
  - id: openwiki-source-05b3a8056850c842914f397e
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/gpg.cpp
  - id: openwiki-source-e6e4736ef6a590e6a2759cf9
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgKeyPayload.cpp
  - id: openwiki-source-ac5e46a8a6d599bee3614bfb
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgModule.cpp
  - id: openwiki-source-fd3fffd2204a12cca83d152c
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgRecvStore.cpp
  - id: openwiki-source-ba115adab2ec01a71ca982c8
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgSelfCertStore.cpp
  - id: openwiki-source-dfe2d587b60fd9ec3592f0ac
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/GpgStorage.cpp
  - id: openwiki-source-fdf2eabf8208358f5ab2f98f
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/openpgp/openpgp.cpp
  - id: openwiki-source-d530a2f35f1ec5b1545e3d31
    resource: repo://references/cdc-badge-os/components/mod_gpg/src/openpgp/xsig.cpp
  - id: openwiki-source-d9cf7e4d356f8ac737de3624
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/proto/gpg-cross-signing.md
generated: { by: "claude-code", at: "2026-11-12T20:57:16.971Z" }
---

# GPG / OpenPGP module review

Scope: `references/cdc-badge-os/components/mod_gpg/` (an OpenPGP card based on
pico-openpgp, plus badge-to-badge key exchange and cross-signing),
`cdc_scard` (ISO 7816 applet router), and
`cdc_core/src/KeyFingerprint.cpp`. The upstream protocol description is
`website/src/content/docs/dev/proto/gpg-cross-signing.md`. Transport details
are in [BLE message transfer](ble-message-transfer.md).

**Method:** static reading of the vendored snapshot (OS commit `181a24d`). Key
claims were re-read in source. Items marked *(inference)* need a device test.

## Key material

| Role | Algorithms | Where the private key lives |
|---|---|---|
| SIG (signing / certifying) | Ed25519 or P-256 | TROPIC01 ECC slot 1, non-exportable |
| AUT | Ed25519 or P-256 | TROPIC01 ECC slot 3 |
| DEC | **P-256 ECDH only** (X25519 rejected) | **Software key**: generated on the ESP32, stored AES-GCM-wrapped in R-Memory; ECDH runs in ESP32 RAM |
| RSA 2048/3072/4096 (any role) | software (mbedTLS) | wrapped blobs in R-Memory 131–136 |

- **The wrapping key for DEC and RSA blobs is bound to the chip only.**
  - It is `HKDF(chip_id[, pin_hash])` (`GpgStorage.cpp`), but every DEC/RSA
    save and load passes `pin = nullptr` (`gpg.cpp:175`, `gpg.cpp:328`).
  - So anyone holding the TROPIC01 pairing key, which is the public default on
    stock badges, can read and unwrap these keys. A code comment claiming a
    "PIN-derived key" is inaccurate.
- **Key creation:** keys are generated on-device (UI wizard, serial, or CCID
  GENERATE with PW3), or imported via PUT DATA with PW3.

## OpenPGP card compliance

- The AID advertises **OpenPGP card v3.4** (`openpgp/openpgp.cpp:150-160`).
- **Supported commands:**
  - SELECT, GET/PUT DATA, VERIFY, CHANGE REFERENCE DATA, RESET RETRY COUNTER;
  - PSO CDS/DECIPHER, INTERNAL AUTHENTICATE, GENERATE, GET CHALLENGE;
  - TERMINATE/ACTIVATE.
- **KDF-DO (F9)** is supported. PW1 must be ≥ 6 characters, PW3 ≥ 8, each with
  3 retries.
- **Deviations:**
  - **One `pw1_verified` flag** covers both PW1 references 0x81 and 0x82, so
    VERIFY 82 also unlocks signing.
  - **No touch/confirm-on-badge.** UIF DOs are hard-coded "disabled", and once
    PW1 is verified, signing needs no physical confirmation.
  - The PW1 cleartext stays in RAM until deselect.
  - Extended Capabilities advertise features that PUT DATA does not handle.

## Cross-signing flow: what is and isn't checked

1. **Receive.** A peer key record arrives over BLE (`application/pgp-keys`).
   - The only check is that the transmitted v4 fingerprint recomputes from
     (pubkey, created_at) (`GpgKeyPayload.cpp:164-172`). That is
     self-consistency, which any sender can produce.
   - **The peer's UID self-signature and DEC binding signature are not
     verified.** They are stored as-is and left for GnuPG to check on import.
2. **Review.** The detail view shows the UID, curve and hex v4 fingerprint.
   - No word fingerprint is shown for received keys.
   - There is no comparison step, and nothing requires the user to read or
     confirm the fingerprint.
3. **Sign.** "Cross-Sign" is a single yes/no confirm (`GpgModule.cpp:1092-1096`).
   - No PIN is asked.
   - The serial command `GPG RECV_CROSS_SIGN` signs with **no on-device
     confirmation**; it needs only serial AUTH (which is off by default in beta
     builds).
4. **What gets signed:**
   - certification type **0x10** only, SHA-256;
   - hashed subpackets: creation time only;
   - exactly one UID (≤ 63 bytes);
   - no levels 0x11–0x13, no expiry, no trust signatures, no
     issuer-fingerprint subpacket.
5. **Naming.** After signing, the entry is flagged `kGpgRecvFlagVerified`,
   which means "we signed it", not "we verified it".

## Stores and payload handling

- **The received-key store is keyed on 32 bits.**
  - The NVS key name is the first 4 bytes of the peer's v4 fingerprint
    (`GpgRecvStore.cpp:29-32`), and `addKey` overwrites on collision.
  - Grinding a 32-bit prefix (by varying `created_at`) is cheap. It lets an
    attacker replace a stored key and wipe the cross-signature on it. A plain
    re-send also wipes it.
- **The self-certification store** (third-party certs on your own key) has three
  weaknesses:
  - It is keyed on the first 4 bytes of a **self-asserted** `issuer_fp`
    (`GpgSelfCertStore.cpp:29-33`).
  - Certifications are **not verified**. They are re-emitted verbatim (as
    framed Tag-2 packets) in your own key export.
  - It holds at most 16 entries, so anyone can overwrite genuine
    certifications, fill the store, or inject bad-signature noise. Entries are
    capped at 160 bytes, so RSA certifications don't fit.
- **Index race.** Signatures attach to received keys by their position in a
  re-sorted list, so a key arriving mid-flow can misattach a signature.
- **Untrusted input is lightly validated.**
  - UIDs may contain control characters and newlines.
  - Trailing bytes are accepted.
  - P-256 points aren't validated on receive.
- **Your own UID** built by the wizard is truncated to 39 characters by the
  cardholder-name field. That truncated string is what gets self-signed and
  exchanged.
- **Primary-key assumption.** The card's SIG key is always exported as the
  primary key. *(Inference)* For users whose real primary key is offline and
  whose card holds only a signing subkey, certifications land on the wrong key.
- **The "v5" fingerprint** is SHA-256 over a v4 body with a 0x9A prefix, not a
  real v5/v6 fingerprint.

## The alchemical word fingerprint

- It is SHA-256 over the **raw SIG public key only**, not the OpenPGP packet
  and not the creation time (`KeyFingerprint.cpp:49-71`).
- The first 25 bits pick **5 words from a 32-word list** ("Fire" … "Stone").
- It is shared with FIDO2.
- At 25 bits it catches typos but **can be brute-forced** (minutes at most,
  by estimate), so it offers no protection against an active man-in-the-middle.
- It can't be compared with the hex v4 fingerprint, and it is never shown for
  received keys.

## Implications for a keysigning-party plugin

- **What the OS gives you:** a working exchange → certify → return →
  export pipeline that imports cleanly into GnuPG.
- **What it lacks** is the trust ceremony:
  - an authenticated channel ([BLE review](ble-message-transfer.md));
  - a fingerprint comparison with enough entropy;
  - a confirm-before-sign step with recorded verification;
  - certification levels and expiry;
  - verification of self-signatures and incoming certifications;
  - collision-proof stores.
- **A plugin can't fix this inside mod_gpg.**
  - There is no host API into mod_gpg, and the SIG key is in an OS-owned slot.
  - A plugin could run the ceremony and the event-level features itself (party
    list and checksum, high-entropy SAS words, who-signed-whom), but can only
    sign with its **own** key (the single plugin ECC slot), not your card key.
  - Unless the OS gains hooks, the real certification still happens in the GPG
    menu.
- **Upstream candidates:**
  - key the stores on the full fingerprint;
  - verify signatures on receipt;
  - add a confirm/compare step and touch-to-sign;
  - bind the PIN into the DEC/RSA wrapping key;
  - fix the PW1 flag.

Related: [secure element and slot map](../../hardware/secure-element.md),
[open questions](../../reference/open-questions-and-discrepancies.md).
