{ writeShellApplication, bash, coreutils, direnv, nix }:
# The agent's shell for this devbox.
#
# opencode spawns the configured shell as `<shell> -c "<command>"` with cwd set
# to the project (or worktree) and the process environment inherited, so this
# wrapper gets the same contract bash would. It walks up from cwd looking for a
# project environment and runs the command inside it, which is what makes the
# environment a per-project property instead of a global setting.
writeShellApplication {
  name = "agent-shell";
  runtimeInputs = [
    bash
    coreutils
    direnv
    nix
  ];
  text = ''
    cmd=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -c) cmd="''${2-}"; shift 2 ;;
        *) shift ;;
      esac
    done

    # nearest ancestor that declares an environment
    root="$PWD"
    while [ "$root" != "/" ] && [ ! -e "$root/.envrc" ] && [ ! -e "$root/flake.nix" ]; do
      root="$(dirname "$root")"
    done

    prefix=()
    if [ -e "$root/.envrc" ]; then
      # nix-direnv caches the profile, so this costs milliseconds after the
      # first evaluation -- unlike `nix develop`, which re-evaluates every call.
      prefix=(direnv exec "$root")
    elif [ -e "$root/flake.nix" ]; then
      prefix=(nix develop "$root" --command)
    fi

    # an empty array must not be expanded under `set -u`
    if [ "''${#prefix[@]}" -eq 0 ]; then
      prefix=(env)
    fi

    if [ -n "$cmd" ]; then
      exec "''${prefix[@]}" bash -c "$cmd"
    fi
    exec "''${prefix[@]}" bash -i
  '';
}
