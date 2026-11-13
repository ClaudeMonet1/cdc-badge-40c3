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
mkdir -p "${DIST}"
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
