# Files

- [Example and production plugins](example-plugins.md) - Catalogue of every Rust plugin in cdc-badge-plugins (examples/ and plugins/) plus the starter plugin and SDK template — what each one demonstrates, the capabilities and prerequisites it declares, its size, and which to copy as a template for which kind of application.
- [Rust plugin SDK (cdc-badge-plugin crate)](rust-sdk.md) - The cdc-badge-plugin crate (v0.8.0, GPL-3.0) that wraps the cdc-badge-os host API for Rust — no_std + alloc with a dlmalloc global allocator, the ffi layer and build.rs constant generation from host_api.h, the unified Error/Result type, the plugin_main! macro and optional panic handler, module map, crate setup for wasm32-unknown-unknown, and practical idioms and pitfalls for writing our own plugin.
