---
type: developer workflow
title: Building, packaging and installing a plugin
description: End-to-end path from Rust source to a running plugin on the CDC Badge — cargo build for wasm32-unknown-unknown, wasm-opt flags, the dist/ artifact layout and catalog, the badge CLI (new/build/test/flash/monitor/emulate), the firmware upload.py and the PLUGIN serial command set with its raw-stream CRC32 upload protocol, the browser plugin installer, on-device management, and upstream CI.
tags: [workflow, build, cargo, wasm-opt, upload, serial, badge-cli, installer, ci]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-a46cc211e85b62a0281932e0
    resource: repo://references/cdc-badge-development/Dockerfile
  - id: openwiki-source-199033859ed56647754a5d26
    resource: repo://references/cdc-badge-development/tools/badge.py
  - id: openwiki-source-84576151a1e5dc8e04fe8055
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/PluginSerialCommands.cpp
  - id: openwiki-source-6ead3daaa4595a9e938eaff9
    resource: repo://references/cdc-badge-os/tools/upload.py
  - id: openwiki-source-1381c889af1517bc2f7a6dc3
    resource: repo://references/cdc-badge-plugins/.github/workflows/build.yml
  - id: openwiki-source-f915b2b560abca986a197ff6
    resource: repo://references/cdc-badge-plugins/.github/workflows/release.yml
  - id: openwiki-source-eaec7910cde836ec103e8773
    resource: repo://references/cdc-badge-plugins/tools/build_all.sh
  - id: openwiki-source-bf1c2b0881579acc1bdafb13
    resource: repo://references/cdc-badge-plugins/tools/generate_catalog.py
  - id: openwiki-source-237bcaf85135d1787411513f
    resource: repo://references/cdc-badge-plugins/webflasher/js/chunk-protocol.js
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Building, packaging and installing a plugin

```
src/lib.rs ──cargo build --release --target wasm32-unknown-unknown──► target/.../<id>.wasm
          ──wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int──► dist/<id>.wasm
meta.json ───────────────────────────────────────────────────────────► dist/<id>.meta.json
<id>.lang.json (optional) ───────────────────────────────────────────► dist/<id>.lang.json
                           │
         ┌─────────────────┼──────────────────────────┐
   badge flash / upload.py │  browser installer        │  emulator (no hardware)
   (USB-CDC serial)        │  (Web Serial)             │  see emulator page
         └──────► /vfat/system/<id>.wasm|.meta|.lang on the badge
```

## 1. Build

Plain cargo (from `cdc-badge-plugins/docs/getting_started.md`):

```bash
cargo build --release --target wasm32-unknown-unknown -p <crate>
wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
  target/wasm32-unknown-unknown/release/<id>.wasm -o dist/<id>.wasm
```

- Release profile: `opt-level="z"`, LTO, `codegen-units=1`, `panic="abort"`,
  `strip` (see [Rust SDK](../plugin-sdk/rust-sdk.md)).
- The wasm-opt feature flags match what WAMR accepts: bulk memory, and
  non-trapping float-to-int (rustc emits it by default).
- `cdc-badge-plugins/tools/build_all.sh` builds the whole workspace into
  `dist/`. `matrix` is built separately because it is a `std` crate: building it
  together with the `no_std` plugins unifies features and leaks `std` into them
  (duplicate `panic_impl`). The script also **fails if `meta.json` `id` doesn't
  equal the directory name**, since catalog URLs use the id and build output uses
  the directory.
- Upstream CI (`.github/workflows/build.yml`) caps each `.wasm` at **768 KB**
  (786,432 bytes). That is the practical size ceiling to design for, given the
  2 MB shared `vfat` partition.
- Validate the manifest with `python3 tools/validate_manifest.py` (range and
  name checks; see [manifest](../plugin-runtime/manifest-and-capabilities.md)).
- Check imports before uploading:
  `wasm-tools print dist/<id>.wasm | grep import`. Only `(import "cdc" ...)`
  entries may appear.

Our Nix shell provides cargo with the wasm32 target, `wasm-opt`, `wasm-tools`
and wabt.

## 2. The `badge` CLI (`cdc-badge-development/tools/badge.py`)

A front end for newcomers:

| Command | Does |
|---|---|
| `badge new <name>` | Create a test-ready plugin under `plugins/` (from the starter layout) |
| `badge build <name>` | cargo build + wasm-opt (`WASM_OPT_FLAGS` as above) into `dist/`. Also resolves the vendored examples. |
| `badge test <name>` | `cargo test` on the host: the TDD loop for the pure logic |
| `badge flash <name> [--start] [--monitor] [--pin] [--port]` | Build if needed, then upload `.wasm` and `meta.json` via the firmware's `tools/upload.py` |
| `badge monitor` | Stream the serial log (auto-detects `usbmodem`/`ACM`/`COM` ports) |
| `badge emulate <name>` | Run in the [emulator](emulator.md) |
| `badge info\|list\|start\|stop\|delete` | Thin wrappers over the plugin serial commands |

