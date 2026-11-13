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
