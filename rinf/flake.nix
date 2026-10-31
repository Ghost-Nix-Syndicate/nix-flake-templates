{
  description = "RINF (Rust + Flutter) Development Environment";

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
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; config.allowUnfree = true; };

        # Rust toolchain matching RINF requirements
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Shared dependencies for Flutter Linux Desktop & Rust C bindings
        buildDeps = with pkgs; [
          # Flutter & Rust
          flutter
          rustToolchain
          protobuf             # Required for RINF Protobuf generation
          google-chrome
          android-tools
          
          # Native compilation tools
          cmake
          ninja
          pkg-config
          clang
          llvmPackages.libclang

          # Linux GUI GTK libraries needed by Flutter
          gtk3
          glib
          pango
          cairo
          gdk-pixbuf
          atk
          harfbuzz
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = buildDeps;

          shellHook = ''
            # Bindgen needs libclang to generate C bindings
            export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"

            # Flutter Linux desktop build flags
            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildDeps}"
            
            echo "RINF Dev Environment Loaded!"
            echo "Rust version: $(rustc --version)"
            echo "Flutter version: $(flutter --version | head -n 1)"
          '';
        };
      }
    );
}