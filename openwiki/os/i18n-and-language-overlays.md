---
type: os subsystem
title: I18n and language overlays
description: How cdc-badge-os localises strings — compiled-in English tables, flat lang_<code>.json overlay files in /vfat/system/i18n converted from UTF-8 to CP437, per-plugin translations from the manifest and <id>.lang.json files, the host_i18n_* calls, and the limitation that the plugin language API only distinguishes English and German.
tags: [i18n, localisation, language, cp437, plugins, overlays]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-d0991e12e4e4e071d3ad46b8
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_i18n.cpp
  - id: openwiki-source-db8c17621ce0dafcf11e977d
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/Plugin.cpp
  - id: openwiki-source-f437498cd3f8592558b32c38
    resource: repo://references/cdc-badge-os/website/src/content/docs/power/languages.md
  - id: openwiki-source-425adb9ce7212000d9aa61c5
    resource: repo://references/cdc-badge-plugins/examples/hello_world/hello_world.lang.json
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# I18n and language overlays

## OS strings

The user docs are `website/src/content/docs/power/languages.md`; the code is
`components/cdc_ui/src/I18n.cpp`.

- **Keys, not literals.** Every UI string is looked up by key
  (`core.language`, `mod_gpg.recv_confirm_sign`, …).
- **English is compiled in.** Core and per-module English tables live in
  rodata, so English is always available and is the fallback for any missing
  key.
- **Other languages are overlays.** Each is a flat JSON object
  `{"<key>": "<value>"}` named `lang_<code>.json` under `/vfat/system/i18n/`
  on the FAT partition. Only the active overlay is parsed, into PSRAM.
  - A partial overlay leaves the untranslated strings in English.
  - The loader converts UTF-8 to the display's **CP437** at parse time (see
    [display](../hardware/display-and-graphics.md)).
- **Picker.** Settings → Language lists English plus one entry per overlay file,
  labelled by that file's `core.lang_name` (the endonym). Switching applies
  immediately and reloads plugin overlays too.
- **Installing a language** means dropping in the file. Either:
  - over serial with `tools/upload.py --lang-overlay lang_xx.json`, or
  - baked into the Factory Setup image `plugins_initial.bin` by
    `tools/build_lang_image.py` (see [build and flashing](build-flash-and-partitions.md)).

  The reference key list is `assets/i18n/lang_de.json`.

## Plugin strings

Plugins carry their own translations in two places.

1. **The manifest `i18n` block** (`default_language`, `meta.name/description`,
   `strings`; see [manifest](../plugin-runtime/manifest-and-capabilities.md)).
2. **An optional `<id>.lang.json`** uploaded next to the plugin
   (`PLUGIN UPLOAD_LANG`; `build_all.sh` stages it into `dist/`). Its shape is:

   ```json
   { "version": 1,
     "translations": { "de": { "meta.name": "Hallo Welt", "greeting": "Hallo aus WASM!" } } }
   ```

   `Plugin::loadLangOverlay` picks the object for the active language code
   (`Plugin.cpp:204-260`) and reloads it when the user switches language.

Host calls (`host_api.h` i18n group):

| Call | Resolves |
|---|---|
| `host_i18n_tr_key(key, out, cap)` | plugin-local key in the current language, falling back to the default |
| `host_i18n_tr_meta(field, out, cap)` | manifest metadata (`name`, `description`) |
| `host_i18n_tr_core(key, out, cap)` | firmware `core.*` strings (use these for "Back", "Save", …) |
| `host_i18n_current_language()` | `HOST_LANG_EN` (0) or `HOST_LANG_DE` (1) |

All results are **UTF-8**. The host converts to CP437 when drawing.

### Limitation: only English and German in the plugin API

`host_i18n_current_language()` maps the active code to `HOST_LANG_DE` only for
`"de"`, and to `HOST_LANG_EN` for everything else. Manifest lookups likewise use
`"de"` or `"en"` (`host_api_i18n.cpp:30-45`). The OS overlays support any
language, and the `.lang.json` overlay is keyed by the active code. But a plugin
can't tell, for example, French from English through the language call, and
manifest-embedded strings only cover en/de. Ship translations in `.lang.json`
when targeting more languages.

## Guidance for badge-cdc

- Keep user-visible text in keys from day one, with English in the manifest and
  extra languages in `<id>.lang.json`.
- Use `host_i18n_tr_core` for standard words so they match the OS.
- Remember the five display fonts have different character coverage. Font 0
  (6×8) has the full CP437 set; the large fonts are ASCII only. See
  [canvas](../plugin-runtime/canvas-surfaces-and-animation.md).
