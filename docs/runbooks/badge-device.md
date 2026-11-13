# CDC Badge on-device runbook

Prereq: `nix develop`, OS image built by `scripts/os-build.sh` in
`build/cdc-badge-os/.pio/build/`, plugin artifacts in `dist/`.

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

(If §1 showed a different `/dev/ttyACM*` port, substitute it for `--port`.)

115200 baud. Secure serial is on: authenticate first with `AUTH <pin>`. The
first-boot default PIN is `123456`, documented in
`references/cdc-badge-os/website/src/content/docs/start/first-boot.md`. The
full serial command reference is at
`references/cdc-badge-os/website/src/content/docs/dev/proto/serial-commands.md`.

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
