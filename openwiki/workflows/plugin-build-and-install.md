---
type: "Reference"
title: "Building, packaging and installing a plugin"
openwiki_generated: true
verified:
  - by: openwiki/0.5.2
    at: 2026-11-14T16:21:12.965Z
sources:
  - id: openwiki-source-16e6e7418602542c69565bde
    resource: repo://Cargo.lock
  - id: openwiki-source-509b419231691d6726c59308
    resource: repo://docs/superpowers/plans/2026-11-13-os-plugin-bootstrap.md
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
  - id: openwiki-source-8889d9a88195e93cba20df1e
    resource: repo://scripts/plugin-build.sh
generated: { by: "opencode", at: "2026-11-14T16:21:12.965Z" }
---


# Building, packaging and installing a plugin

```
src/lib.rs ──cargo build --release --target wasm32-unknown-unknown──► target/.../<id>.wasm
           ──wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int──► dist/<id>.wasm
meta.json ───────────────────────────────────────────────────────────► dist/<id>.meta.json
                            │
          ┌─────────────────┼──────────────────────────┐
    badge flash / upload.py │  browser installer        │  emulator (no hardware)
    (USB-CDC serial)        │  (Web Serial)             │  see emulator page
          └──────► /vfat/system/<id>.wasm|.meta|.lang on the badge
```

## 1. Build

### In-repo entry point: `scripts/plugin-build.sh <id>`

From the nix dev shell, one command builds and enforces the contract:

```bash
scripts/plugin-build.sh snake   # → dist/snake.wasm + dist/snake.meta.json
```

- `cargo build --release --target wasm32-unknown-unknown -p <id>` under the
  workspace release profile (`opt-level="z"`, LTO, `codegen-units=1`,
  `panic="abort"`, `strip` — see [Rust SDK](../plugin-sdk/rust-sdk.md)), then
  `wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int` into the
  gitignored `dist/`.
- Contract checks, all loud failures:
  1. **Only `cdc` imports** — `wasm-tools print` runs as a standalone statement
     (so `set -e` aborts on a tool error instead of passing vacuously), then any
     non-`cdc` import line fails the build.
  2. **Size ≤ 786432 bytes** (768 KiB, the upstream CI cap — the practical
     ceiling given the 2 MB shared `vfat` partition).
  3. **Manifest** — the vendored
     `references/cdc-badge-plugins/tools/validate_manifest.py` (range and name
     checks; see [manifest](../plugin-runtime/manifest-and-capabilities.md)).
- Builds are **byte-identical across clean rebuilds** (committed `Cargo.lock` +
  pinned profile); the snake build is 30,662 bytes.

### Manual / upstream flow

Plain cargo (from `cdc-badge-plugins/docs/getting_started.md`):

```bash
cargo build --release --target wasm32-unknown-unknown -p <crate>
wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
  target/wasm32-unknown-unknown/release/<id>.wasm -o dist/<id>.wasm
```

- The wasm-opt feature flags match what WAMR accepts: bulk memory, and
  non-trapping float-to-int (rustc emits it by default).
- For manual builds, apply the same contract checks as
  `scripts/plugin-build.sh`: cdc-only imports (`wasm-tools print | grep import`
  — only `(import "cdc" ...)` entries may appear), size ≤ 786432 bytes, and
  `validate_manifest.py` on the manifest.
- `cdc-badge-plugins/tools/build_all.sh` builds the whole workspace into
  `dist/`. `matrix` is built separately because it is a `std` crate: building it
  together with the `no_std` plugins unifies features and leaks `std` into them
  (duplicate `panic_impl`). The script also **fails if `meta.json` `id` doesn't
  equal the directory name**, since catalog URLs use the id and build output uses
  the directory.
- Upstream CI (`.github/workflows/build.yml`) caps each `.wasm` at **768 KB**
  (786,432 bytes).

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
> AUTH <pin>                                   required in shipped builds (CONFIG_SECURE_SERIAL=y)
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

1. Write pure logic and test it with `cargo test` on the host
   (`cargo test -p <id>`; the in-repo `snake` shows the layout).
2. `scripts/plugin-build.sh <id>` — cargo + wasm-opt + contract checks
   (cdc-only imports, size ≤ 768 KB, manifest) in one command; artifacts land at
   `dist/<id>.wasm` + `dist/<id>.meta.json`.
3. Run headless in the [emulator](emulator.md) with key scripts and snapshots
   (mind its older host-API pin).
4. Upload with `upload.py`, then `PLUGIN START <id>` and watch the log
   (`badge monitor` or any serial terminal at 115200). Look for `PLUGIN TRAP`
   banners.
