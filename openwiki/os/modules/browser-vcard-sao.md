---
type: os modules
title: Browser, vCard and SAO modules
description: Three cdc-badge-os feature modules a plugin can lean on — mod_browser (readable-text web browser reachable via host_browser_open, which needs the http capability), mod_vcard (vCard 4.0 store and badge-to-badge exchange as text/vcard, reachable via host_vcard_*), and mod_sao (SAO add-on detection via an "SAO1" EEPROM descriptor at I2C1 0x50).
tags: [os, modules, browser, vcard, sao, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-f286a527714018f2f5706a6c
    resource: repo://references/cdc-badge-os/components/mod_sao/src/sao.cpp
  - id: openwiki-source-1ee00fee79c20eb9c940bfbf
    resource: repo://references/cdc-badge-os/components/mod_vcard/src/VcardModule.cpp
  - id: openwiki-source-6619762b6b23e314f0b6c118
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_ui.cpp
  - id: openwiki-source-4ef6060c62c23f632ba3c0b1
    resource: repo://references/cdc-badge-os/website/src/content/docs/guide/vcard.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Browser, vCard and SAO modules

These are three built-in modules with a plugin-facing surface. The other modules
are covered under [credential modules](credential-modules.md), [storage tools](../storage-tools.md),
the [GPG review](../security/gpg-openpgp-module.md) and the
[FIDO2 review](../security/fido2-ctap2.md).

## mod_browser: text web browser

**User view** (`website/src/content/docs/guide/browser.md`; Tools → Browser):

- It fetches a page over Wi-Fi and shows the extracted main content as
  scrollable text, with links, checkboxes and submit controls selectable.
- It keeps bookmarks, and offers a links list, a view-source mode, and a
  readable/full toggle.
- The code lives in `components/mod_browser/src/`: `PageFetcher`,
  `HtmlTokenizer`, `ContentExtractor`, `FeedParser`, `Bookmarks`.

**From a plugin:** `host_browser_open(url)` hands a URL to the browser
(`host_api_ui.cpp:89-97`).

- It **requires the `http` capability**, otherwise `HOST_ERR_NO_CAPABILITY`.
- It returns `HOST_ERR_NOT_SUPPORTED` if the browser module isn't built in.
- The URL is passed as raw UTF-8.
- Note that `mod_browser` has no entry in `module_defaults.h`, so every boot logs
  a misconfiguration error (see [module development](../module-development.md)).

## mod_vcard: contact cards

**User view** (`guide/vcard.md`; Tools → vCards):

- Your own **vCard 4.0** card, edited field by field: name, org, email, phones,
  website, Telegram, Signal, Matrix, Threema, social profile, note. The whole
  card is limited to 768 bytes.
- Sent badge-to-badge, and shown as a QR code from the lock screen.
- Included in the [encrypted backup](../backup-and-restore.md).

**Transport.** It registers the MIME handler **`text/vcard`** on the BLE message
framework (`VcardModule.cpp:740-742`), with the same trust caveats as GPG
exchange; see the [BLE review](../security/ble-message-transfer.md).

**From a plugin** (`vcard` capability):

- `host_vcard_get_own` / `host_vcard_set_own`;
- `host_vcard_received_count` / `get` / `display` / `add` / `update` / `delete`
  (indices are positions in a sorted list that re-sorts after writes).

The `thermo_printer` plugin uses this to print received cards. For a
cypherpunk badge, note that **any plugin with `vcard` can read every contact
you've collected**.

## mod_sao: Shitty Add-On detection

- The SAO port puts I²C bus 1 plus GPIO15/16 on a 2×3 header (see
  [pin map](../../hardware/pin-map-and-buses.md)).
- `mod_sao` reads an optional EEPROM at **0x50** on I²C1.
  - The descriptor must start with the magic bytes **`SAO1`**
    (`53 41 4F 31`; `sao.cpp:39-49`).
  - It is followed by length-prefixed name and driver-name fields.
- Add-ons without that EEPROM are simply not identified. Their pins still work.
- **From a plugin:** with the `sao` capability, plugins get GPIO15/16 and
  `host_sao_eeprom_read/write` (I²C1 0x50). See
  [hardware I/O for plugins](../../plugin-runtime/hardware-io-for-plugins.md).
