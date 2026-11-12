# badge-cdc

Sandboxed WebAssembly applications, written in Rust, for the **CDC Badge**
(ESP32-S3, e-paper display, TROPIC01 secure element, TCA9555 GPIO expander).

This repository currently gathers the reference implementations and
documentation needed to start the project:

- `references/` — vendored upstream snapshots (see [`references/SOURCES.md`](references/SOURCES.md)).
- `openwiki/` — OpenWiki knowledge base generated over this repository
  (brief in [`openwiki/INSTRUCTIONS.md`](openwiki/INSTRUCTIONS.md)).
- `flake.nix` — Nix dev shell: Rust (wasm32-unknown-unknown, wasm32-wasip1),
  binaryen, wabt, wasm-tools, wasmtime, esptool/espflash, pyserial, SDL2/CMake
  for the emulator, Node 22 for OpenWiki and the docs site.

## Getting started

```sh
nix develop          # or: direnv allow
openwiki visualize   # browse the wiki graph
```
