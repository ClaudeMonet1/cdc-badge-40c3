# OS Source Build + First WASM Plugin (snake) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cdc-badge-os buildable and flashable from source via a deterministic Nix toolchain, and land the upstream `snake` plugin as our first sandboxed WASM application with a verified build pipeline.

**Architecture:** A gitignored working clone of cdc-badge-os at the pinned commit is built with PlatformIO (pinned in `flake.nix` via fetchPypi; PIO state hermetic in `build/.platformio`). Local build modifications live in a git patch applied by the build script. The plugin side is a root Cargo workspace containing `plugins/snake`, path-depending on the vendored SDK, with a build script that enforces the import/size/manifest contract.

**Tech Stack:** Nix (flake.nix, rust-overlay, python313), PlatformIO Core 6.2.0 / ESP-IDF 5.5 (espressif32@6.12.0), Rust 1.100.0 (wasm32-unknown-unknown), binaryen wasm-opt, wasm-tools, Python 3 (pyserial, validate_manifest.py).

**Spec:** `docs/superpowers/specs/2026-11-13-os-plugin-bootstrap-design.md`

## Global Constraints

- All tooling is deterministic and provided by `flake.nix`. No Docker.
- OS source pinned to commit `181a24d94353e0318835a7b0801f2ce8d4937fb4` (upstream `krim404/cdc-badge-os`, `release` branch).
- PlatformIO Core 6.2.0, PyPI **sdist** SRI hash `sha256-iA6gZzSQiz1sCpZZjKe+VywrZ1VYV4SqY6IBu9+4xZ0=` (`fetchPypi` downloads the sdist, not the wheel), built against `pkgs.python313`.
- Rust toolchain pinned to exactly `1.100.0` in both `flake.nix` and `rust-toolchain.toml`.
- ESP-IDF platform pins: `espressif32@6.12.0`, `framework-espidf @ 3.50500.0` (exact, via local patch), `toolchain-xtensa-esp32s3 @ 12.2.0+20230208` (already exact upstream).
- `PLATFORMIO_CORE_DIR` = `<repo>/build/.platformio`, exported by the flake shellHook and by every script.
- Plugin contract: target `wasm32-unknown-unknown`, cdylib, `wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int`, imports only `"cdc"`, size ≤ 786432 bytes, manifest passes `validate_manifest.py`.
- `references/` is read-only (vendored snapshots). Never edit files under it.
- Work happens on branch `os-plugin-bootstrap`. Commit after every task.

## File Structure

| File | Responsibility |
|---|---|
| `flake.nix` (modify) | Pinned Rust 1.100.0, PlatformIO 6.2.0 derivation, `PLATFORMIO_CORE_DIR` in shellHook |
| `.gitignore` (modify) | Ignore `build/`, `dist/` (`target/` already ignored) |
| `Cargo.toml` (create) | Root workspace: members, release profile mirroring upstream |
| `rust-toolchain.toml` (create) | rustup parity pin for non-Nix users (must match flake) |
| `plugins/snake/*` (create, 6 files) | Copied upstream snake plugin; dep path repointed to vendored SDK |
| `patches/os-platformio.patch` (create) | Local OS build patches: framework pin, reproducible flags, Linux monitor port |
| `scripts/os-build.sh` (create) | Clone-if-missing + submodules + patch apply + pinned penv dep + `pio run` |
| `scripts/plugin-build.sh` (create) | cargo build + wasm-opt + import/size/manifest checks → `dist/` |
| `scripts/os-flash.sh` (create) | Flash the built OS (`pio run -t upload`), optional port arg, wipe warning |
| `docs/runbooks/badge-device.md` (create) | On-device runbook: download mode, flash, AUTH/PIN, plugin upload, monitor, play |

---

### Task 1: Pin the Nix toolchain (Rust 1.100.0 + PlatformIO 6.2.0)

**Files:**
- Modify: `flake.nix`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: existing flake (rust-overlay input, devShells.default)
- Produces: `nix develop` shell with `rustc` 1.100.0 (wasm32 targets) and `pio` 6.2.0 on PATH; `PLATFORMIO_CORE_DIR` exported

- [ ] **Step 1: Extend .gitignore**

Append to `.gitignore` (after the `# Rust / wasm build output` block):

```
# OS source clone + hermetic PlatformIO state (see scripts/os-build.sh)
build/

# Plugin build output (see scripts/plugin-build.sh)
dist/
```

