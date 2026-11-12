# Shared environments for projects that do not ship their own.
#
# A project gets one by putting `use flake devbox#<name>` in the .envrc of its
# *parent* directory (devbox-project init does this), never inside the clone.
# They carry system libraries and the language's own version manager; the
# project's version files (.nvmrc, .python-version, rust-toolchain.toml, go.mod)
# still decide the toolchain version.
{ pkgs }:
let
  # what `apt install build-essential pkg-config libssl-dev zlib1g-dev ...`
  # would have given; mkShell already brings gcc and make
  base = pkgs.mkShell {
    packages = with pkgs; [
      pkg-config
      openssl
      zlib
      libffi
      sqlite
    ];
  };

  extend = packages: attrs: pkgs.mkShell ({ inherit packages; inputsFrom = [ base ]; } // attrs);
in
{
  inherit base;
  default = base;

  # corepack (bundled with nodejs) provides pnpm/yarn at the version the
  # project's package.json asks for
  node = extend [ pkgs.nodejs ] { };

  # Wheels from PyPI expect libstdc++ and zlib in the usual places. Nix's python
  # does not see them, so expose them explicitly; uv-managed interpreters find
  # them through nix-ld instead.
  python = extend [ pkgs.python3 pkgs.uv ] {
    LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
    ];
  };

  # rustup reads rust-toolchain.toml; the nixpkgs build patches the toolchains
  # it downloads so they run on NixOS
  rust = extend [ pkgs.rustup ] { };

  go = extend [ pkgs.go ] { };
}
