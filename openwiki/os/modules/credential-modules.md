---
type: os modules
title: "Credential modules: TOTP, password vault, PIV, HID auto-type"
description: The cdc-badge-os credential modules — mod_2fa (OATH TOTP/HOTP/challenge-response over screen, CCID, BLE and OTP HID), mod_password (364-entry vault in TROPIC01 R-Memory), mod_piv (P-256 PIV card), and the keyboard transports mod_blehid, mod_usbhid and mod_otphid — with capacities, transports and the at-rest protection model (secrets stored unencrypted in R-Memory, reachable with the pairing key).
tags: [os, modules, totp, oath, password-vault, piv, hid, auto-type, security]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-38930eac3f0070e9c61b34aa
    resource: repo://references/cdc-badge-os/components/mod_2fa/src/OathStore.cpp
  - id: openwiki-source-954633afdf8b8c3c5ad910f7
    resource: repo://references/cdc-badge-os/components/mod_password/src/PasswordStore.cpp
  - id: openwiki-source-a87e7da9b83ace94a4bdfd10
    resource: repo://references/cdc-badge-os/components/mod_piv/src/piv_defs.h
  - id: openwiki-source-961bfad743ca64463e3cf273
    resource: repo://references/cdc-badge-os/main/module_defaults.h
  - id: openwiki-source-b867d153675ba33ae714dd88
    resource: repo://references/cdc-badge-os/main/tropic_slot_map.h
  - id: openwiki-source-2142e2efb78dc6c386c1ad73
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/proto/otp-hid-cr.md
  - id: openwiki-source-2335d41be8297878baaeb7fa
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/auto-type.md
  - id: openwiki-source-63ab55f66a0777044482502b
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/password-vault.md
  - id: openwiki-source-9a6be6ea4cb0c1694e6cbc53
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/two-factor.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Credential modules: TOTP, password vault, PIV, HID auto-type

These modules make the badge a credential device alongside
[GPG](../security/gpg-openpgp-module.md) and [FIDO2](../security/fido2-ctap2.md).
**Plugins have no host API into any of them.** They matter to us as prior art,
as competition for TROPIC01 slots, and as part of the threat model.

## mod_2fa: OATH authenticator

Sources: `website/src/content/docs/guide/two-factor.md`,
`components/mod_2fa/`.

| Aspect | Detail |
|---|---|
| Entry types | TOTP, HOTP, CR (raw HMAC challenge-response, no displayed code) |
| Algorithms | TOTP/HOTP: SHA1, SHA256, **SHA512**. CR: SHA1, SHA256 only. |
| Digits / period | 6–8 digits; TOTP period 15–300 s (wizard offers 30/60 s) |
| Capacity | **100 accounts**: R-Memory slots 31–130 |
| Transports | E-paper display; **CCID OATH applet** (ykman-style, touch-required codes aren't computed silently); **BLE GATT challenge-response** service; **USB OTP HID** slot-2 responder via `mod_otphid` |
| Backup | Included, secrets exported as Base32 ([backup](../backup-and-restore.md)) |

- TOTP needs the RTC set. The clock is lost after deep sleep or a power cycle
  until Wi-Fi time sync or `SET_TIME` (see
  [networking](../../plugin-runtime/networking-wifi-http-sockets.md)).
- CR requests over BLE or USB are answered only after an on-device
  confirmation.
- **HMAC-SHA512 note:** TOTP/HOTP can use SHA512, but the raw
  challenge-response transports offer only SHA1/SHA256. Plugins can't call any of
  it.

## mod_password: password vault

Sources: `guide/password-vault.md`, `components/mod_password/`.

- **Capacity:** R-Memory slots 137–500, so **up to 364 entries**, one per slot.
- **Fields:** title, username, password, URL, notes (≤ 173 characters, the
  remainder of a slot), and an optional linked TOTP slot.
- Includes a random-password generator.
- Entries can be typed into a host via HID auto-type (below).
- Included in the encrypted backup.

## At-rest protection model (2FA and vault)

Both stores write records with `rmemWriteWithHeader`
(`mod_password/src/PasswordStore.cpp:136,186`; `mod_2fa/src/OathStore.cpp:258`).
**No application-level encryption** is applied: the vault guide itself says no
field encryption is described.

So their confidentiality rests entirely on access to TROPIC01 R-Memory, which
anyone holding the **pairing key** can read. On stock badges that key is the
public libtropic production key (see [secure element](../../hardware/secure-element.md)
and [production hardening](../production-hardening.md)).

Combined with the Raspberry Pi header switch that exposes the TROPIC01 chip
select (see [pin map](../../hardware/pin-map-and-buses.md)), an attacker with
brief physical access to an unhardened badge could read TOTP secrets and vault
passwords without the PIN. *(Inference from code and hardware docs; not
demonstrated.)*

## mod_piv: PIV smartcard

- A CCID applet (`components/mod_piv/`), registered as **non-default** next to
  OpenPGP (the default) and OATH.
- Keys **9A** (authentication), **9C** (signature) and **9E** (card
  authentication) live in TROPIC01 ECC slots 5–8.
- **9D** (key management, ECDH) is a **software key** in R-Memory, because the
  TROPIC01 has no ECDH.
- **P-256 only** (`piv_defs.h:40-52`). The management key 9B is AES.
- The website has **no user guide page for PIV**.

## Keyboard transports (auto-type)

Source: `guide/auto-type.md`.

| Module | Default | Notes |
|---|---|---|
| `mod_blehid` | **enabled** | HID-over-GATT keyboard on an encrypted BLE link; uses no USB slot. It is the default active keyboard. |
| `mod_usbhid` | disabled | USB HID keyboard; takes over as the active keyboard while running |
| `mod_otphid` | disabled | Yubico-style slot-2 HMAC-SHA1 challenge-response over USB HID, presenting as OnlyKey `1D50:60FC`. It takes the single USB **Keyboard** interface slot, so it's mutually exclusive with `mod_usbhid` (see [USB stack](../usb-stack-and-smartcard.md)). |

Plugins can't emit HID reports: raw HID is on the "forbidden" list in
[manifest and capabilities](../../plugin-runtime/manifest-and-capabilities.md).

## Slot pressure

Together, 2FA (100), the vault (364), GPG, PIV and FIDO2 consume almost all of
TROPIC01's 512 R-Memory and 32 ECC slots. That leaves plugins **11 R-Memory
slots and 1 ECC slot** badge-wide.
