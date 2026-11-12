---
type: os modules
title: "Storage tools: MSC, vFAT and NVS editor"
description: The cdc-badge-os storage modules — mod_vfat file explorer and VFAT serial shell over the 2 MB FAT partition, mod_msc USB mass storage (unlocked-only, exposes /vfat/system unless FEATURE_PLUGIN_SYSTEM_LOCK, blocks badge-side writes while mounted), and the read-only-by-default NVS browser — and what they mean for plugin storage, backups and the unsigned plugin install path.
tags: [storage, vfat, msc, usb, nvs, plugins, security]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-9b1eaa02194157f882b92ba1
    resource: repo://references/cdc-badge-os/components/cdc_core/include/cdc_core/feature_flags.h
  - id: openwiki-source-961bfad743ca64463e3cf273
    resource: repo://references/cdc-badge-os/main/module_defaults.h
  - id: openwiki-source-39324d20498b9e1debc3800f
    resource: repo://references/cdc-badge-os/website/src/content/docs/power/storage-tools.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Storage tools: MSC, vFAT and NVS editor

Source: `website/src/content/docs/power/storage-tools.md`,
`components/mod_vfat/`, `components/mod_msc/`, `components/mod_nvsedit/`,
`components/cdc_core/include/cdc_core/feature_flags.h`.

Everything here operates on the 2 MB FAT partition (`vfat` at `0xDF0000`,
mounted as `/vfat`) or on NVS. Those are the two places where plugin data
lives (see [build and flashing](build-flash-and-partitions.md) and
[manifest](../plugin-runtime/manifest-and-capabilities.md)).

```
/vfat/                 user files (demo.jpg, demo.md, backup.cdcbak, …)
/vfat/system/<id>.wasm|.meta|.lang   installed plugins
/vfat/system/i18n/lang_<code>.json   language overlays
/vfat/data/<id>/       per-plugin sandboxed files (host_fs_*)
```

## mod_vfat: file explorer (enabled by default)

- **Files** (main menu) browses the root and hides `system/`. **System Files**
  (Tools → Expert) shows everything.
- **Viewers:**
  - text;
  - rendered Markdown, up to 64 KB, with interactive `- [ ]` checkboxes written
    back to the file and links opened in the browser;
  - PNG/JPEG, up to 512 KB and about 1 MP, dithered to 1-bit.

  These are the same viewers plugins get through `host_fs_view*` /
  `host_ui_view_*`.
- **Serial `VFAT` shell** (AUTH-gated): `LIST`, `PWD`, `CD`, `GET`, `PUT`,
  `RECEIVE <file> <size> <crc32>`, `DELETE`, `MKDIR`, `RMDIR`, `FREE`.
  `RECEIVE` is the binary path behind `upload.py --put`.

## mod_msc: USB mass storage (disabled by default)

- Presents the FAT volume to the host as a removable drive.
  - **No medium while the badge is locked.** It appears after PIN unlock and is
    withdrawn when the badge locks.
  - While a host has it mounted, the badge doesn't write to the volume:
    `VFAT PUT/RECEIVE/...` and **plugin uploads report busy**.
- **It exposes `system/`.** The host can read, overwrite or add
  `system/*.wasm` and `.meta` files unless the firmware is built with
  `FEATURE_PLUGIN_SYSTEM_LOCK=1`. That flag defaults to **0**
  (`feature_flags.h:48-54`).
  - With MSC enabled, an unlocked badge plugged into a computer is therefore a
    **plugin install and replace path with no serial AUTH and no signature**.
  - It also exposes every plugin's `/vfat/data/<id>/` files.
- Shares the USB endpoint budget. Enabling it can fail with too many USB
  services active (see [USB stack](usb-stack-and-smartcard.md)).

## mod_nvsedit: NVS browser (enabled by default, read-only)

- Tools → NVS Browser lists namespaces, keys, types and previews of values.
- Deleting is possible only in builds with `FEATURE_NVS_EDIT=1`, which defaults
  to 0 (`feature_flags.h:27-28`).
- The module has no serial command. The core serial `NVS` group (AUTH-gated)
  provides `LIST/READ/DEL/CLEAR` separately (see
  [serial console](serial-console-and-auth.md)).
- **Plugin NVS namespaces (`plg_*` / `plugin_*`) are fully visible here** to
  anyone holding the unlocked badge.

## Implications for badge-cdc

| Concern | Consequence |
|---|---|
| Confidentiality of plugin data | NVS (browser, serial `NVS READ`) and vFAT data (MSC, `VFAT GET`) are readable on an unlocked badge, and NVS is plaintext unless the badge is [hardened](production-hardening.md). Encrypt anything sensitive inside the plugin. |
| Integrity of the plugin itself | Anyone with an unlocked badge and MSC enabled can replace `system/<id>.wasm`. The OS doesn't check plugin signatures, so a plugin can't vouch for itself. |
| Export path | MSC (or `VFAT GET`) is a convenient way for users to copy an encrypted export out of `/vfat/data/<id>/`. Plugin data isn't in the OS backup ([backup](backup-and-restore.md)). |
| Availability | Uploads and badge-side writes fail with busy while a host has the drive mounted |
