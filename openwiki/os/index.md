# Files

- [cdc-badge-os architecture](architecture.md) - Layered structure of the cdc-badge-os reference firmware (ESP-IDF on ESP32-S3) — components, the staged boot in main.cpp, the cooperative main loop, service and module registries, EventBus, UI stack, feature modules, the PSRAM-first memory rule and the no-migration policy — and where the WASM plugin system fits.
- [OS build, partitions and flashing](build-flash-and-partitions.md) - How cdc-badge-os is built with PlatformIO/ESP-IDF, its build environments and security profiles, the 16 MB partition table (including the 2 MB FAT partition that holds plugins), and the ways to flash it — PlatformIO, flash_firmware.py, and the esp-web-tools browser flasher with its Update vs Factory Setup manifests.
