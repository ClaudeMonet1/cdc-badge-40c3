---
type: repository overview
title: Repository layout and vendored references
description: What the badge-cdc repository contains today — the Nix dev shell, nine vendored upstream snapshots under references/ with pinned commits and roles, the refresh script, nested submodules that are not vendored, the substitution for the missing krim404/cdc-badge repo, and how OpenWiki is wired in.
tags: [repository, references, provenance, nix, dev-shell, openwiki]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-f5a489e5822d87c0b8fc66ef
    resource: repo://.mcp.json
  - id: openwiki-source-e119253b3c3737247dc63f2a
    resource: repo://.openwikiignore
  - id: openwiki-source-3eda5d2b85501c78fc0ba02d
    resource: repo://flake.nix
  - id: openwiki-source-782754752a7fccf1126740d6
    resource: repo://references/cdc-badge-development/.gitmodules
  - id: openwiki-source-bc24ba55b19d9850e16a9b6c
    resource: repo://references/cdc-badge-os/.gitmodules
  - id: openwiki-source-edf57d425cf4973bb79fe308
    resource: repo://references/SOURCES.md
  - id: openwiki-source-5da280b914160b3778d1cee0
    resource: repo://scripts/fetch-references.sh
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# Repository layout and vendored references

`badge-cdc` will hold our **sandboxed Rust/WebAssembly application for the CDC
Badge**. For now it is a reference workspace: no application code yet, only the
upstream material we build against plus this wiki.

```
badge-cdc/
├── flake.nix, flake.lock, .envrc   Nix dev shell (direnv: `use flake`)
├── references/                      read-only upstream snapshots (plain files)
│   └── SOURCES.md                   inventory: upstream, branch, commit, role
├── scripts/fetch-references.sh      re-vendor references at branch tips
├── openwiki/                        this wiki (INSTRUCTIONS.md = wiki brief)
├── .openwikiignore                  bulk assets excluded from the wiki
├── .mcp.json                        OpenWiki MCP server for Claude Code
└── .claude/skills/openwiki/         OpenWiki host skill
```

## Vendored references

The references are **plain files, not git submodules**. That keeps every source
citable as `repo://references/...` and searchable without network access. Don't
edit them. The snapshot is dated 2026-11-12, and the pinned commits are in
`references/SOURCES.md`.

| Directory | Upstream (branch) | Role | Wiki entry point |
|---|---|---|---|
| `cdc-badge-os/` | krim404/cdc-badge-os (`release`) | Reference OS (ESP-IDF) with the WAMR plugin runtime. Includes `website/` (the full documentation site, Astro Starlight) and `web-flasher/` | [OS architecture](../os/architecture.md), [WAMR runtime](../plugin-runtime/wamr-runtime.md) |
| `cdc-badge-plugins/` | krim404/cdc-badge-plugins (`main`) | Rust plugin SDK crate, C template, examples, production plugins, browser plugin installer | [Rust SDK](../plugin-sdk/rust-sdk.md), [example plugins](../plugin-sdk/example-plugins.md) |
| `cdc-badge-development/` | krim404/cdc-badge-development (`main`) | Developer environment: `badge` CLI, off-device emulator, starter plugin, Docker/devcontainer | [plugin build and install](../workflows/plugin-build-and-install.md), [emulator](../workflows/emulator.md) |
| `cdc-badge-nametag/` | riatlabs/cdc-badge-nametag (`main`) | Vendor Arduino/PlatformIO nametag firmware | [vendor firmware](../vendor/nametag-firmware.md) |
| `cdc-badge-hardware/` | riatlabs/cdc-badge (`main`) | KiCad schematic and PCB, design docs, datasheet list, cases | [hardware overview](../hardware/board-overview.md) |
| `libtropic-arduino/` | tropicsquare/libtropic-arduino (`main`) | TROPIC01 Arduino wrapper (its `libtropic` submodule is not vendored) | [secure element](../hardware/secure-element.md) |
| `TCA9555/` | robtillaart/TCA9555 (`master`) | I²C GPIO expander library (badge uses the TCA9535 variant) | [keypad](../hardware/keypad-and-io-expander.md) |
| `GxEPD2/` | ZinggJM/GxEPD2 (`master`) | E-paper driver used by the vendor firmware | [display](../hardware/display-and-graphics.md) |
| `Adafruit-GFX-Library/` | adafruit/Adafruit-GFX-Library (`master`) | Drawing and font layer under GxEPD2 (and, as an ESP-IDF port, under the OS) | [display](../hardware/display-and-graphics.md) |

