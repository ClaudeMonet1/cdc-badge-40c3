---
type: sdk guide
title: Rust plugin SDK (cdc-badge-plugin crate)
description: The cdc-badge-plugin crate (v0.8.0, GPL-3.0) that wraps the cdc-badge-os host API for Rust — no_std + alloc with a dlmalloc global allocator, the ffi layer and build.rs constant generation from host_api.h, the unified Error/Result type, the plugin_main! macro and optional panic handler, module map, crate setup for wasm32-unknown-unknown, and practical idioms and pitfalls for writing our own plugin.
tags: [rust, sdk, wasm32, no_std, ffi, cargo, plugin]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-0b8948a6ead6a21b8a80f7ed
    resource: repo://references/cdc-badge-plugins/Cargo.toml
  - id: openwiki-source-675a46d192428907f5aad266
    resource: repo://references/cdc-badge-plugins/docs/rust_sdk_guide.md
  - id: openwiki-source-a07d4a55045963e6ba3e8c43
    resource: repo://references/cdc-badge-plugins/plugins/matrix/Cargo.toml
  - id: openwiki-source-ea1051a427f447e472180027
    resource: repo://references/cdc-badge-plugins/sdk/cdc-badge-plugin/build.rs
  - id: openwiki-source-13549246cd5d10c200b09d58
    resource: repo://references/cdc-badge-plugins/sdk/cdc-badge-plugin/Cargo.toml
  - id: openwiki-source-d1fe696fa2b4d4994affdb13
    resource: repo://references/cdc-badge-plugins/sdk/cdc-badge-plugin/src/lib.rs
  - id: openwiki-source-8959f4c4fa5454411f7963ca
    resource: repo://references/cdc-badge-plugins/sdk/plugin_template_rust/Cargo.toml
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Rust plugin SDK (`cdc-badge-plugin` crate)

Location: `references/cdc-badge-plugins/sdk/cdc-badge-plugin/` (upstream
`krim404/cdc-badge-plugins`). Version **0.8.0**, matching host API level 0.8.
License **GPL-3.0**: linking it into our plugin makes the plugin a combined
work under GPL terms. That is a licensing decision to make early (see
[open questions](../reference/open-questions-and-discrepancies.md)).

## Crate anatomy

| Piece | Role |
|---|---|
| `src/lib.rs` | `#![no_std]` + `extern crate alloc`, `HOST_API_LEVEL_MAJOR/MINOR` (0/8), the `Error`/`Result` types, `check()`, the `plugin_main!` macro, the optional panic handler, and the global allocator |
| `src/ffi.rs` | Raw `extern "C"` declarations in `#[link(wasm_import_module = "cdc")]`, using the **wasm32 import forms** (e.g. `host_fs_read(name, buf, buf_size) -> c_int`), plus constants |
| `build.rs` | Parses `../host_api.h` and generates Rust constants for the prefixes `UI_ICON_`, `HOST_OK`, `HOST_ERR_`, `LOG_LEVEL_`, `HOST_EXT_FEATURE_`, `HOST_MSG_`, `HOST_VCARD_`, `HOST_SURFACE_`, `HOST_SPRITE_`, `HOST_ANIM_`, `HOST_EASE_` and `HOST_CANVAS_ANIM_`, so constants never drift from the C header. It reruns when the header changes. |
| Safe modules | `anim`, `ble`, `canvas`, `cmd`, `crypto`, `display`, `event`, `feature`, `fs`, `gpio`, `http`, `i18n`, `i2c`, `image`, `keypad`, `lifecycle`, `lockscreen`, `log`, `msg`, `net`, `nvs`, `pixel_strip`, `power`, `qr`, `random`, `rmem`, `sao`, `secure_element`, `socket`, `sprite`, `surface`, `sysinfo`, `time`, `ui`, `usb`, `vcard`, `wifi`, roughly one per host-API family ([host API reference](../plugin-runtime/host-api-reference.md)) |
| `../host_api.h`, `../plugin_lifecycle.h` | The mirrored C contract |
| `../plugin_template_rust/`, `../plugin_template_c/` | Starting skeletons |

### Features

