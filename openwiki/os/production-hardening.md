---
type: operations
title: Production hardening and provisioning
description: The opt-in, irreversible lockdown flow for a CDC Badge running cdc-badge-os — why stock badges are open (public TROPIC01 pairing key, no secure boot or flash encryption, open download mode), the disarmed provision.py tool with its guards and per-chip manifests, TROPIC01 pairing-key rotation, the cdc_badge_release build, the ESP32-S3 eFuse state machine, and what it changes for plugins.
tags: [security, hardening, provisioning, secure-boot, flash-encryption, efuse, tropic01, pairing-key]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-2a97049eb475edb4a2987a71
    resource: repo://references/cdc-badge-os/partitions.release.csv
  - id: openwiki-source-b1ff795d15ce0723bf319255
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/production-hardening.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Production hardening and provisioning

Source: `website/src/content/docs/dev/production-hardening.md`,
`tools/provision.py` (with tests in `tools/tests/test_provision.py`),
`tools/pio_release_guard.py`, `sdkconfig.release`, `partitions.release.csv`.

## Why it exists

A stock badge has three openings:

1. **The TROPIC01 pairing key is public.** The firmware uses libtropic's
   production SH0 key (`lt_sh0priv_prod0`), so anyone holding it can open a
   secure session. That exposes R-Memory, where the vault, 2FA secrets and
   wrapped GPG/PIV software keys live (see
   [credential modules](modules/credential-modules.md)).
2. **The ESP32-S3 has no flash encryption, no secure boot, and an open ROM
   download mode.** Flash can be dumped and modified.
3. **No OTA.** There is a single factory app partition, so every update is a
   serial reflash. The lockdown has to keep a signed serial update path.

## The tool's guards

- `provision.py` **ships disarmed**. You must edit the source to set
  `ARMED = True` *and* export `CDC_PROVISION_EXPERIMENTAL=1`. The docs say it has
  **never been validated on real hardware**.
- Every destructive step needs `--i-understand-this-is-irreversible` plus a
  typed, operation-specific phrase.
- Every eFuse change reads back the live state first.
- It requires esptool/espefuse/espsecure **v5.x**. The ESP-IDF-bundled v4 is
  refused.
- Per-chip secrets and manifests live in `tools/secrets/esp-<mac>/` and
  `tools/secrets/tr01-<chipid>/` (git-ignored, mode 0700). The manifests bind
  chip identity to key-file hashes, so keys are never mixed up or overwritten.

## Mandatory order

```
rotate-key (soft) → rotate-key --verify → rotate-key --invalidate-old-slot
  → lock-esp (state machine, one step per --continue) → [disable-download]
```

The key rotation comes first, because the custom pairing key is compiled into
the firmware and stays readable in a plaintext flash dump until flash encryption
is on.

### 1. Rotate the TROPIC01 pairing ("sync") key

1. Build a **provisioning firmware**: `-DFEATURE_PROVISIONING=1` enables the
   serial commands `TR01 PAIR_WRITE` and `TR01 PAIR_INVALIDATE`, which normal
   builds lack.
2. **Soft phase.** Generate an X25519 keypair, write it to pairing slot 1, and
   emit `cdc_hal/pairing_key_custom.h`. Rebuild with
   `-DCDC_PAIRING_KEY=CDC_PAIRING_KEY_CUSTOM`. Slot 0 still works as a fallback.
3. **Verify.** `VERSION` must report `pairing_slot=1`, a secure session must
   open, and the chip ID must match the manifest.
4. **Invalidate** the old slot. This is irreversible, and refused unless verify
   succeeded.

### 2. Release build

`CDC_PROVISION_EXPERIMENTAL=1 pio run -e cdc_badge_release` layers
`sdkconfig.release` on top:

- secure boot v2 (RSA-3072, signed externally);
- release-mode flash encryption;
- `CONFIG_SECURE_SERIAL=y`, `DEBUG_MODE=0`;
- **NVS encryption**, using an extra encrypted `nvs_keys` partition. Without it
  NVS stays plaintext under flash encryption, and that's where GPG stores,
  FIDO2 metadata and **plugin NVS** live.

`pio_release_guard.py` refuses the build without the opt-in, and **always**
refuses `-t upload`. The bootloader self-burns eFuses on an unlocked chip, so
the only flash path is through provision.py.

### 3. Lock the ESP32-S3 (`lock-esp`, a strict state machine)

| Step | Action |
|---|---|
| 1 | `gen_fe_key`: host-generate the flash-encryption key |
| 2 | `gen_sb_key`: RSA-3072 secure-boot key + digest |
| 3 | `burn_fe_key`: into a free key block (chosen from the live eFuse summary) |
| 4 | `burn_sb_digest`: burn the secure-boot digest |
| 5 | `flash_release`: verify signatures and sizes, sign, encrypt, write all segments in one call |
| 6 | `enable_lockdown`: `SPI_BOOT_CRYPT_CNT=7`, `SECURE_BOOT_EN=1`, then verify over serial: `flash_enc=1 secure_boot=1 debug=0 secure_serial=1` |
| 7 | `harden`: disable manual-encrypt download, download cache, JTAG and USB-JTAG, and direct boot |

USB-OTG download fuses are deliberately never burned, because that would kill
TinyUSB.

The badge stays recoverable at each step boundary up to step 5.
**`fe_key.bin` and `sb_key.pem` are the only way to update a locked badge**, so
lose them and the badge is frozen.

### 4–5. Reflash and disable download

- `reflash` signs, pre-encrypts and serial-flashes new images onto a locked
  badge.
- `disable-download` is the final, irreversible lock (security or permanent
  mode).

## What changes for badge-cdc

- On a hardened badge, plugin **NVS is encrypted at rest** and R-Memory is
  readable only with the per-device pairing key. That's the configuration under
  which on-device secrets are meaningfully protected.
- `FEATURE_SECURE_SERIAL=1` puts serial plugin upload behind `AUTH <pin>`, which
  closes the unauthenticated install path (see
  [serial console](serial-console-and-auth.md)). USB mass storage remains a
  separate path (see [storage tools](storage-tools.md)).
- **Plugin installation is unaffected.** Plugins are data on the FAT partition,
  not signed firmware, so the hardened badge still has **no plugin signing**.
- Every lockdown step that rebuilds the firmware changes the build profile.
  Under the no-migration policy, expect a wipe (see
  [build and flashing](build-flash-and-partitions.md)).
