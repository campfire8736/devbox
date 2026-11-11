{ writeShellApplication, uv }:
# Serena is pinned but realised at first run through uv (large, fast-moving
# dependency tree); converting to uv2nix later makes this hermetic.
writeShellApplication {
  name = "serena";
  runtimeInputs = [ uv ];
  text = ''
    export UV_CACHE_DIR="''${UV_CACHE_DIR:-''${HOME:-/tmp}/.cache/uv}"
    exec uvx --python 3.13 --from "serena-agent==2.1.0" serena "$@"
  '';
}
