---
type: os subsystem
title: Encrypted backup and restore
description: The cdc-badge-os .cdcbak backup — PBKDF2-SHA256 (200k) + AES-256-GCM container with an authenticated header, the JSON payload of semantic records from mod_2fa, mod_password, mod_vcard and system settings, restore semantics, the backup.py companion tool, and what is never backed up (FIDO2/GPG keys and all plugin data).
tags: [backup, restore, encryption, aes-gcm, pbkdf2, data-durability, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-b473b99308069a3170043504
    resource: repo://references/cdc-badge-os/components/cdc_os_ui/src/BackupManager.cpp
  - id: openwiki-source-1a6e1eda5e08d8ed9bd88a40
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/proto/backup-format.md
  - id: openwiki-source-5a741092f0ff54e723d67165
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/backup-restore.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Encrypted backup and restore

Pre-1.0 firmware flashes can wipe the badge (see
[build and flashing](build-flash-and-partitions.md)), so the encrypted
backup is the user's main safety net. Plugin authors need to know what it does
**not** cover.

- Canonical implementation: `references/cdc-badge-os/components/cdc_os_ui/src/BackupManager.cpp`.
- Byte-compatible host tool: `tools/backup.py`.
- Specifications: `website/src/content/docs/dev/proto/backup-format.md` and
  `guide/backup-restore.md`.

## Container (`.cdcbak`)

The file is stored **base64-encoded** as `backup.cdcbak` on the FAT (`vfat`)
partition. Only one exists at a time, and each export overwrites it. The decoded
binary layout (little-endian):

| Field | Bytes | Value |
|---|---|---|
| magic | 6 | `"CDCBAK"` |
| version | 1 | `0x01` (others rejected) |
| kdf_iters | 4 | PBKDF2 iterations (`KDF_ITERATIONS = 200000`) |
| salt | 16 | random per export |
| nonce | 12 | random per export |
| ciphertext | N | AES-256-GCM of the JSON payload |
| tag | 16 | GCM tag |

- Key = `PBKDF2-HMAC-SHA256(passphrase, salt, kdf_iters)`, 32 bytes.
- The passphrase can be up to 64 characters and can't be empty.
- The whole 39-byte header is GCM **associated data**, so tampering with the
  iteration count, salt or nonce fails authentication.
- A wrong passphrase and a corrupted file produce the same error.

## Payload

The payload is one JSON document:
`{ host_api_level, fw_version, modules: {...}, system: {...} }`.

- **Modules write semantic records, never raw slots or NVS blobs**, so a backup
  survives storage-layout changes.
- Only modules that implement `IModule::exportBackup` contribute:

| Section | Contents |
|---|---|
| `mod_2fa` | OATH accounts including secrets (Base32), type, algorithm, digits, period, counter |
| `mod_password` | vault entries in cleartext (title, username, password, URL, notes, linked TOTP), protected only by the container encryption |
| `mod_vcard` | own vCard + received vCards |
| `system` | language, backlight, sleep interval, timezone, badge name and info lines, and **Wi-Fi config including the password** |

## Restore semantics

- The file is rejected if its `host_api_level` is **newer** than the
  firmware's (`BackupManager.cpp:378-386`).
- Each section carries a `schema_ver`. On a mismatch that section is
  **skipped**; there is no migration.
- Import is a best-effort upsert. Sections for modules absent on the target are
  skipped, and a summary of imported, failed and skipped items is shown.

## What is NOT backed up

| Not backed up | Why |
|---|---|
| FIDO2 / WebAuthn credentials | Private keys are non-exportable TROPIC01 keys. The badge says "No keys are backed up (FIDO2/GPG); only data." |
| GPG / SSH (OpenPGP card) keys, received keys, certifications | Same reason, and mod_gpg has no backup hook |
| **All plugin data**: plugin NVS namespaces, `/vfat/data/<id>/` files, plugin R-Memory and ECC slots | Plugins have no backup hook. There is no host API for it. |
| Installed plugins themselves | They live in `/vfat/system/` and are reinstalled via the installer |

**Consequence for badge-cdc:** our plugin must offer its own export path for
anything the user can't afford to lose. Examples: an encrypted blob shown as a
QR code, written to a file the user can copy off over USB mass storage (see
[storage tools](storage-tools.md)), or sent over serial via `plugin_on_cmd`.
Otherwise a firmware update can silently destroy it.

## Tooling

`tools/backup.py` drives the badge over serial (`BACKUP EXPORT <pass>` /
`BACKUP IMPORT <pass>`). It downloads and uploads the container, and can
decrypt or encrypt it **off-device** with the same format. That makes it
possible to inspect or edit a backup on a computer.

Related: [credential modules](modules/credential-modules.md),
[manifest and storage isolation](../plugin-runtime/manifest-and-capabilities.md).