- [ ] **Step 2: Pin the Rust toolchain in flake.nix**

In `flake.nix`, change:

```nix
        rust = pkgs.rust-bin.stable.latest.default.override {
```

to:

```nix
        rust = pkgs.rust-bin.stable."1.100.0".default.override {
```

(Keep the existing `extensions` and `targets` lines unchanged.)

- [ ] **Step 3: Add the PlatformIO derivation**

In the `let` block of `flake.nix`, after the `python = ...` line, add:

```nix
        py313 = pkgs.python313Packages;
        platformio = pkgs.python313.pkgs.buildPythonPackage {
          pname = "platformio";
          version = "6.2.0";
          pyproject = true;
          build-system = [ py313.setuptools ];
          src = pkgs.fetchPypi {
            pname = "platformio";
            version = "6.2.0";
            hash = "sha256-iA6gZzSQiz1sCpZZjKe+VywrZ1VYV4SqY6IBu9+4xZ0=";
          };
          dependencies = [
            py313.bottle
            py313.click
            py313.colorama
            py313.marshmallow
            py313.pip
            py313.pyelftools
            py313.pyserial
            py313.requests
            py313."semantic-version"
            py313.tabulate
            py313.ajsonrpc
            py313.starlette
            py313.uvicorn
            py313.wsproto
          ];
        };
```

Notes from Task 1 execution (2026-11-13, keep if re-running):
- Call `buildPythonPackage` directly — `py313.callPackage …` crashes in this nixpkgs (a `disabled` function leaks into the scope).
- `fetchPypi` is the nixpkgs attribute name (not `fetchPyPi`); the hash above is the verified **sdist** SRI.
- `py313.pip` is required by nixpkgs' runtime-deps check (PlatformIO's `Requires-Dist` includes pip).
- If the locked `rust-overlay` predates Rust 1.100.0, run `nix flake update rust-overlay` (single-node lock change) and commit `flake.lock` with this task.

- [ ] **Step 4: Add platformio to the dev shell and export PIO state dir**

In `devShells.default.packages`, after the `# Rust → WebAssembly plugin toolchain` group (next to `pkgs.wasmtime`), add:

```nix
            # OS source build (PlatformIO Core; state in build/.platformio)
            platformio
```

In `shellHook`, add one line before the existing `echo`:

```nix
             export PLATFORMIO_CORE_DIR="$PWD/build/.platformio"
```

- [ ] **Step 5: Verify the shell**

Run: `nix develop -c bash -c 'rustc --version && cargo --version && wasm-opt --version && pio --version'`
(on nix 2.35, `-c` execs its single argument verbatim — the `bash -c` wrapper is needed for compound commands)
Expected: `rustc 1.100.0`, cargo matching, a `wasm-opt` version line, `PlatformIO Core, version 6.2.0`.
(First run builds the platformio package; ~1–2 min.)

Contingencies (only if the expected output is not produced):
- platformio build fails with `setup.py: not found` → add `pyproject = true;` to the derivation and re-run.
- a `py313.<name>` package does not exist in nixpkgs → check the name with `nix eval nixpkgs#x86_64-linux.python313Packages.<name>.name`; the likely culprit is `ajsonrpc` (may be named `aiojsonrpc` — verify and use the existing name).
- `pio --version` crashes on a Python 3.13 incompatibility → replace `py313`/`python313` with `pkgs.python312Packages`/`pkgs.python312` throughout this task and note it in the commit message.

- [ ] **Step 6: Commit**

```bash
git add flake.nix .gitignore
git add flake.lock   # only if Step 3's note triggered `nix flake update rust-overlay`
git commit -m "build: pin Rust 1.100.0 and add PlatformIO 6.2.0 to the dev shell"
```

---

### Task 2: Plugin workspace + snake

**Files:**
- Create: `Cargo.toml`
- Create: `rust-toolchain.toml`
- Create: `plugins/snake/Cargo.toml`, `plugins/snake/meta.json`, `plugins/snake/src/lib.rs`, `plugins/snake/src/game.rs`, `plugins/snake/src/render.rs`, `plugins/snake/src/sprites.rs`

**Interfaces:**
- Consumes: Task 1 shell (cargo 1.100.0 with wasm32 target); vendored SDK at `references/cdc-badge-plugins/sdk/cdc-badge-plugin`
- Produces: workspace member `snake` (cdylib+rlib); `cargo test -p snake` runs 18 host unit tests from `src/game.rs`