### Substitution: `krim404/cdc-badge`

The original request named `https://github.com/krim404/cdc-badge`. That URL is not
publicly reachable (HTTP 404, and `git ls-remote` asks for credentials, which
means the repo is private or doesn't exist). The same author's device development
repository `krim404/cdc-badge-development` is vendored in its place.
`krim404/cdc-badge-updater` (a TROPIC01 firmware updater) exists but is not
vendored.

### Nested submodules that are *not* vendored

Upstream pins these as submodules. They are empty in our snapshots:

| Inside | Path | Upstream |
|---|---|---|
| cdc-badge-os | `components/wamr_runtime/wasm-micro-runtime` | bytecodealliance/wasm-micro-runtime |
| cdc-badge-os | `third_party/libtropic` | tropicsquare/libtropic |
| cdc-badge-os | `components/CalEPD` | martinberlin/CalEPD |
| cdc-badge-os | `components/Adafruit-GFX` | martinberlin/Adafruit-GFX-Library-ESP-IDF |
| libtropic-arduino | `libtropic` | tropicsquare/libtropic |
| cdc-badge-development | `vendor/cdc-badge-os`, `vendor/cdc-badge-plugins` | the two krim404 repos. Their pins are **older** than our vendored snapshots. |

So WAMR internals, the libtropic C API and the CalEPD driver are only documented
here through how the OS uses them. Building the OS or the emulator needs these
submodules fetched from upstream.

### Refreshing

`scripts/fetch-references.sh [dir...]` shallow-clones each listed upstream at
its branch tip, strips `.git`, replaces the directory, prints the new commit
for `SOURCES.md`, and stages the result (`git add -f`). It does not fetch nested
submodules. After refreshing, update `SOURCES.md` and run an OpenWiki update so
affected wiki claims are rechecked.

### Upstream agent files

Several references ship their own `CLAUDE.md`, `AGENTS.md`, `.claude/skills/`,
`.agents/` or `.specify/` trees. For example, cdc-badge-development has a
`cdc-badge-plugin-dev` skill with a host-API map, pitfalls and a codebook. These
are **upstream reference material** for reading, not instructions that apply to
this repository.

## Dev shell (`flake.nix`)

`nix develop` (or `direnv allow`) provides:

| Purpose | Packages |
|---|---|
| Rust → WASM | Rust stable from rust-overlay with `rust-src`, rustfmt, clippy, rust-analyzer, targets `wasm32-unknown-unknown` and `wasm32-wasip1` |
| WASM tooling | binaryen (`wasm-opt`), wabt (`wasm2wat`, `wasm-objdump`), wasm-tools, wasmtime |
| Device I/O | Python 3 with pyserial (for `tools/badge.py`), esptool, espflash |
| Emulator build | cmake, pkg-config, SDL2, gcc |
| Docs and wiki | Node.js 22 (OpenWiki, Astro site, web flasher), git, gh |

The Rust setup mirrors the toolchain in `cdc-badge-development/Dockerfile`
(stable + `wasm32-unknown-unknown`). The shell hook prepends
`~/.npm-global/bin` to `PATH`, where the `openwiki` CLI is installed. PlatformIO
is **not** included, so building the OS itself needs a separate install.

## OpenWiki setup

- The `openwiki` npm CLI (v0.5.0) is installed under `~/.npm-global`.
- `.mcp.json` starts the MCP server as `${HOME}/.npm-global/bin/openwiki mcp --host claude`.
  The absolute path is deliberate: a bare `openwiki` only resolves inside
  `nix develop`, and Claude Code sessions started outside the shell could not
  launch the server.
- `.claude/skills/openwiki/SKILL.md` is the host skill that drives the page loop.
- `openwiki/INSTRUCTIONS.md` is the wiki brief: organise around what a
  Rust/WASM developer needs, cite `references/...`, and document disagreements.
- `.openwikiignore` excludes bulk or binary material: GxEPD2 bitmaps and
  extras, lockfiles, the KiCad PCB layout and 3D shapes, pictures, PDFs, and
  `.bin`/`.wasm`/CAD files.
- `openwiki visualize` renders the page and claim graph.
