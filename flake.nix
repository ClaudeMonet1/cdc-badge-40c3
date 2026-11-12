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
        rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
          targets = [ "wasm32-unknown-unknown" "wasm32-wasip1" ];
        };

        python = pkgs.python3.withPackages (ps: [ ps.pyserial ]);
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
            echo "badge-cdc dev shell: $(rustc --version), wasm-opt $(wasm-opt --version | cut -d' ' -f3)"
          '';
        };
      });
}
