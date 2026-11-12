---
type: os subsystem
title: USB stack and smartcard (CCID)
description: How cdc-badge-os presents itself over USB — a TinyUSB composite device (CDC serial plus optional FIDO HID, keyboard HID, OTP HID, CCID and MSC) managed by UsbServiceManager under the ESP32-S3's 4-IN/6-OUT endpoint budget, the VID/PID identities it switches between (Gemalto for libccid, Espressif, OnlyKey), and the CCID applet router hosting OpenPGP, OATH and PIV.
tags: [usb, tinyusb, ccid, smartcard, hid, msc, endpoints, os]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-04abe07980dc7256739c3dc4
    resource: repo://references/cdc-badge-os/components/cdc_core/src/UsbServiceManager.cpp
  - id: openwiki-source-36a1f1469f7116e11fdb8bde
    resource: repo://references/cdc-badge-os/components/cdc_scard/include/cdc_scard/applet.h
  - id: openwiki-source-858f2fa86bcce31323503939
    resource: repo://references/cdc-badge-os/components/usb_badge/include/usb_badge/usb_endpoint_budget.h
  - id: openwiki-source-0da5c49760189c86192c1021
    resource: repo://references/cdc-badge-os/components/usb_badge/usb_descriptors.h
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# USB stack and smartcard (CCID)

Sources: `components/usb_badge/` (descriptors, endpoint budget),
`components/cdc_core/src/UsbManager.cpp` and `UsbServiceManager.cpp`,
`components/cdc_scard/`, `website/src/content/docs/dev/proto/otp-hid-cr.md`,
`dev/proto/openpgp-ccid.md`. Host tests: `test/host/test_usb_budget`,
`test_usb_service_manager`.

Plugins **can't add USB interfaces**. The only plugin USB surface is
`host_usb_cdc_write` (`usb_cdc` capability), which writes to the serial
endpoint. This page explains the environment a plugin shares the USB port with.

## Composite device

The device is CDC-ACM serial (always present) plus optional interfaces
contributed by modules:

| Interface | Provided by | Default |
|---|---|---|
| CDC-ACM serial console | `usb_badge` | always |
| FIDO HID (CTAPHID) | `mod_fido2` | on |
| CCID smartcard | `cdc_scard` (OpenPGP, OATH, PIV applets) | on |
| Keyboard HID | `mod_usbhid` **or** `mod_otphid` (one Keyboard slot) | off |
| Mass storage | `mod_msc` | off |

Bluetooth HID (`mod_blehid`) uses no USB interface.

## Endpoint budget

- The ESP32-S3 USB-OTG has a non-control budget of **4 IN and 6 OUT**
  endpoints (`usb_endpoint_budget.h:10-17`). The CDC-ACM interface permanently
  costs 2 IN.
- `UsbServiceManager` checks every module start against the remaining budget.
  If it doesn't fit, the toggle returns `BudgetFull` (`UsbServiceManager.cpp:147-165`)
  and the Modules list shows a failure.
- In practice, enabling MSC or a USB keyboard may require disabling another USB
  service.

## USB identities

`usb_descriptors.h:9-20`:

| Situation | VID:PID | Why |
|---|---|---|
| CCID enabled | `08E6:4433` (Gemalto GemPC433) | whitelisted by libccid/pcscd, the same trick pico-openpgp and Rugart use |
| Otherwise | `303A:BADE` (Espressif / "CDC Badge") | |
| `mod_otphid` active | `1D50:60FC` (OnlyKey) | recognised by KeePassXC and ykinfo for HMAC-SHA1 challenge-response |

The device enumerates as `BadgeV1`, and re-enumerates whenever the interface
set changes (MSC on/off, keyboard start).

## CCID applet router (`cdc_scard`)

- An ISO 7816 multi-applet router with up to **4 applets** (`applet.h:21`).
- Each applet registers an AID prefix, an APDU handler and a `deselect` hook
  that wipes PIN and session state.
- **Registered applets:**
  - **OpenPGP** (default selected): see the [GPG review](security/gpg-openpgp-module.md);
  - **OATH** (ykman-compatible), from `mod_2fa`;
  - **PIV**, from `mod_piv`. See [credential modules](modules/credential-modules.md).
- The USB keyboard can temporarily borrow the CCID slot during auto-type
  (`UsbManager.h` comment).

## Interplay to remember

- `mod_otphid` and `mod_usbhid` compete for the single Keyboard HID slot, so
  they're mutually exclusive.
- The serial console keeps working while MSC is mounted.
- Plugin uploads still fail while a host has the MSC drive mounted (see
  [storage tools](storage-tools.md)).
- **Charger detection:** the OS disables the BQ25895's D+/D- detection
  instead of yielding the USB bus, so charging stays at USB 2.0 default current
  (see [power](../hardware/power-and-charging.md)).
- **USB host / OTG mode** is unsupported by the hardware (see
  [board overview](../hardware/board-overview.md)).
