# Spec: OS source build + first WASM plugin (snake)

Branch: `os-plugin-bootstrap` · Date: 2026-11-13 · Status: approved design, pending implementation plan

## Context & goal

badge-cdc will hold a sandboxed Rust/WebAssembly application for the CDC Badge
(ESP32-S3, e-paper, TROPIC01 secure element). This workstream makes two things
possible:

1. **Deploy cdc-badge-os from source** to a badge — with the ability to modify
   the OS if needed.
2. **Start the plugin application**, using the upstream `snake` example as the
   first demo (scaffold + end-to-end pipeline, iterate on the real app later).

All tooling is deterministic and provided by `flake.nix`. No Docker.

## Non-goals

- Modifying the OS itself (the design only needs to make that *possible*).
- The off-device emulator — it re-hosts an older OS pin (225 vs 307 host
  symbols), so snake (host API 0.8) may not instantiate there. Optional follow-up.
- The real application beyond snake (next spec).
- Production hardening / pairing-key rotation.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| OS build system | PlatformIO (upstream's) via nix | A native ESP-IDF port would fork the build system from upstream; Docker was ruled out in favor of flake-pinned determinism |
| PlatformIO packaging | `fetchPypi` in the flake, pinned version + sha256 | nixpkgs has no `platformio` package (verified against the pinned nixos-unstable); a pinned fetchPypi hash is reproducible |
| PlatformIO version | 6.2.0 (latest as of 2026-11-13; requires Python ≥ 3.9, Apache-2.0) | pinned explicitly |
| Python for PlatformIO | `pkgs.python313` explicitly | avoids surprises from a too-new default interpreter; if a pio dependency breaks on 3.13, pin `python312` |
| OS source | working clone in gitignored `build/cdc-badge-os/` at pinned commit `181a24d94353e0318835a7b0801f2ce8d4937fb4` | the vendored `references/cdc-badge-os/` has no `.git`; the build pre-script (`tools/pio_submodules.py`) requires git submodules. The clone is disposable and reproducible from the pinned commit |
| Local OS modifications | `patches/` directory of git patches, applied idempotently by the build script | explicit, reviewable seam for future OS changes; if modifications become real, fork `cdc-badge-os` and repoint the clone |
| PIO state | `PLATFORMIO_CORE_DIR=$PWD/build/.platformio` (gitignored), exported by both the flake `shellHook` and the build scripts (scripts are canonical) | hermetic per project; pio's downloaded platform/framework/toolchain are version-pinned registry artifacts |
| First plugin | copy upstream `snake` into `plugins/snake/` | complete, tested example: pure-logic unit tests, animated sprites, per-level high scores in NVS |
| Plugin SDK | path dependency on vendored `references/cdc-badge-plugins/sdk/cdc-badge-plugin` | no network dependency; pinned by the commit recorded in `references/SOURCES.md` |

## Determinism chain (what is pinned where)

| Artifact | Pin | Where |
|---|---|---|
| nixpkgs, rust-overlay, flake-utils | `flake.lock` | existing |
| Rust toolchain | exact stable version (the latest `stable` channel release at implementation time; flake and `rust-toolchain.toml` must match) | flake.nix (replaces `stable.latest`) + root `rust-toolchain.toml` |
| PlatformIO Core | 6.2.0 + PyPI sha256 | flake.nix `fetchPypi` |
| espressif32 platform | 6.12.0 (exact, as in upstream `platformio.ini`) | clone's `platformio.ini` |
| ESP-IDF framework | exactly `3.50500.0` (upstream uses the range `~3.50500.0`, which would drift) | patch in `patches/` applied to the clone |
| xtensa toolchain | 12.2.0 (pinned by the platform version) | pio registry artifact |
| OS source + submodules (WAMR, libtropic, CalEPD, Adafruit-GFX) | commit `181a24d…` + upstream gitlinks | clone script |
| Plugin SDK + snake source | `references/` snapshot (commit in `SOURCES.md`) + copied files | repo |

## Repo layout (new / changed)

```
flake.nix                     rust pinned to an exact version; + platformio
                              (python313 + fetchPypi 6.2.0); shellHook exports
                              PLATFORMIO_CORE_DIR
Cargo.toml                    workspace: members = ["plugins/snake"], resolver 2;
                              [profile.release] opt-level="z", lto=true,
                              codegen-units=1, panic="abort", strip=true
rust-toolchain.toml           pinned channel + wasm32-unknown-unknown, rustfmt, clippy
plugins/snake/                copied from references/cdc-badge-plugins/plugins/snake/
                              (Cargo.toml, meta.json, src/{lib,game,render,sprites}.rs);
                              dep path changed to
                              ../../references/cdc-badge-plugins/sdk/cdc-badge-plugin;
                              meta.json unchanged (id "snake", nvs plg_snake)
patches/os-framework-pin.patch  pins framework-espidf to exactly 3.50500.0 in the clone
scripts/os-build.sh           clone-if-missing → checkout pinned commit →
                              git submodule update --init --recursive → apply patches/
                              → pio run -e cdc_badge_usb
scripts/os-flash.sh           pio run -t upload (+ documented download-mode and
                              factory-wipe warnings)
scripts/plugin-build.sh <id>  cargo build --release --target wasm32-unknown-unknown
                              → wasm-opt -Oz --enable-bulk-memory
                                --enable-nontrapping-float-to-int → dist/<id>.wasm
                              + dist/<id>.meta.json → checks: imports only "cdc",
                              size ≤ 786432 B, validate_manifest.py on the manifest
.gitignore                    + build/, dist/, target/
```

## Verification (this session — badge not connected)

1. `nix develop`: `pio --version`, `cargo --version`, `wasm-opt --version` all resolve.
2. `scripts/os-build.sh`: clone + submodules + build succeed; record the paths and
   sizes of `firmware.bin`, bootloader and partitions under
   `build/cdc-badge-os/.pio/build/cdc_badge_usb/` (first run downloads ~1–2 GB of
   pinned artifacts).
3. `cargo test -p snake`: pure game-logic tests pass on the host.
4. `scripts/plugin-build.sh snake`: `dist/snake.wasm` + `dist/snake.meta.json`
   produced; import check passes (only `"cdc"` imports); size ≤ 768 KB; manifest
   validation passes.
5. Record sha256 of `firmware.bin` and `snake.wasm`; rebuild both → identical
   hashes (determinism spot-check).

## Runbook: with the badge connected (later)

1. Connect USB-C. If the badge does not enumerate or is in a boot loop: hold
   Flash (IO0) → tap Reset (EN) → release Flash (download mode).
2. `scripts/os-flash.sh`. **Expected factory wipe**: our build is `DEBUG_MODE=1`;
   a build-profile byte change wipes NVS + TROPIC01 slots, and pre-1.0 firmware
   can wipe all stored data on any flash. Confirm the badge holds no data the
   user needs before flashing.
3. Serial console at 115200: `AUTH <pin>` (secure serial is on via
   `sdkconfig.defaults`; the first-boot default PIN is documented in the
   cdc-badge-os website docs — confirm at execution time).
4. `python3 references/cdc-badge-os/tools/upload.py --wasm dist/snake.wasm
   --meta dist/snake.meta.json --pin <pin>` (pyserial comes from the nix shell).
5. `PLUGIN START snake` over serial, or Main menu → Plugins → Snake on the badge.
   Play: steer with 2/4/6/8, pause with 5. Verify high scores persist in the
   `plg_snake` NVS namespace across plugin restarts.

## Risks & mitigations

- **PlatformIO `buildPythonPackage` dependency list** (bottle, tabulate,
  starlark, …) may be fiddly to declare → resolve it from the sdist at
  implementation time; fallback: wrap a pinned wheel via `python313Packages.venv`;
  last resort: revisit the Docker exception with the user.
- **Python 3.13 incompatibility** of some pio dependency → pin `python312`.
- **GPL-3.0**: the SDK is GPL; linking it makes our plugin a combined work under
  GPL terms. Fine for internal use; decide before anything public.
- **Upstream drift**: the clone is frozen at the pinned commit. Updating it =
  change the commit in `scripts/os-build.sh`, re-vendor references with
  `scripts/fetch-references.sh`, and run an OpenWiki update.
- **Network**: one-time ~1–2 GB download of pinned pio artifacts; recorded hashes
  land in the session report.

## Success criteria

- `nix develop` yields a hermetic, reproducible toolchain (pio + pinned Rust
  wasm32).
- The OS image builds from the pinned commit; recorded hashes reproduce on rebuild.
- snake: host tests pass, wasm is valid (imports and size), manifest validated.
- The on-device runbook is written; badge steps are deferred until hardware is
  connected.
