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
#
# "From" is cwd, or the target of a leading `cd <dir> &&` in the command.
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
    resolve=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -c) cmd="''${2-}"; shift 2 ;;
        # `agent-shell --resolve DIR` prints "<kind>\t<root>" (kind: direnv,
        # flake or none) and exits: the same rules, for the Claude Code hook
        # and the agy wrapper, which cannot route commands through this shell.
        --resolve) resolve="''${2:-$PWD}"; shift 2 || shift ;;
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

    # Agents habitually write `cd /srv/work/foo/src && make test` instead of
    # setting the tool's workdir. Sessions opened at the workspace root then
    # start here in /srv/work, where no environment applies. Resolve the
    # environment from the cd target instead; the command runs unchanged.
    start="''${resolve:-$PWD}"
    re='^[[:space:]]*cd[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&|]+)[[:space:]]*(&&|;)'
    if [[ "$cmd" =~ $re ]]; then
      target="''${BASH_REMATCH[1]}"
      target="''${target#[\"\']}"
      target="''${target%[\"\']}"
      # matching a literal "~" typed by the agent, so no expansion is wanted
      # shellcheck disable=SC2088
      case "$target" in
        "~") target="$HOME" ;;
        "~/"*) target="$HOME/''${target#\~/}" ;;
        /*) ;;
        *) target="$PWD/$target" ;;
      esac
      if [ -d "$target" ]; then
        start="$(cd "$target" && pwd)"
      fi
    fi

    kind=none
    root=""
    top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"

    if [ -n "$top" ] && root="$(find_up "$(dirname "$top")" .envrc)"; then
      # nix-direnv caches the profile, so this costs milliseconds after the
      # first evaluation -- unlike `nix develop`, which re-evaluates every call.
      kind=direnv
    elif root="$(find_up "$start" .envrc flake.nix)"; then
      if [ -e "$root/.envrc" ]; then
        kind=direnv
      else
        kind=flake
      fi
    fi

    if [ -n "$resolve" ]; then
      printf '%s\t%s\n' "$kind" "$root"
      exit 0
    fi

    prefix=()
    case "$kind" in
      direnv) prefix=(direnv exec "$root") ;;
      flake) prefix=(nix develop "$root" --command) ;;
    esac

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
