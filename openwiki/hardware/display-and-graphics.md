---
type: hardware subsystem
title: E-paper display and graphics stack
description: The GDEY029T94-FL03 296x128 monochrome e-paper (SSD1680) and frontlight, how the vendor firmware drives it with GxEPD2 + Adafruit GFX, how cdc-badge-os drives it with CalEPD and a PARTIAL→FAST→FULL refresh escalation, and what that means for plugin rendering.
tags: [display, e-paper, ssd1680, gxepd2, adafruit-gfx, calepd, refresh, fonts]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-1ec803e44a7d0822cf17f757
    resource: repo://references/Adafruit-GFX-Library/src/Adafruit_GFX.h
  - id: openwiki-source-fc38313e8e0fdcb433492026
    resource: repo://references/Adafruit-GFX-Library/src/gfxfont.h
  - id: openwiki-source-72c9ac63f5e59b7aed1a202e
    resource: repo://references/cdc-badge-hardware/docs/design-choices.md
  - id: openwiki-source-e5cb86e040b32ac246cc1c5f
    resource: repo://references/cdc-badge-nametag/lib/cdc-badge/display.cpp
  - id: openwiki-source-9b1eaa02194157f882b92ba1
    resource: repo://references/cdc-badge-os/components/cdc_core/include/cdc_core/feature_flags.h
  - id: openwiki-source-76547c606a2107fc42240525
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/EpaperDisplay.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-3ba5f4d65d6a3e32f3d568a7
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0010-cp437-display-pipeline.md
  - id: openwiki-source-d0c058b2a3d0a51156df970b
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/adr/0014-epaper-refresh-escalation.md
  - id: openwiki-source-36fa94fb82be57b5237f36c0
    resource: repo://references/GxEPD2/README.md
  - id: openwiki-source-efe37836f53b3afe06548dae
    resource: repo://references/GxEPD2/src/epd/GxEPD2_290_T94_V2.h
  - id: openwiki-source-57e22bfc4eae802a22cb47eb
    resource: repo://references/GxEPD2/src/gdey/GxEPD2_290_GDEY029T94.h
  - id: openwiki-source-f7261b16592f6414a6eb196f
    resource: repo://references/GxEPD2/src/GxEPD2_BW.h
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# E-paper display and graphics stack

## The panel

| Property | Value | Source |
|---|---|---|
| Panel | Good Display **GDEY029T94-FL03** (2.9", black/white, bonded frontlight) | hardware design-choices |
| Controller | **SSD1680** | GxEPD2 driver headers |
| Native resolution | 128 × 296 (portrait); used as **296 × 128 landscape** by both firmwares | GxEPD2, cdc-badge-os `EpaperDisplay.cpp` |
| Interface | SPI shared with the TROPIC01, plus CS, DC, RST, BUSY GPIOs | see [pin map](pin-map-and-buses.md) |
| Endurance | Rated 1,000,000 refreshes or 5 years | ADR-0014 |
| Frontlight | LEDC PWM, 10-bit (0–1023), 10 kHz, through a Si1308EDL MOSFET | design-choices, `EpaperDisplay.cpp` |

E-paper retains its image without power and only changes on an explicit refresh.
A refresh is slow and visible, so every software layer above the panel is built
around *when* and *how* to refresh, not around frame rate.

### Refresh waveforms

| Mode | Behaviour | Typical time |
|---|---|---|
| FULL | Multi-flash OTP waveform; clears all ghosting and DC-balances the film | ~2 s (GxEPD2 lists 1750 ms for GDEY029T94) |
| FAST | Single flash (loaded via a temperature-register override); clears most ghosting, not fully DC-balanced | ~1 s |
| PARTIAL | No flash; accumulates ghosting | ~0.4 s (GxEPD2 GDEY029T94) |

## Vendor firmware: GxEPD2 + Adafruit GFX

The vendor nametag firmware (`references/cdc-badge-nametag/lib/cdc-badge/display.cpp`)
is the simplest working example of driving the panel:

- It instantiates `GxEPD2_BW<GxEPD2_290_T94_V2, GxEPD2_290_T94_V2::HEIGHT>` with
  the CS/DC/RST/BUSY pins. Note that **this is not the `GxEPD2_290_GDEY029T94`
  class** that GxEPD2 provides for this exact panel: `GxEPD2_290_T94_V2` targets
  the GDEM029T94 / Waveshare 2.9" V2 (same SSD1680 controller, same 128×296
  geometry, partial-update waveform written to registers, slower listed timings
  4100 ms full / 750 ms partial). Both work with the SSD1680; the dedicated
  `gdey/GxEPD2_290_GDEY029T94` class has the panel-specific timings.
- `display.init(115200, true, 20, false, SPI_Bus, SPISettings(4000000, MSBFIRST, SPI_MODE0))`
  reuses the already-initialised shared SPI bus at 4 MHz, mode 0.
- `setRotation(1)` gives the landscape 296×128 orientation.
- It sets a full-screen *partial window* to avoid the flashing of full refreshes
  and draws with GxEPD2's paged loop (`firstPage()` / `do { ... } while (nextPage())`).
- Text uses Adafruit GFX fonts `FreeMonoBold9pt7b`, `12pt7b`, `18pt7b`.
- Frontlight: Arduino `ledcSetup` / `ledcAttachPin` on channel 0, 10-bit.

### GxEPD2 model

