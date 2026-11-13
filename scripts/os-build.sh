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

# Build environment bootstrap (idempotent). PlatformIO 6.2.0 runs the build in
# a subprocess of the bare interpreter, whose sys.path lacks the nix store
# site dirs (they are added only by the pio entry-point wrapper), so
# `import click` fails in platformio/builder/main.py. The espressif32 espidf
# framework then strips PYTHONPATH from the environment, so esptool children
# (bootloader/firmware .bin generation via $PYTHONEXE) lose it too and fail
# on `import serial`. Fix, all derived at runtime (no hardcoded store paths):
#  - create the PIO penv venv with the same interpreter that runs pio, and pin
#    intelhex==2.3.0 into it; tools/pio_python_deps.py pip-installs
#    "intelhex>=2.3" UNPINNED on first run when it is missing, so the pre
#    install makes it skip (pinned version, reproducible build);
#  - export PYTHONPATH = nix store site dirs + penv for the SCons process;
#  - point PYTHONEXEPATH at a wrapper that re-adds those dirs for every child
#    python it launches (PIO honors PYTHONEXEPATH for $PYTHONEXE).
# The store site dirs come from the nix pio wrapper's site.addsitedir list.
PIO_WRAPPED="$(dirname "$(command -v pio)")/.pio-wrapped"
if [ ! -f "${PIO_WRAPPED}" ]; then
  echo "os-build.sh: nix pio wrapper not found at ${PIO_WRAPPED} (run inside 'nix develop')" >&2
  exit 1
fi
REAL_PY="$(head -n1 "${PIO_WRAPPED}" | sed 's/^#!//')"
SITE_DIRS="$(
  "${REAL_PY}" - "${PIO_WRAPPED}" <<'PYEOF'
import ast, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"addsitedir\(p, k\), \[(.*?)\]", src, re.S)
if not m:
    sys.exit("os-build.sh: site dir list not found in %s" % sys.argv[1])
print(":".join(ast.literal_eval("[" + m.group(1) + "]")))
PYEOF
)"

PENV_PY="${PLATFORMIO_CORE_DIR}/penv/bin/python"
if [ ! -x "${PENV_PY}" ]; then
  "${REAL_PY}" -m venv "${PLATFORMIO_CORE_DIR}/penv"
fi
"${PENV_PY}" -m pip install --quiet --disable-pip-version-check "intelhex==2.3.0"

PENV_SITE="$("${PENV_PY}" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
PYBOOT="${PLATFORMIO_CORE_DIR}/py-bootstrap"
mkdir -p "${PYBOOT}"
cat > "${PYBOOT}/pio-python" <<EOF
#!/bin/bash
export PYTHONPATH="${SITE_DIRS}:${PENV_SITE}\${PYTHONPATH:+:\${PYTHONPATH}}"
exec "${REAL_PY}" "\$@"
EOF
chmod +x "${PYBOOT}/pio-python"
export PYTHONPATH="${SITE_DIRS}:${PENV_SITE}${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONEXEPATH="${PYBOOT}/pio-python"

pio run -e cdc_badge_usb --project-dir "${OS_DIR}"
echo "Build OK: ${OS_DIR}/.pio/build/cdc_badge_usb/firmware.bin"
