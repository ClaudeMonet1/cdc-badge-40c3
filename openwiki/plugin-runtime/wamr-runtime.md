---
type: runtime internals
title: WAMR plugin runtime
description: How cdc-badge-os embeds the WebAssembly Micro Runtime — build features (fast interpreter, AOT compiled but rejected, ref-types, bulk memory, no WASI), the PSRAM allocator, how a plugin binary is loaded and instantiated (64 KiB stacks, heap 0 for Rust), per-call instruction metering, trap semantics, and the concrete constraints this puts on Rust wasm32 output.
tags: [wamr, wasm, runtime, psram, memory, stack, traps, rust, wasm32]
verified:
  - by: openwiki/0.5.0
    at: 2026-11-12T17:37:01.155Z
sources:
  - id: openwiki-source-db8c17621ce0dafcf11e977d
    resource: repo://references/cdc-badge-os/components/plugin_manager/src/Plugin.cpp
  - id: openwiki-source-e895530978a4cd86ad30e138
    resource: repo://references/cdc-badge-os/components/wamr_runtime/CMakeLists.txt
  - id: openwiki-source-e238f17cc7d858f1bfc24969
    resource: repo://references/cdc-badge-os/components/wamr_runtime/Kconfig
  - id: openwiki-source-673280155c3be387d0df9b0b
    resource: repo://references/cdc-badge-os/components/wamr_runtime/README.md
  - id: openwiki-source-2bd93e707e6064446d1461a2
    resource: repo://references/cdc-badge-os/components/wamr_runtime/src/wamr_psram_alloc.c
  - id: openwiki-source-2d4749bf962c71a4f51a720d
    resource: repo://references/cdc-badge-os/components/wamr_runtime/src/Wamr.cpp
  - id: openwiki-source-ec501a1360d6ab5d28addc31
    resource: repo://references/cdc-badge-plugins/.cargo/config.toml
  - id: openwiki-source-cf2c640b5377ee55fbec6864
    resource: repo://references/cdc-badge-plugins/plugins/matrix/build.rs
  - id: openwiki-source-4d6f7aef80a4a50a2b6b9010
    resource: repo://references/cdc-badge-plugins/rust-toolchain.toml
generated: { by: "claude-code", at: "2026-11-12T17:37:01.155Z" }
---

# WAMR plugin runtime

Two components implement the sandbox: `components/wamr_runtime` (WAMR packaged
for ESP-IDF) and `components/plugin_manager` (loading, scheduling, host API).
The WAMR sources come from a git submodule that is not vendored here (see
[repository and references](../overview/repository-and-references.md)), so this
page covers how the OS configures and drives WAMR.

## Build configuration (`wamr_runtime/CMakeLists.txt`)

| Option | Value | Meaning for us |
|---|---|---|
| Platform / target | `esp-idf` / `XTENSA` | |
| `WAMR_BUILD_INTERP` + `FAST_INTERP` | 1 / 1 | **Fast interpreter**: bytecode is pre-compiled to an internal format at load |
| `WAMR_BUILD_AOT` | 1 | Compiled in, but plugins in AOT format are **rejected** while `FEATURE_PLUGIN_AOT=0` (the default) |
| `WAMR_BUILD_JIT` | 0 | |
| `WAMR_BUILD_LIBC_BUILTIN` / `LIBC_WASI` | 1 / 0 | **No WASI**: target `wasm32-unknown-unknown`, not `wasm32-wasip1`. No filesystem, clock or env imports. |
| `WAMR_BUILD_REF_TYPES` / `BULK_MEMORY` | 1 / 1 | Modern rustc output (`memory.copy/fill`, reference types) is accepted |
| `MULTI_MODULE`, `SHARED_MEMORY`, `LIB_PTHREAD` | 0 | No threads, no atomics-based sharing, single module |
| `MINI_LOADER` | 0 | Full validating loader |
| `INSTRUCTION_METERING` | 1 | Enables the per-call budget below |

`Wamr.cpp` calls `wasm_runtime_full_init` once with `Alloc_With_Allocator`
hooks from `wamr_psram_alloc.c`. **Every** WAMR allocation (runtime structures,
module bytecode, linear memory, stacks) goes to
`heap_caps_*(MALLOC_CAP_SPIRAM)`, so the runtime never touches internal DRAM
(ADR-0001). An enlarge-memory error callback logs the reason and the PSRAM state
when `memory.grow` fails. That matters because a Rust guest that hits OOM traps
with a bare `unreachable`.

`wamr_runtime/Kconfig` defines `WAMR_PSRAM_LINEAR_MEMORY_KB_DEFAULT` (128) and
`WAMR_PSRAM_OPERAND_STACK_KB` (16). In this snapshot **no source reads them**:
the sizes that apply are hard-coded in `Plugin.cpp`, below.

## Loading a plugin (`plugin_manager/src/Plugin.cpp`)