- [ ] **Step 1: Copy the snake plugin**

```bash
mkdir -p plugins
cp -r references/cdc-badge-plugins/plugins/snake plugins/snake
find plugins/snake -type f | sort
```

Expected: exactly 6 files — `Cargo.toml`, `meta.json`, `src/game.rs`, `src/lib.rs`, `src/render.rs`, `src/sprites.rs`.

- [ ] **Step 2: Repoint the SDK dependency**

In `plugins/snake/Cargo.toml`, change:

```toml
cdc-badge-plugin = { path = "../../sdk/cdc-badge-plugin", features = ["panic_handler"] }
```

to:

```toml
cdc-badge-plugin = { path = "../../references/cdc-badge-plugins/sdk/cdc-badge-plugin", features = ["panic_handler"] }
```

- [ ] **Step 3: Create the root workspace manifest**

Create `Cargo.toml`:

```toml
[workspace]
resolver = "2"
members = ["plugins/snake"]

# Mirrors references/cdc-badge-plugins/Cargo.toml [profile.release]
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

- [ ] **Step 4: Create the rustup parity pin**

Create `rust-toolchain.toml`:

```toml
# Parity pin for rustup users. The authoritative toolchain for the nix dev
# shell is flake.nix (rust-bin 1.100.0); keep the two in sync.
[toolchain]
channel = "1.100.0"
targets = ["wasm32-unknown-unknown"]
components = ["rustfmt", "clippy"]
```

- [ ] **Step 5: Verify the toolchain resolves to Nix**

Run: `nix develop -c bash -c 'which cargo && rustc --version'`
Expected: `cargo` path inside the nix store, `rustc 1.100.0`.

- [ ] **Step 6: Run the host unit tests**

Run: `nix develop -c bash -c 'cargo test -p snake'`
Expected: `test result: ok. 18 passed; 0 failed` (from `src/game.rs`).

- [ ] **Step 7: Commit**

```bash
git add Cargo.toml rust-toolchain.toml plugins/snake Cargo.lock
git commit -m "feat: add snake plugin workspace with vendored SDK path dep"
```

(`Cargo.lock` is generated by the `cargo test` in Step 6; committing it now makes Task 6's reproducibility check meaningful.)

---

### Task 3: Plugin build script with contract checks

**Files:**
- Create: `scripts/plugin-build.sh`

**Interfaces:**
- Consumes: Task 2 workspace (`cargo build -p <id>`), `wasm-opt`, `wasm-tools`, `python3` + pyserial-free validator at `references/cdc-badge-plugins/tools/validate_manifest.py`
- Produces: `dist/<id>.wasm` + `dist/<id>.meta.json`; exits non-zero on any contract violation. Later tasks and the runbook rely on these exact paths.

- [ ] **Step 1: Write the script**

Create `scripts/plugin-build.sh`:

```bash
#!/usr/bin/env bash
# Build a plugin to dist/<id>.wasm + dist/<id>.meta.json and enforce the
# contract: only "cdc" imports, size <= 768 KiB, valid manifest.
# Run from the nix dev shell (needs cargo wasm32, wasm-opt, wasm-tools).
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGIN="${1:?usage: scripts/plugin-build.sh <plugin-id>}"
DIST="dist"
WASM_SRC="target/wasm32-unknown-unknown/release/${PLUGIN}.wasm"

cargo build --release --target wasm32-unknown-unknown -p "${PLUGIN}"
mkdir -p "${DIST}"   # wasm-opt cannot create parent dirs; dist/ is gitignored
wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
  "${WASM_SRC}" -o "${DIST}/${PLUGIN}.wasm"
cp "plugins/${PLUGIN}/meta.json" "${DIST}/${PLUGIN}.meta.json"

# Check 1: only "cdc" module imports are allowed.
IMPORTS="$(wasm-tools print "${DIST}/${PLUGIN}.wasm" | grep -E '^\s*\(import' || true)"
if [ -n "${IMPORTS}" ]; then
  BAD="$(printf '%s\n' "${IMPORTS}" | grep -vE 'import "cdc"' || true)"
  if [ -n "${BAD}" ]; then
    echo "ERROR: non-cdc imports in ${DIST}/${PLUGIN}.wasm:" >&2
    printf '%s\n' "${BAD}" >&2
    exit 1
  fi
fi

