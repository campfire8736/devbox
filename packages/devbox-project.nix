{ writeShellApplication, coreutils, direnv, git, workspaceDir }:
# devbox-project init <git-url> [base|node|python|rust|go|upstream|none]
#
# Creates the layout agent-shell expects, with the environment outside git:
#   <workspace>/<name>/.envrc   use flake devbox#<shell>
#   <workspace>/<name>/src      the clone
#   <workspace>/<name>/wt/      worktrees
writeShellApplication {
  name = "devbox-project";
  runtimeInputs = [
    coreutils
    direnv
    git
  ];
  text = ''
    usage() {
      echo "usage: devbox-project init <git-url> [base|node|python|rust|go|upstream|none]" >&2
      exit 2
    }

    [ "''${1-}" = init ] || usage
    url="''${2-}"
    [ -n "$url" ] || usage
    shell="''${3-base}"

    name="$(basename "''${url%/}" .git)"
    dir="''${DEVBOX_WORKSPACE:-${workspaceDir}}/$name"
    [ -e "$dir" ] && { echo "devbox-project: $dir already exists" >&2; exit 1; }

    case "$shell" in
      base|node|python|rust|go) envrc="use flake devbox#$shell" ;;
      upstream) envrc="use flake ./src" ;;
      none) envrc="" ;;
      *) usage ;;
    esac

    mkdir -p "$dir/wt"
    git clone "$url" "$dir/src"

    if [ "$shell" = upstream ] && [ ! -e "$dir/src/flake.nix" ]; then
      echo "devbox-project: $name has no flake.nix; falling back to devbox#base" >&2
      envrc="use flake devbox#base"
    fi

    printf '%s\n' "$envrc" > "$dir/.envrc"
    direnv allow "$dir"

    echo "created $dir  (env: ''${envrc:-none})"
    echo "the first command in it builds the environment; later ones are cached"
  '';
}
