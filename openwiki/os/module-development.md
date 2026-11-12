---
type: developer guide
title: Writing an OS module
description: How native cdc-badge-os feature modules are built — ModuleBase/IModule lifecycle, the single MODULES registration point and generated registration header, the boot order (init all, then start the enabled set from module_defaults.h and NVS), and the checklist — plus when a native module is the right choice instead of a WASM plugin.
tags: [os, modules, native, esp-idf, registration, lifecycle]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-8652c71d96f25b3c174d952f
    resource: repo://references/cdc-badge-os/components/cdc_core/src/ModuleRegistry.cpp
  - id: openwiki-source-91a63a3beacec1226cac4b20
    resource: repo://references/cdc-badge-os/main/CMakeLists.txt
  - id: openwiki-source-961bfad743ca64463e3cf273
    resource: repo://references/cdc-badge-os/main/module_defaults.h
  - id: openwiki-source-434c30a919ab4efc9aaf3961
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/module-development.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Writing an OS module

A **module** is native C++ compiled into the firmware with full HAL access. A
**plugin** is sandboxed WASM loaded at runtime. badge-cdc targets a plugin.
This page matters only if we need something the [host API](../plugin-runtime/host-api-reference.md)
can't provide, such as access to mod_gpg keys, an HMAC engine or new host
functions. That would mean maintaining an OS fork.

Upstream guide: `website/src/content/docs/dev/module-development.md`. The
architecture rules are in [OS architecture](architecture.md) (ADR-0002: the
core never references modules).

## Anatomy

- **Location:** a component `components/mod_<name>/` with its own
  `CMakeLists.txt`.
- **Class:** derives from `ModuleBase`, which provides the state handling.
  - `start()` is only valid from `INITIALIZED` or `STOPPED`.
  - `stop()` moves the module to `STOPPED`.
  - The module implements `init()` and its feature logic.
- **Optional `IModule` hooks:**
  - `onUnlock` / `onLock`, `onUsbConnect` / `onUsbDisconnect`, `onTick(nowMs)`;
  - menu items per `MenuLocation` and an entry view;
  - lock-screen items;
  - `exportBackup` / `importBackup` (see [backup](backup-and-restore.md));
  - `getSlotRequest` / `setSlotRange` for TROPIC01 slots.
- **Self-contained:** views, the English i18n table (`registerStrings()`), its
  NVS namespace (prefix `mod_`) and helpers all stay inside the component.

## Registration and boot

1. Export `extern "C" void mod_<name>_register()`, which registers a deferred
   initializer.
2. Add `mod_<name>` to `MODULES` in `main/CMakeLists.txt`. CMake adds it to
   `REQUIRES` and generates `modules_init.gen.h`, which calls every
   `*_register()`.
3. Add `X("mod_<name>", true|false)` to `MODULE_DEFAULT_MAP` in
   `main/module_defaults.h`.
4. At boot, `modules_register_all()` runs, then
   `ModuleRegistry::runAllInitializers()`, which:
   1. calls every module's `init()` (the module registers itself and reports
      `INITIALIZED`);
   2. checks every registered module has a defaults entry, logging an
      **error** if one is missing;
   3. loads the NVS disabled-module list;
   4. stops disabled modules that started themselves;
   5. starts exactly the enabled set.
5. Finally `ui_on_modules_ready()` rebuilds the menus.

**Snapshot quirk:** `mod_browser` is in `MODULES` but not in
`MODULE_DEFAULT_MAP` (see [architecture](architecture.md)). Per step 4.2, every
boot logs that misconfiguration.

## Removing a module

Delete the folder and its `MODULES` line. Because the core never references
modules, nothing else changes. `ModuleRegistry::cleanupOrphanedModuleData`
removes leftover `mod_*` NVS namespaces.

## Module or plugin?

| Need | Plugin | Module |
|---|---|---|
| Ship without reflashing; installable by users | ✔ | ✘ (firmware build + flash, wipes data on profile change) |
| Sandboxed from secrets and hardware | ✔ | ✘ |
| Use OS-owned keys (GPG SIG slot, FIDO2), add host functions, crypto engines | ✘ | ✔ |
| Survive in upstream releases | only via the stable host API | only if merged upstream |
