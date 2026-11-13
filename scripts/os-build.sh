#!/usr/bin/env bash
# Build cdc-badge-os from the pinned commit.
# Hermetic: PlatformIO state lives in build/.platformio (PLATFORMIO_CORE_DIR).
# Run from the nix dev shell (nix develop): needs git and pio.
set -euo pipefail
cd "$(dirname "$0")/.."

OS_DIR="build/cdc-badge-os"
OS_COMMIT="181a24d94353e0318835a7b0801f2ce8d4937fb4"
PATCH="$(pwd)/patches/os-platformio.patch"

if [ ! -d "${OS_DIR}/.git" ]; then
  mkdir -p build
  git clone https://github.com/krim404/cdc-badge-os.git "${OS_DIR}"
  git -C "${OS_DIR}" checkout "${OS_COMMIT}"
fi

# Pinned-commit guard: an existing clone may sit at a different commit (e.g.
# after a local checkout), and building it would silently break the
# pinned-commit contract. Do not auto-checkout: deliberate local edits must
# not be clobbered — rebuild from the pinned commit instead.
HEAD_COMMIT="$(git -C "${OS_DIR}" rev-parse HEAD)"
if [ "${HEAD_COMMIT}" != "${OS_COMMIT}" ]; then
  echo "os-build.sh: ${OS_DIR} is at commit ${HEAD_COMMIT}, not pinned commit ${OS_COMMIT}" >&2
  echo "os-build.sh: remove it to rebuild from the pinned commit: rm -rf ${OS_DIR}" >&2
  exit 1
fi

git -C "${OS_DIR}" submodule update --init --recursive

# Local build patches (idempotent): exact framework pin, reproducible build
# flags, Linux monitor port. See patches/os-platformio.patch.
if ! git -C "${OS_DIR}" apply --check --reverse "${PATCH}"; then
  git -C "${OS_DIR}" apply "${PATCH}"
fi

source "$(dirname "$0")/os-pio-env.sh"

pio run -e cdc_badge_usb --project-dir "${OS_DIR}"
echo "Build OK: ${OS_DIR}/.pio/build/cdc_badge_usb/firmware.bin"