| Feature | Default | Effect |
|---|---|---|
| `allocator` | **on** | On wasm32, `dlmalloc::GlobalDlmalloc` becomes the `#[global_allocator]`. It grows linear memory with `memory.grow`, which is why the host must instantiate with heap 0 (see [WAMR runtime](../plugin-runtime/wamr-runtime.md)). |
| `panic_handler` | off | `#[panic_handler]` that formats the `PanicInfo` into a fixed 256-byte stack buffer (it never allocates, so an OOM panic can't recurse), logs it under tag `PANIC` via `host_log`, then executes `unreachable` (a trap, so the host unloads the plugin) |

## Workspace and toolchain

`references/cdc-badge-plugins/Cargo.toml` is a workspace (resolver 2) of the SDK
and all examples and plugins:

```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

- `rust-toolchain.toml`: `channel = "stable"`, `targets = ["wasm32-unknown-unknown"]`,
  `profile = "minimal"`, components rustfmt and clippy.
- `.cargo/config.toml`: for `wasm32-unknown-unknown`,
  `rustflags = ["--cfg", 'getrandom_backend="custom"']`. getrandom has no
  entropy source on this target, so a plugin that pulls it in transitively must
  register a custom backend. `plugins/matrix/src/getrandom_shim.rs` routes it to
  `host_random`.
- Our Nix shell provides the same toolchain shape (stable + wasm32 targets).

## Minimal plugin

`plugin_template_rust/Cargo.toml`:

```toml
[lib]
crate-type = ["cdylib"]

[dependencies]
cdc-badge-plugin = { git = "https://github.com/krim404/cdc-badge-plugins", features = ["panic_handler"] }
```

For reproducible builds in this repository, depend on the vendored copy by
`path = "references/cdc-badge-plugins/sdk/cdc-badge-plugin"` (relative to the
crate), or pin the git dependency with `rev = "9a8229422ef0…"` from
`references/SOURCES.md`.

```rust
#![no_std]
extern crate alloc;
use cdc_badge_plugin::{plugin_main, ui, log};

plugin_main!();   // plugin_required_api_major/minor exports

#[no_mangle] pub extern "C" fn plugin_init()   -> i32 { log::info("demo", "init"); 0 }
#[no_mangle] pub extern "C" fn plugin_deinit() -> i32 { 0 }
#[no_mangle] pub extern "C" fn plugin_on_enter() -> i32 {
    ui::push_toast("Hello!", ui::UI_ICON_SUCCESS, 1500);
    0
}
#[no_mangle] pub extern "C" fn plugin_on_exit() -> i32 { 0 }
```

The other exports (`plugin_on_action`, `plugin_on_tick`, …) are plain
`#[no_mangle] extern "C"` functions as well. See
[lifecycle](../plugin-runtime/lifecycle-events-and-ui.md).

### Testable layout (from `cdc-badge-development/plugins/starter`)

```rust
#![cfg_attr(target_arch = "wasm32", no_std)]
pub fn pure_logic(...) { ... }            // unit-tested with `cargo test` on the host
#[cfg(target_arch = "wasm32")] mod plugin { /* exports + SDK calls */ }
#[cfg(test)] mod tests { ... }
```

with `crate-type = ["cdylib", "rlib"]` and the SDK as a
`[target.'cfg(target_arch = "wasm32")'.dependencies]` entry. That keeps host
tests free of the `cdc` imports. `matrix` goes further with
`host_test_stubs.rs` / `store_test_stubs.rs` that fake the host for native tests.

## Error handling

Every fallible wrapper returns `cdc_badge_plugin::Result<T>` with one `Error`
enum: `Generic`, `InvalidArg`, `NoCapability`, `NotFound`, `Timeout`,
`NoMemory`, `Busy`, `NotSupported`, `RmemFull`, `Other(code)`. Lookups that can
legitimately be empty return `Option<T>` (`nvs::get_*`, `wifi::ssid`,
`keypad::consume_next`), and infallible reads return values directly. Callbacks
are action IDs: subscribe with `event::subscribe(mask, ACTION_X)?`, then match
`ACTION_X` in `plugin_on_action`.

## Idioms and pitfalls

- **`no_std` is the default, not a requirement.** `matrix` is a `std` crate
  (vodozemac needs std). `std` compiles for `wasm32-unknown-unknown`, but
  filesystem, time, threads and env are stubs that fail or panic at runtime. Use
  host APIs instead.
- **Never `unwrap()` host results.** `NoCapability` can come back even for
  capabilities you think you declared (wrong name, a 15-character limit, bus 0,
  a blocked pin), and a panic unloads the plugin.
- **Strings.** Wrappers take `AsRef<[u8]>` / `&str` and copy into
  NUL-terminated buffers (`CString`-style) per call. Pass UTF-8; the host handles
  CP437. Name parameters (`rmem`, `ecc`) are checked for 1–15 bytes before the
  host call.
- **Empty slices** are passed as null pointers (`slice_ptr`), because the host
  must not read anything at length 0.
- **Size budget.** Avoid `format!`/`core::fmt` in hot paths (it pulls in the
  formatting machinery) and prefer fixed buffers. Run `wasm-opt -Oz` on the
  output.
- **Curve IDs** for `secure_element` follow the plugin ABI (P-256 = 0,
  Ed25519 = 1). See [secure element](../hardware/secure-element.md).
- **Upstream plugin dev notes.** The development repo ships a
  `.claude/skills/cdc-badge-plugin-dev/` skill with a host-API map, canvas,
  storage, connectivity, crypto, debugging and pitfalls references. It is upstream
  material worth reading, not instructions for this repository.

Building, packaging and installing are covered in
[plugin build and install](../workflows/plugin-build-and-install.md), and
off-device testing in the [emulator](../workflows/emulator.md).