1. Read `/vfat/system/<id>.wasm` entirely into a PSRAM buffer.
2. If `FEATURE_PLUGIN_AOT` is off, reject any file that is not
   `Wasm_Module_Bytecode`, whatever its name.
3. `wasm_runtime_load(...)`. Validation errors are logged.
4. `wasm_runtime_instantiate(module, stack_bytes = 64 KiB, heap_bytes = 0)`.
   - **`heap_bytes = 0` is mandatory for Rust.** A non-zero value makes WAMR
     take over `__heap_base` for its own allocator, which collides with Rust's
     allocator growing memory via `memory.grow`.
   - The manifest's `linear_memory_kb` is **not** used for sizing (it is
     explicitly `(void)`-ed). The module's own memory section decides the initial
     and maximum size.
5. `wasm_runtime_create_exec_env(inst, 64 KiB)`: the WAMR operand and frame
   stack.
6. `PluginManager` checks the required exports (see
   [lifecycle](lifecycle-events-and-ui.md)), validates the manifest
   ([capabilities](manifest-and-capabilities.md)), and registers natives once
   under module `"cdc"` ([host API](host-api-reference.md)).

Unloading reverses this through RAII: exec env → instance → module → bytecode.

## Calling into a plugin

`Plugin::callI(name, args, &ret)`:

- passes up to 8 `i32` arguments (64-bit values such as `uptime_ms` are split
  into lo/hi);
- sets the *active plugin* pointer, which host functions use to find the caller's
  manifest, namespace and capabilities;
- resets the **instruction budget to 500,000,000** before each call
  (`kInstrLimit`). A runaway loop traps within a few seconds of tick-task time
  instead of hanging;
- logs a missing optional export once, then skips it;
- on failure records the WAMR exception text (`last_trap_`) and clears the
  exception. `PluginManager::handleTrap` then force-unloads the plugin.

All calls run on the `plg_tick` task or the UI and main task, under one recursive
call mutex. See [lifecycle](lifecycle-events-and-ui.md#threading-and-scheduling).

## Memory picture for one Rust plugin

```
PSRAM ─┬─ bytecode copy (size of .wasm)
       ├─ WAMR module + fast-interp code
       ├─ exec-env stack 64 KiB          (WAMR operand/frame stack)
       └─ linear memory  [ data | shadow stack (wasm-ld default 1 MiB!) | heap → memory.grow ]
```

- **Shadow stack:** `wasm-ld` reserves a 1 MiB stack below `__heap_base` by
  default. The `matrix` plugin (`plugins/matrix/build.rs`) passes
  `-z stack-size=262144` because a 1 MiB stack forced linear memory to grow into
  ever-larger contiguous PSRAM blocks, until `memory.grow` could no longer
  relocate and the guest trapped. Do the same in our `build.rs`
  (`cargo:rustc-link-arg-cdylib=-z` and `stack-size=…`), sized to the real call
  depth.
- **Growth means relocation:** PSRAM is plentiful (8 MB, shared with the OS) but
  fragmentable. Keep the heap bounded and avoid large transient allocations.
- **Firmware validation range:** 16–4096 KB declared; keep the manifest ≤ 1024
  for the SDK validator.
- **Free memory:** plugins can use `min_free_psram` / `min_free_dram`
  prerequisites, and the serial plugin stats print free SPIRAM and internal
  heap.

## Implications for our Rust build

| Topic | Requirement |
|---|---|
| Target | `wasm32-unknown-unknown` (`cdc-badge-plugins/rust-toolchain.toml` pins stable + that target). Not WASI. |
| Crate type | `cdylib`, `#![no_std]` + `alloc` via the SDK (see [Rust SDK](../plugin-sdk/rust-sdk.md)) |
| Imports | Only module `"cdc"`. Any other import (e.g. `wasi_snapshot_preview1`, `env`) fails instantiation. Check with `wasm-tools print` / `wasm-objdump -x`. |
| Randomness | `getrandom` has no backend on this target. Use `host_random[_strict]`, or a custom getrandom backend as `matrix` does (`--cfg getrandom_backend="custom"` in `.cargo/config.toml`). |
| Panics | A panic is a trap: the plugin is unloaded without `deinit`. Use `panic = "abort"` and route messages through `host_log` with a panic hook. |
| Performance | Interpreted. CPU-heavy work (crypto, JSON, image processing) is slow, and each call is capped at 5×10⁸ instructions. Prefer host crypto (`host_sha256`, `host_aes_gcm_*`, SE signing). |
| Size | The binary sits in the 2 MB `vfat` partition with every other plugin, and in PSRAM at runtime. Use `opt-level = "z"`, LTO, `wasm-opt -Oz`, and avoid `core::fmt`-heavy code. |
| Threads, SIMD | No threads. SIMD is not enabled in this build; keep `target-feature` defaults. |