It finds the real `cargo` via `rustup which cargo` (skipping proxy shims) and
looks for `wasm-opt` in a local `.tools/binaryen-*` or on `PATH`. It needs the
`vendor/` submodules (`upload.py` lives in `vendor/cdc-badge-os/tools/`), which
are empty in our snapshot. Call `references/cdc-badge-os/tools/upload.py`
directly instead.

Environment options upstream: `scripts/setup.py` / `setup.sh` (installs Rust,
binaryen and a `.venv` with pyserial), `Dockerfile` (`rust:1-bookworm` +
wasm32 target + binaryen `version_119` + SDL2/cmake + pyserial),
`.devcontainer/` and VS Code tasks. `EASY.md` is a from-scratch walkthrough for
macOS, Linux and Windows.

## 3. Upload over serial

`references/cdc-badge-os/tools/upload.py` is the unified tool. It uses pyserial
at 115200 baud and an optional `--pin`.

```bash
python3 references/cdc-badge-os/tools/upload.py --wasm dist/<id>.wasm --meta dist/<id>.meta.json [--lang dist/<id>.lang.json] --pin 123456
python3 references/cdc-badge-os/tools/upload.py --list | --info <id> | --start <id> | --stop | --delete <id>
```

### `PLUGIN` serial commands (`PluginSerialCommands.cpp`)

`LIST` (JSON), `INFO <id>`, `START <id>`, `STOP`, `CMD <id> <args>` (sent to
`plugin_on_cmd`), `ENABLE` / `DISABLE <id>`, `DELETE <id>`,
`UPLOAD` / `UPLOAD_META` / `UPLOAD_LANG` / `UPLOAD_AOT <id> <size> <crc32_hex>`,
`ABORT`, `DEBUG` (verbose host_* logging), `FEATURES` (provided external
features). The firmware also registers GPIO serial commands that share the same
pin policy.

### Upload protocol (current, per the command table and the JS installer)

```
> AUTH <pin>                                   only when FEATURE_SECURE_SERIAL=1
< OK: Authenticated
> PLUGIN UPLOAD <id> <size> <crc32_hex>\n      (or UPLOAD_META / UPLOAD_LANG)
< READY
> <size raw bytes>                             a byte interceptor takes over; no line parsing
< OK <size>        |  ERR <reason>             CRC-32 (IEEE) over the whole payload
```

Commands end with a bare `\n`. A CR would be taken as a payload byte once the
interceptor switches in. The header comment of `PluginSerialCommands.cpp` still
describes an older hex-chunk/ACK scheme (`<idx> <crc32> <hex>` lines, `END`).
The command table and `webflasher/js/chunk-protocol.js` describe the raw-stream
form shown above. Integrity is checked; authenticity is not (no signing, see
[manifest and capabilities](../plugin-runtime/manifest-and-capabilities.md)).
`UPLOAD_AOT` exists, but AOT images are rejected at load unless
`FEATURE_PLUGIN_AOT=1`.

## 4. Browser installer

`cdc-badge-plugins/webflasher/` (`index.html`, `js/webserial.js`,
`js/chunk-protocol.js`, `js/plugin-installer.js`) is published at
`https://krim404.github.io/cdc-badge-plugins/`. It connects over Web Serial
(Chrome/Edge), loads `catalog.json` and installs the selected plugin with the
protocol above, writing in 4096-byte chunks with a 5 s READY / 30 s OK timeout.
`tools/generate_catalog.py` builds the catalog from every `meta.json`
(`wasm_url`, `meta_url`, optional lang URL pointing at the GitHub release
assets), and `.github/workflows/release.yml` runs `build_all.sh`, generates the
catalog and publishes a release. The OS [web flasher](../os/build-flash-and-partitions.md)
links to this installer as step 3.

## 5. On the badge

Plugins appear under **Main menu → Plugins** (`PluginListView`): start, info,
and on `[3]` the context menu with stop-background, enable/disable and delete.
Files land in `/vfat/system/` on the 2 MB FAT partition, so no firmware rebuild
is needed. A **Factory Setup** flash of the OS wipes every installed plugin.

## Suggested loop for badge-cdc

1. Write pure logic and test it with `cargo test` on the host.
2. `cargo build` + `wasm-opt`, check imports and size (≤ 768 KB, ideally much less).
3. Run headless in the [emulator](emulator.md) with key scripts and snapshots
   (mind its older host-API pin).
4. Upload with `upload.py`, then `PLUGIN START <id>` and watch the log
   (`badge monitor` or any serial terminal at 115200). Look for `PLUGIN TRAP`
   banners.
