---
type: developer workflow
title: OS testing and host tools
description: How cdc-badge-os is tested — PlatformIO native host unit tests (test/host, run in CI), the on-device serial test runner with automatic and operator-assisted catalogs, provisioning tests — and the Python companion tools (flash, upload, BLE serial, backup, 2FA, coredump, language image, local web flasher) useful when developing and debugging a plugin.
tags: [testing, unit-tests, hil, tools, python, ci, workflow]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-217b5305ee3b840b20ea028e
    resource: repo://references/cdc-badge-os/.github/workflows/build.yml
  - id: openwiki-source-cc192a03e20f74093de23c8a
    resource: repo://references/cdc-badge-os/test/host/README.md
  - id: openwiki-source-bf700fc1449a2d67fdaa56ba
    resource: repo://references/cdc-badge-os/tools/ondevice/run.py
  - id: openwiki-source-a04947f85779c6120cd89d63
    resource: repo://references/cdc-badge-os/website/src/content/docs/power/companion-tools.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# OS testing and host tools

How upstream tests the OS, and which of its tools we reuse while building a
plugin. Plugin-side testing (host `cargo test` and the emulator) is in
[plugin build and install](plugin-build-and-install.md) and
[emulator](emulator.md).

## Host unit tests (`test/host/`)

- **What they cover:** pure logic run by PlatformIO's `native` environment, with
  no flash and no hardware (`test/host/README.md`).
- **How to run:** `~/.platformio/penv/bin/pio test -e native`. CI runs this in
  `.github/workflows/build.yml`. The firmware env ignores `host/*`.
- **Suites:** `test_base64`, `test_canvas_anim`, `test_cbor`, `test_cp437`,
  `test_crc`, `test_event_bits`, `test_ext_feature_name`,
  `test_fido2_largeblob`, `test_gpg_algo_attr`, `test_gpg_ecdh`, `test_gpg_kdf`,
  `test_html_extract`, `test_image_engine`, `test_markdown`, `test_msc`,
  `test_msg_frame`, `test_oath_applet`, `test_pin_lockout`, `test_piv_applet`,
  `test_qr_raster`, `test_scard_dispatch`, `test_scard_usb`, `test_smoke`,
  `test_usb_budget`, `test_usb_service_manager`.
- **Not covered here:** the secure element, USB, BLE and e-paper behaviour.
  Those are covered by HIL plans under `specs/001-current-system-spec/hil/`,
  which are **not in the `release` branch snapshot** we vendor.
- The unit tests don't cover the review findings in
  [GPG](../os/security/gpg-openpgp-module.md), [BLE](../os/security/ble-message-transfer.md)
  and [FIDO2](../os/security/fido2-ctap2.md): no test exercises plugin message
  registration or ES256 DER encoding.

## On-device runner (`tools/ondevice/`)

- `run.py` drives a flashed badge **over serial only**:
  - an automatic catalog (`catalog_auto.py`) of about 14 entries runs unattended;
  - `--semi` appends an operator-assisted catalog (`catalog_semi.py`, about 11
    entries).
- **Options:** `--list`, `--only A-PWD,A-2FA`, `--mutating`, `--slow`.
- It's a developer and QA tool, never a CI gate. It never flashes test firmware.
- The PIN comes from `--pin`, or `$BADGE_PIN`, or defaults to `123456`.
- **Useful for us** as a smoke test before and after plugin work, to confirm the
  badge itself is healthy.

`tools/tests/test_provision.py` covers the guarded
[production hardening](../os/production-hardening.md) tool.

## Companion tools (`tools/`)

Upstream docs: `website/src/content/docs/power/companion-tools.md`. All use
pyserial, which our Nix shell provides.

| Tool | Use while developing a plugin |
|---|---|
| `upload.py` | Install, list, start, stop and delete plugins; write language overlays; push arbitrary files into the FAT partition (`--put`) ([build and install](plugin-build-and-install.md)) |
| `flash_firmware.py` | Flash a released OS (`--release latest`) or local binaries; `--erase-nvs` wipes settings ([build and flashing](../os/build-flash-and-partitions.md)) |
| `start_webflasher.py` | Serve the web flasher locally against the latest local build |
| `ble_serial.py` | Wireless serial console over the BLE Nordic UART Service ([serial console](../os/serial-console-and-auth.md)) |
| `coredump.py` | Fetch and analyse firmware core dumps ([debugging](debugging-and-troubleshooting.md)) |
| `backup.py` | Export, import, download, upload, and offline decrypt/encrypt `.cdcbak` backups ([backup](../os/backup-and-restore.md)) |
| `2fa.py` | Provision OATH accounts over serial ([credential modules](../os/modules/credential-modules.md)) |
| `build_lang_image.py` | Build `plugins_initial.bin`, the FAT image with language overlays and demo files, for Factory Setup |
| `gpg_selftest.py`, `gpg_card_test.py` | Exercise the OpenPGP card from the host |
| `fido2_largeblob.py` | Exercise FIDO2 large blobs |
| `provision.py` | Production lockdown (disarmed by default) |
| `pio_*.py` | PlatformIO build hooks: submodules, component manager, Python deps, release guard |
