---
type: runtime subsystem
title: "Networking for plugins: Wi-Fi, HTTP, sockets, listener"
description: What a cdc-badge-os plugin actually gets from the wifi, http, socket and net_listen capabilities — hold-counted Wi-Fi shared with prerequisites (timeout argument ignored), 4 HTTP slots with whole-body PSRAM buffering up to 1 MiB, TLS via the ESP-IDF certificate bundle and a per-origin keep-alive pool, 8 TCP/UDP sockets without TLS, an inbound listener with backlog 4, and SNTP time sync that TLS and TOTP-style plugins depend on.
tags: [networking, wifi, http, tls, sockets, sntp, time, plugins]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T21:07:57.649Z
sources:
  - id: openwiki-source-ad303c1143b6b7d7da0f6593
    resource: repo://references/cdc-badge-os/components/cdc_hal/src/Rtc.cpp
  - id: openwiki-source-9a87542c6a38fe5fdfd19645
    resource: repo://references/cdc-badge-os/components/cdc_os_ui/src/WifiHandlers.cpp
  - id: openwiki-source-4c23ee90f461b46c725d4482
    resource: repo://references/cdc-badge-os/components/plugin_manager/include/plugin_manager/host_api.h
  - id: openwiki-source-3f00bf683fd77308725c121c
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_http.cpp
  - id: openwiki-source-024e41c78b95a864b38fc45d
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_net.cpp
  - id: openwiki-source-ffa8dfffbccd5442af1f9e0e
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_socket.cpp
  - id: openwiki-source-1cf8e76e4af214efa7b3bd8f
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/host_api_wifi.cpp
generated: { by: "claude-code", at: "2026-11-12T21:07:57.649Z" }
---

# Networking for plugins: Wi-Fi, HTTP, sockets, listener

Sources: `components/plugin_manager/src/host_api_wifi.cpp`, `host_api_http.cpp`,
`host_api_socket.cpp`, `host_api_net.cpp`, `components/cdc_os_ui/src/WifiHandlers.cpp`,
`components/cdc_hal/src/Rtc.cpp`, user guide `guide/wifi-time.md`, and the
upstream skill reference `…/cdc-badge-plugin-dev/reference/connectivity.md`.
Examples: `news_feed` (HTTP + XML), `gpio_mqtt` (raw TCP MQTT), `webserver`
(listener), `home_assistant` and `matrix` (REST clients).

## Wi-Fi (`wifi`)

- **Hold-counted** (`host_api_wifi.cpp:1-14`): `host_wifi_request()` acquires a
  hold and `host_wifi_release()` drops it. `WifiHandlers` keeps the radio up
  while any holder (plugin code, prerequisites, the user's own Wi-Fi intent)
  needs it.
- **Prerequisite shortcut:** declaring the `wifi_connected` prerequisite takes a
  hold *for* the plugin before `plugin_on_enter`, and releases it on exit.
- **The `timeout_ms` argument is ignored** (`host_api_wifi.cpp:38-44`). The
  connect timeout is the global setting (`WIFI TIMEOUT`, 3–60 s). The call
  returns `HOST_OK` or `HOST_ERR_TIMEOUT`.
- **Info and scanning:** `host_wifi_is_connected/ssid/ip/rssi/mac`, and
  `host_wifi_start_scan` → `scan_done` → `scan_results`.
- Credentials are configured by the user (Settings or serial `WIFI CONNECT`).
  Plugins can't set them.
- **Power:** Wi-Fi listening costs about 95 mA. A held connection plus
  `prevent_sleep` keeps the badge awake (see [power](../hardware/power-and-charging.md)).

## HTTP(S) (`http`)

`esp_http_client` wrapper (`host_api_http.cpp:1-17`, `:71-73`):

| Property | Value |
|---|---|
| Concurrent requests | **4** slots |
| Default timeout | 5000 ms (per request, via `host_http_open(method, url, timeout_ms)`) |
| Body handling | The **whole response is buffered in PSRAM** during `host_http_perform`, up to **1 MiB, then silently truncated**. `host_http_read_chunk` hands it out sequentially: chunked, but not streamed, and **one-way** (no re-read). |
| Headers | Request headers via `host_http_set_header`. **Response `Content-Type` is not exposed**; only status and content length. |
| TLS | `crt_bundle_attach = esp_crt_bundle_attach` (`:195`): server certificates are verified against the ESP-IDF CA bundle. No client certificates, no custom pinning API. |
| Connection reuse | Keep-alive **per-origin pool**. A slot borrows a pooled client or, when the pool is full, owns a transient one. Headers are cleared on close. |

Practical consequences:

- Large downloads (images, feeds) count against the 1 MiB cap and PSRAM.
- TLS needs a correct clock (see time, below).

## Sockets (`socket`)

- `host_socket_open(HOST_SOCK_TCP | HOST_SOCK_UDP, host, port, timeout_ms)`,
  `write`, `read`, `close`.
- **8 slots**, 5 s default timeout (`host_api_socket.cpp:36-37`).
- **Plain TCP/UDP: no TLS on raw sockets.** Encrypt at the application layer
  (e.g. Noise) or use HTTPS.

## Inbound listener (`net_listen`)

- `host_net_listen(port, action_id)` binds and listens with **backlog 4**
  (`host_api_net.cpp:66-69`). `host_net_accept` returns a connection id, and
  `host_net_close` closes the listener.
- Accepted connections use the socket read/write/close calls. Those are allowed
  with `net_listen` even without `socket` (`host_api_socket.cpp:54-61`).
- Example: `webserver` serves its vFAT folder over HTTP on port 80.
- **There's no TLS server.** Anything listening is cleartext on the local network.

## Time

- **SNTP** starts on Wi-Fi connect with the servers **`time.krim.dev`** (the OS
  author's server, tried first), `pool.ntp.org`, then `time.google.com`
  (`WifiHandlers.cpp:318-330`), in smooth-slew mode.
- It syncs **only when the RTC is unset** (`:380-387`).
- **The RTC survives light sleep but not deep sleep or power-off**, and time is
  deliberately not persisted (`Rtc.cpp` header). After a deep sleep, the clock
  is unknown until Wi-Fi sync or serial `SET_TIME` / `SET_DATE`, which need **no
  AUTH**.
- **Check `host_is_time_set()`** before TLS, TOTP-like logic or timestamps.
  Use the `time_synced` prerequisite to make the host do it.
- **Privacy:** every badge contacts `time.krim.dev` on Wi-Fi connect.

## Security notes for badge-cdc

- Server authentication over HTTPS relies on the public CA bundle. For
  cypherpunk-grade guarantees, add application-level signatures or pinned keys
  and verify them in the plugin.
- Raw sockets and the listener are unencrypted, and the clock can be set by
  anyone with serial access. Never derive security decisions from wall-clock
  time alone.
