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
