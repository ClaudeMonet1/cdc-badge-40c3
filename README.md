# badge-cdc

Sandboxed WebAssembly applications, written in Rust, for the **CDC Badge**
(ESP32-S3, e-paper display, TROPIC01 secure element, TCA9555 GPIO expander).
Applications run as **plugins** inside the reference firmware **cdc-badge-os**
(WAMR interpreter, capability-gated C ABI).

## What's in the repository

- `plugins/snake/` — first in-repo plugin (root Cargo workspace member, 18 host tests).
- `scripts/` — build pipeline: `plugin-build.sh` (plugin → `dist/`, contract checks),
  `os-build.sh` + `os-flash.sh` (source build and flash of cdc-badge-os),
  plus `fetch-references.sh`.
- `patches/os-platformio.patch` — local build edits applied to the OS clone.
- `docs/runbooks/badge-device.md` — on-device session runbook (flash, serial AUTH, upload, play).
- `references/` — vendored upstream snapshots (see [`references/SOURCES.md`](references/SOURCES.md)); read-only.
- `openwiki/` — OpenWiki knowledge base generated over this repository
  (brief in [`openwiki/INSTRUCTIONS.md`](openwiki/INSTRUCTIONS.md)).
- `flake.nix` — Nix dev shell: Rust 1.100.0 (wasm32-unknown-unknown, wasm32-wasip1),
  binaryen, wabt, wasm-tools, wasmtime, PlatformIO 6.2.0 (OS source build),
  esptool/espflash, pyserial, SDL2/CMake for the emulator, Node 22 for OpenWiki and the docs site.

## Getting started

```sh
nix develop          # or: direnv allow
openwiki visualize   # browse the wiki graph

cargo test -p snake              # host unit tests for the game logic
scripts/plugin-build.sh snake    # → dist/snake.wasm + dist/snake.meta.json (contract checks)
```

Building and flashing the OS from source: `scripts/os-build.sh` then
`scripts/os-flash.sh [PORT]` — see the wiki page
[OS build, partitions and flashing](openwiki/os/build-flash-and-partitions.md).
