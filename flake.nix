{
  description = "badge-cdc — sandboxed Rust/WebAssembly applications for the CDC Badge (ESP32-S3)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # Mirrors references/cdc-badge-development/Dockerfile:
        # stable Rust + wasm32-unknown-unknown + rustfmt/clippy.
        rust = pkgs.rust-bin.stable."1.100.0".default.override {
          extensions = [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
          targets = [ "wasm32-unknown-unknown" "wasm32-wasip1" ];
        };

        python = pkgs.python3.withPackages (ps: [ ps.pyserial ]);

        py313 = pkgs.python313Packages;
        platformio = pkgs.python313.pkgs.buildPythonPackage {
          pname = "platformio";
          version = "6.2.0";
          pyproject = true;
          build-system = [ py313.setuptools ];
          src = pkgs.fetchPypi {
            pname = "platformio";
            version = "6.2.0";
            hash = "sha256-iA6gZzSQiz1sCpZZjKe+VywrZ1VYV4SqY6IBu9+4xZ0=";
          };
          dependencies = [
            py313.bottle
            py313.click
            py313.colorama
            py313.marshmallow
            py313.pyelftools
            py313.pyserial
            py313.requests
            py313."semantic-version"
            py313.tabulate
            py313.ajsonrpc
            py313.starlette
            py313.uvicorn
            py313.wsproto
            py313.pip
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            # Rust → WebAssembly plugin toolchain
            rust
            pkgs.binaryen # wasm-opt
            pkgs.wabt # wasm2wat, wasm-objdump
            pkgs.wasm-tools
            pkgs.wasmtime # host-side sandbox testing

            # OS source build (PlatformIO Core; state in build/.platformio)
            platformio

            # badge CLI (tools/badge.py), serial upload, flashing
            python
            pkgs.esptool
            pkgs.espflash

            # Off-device emulator (references/cdc-badge-development/emulator)
            pkgs.cmake
            pkgs.pkg-config
            pkgs.SDL2
            pkgs.gcc

            # Wiki + docs site (openwiki, Astro website, web-flasher)
            pkgs.nodejs_22
            pkgs.git
            pkgs.gh
          ];

          shellHook = ''
            export PATH="$HOME/.npm-global/bin:$PATH"
            export PLATFORMIO_CORE_DIR="$PWD/build/.platformio"
            echo "badge-cdc dev shell: $(rustc --version), wasm-opt $(wasm-opt --version | cut -d' ' -f3)"
          '';
        };
      });
}
