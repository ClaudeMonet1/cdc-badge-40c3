---
type: runtime subsystem
title: Canvas, surfaces, sprites and animation
description: How a plugin draws custom screens on cdc-badge-os — the CanvasView retained display list (128 commands, text/bitmap/sprite arenas), named elements for cheap animation, inline widgets, fonts, off-screen surfaces, sprites, host-driven tweens capped at 5 fps, refresh policies and the view/modal stack limits.
tags: [canvas, ui, drawing, animation, sprites, surfaces, e-paper, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-1e8beb29d1cfd29debf7882a
    resource: repo://references/cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/canvas.md
  - id: openwiki-source-80ce5e2ae51351b729556943
    resource: repo://references/cdc-badge-os/components/cdc_views/include/cdc_views/CanvasView.h
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-fe0ff4a6664e2ba4afa0f984
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_surface.cpp
  - id: openwiki-source-c561d477c3b54260e9f35fe3
    resource: repo://references/cdc-badge-os/website/src/content/docs/dev/ui-framework.md
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Canvas, surfaces, sprites and animation

Sources: `components/cdc_views/include/cdc_views/CanvasView.h`,
`cdc_views/src/CanvasView.cpp` and `CanvasAnim.cpp`,
`plugin_manager/src/host_api_canvas.cpp` and `host_api_surface.cpp`, the
canvas/sprite/anim groups of `host_api.h`, the upstream skill reference
`cdc-badge-development/.claude/skills/cdc-badge-plugin-dev/reference/canvas.md`,
and the example `cdc-badge-plugins/examples/canvas_demo` (which walks through
every feature).

The canvas is the main way to draw custom screens **without** the
`display_lowlevel` capability. Choosing between prebuilt views, canvas and
low-level drawing is covered in [lifecycle and UI](lifecycle-events-and-ui.md);
panel physics are in [display](../hardware/display-and-graphics.md).

## Model: a retained display list

```
plugin_on_enter:  host_view_canvas_push(title, key_action, widget_action)
on change:        host_view_canvas_clear()  → draw_* calls (recorded) → host_view_canvas_commit(full?)
animation:        elem_set_offset / elem_show / host_anim_* → commit (replay only)
```

- Draw calls are **recorded, not drawn**. On commit, the view stack replays the
  list onto the framebuffer after clearing, then flushes the e-paper.
- `host_view_canvas_get_body_size` gives the drawable body below the optional
  header (empty title means no header bar). The footer hint is set with
  `set_footer`.
- Pushing a canvas uses a **FAST** first refresh, and later commits are PARTIAL
  unless you ask for FULL. The refresh escalation chain still applies.

### Hard limits (`CanvasView.h:41-63`)

| Resource | Limit |
|---|---|
| Recorded draw commands | **128** (`MAX_CMDS`); the upstream skill doc still says 96 |
| Text arena | 2 KiB |
| Bitmap ("blob") arena | 8 KiB (one full-body 1-bit bitmap) |
| Sprite arena | 64 KiB, allocated lazily in PSRAM |
| Widgets | 8 |
| Elements | 16 |
| Text widget length | 256 |
| Sprites per canvas / frames per sprite | 8 / 32 (`host_api.h:2417-2419`) |
| Concurrent tweens | 16 (`HOST_ANIM_MAX`) |
| Animation rate | **4 fps default, 5 fps max**: the partial waveform (~200–300 ms) bounds the panel |

Running out of space makes calls fail rather than grow, so check return codes.

## Drawing primitives and fonts

- **Shapes:** pixel, line, h/v-line, rect, round-rect, circle, triangle (filled
  or outline), bitmap (packed 1-bpp, MSB-first, set bit = black).
- **Ink:** `set_shade` (dither patterns for grey) and `set_ink` (normal or
  inverted).
- **Text:** `draw_text`, `draw_text_aligned`, `text_pick_font_that_fits`, and
  a `marquee` for scrolling text.
- **Fonts** (`host_api.h:1234-1239`):
  - `HOST_FONT_BUILTIN` 6×8: full CP437, umlauts and symbols;
  - FreeMonoBold 9 pt and 12 pt: Latin-1;
  - FreeMonoBold 18 pt and 24 pt: **ASCII only**.

  Text is passed as UTF-8, and the host converts it. Unicode symbols that have a
  CP437 code (♥, →, box drawing…) render in the built-in font.

## Elements: animation without redrawing

- `elem_begin(id)` … draw … `elem_end()` tags draw calls into a named element
  (ids are non-zero and plugin-chosen).
- Afterwards, `elem_set_offset` / `elem_move` / `elem_show` / `elem_remove` /
  `elem_set_z` change only the replay. A frame update is then a couple of calls
  plus `commit`.
- To change an element's *content*, remove it, then begin it again and redraw.
  The arena compacts.
- `clear()` drops all elements, widgets and tweens.
  `clear_ex(HOST_CANVAS_CLEAR_KEEP_SPRITES)` keeps sprite sheets but stops
  their playback.

## Widgets: host-driven input

- `add_slider`, `add_text`, `add_button` create inline widgets.
- The host routes keys to the focused widget. Events arrive at
  `widget_action_id` with `idx` = the widget id and `user_data` =
  `CANVAS_WIDGET_CHANGED` / `COMMITTED` / `CANCELLED`.
- Keys a widget doesn't consume go to `key_action_id` as ASCII codes.
- Helpers: `set/get_value`, `set/get_text`, `set/get_focus`, `set_key_repeat`,
  `set_long_press_action`.

## Tweens, sprites and surfaces

| Feature | What it gives you |
|---|---|
| **Tweens** (`host_anim_start/cancel/pause/state/active_count/blink`) | The host animates an element's offset with easing (linear, quad, cubic, overshoot, bounce, step, elastic) and fires a done action. `set_anim_policy`: `AUTO` (light partials while running + one FAST cleanup after 1 s idle) or `LIGHT` (no automatic cleanup). |
| **Sprites** (`host_sprite_*`) | Frame sheets from bitmaps, surfaces or decoded images, with mask, flags, scale, per-frame durations and play/stop. Drawn into the canvas with `view_canvas_draw_sprite`. |
| **Surfaces** (`host_surface_*`) | Off-screen 1-bit images up to **1024×2048 px**, **2 per plugin** and **8 badge-wide** (`host_api_surface.cpp:28-50`). The same drawing primitives plus `measure_text`. Export packed rows (`surface_export`) or grayscale JPEG (`surface_export_jpg`) for printing or sending. |
| QR / image | `host_qr_render_bitmap` and `host_image_render` produce 1-bpp bitmaps ready for `draw_bitmap` |

## View stack constraints

- The `ViewStack` has max depth 20.
- The **modal stack holds at most 4, and the oldest is dropped** when full
  (`ui-framework.md:98-99`).
- An exclusive lock (`host_ui_acquire_exclusive`) blocks other pushes. FIDO2
  prompts use it.
- `EVENT_DISPLAY_REFRESH` (1 = a FAST/FULL refresh started, 0 = ended) lets
  games pause while the panel is unreadable.

## Patterns for badge-cdc

- Build static chrome once and animate with elements and tweens. Don't redraw
  every tick: `plugin_on_tick` runs at 20 Hz, but the panel manages about 5.
- Fingerprints and QR codes for a key-exchange UI work well. The built-in font
  shows the full CP437 range, and `host_qr_render_bitmap` sizes QR codes for the
  296×128 panel.
- Request a FULL or FAST commit after big screen changes to clear ghosting.
