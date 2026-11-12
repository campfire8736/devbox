{ writeShellApplication, bash, coreutils, direnv, git, nix }:
# The agent's shell for this devbox.
#
# opencode spawns the configured shell as `<shell> -c "<command>"` with cwd set
# to the project (or worktree) and the process environment inherited, so this
# wrapper gets the same contract bash would. It finds the project environment
# and runs the command inside it, which is what makes the environment a
# per-project property instead of a global setting.
#
# Precedence:
#   1. a .envrc ABOVE the git checkout (the devbox layout: <project>/.envrc next
#      to <project>/src and <project>/wt/*). Out of git, shared by every
#      worktree, and it can still `use flake ./src` to pick up upstream's flake.
#   2. otherwise the nearest .envrc or flake.nix from cwd up, i.e. one the
#      repository ships itself (an upstream .envrc still needs `direnv allow`).
#   3. otherwise plain bash.
writeShellApplication {
  name = "agent-shell";
  runtimeInputs = [
    bash
    coreutils
    direnv
    git
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

    # nearest ancestor of $1 (inclusive) containing one of the markers
    find_up() {
      local d=$1; shift
      while :; do
        for m in "$@"; do
          [ -e "$d/$m" ] && { printf '%s\n' "$d"; return 0; }
        done
        [ "$d" = "/" ] && return 1
        d="$(dirname "$d")"
      done
    }

    prefix=()
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"

    if [ -n "$top" ] && root="$(find_up "$(dirname "$top")" .envrc)"; then
      # nix-direnv caches the profile, so this costs milliseconds after the
      # first evaluation -- unlike `nix develop`, which re-evaluates every call.
      prefix=(direnv exec "$root")
    elif root="$(find_up "$PWD" .envrc flake.nix)"; then
      if [ -e "$root/.envrc" ]; then
        prefix=(direnv exec "$root")
      else
        prefix=(nix develop "$root" --command)
      fi
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