# Check 2: size cap (upstream CI enforces 768 KiB = 786432 bytes).
SIZE="$(stat -c%s "${DIST}/${PLUGIN}.wasm")"
if [ "${SIZE}" -gt 786432 ]; then
  echo "ERROR: ${DIST}/${PLUGIN}.wasm is ${SIZE} bytes (> 786432)" >&2
  exit 1
fi

# Check 3: manifest validation (vendored upstream tool).
python3 references/cdc-badge-plugins/tools/validate_manifest.py "plugins/${PLUGIN}/meta.json"

echo "OK: ${DIST}/${PLUGIN}.wasm (${SIZE} bytes) + ${DIST}/${PLUGIN}.meta.json"
```

- [ ] **Step 2: Syntax check**

Run: `chmod +x scripts/plugin-build.sh && bash -n scripts/plugin-build.sh`
Expected: no output (success).

- [ ] **Step 3: Build snake and pass all checks**

Run: `nix develop -c bash -c 'bash scripts/plugin-build.sh snake'`
Expected: final line `OK: dist/snake.wasm (<N> bytes) + dist/snake.meta.json` with N ≤ 786432. Note the size for the session report.
(First run compiles the release wasm; ~1–3 min.)

- [ ] **Step 4: Commit**

```bash
git add scripts/plugin-build.sh
git commit -m "feat: plugin build script with import, size and manifest checks"
```

---

### Task 4: OS source build (clone, local patch, os-build.sh)

**Files:**
- Create: `scripts/os-build.sh`
- Create: `patches/os-platformio.patch` (generated in Step 4)

**Interfaces:**
- Consumes: Task 1 shell (`pio`, `git`); the pinned OS commit; network (one-time ~1–2 GB of version-pinned PIO artifacts + submodule fetch)
- Produces: `build/cdc-badge-os/.pio/build/cdc_badge_usb/{firmware.bin,bootloader.bin,partitions.bin}`; the idempotent patch `patches/os-platformio.patch`; `scripts/os-build.sh` usable for every future build

- [ ] **Step 1: Write the build script**

Create `scripts/os-build.sh`:

```bash
#!/usr/bin/env bash
# Build cdc-badge-os from the pinned commit.
# Hermetic: PlatformIO state lives in build/.platformio (PLATFORMIO_CORE_DIR).
# Run from the nix dev shell (nix develop): needs git and pio.
set -euo pipefail
cd "$(dirname "$0")/.."

OS_DIR="build/cdc-badge-os"
OS_COMMIT="181a24d94353e0318835a7b0801f2ce8d4937fb4"
PATCH="$(pwd)/patches/os-platformio.patch"
export PLATFORMIO_CORE_DIR="$(pwd)/build/.platformio"

if [ ! -d "${OS_DIR}/.git" ]; then
  mkdir -p build
  git clone https://github.com/krim404/cdc-badge-os.git "${OS_DIR}"
  git -C "${OS_DIR}" checkout "${OS_COMMIT}"
fi
git -C "${OS_DIR}" submodule update --init --recursive

# Local build patches (idempotent): exact framework pin, reproducible build
# flags, Linux monitor port. See patches/os-platformio.patch.
if ! git -C "${OS_DIR}" apply --check --reverse "${PATCH}"; then
  git -C "${OS_DIR}" apply "${PATCH}"
fi

# tools/pio_python_deps.py pip-installs "intelhex>=2.3" UNPINNED into the penv
# on first run; pre-install the pinned version so it skips.
PENV_PY="${PLATFORMIO_CORE_DIR}/penv/bin/python"
if [ ! -x "${PENV_PY}" ]; then
  pio --version   # first invocation creates the penv
fi
"${PENV_PY}" -m pip install --quiet --disable-pip-version-check "intelhex==2.3.0"

