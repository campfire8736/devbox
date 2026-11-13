{ writeShellApplication, coreutils, direnv, jq, nix, agent-shell }:
# Claude Code SessionStart + CwdChanged hook: load the project environment.
#
# Claude Code keeps its working directory between Bash commands and runs the
# contents of $CLAUDE_ENV_FILE before each one. On session start and on every
# directory change this hook writes the environment of the new directory into
# that file, chosen by the same rules as agent-shell (a .envrc above the git
# checkout first). CwdChanged clears the previous contents itself.
writeShellApplication {
  name = "devbox-claude-env-hook";
  runtimeInputs = [
    coreutils
    direnv
    jq
    nix
    agent-shell
  ];
  text = ''
    input="$(cat)"
    dir="$(jq -r '.new_cwd // .cwd // empty' <<<"$input" 2>/dev/null || true)"
    [ -n "$dir" ] && [ -d "$dir" ] && [ -n "''${CLAUDE_ENV_FILE:-}" ] || exit 0

    IFS=$'\t' read -r kind root < <(agent-shell --resolve "$dir")

    case "$kind" in
      direnv)
        # Errors (a blocked .envrc, a failing nix build) go to stderr, where
        # Claude Code shows them; the session continues without the env.
        (cd "$root" && direnv export bash) >> "$CLAUDE_ENV_FILE" || true
        ;;
      flake)
        nix print-dev-env "$root" >> "$CLAUDE_ENV_FILE" || true
        ;;
    esac
    exit 0
  '';
}