`GxEPD2_BW<Driver, page_height>` is an `Adafruit_GFX` subclass holding a 1-bit
buffer of `WIDTH × page_height` pixels. Passing the full `HEIGHT` makes it a
single-page full framebuffer (296×128/8 = 4736 bytes). Pixels are packed MSB-first
(`1 << (7 - x % 8)`), white = bit set. `display()` writes the buffer with either a
full or partial update depending on whether a partial window is active.

### Adafruit GFX model

`Adafruit_GFX` (`references/Adafruit-GFX-Library/src/Adafruit_GFX.h`) is the
drawing layer under both GxEPD2 and the OS's CalEPD: a subclass only has to
implement `drawPixel()`, and gets lines, rectangles, circles, triangles, rounded
rectangles, bitmaps and text for free. Fonts are `GFXfont` structs
(`gfxfont.h`): a concatenated 1-bit glyph bitmap plus a `GFXglyph` table
(offset, size, `xAdvance`, offsets) covering a contiguous `first..last`
code range. Without a custom font the classic built-in 6×8 fixed font is used;
it contains the full CP437 set, which is why the OS treats CP437 as its internal
text encoding.

## cdc-badge-os: CalEPD and the refresh escalation chain

The OS does not use GxEPD2. `references/cdc-badge-os/components/cdc_hal/src/EpaperDisplay.cpp`
wraps **CalEPD**'s `Gdey029T94` driver (git submodule `martinberlin/CalEPD`, not
vendored) and an ESP-IDF port of Adafruit GFX (`martinberlin/Adafruit-GFX-Library-ESP-IDF`,
also not vendored). It runs at 296×128, with a default backlight of 512/1023
that is persisted in NVS namespace `display`.

### Concurrency

- A dedicated **render task** handles asynchronous `flush(mode)` requests. If a
  request is already pending, the requests **coalesce** and the strongest mode wins
  (FULL > FAST > PARTIAL > PARTIAL_LIGHT).
- `flushSync(mode)` drives the panel directly. The plugin tick task can use it,
  so a **panel mutex** serialises every SSD1680 transfer (the driver is not
  reentrant). A separate mutex guards the backlight state.

### Escalation (ADR-0009, ADR-0014)

Every ordinary render requests PARTIAL. `resolveRefresh()` escalates centrally:

1. After `FEATURE_EPD_MAX_PARTIALS_BEFORE_FAST` (default **50**) consecutive
   PARTIALs, the next refresh becomes FAST.
2. After `FEATURE_EPD_MAX_FASTS_BEFORE_FULL` (default **10**) FASTs, the next
   refresh becomes FULL. A FAST never resets the FULL counter.
3. A FULL resets both counters.
4. `PARTIAL_LIGHT` (e.g. the lock-screen clock) is **never promoted** and doesn't
   count toward either threshold.
5. If `FEATURE_EPD_FAST_REFRESH=0`, FAST is mapped to FULL.

The thresholds are build-time flags in `cdc_core/feature_flags.h`. Some paths
always use FULL regardless: the first boot render, lock/deep-sleep, and lockdown.
A long press on key **5** forces a manual FULL refresh
(`FEATURE_EPD_LONGPRESS_FULL_REFRESH`).

### Text encoding (ADR-0010)

Internally, on-screen text is **CP437**. CalEPD's `print(std::string)` assumes
UTF-8 and corrupts CP437 bytes, so OS views draw text through
`cdc::ui::render::printText` / `drawText`. The i18n loader converts UTF-8 to
CP437. Plugins are insulated from this: the plugin host API takes **UTF-8** and
converts for whichever font is active.

## What plugins get

Plugins never touch SPI or the panel. They draw through host functions (full
table in [Host API reference](../plugin-runtime/host-api-reference.md); view
semantics in [Plugin lifecycle, events and UI](../plugin-runtime/lifecycle-events-and-ui.md)):

- **Views / canvas** (no special capability): the OS view stack renders and picks
  the refresh. Canvas text uses five fonts: `HOST_FONT_BUILTIN` (6×8, CP437
  umlauts), FreeMonoBold 9 pt and 12 pt (Latin-1), and FreeMonoBold 18 pt and
  24 pt (ASCII only).
- **Low-level GFX** (`display_lowlevel` manifest capability): `host_display_width/height`,
  `clear`, `draw_pixel/line/rect/fill_rect/text`, then
  `host_display_flush(refresh_mode)` with **0 = FULL, 1 = PARTIAL, 2 = FAST**
  (unknown values behave like FULL). `host_display_is_busy()` reports an
  in-progress refresh. A PARTIAL from a plugin still goes through the escalation
  chain.
- **Surfaces**: off-screen bitmaps (`host_surface_*`) with shading, sprites,
  bitmaps, text measurement and PNG/JPEG export, composited into views.
- **Backlight**: `host_display_set_backlight(0..1023)` is applied live, is not
  persisted, and is **not** gated on `display_lowlevel`.

### Design consequences for a Rust plugin

- Budget refreshes rather than frames. Expect ~0.4 s per partial and ~1–2 s
  whenever escalation kicks in. Animations (e.g. `name_badge`, `snake` in
  [example plugins](../plugin-sdk/example-plugins.md)) must tolerate this.
- Request FAST or FULL explicitly after large content changes to clear ghosting,
  instead of relying on the escalation counters.
- Pass UTF-8 strings to the host. Don't pre-encode CP437.