pio run -e cdc_badge_usb --project-dir "${OS_DIR}"
echo "Build OK: ${OS_DIR}/.pio/build/cdc_badge_usb/firmware.bin"
```

- [ ] **Step 2: Create the clone (the script would, but we need it now to generate the patch)**

```bash
mkdir -p build
git clone https://github.com/krim404/cdc-badge-os.git build/cdc-badge-os
git -C build/cdc-badge-os checkout 181a24d94353e0318835a7b0801f2ce8d4937fb4
```

Expected: checkout succeeds (commit is on the `release` branch).

- [ ] **Step 3: Make the three local edits to `build/cdc-badge-os/platformio.ini`**

1. Line 17: `    framework-espidf @ ~3.50500.0` → `    framework-espidf @ 3.50500.0` (exact pin; the `~` range would drift).
2. Delete lines 21–22: `    -D BUILD_TIME=__TIME__` and `    -D BUILD_DATE=__DATE__`. These macros are unused (verified: the only reference in the tree is platformio.ini itself), and `__TIME__/__DATE__` expand to the build timestamp, breaking byte-reproducible `firmware.bin`.
3. Delete line 49: `monitor_port = /dev/cu.usbmodem1020BA59B7481` (hardcoded macOS port; `scripts/os-flash.sh` and the runbook pass explicit ports).

- [ ] **Step 4: Generate the patch, revert the clone, verify it re-applies**

```bash
mkdir -p patches
git -C build/cdc-badge-os diff -- platformio.ini > patches/os-platformio.patch
git -C build/cdc-badge-os checkout -- platformio.ini
git -C build/cdc-badge-os apply --check "$(pwd)/patches/os-platformio.patch"
```

Expected: the `--check` succeeds (exit 0), and `patches/os-platformio.patch` contains exactly three hunks (framework pin, two deleted build flags, deleted monitor_port).

- [ ] **Step 5: Run the full build**

Run: `bash scripts/os-build.sh`
Expected (first run takes 30–60 min: submodule fetch, ~1–2 GB pinned PIO artifact download, ESP-IDF build):
- the patch is applied (clone's platformio.ini matches our edits),
- `pio run` completes,
- final line `Build OK: build/cdc-badge-os/.pio/build/cdc_badge_usb/firmware.bin`.

- [ ] **Step 6: Verify artifacts and record hashes**

```bash
ls -l build/cdc-badge-os/.pio/build/cdc_badge_usb/firmware.bin \
      build/cdc-badge-os/.pio/build/cdc_badge_usb/bootloader.bin \
      build/cdc-badge-os/.pio/build/cdc_badge_usb/partitions.bin
sha256sum build/cdc-badge-os/.pio/build/cdc_badge_usb/firmware.bin
```

Expected: all three files exist with non-trivial sizes (firmware ~3–8 MB). Record the sha256 and sizes in the session report (used by Task 6).

- [ ] **Step 7: Commit**

```bash
git add scripts/os-build.sh patches/os-platformio.patch
git commit -m "build: OS source build script with pinned clone, local patches, hermetic PIO"
```

---

### Task 5: OS flash script + on-device runbook

**Files:**
- Create: `scripts/os-flash.sh`
- Create: `docs/runbooks/badge-device.md`

**Interfaces:**
- Consumes: Task 4 build output + `pio`; badge connected over USB-C (not available this session — script is verified by syntax check only)
- Produces: one-command flash with wipe warning; the runbook that later device sessions follow

- [ ] **Step 1: Write the flash script**

Create `scripts/os-flash.sh`:

```bash
#!/usr/bin/env bash
# Flash the source-built cdc-badge-os to the badge.
# WARNING: this is a DEBUG_MODE build. Flashing it onto a badge running
# release firmware changes the build-profile byte -> FULL FACTORY WIPE
# (NVS + TROPIC01 slots). Pre-1.0 firmware can wipe all stored data on any
# flash. Confirm the badge holds no needed data first.
# Usage: scripts/os-flash.sh [PORT]   (e.g. /dev/ttyACM0; omit to auto-detect)
set -euo pipefail
cd "$(dirname "$0")/.."

OS_DIR="build/cdc-badge-os"
export PLATFORMIO_CORE_DIR="$(pwd)/build/.platformio"

if [ -n "${1:-}" ]; then
  pio run -e cdc_badge_usb --project-dir "${OS_DIR}" -t upload --upload-port "$1"
else
  pio run -e cdc_badge_usb --project-dir "${OS_DIR}" -t upload
fi
```

- [ ] **Step 2: Write the runbook**

Create `docs/runbooks/badge-device.md`:

```markdown
# CDC Badge on-device runbook

Prereq: `nix develop`, Task-built OS image in `build/cdc-badge-os/.pio/build/`,
plugin artifacts in `dist/`.

## 1. Connect and (if needed) enter download mode

Connect USB-C. The badge enumerates as `BadgeV1` (`/dev/ttyACM*` on Linux).
If it does not enumerate, or is in a boot loop:

1. Hold **Flash** (IO0).
2. Tap **Reset** (EN).
3. Release Flash.

In download mode the e-paper does not change and the badge looks dead — that is
normal. After flashing, tap Reset again to boot.

## 2. Flash the OS (factory wipe!)

    bash scripts/os-flash.sh          # or: bash scripts/os-flash.sh /dev/ttyACM0

The build-profile byte differs from release firmware, so the first boot after
flashing does a full factory wipe (NVS + used TROPIC01 slots) and takes a
while. Do not flash a badge holding needed credentials/data without a backup
first (pre-1.0: any flash can wipe everything).

## 3. Serial console

    pio device monitor -e cdc_badge_usb --project-dir build/cdc-badge-os --port /dev/ttyACM0

115200 baud. Secure serial is on: authenticate first with `AUTH <pin>`. The
first-boot default PIN is documented in the cdc-badge-os website docs
(`references/cdc-badge-os/website/` — dev/serial-commands); confirm the exact
default at execution time.

## 4. Upload a plugin

    python3 references/cdc-badge-os/tools/upload.py \
      --wasm dist/snake.wasm --meta dist/snake.meta.json --pin <pin>

Protocol: `AUTH <pin>` → `PLUGIN UPLOAD <id> <size> <crc32>` → raw byte stream
→ `OK`. Integrity is CRC-checked; authenticity is not (no signing).

## 5. Start and play

`PLUGIN START snake` over serial, or on the badge: Main menu → Plugins → Snake.
Steer with 2/4/6/8, pause with 5. High scores persist in the `plg_snake` NVS
namespace — verify they survive a plugin stop/start.

## Notes

- A **Factory Setup** flash of the OS (web flasher) wipes every installed plugin.
- `PLUGIN LIST` / `INFO <id>` / `STOP` / `DELETE <id>` manage installed plugins.
- `DEBUG` toggles verbose host_* logging; look for `PLUGIN TRAP` banners.
```

- [ ] **Step 3: Verify**

Run: `bash -n scripts/os-flash.sh && chmod +x scripts/os-flash.sh`
Expected: no output (syntax OK).

- [ ] **Step 4: Commit**

```bash
git add scripts/os-flash.sh docs/runbooks/badge-device.md
git commit -m "build: OS flash script and on-device runbook"
```

---

### Task 6: End-to-end verification + determinism spot-check

**Files:**
- None created (verification only; commit any fixes found)

**Interfaces:**
- Consumes: Tasks 1–5; the `firmware.bin` sha256 recorded in Task 4 Step 6
- Produces: session report with the hash table and artifact sizes; confidence that the pipeline is reproducible

- [ ] **Step 1: Re-run the plugin host tests**

Run: `nix develop -c bash -c 'cargo test -p snake'`
Expected: `18 passed; 0 failed`.

- [ ] **Step 2: Plugin determinism (rebuild from clean)**

```bash
nix develop -c bash -c 'bash scripts/plugin-build.sh snake && sha256sum dist/snake.wasm'
rm -rf target dist
nix develop -c bash -c 'bash scripts/plugin-build.sh snake && sha256sum dist/snake.wasm'
```

Expected: both sha256 values identical. If they differ, stop and investigate (the usual suspect is an unpinned dependency in `Cargo.lock` — ensure `Cargo.lock` is committed; see Step 5).

- [ ] **Step 3: OS determinism (clean rebuild, ~10–20 min)**

```bash
rm -rf build/cdc-badge-os/.pio/build
bash scripts/os-build.sh
sha256sum build/cdc-badge-os/.pio/build/cdc_badge_usb/firmware.bin
```

Expected: sha256 identical to the one recorded in Task 4 Step 6 (same checkout path required; nix store paths are stable). If it differs, do not silently accept — investigate and record the finding in the session report (candidates: path-dependent build-id, nondeterministic archive ordering).

- [ ] **Step 4: Confirm Cargo.lock is tracked**

Run: `git ls-files | grep -c '^Cargo.lock$'`
Expected: `1` (committed in Task 2 Step 7). If it is missing, add and commit it:

```bash
git add Cargo.lock
git commit -m "build: track Cargo.lock for reproducible plugin builds"
```

- [ ] **Step 5: Final state + session report**

Run: `git status --short` (expected: empty) and `git log --oneline main..HEAD`.
Write the session report (in chat, not a file): artifact sizes, the three
sha256 values (firmware.bin, snake.wasm ×2 builds), test results, and anything
that deviated from the plan.
