{ writeShellApplication, coreutils, direnv, git, gnused, workspaceDir }:
# devbox-project: create projects in the layout agent-shell expects, with the
# environment outside git:
#   <workspace>/<name>/.envrc   use flake devbox#<shell>
#   <workspace>/<name>/<name>/  the checkout (named after the project, because
#                               opencode shows a project by its folder name)
#   <workspace>/<name>/wt/      worktrees
writeShellApplication {
  name = "devbox-project";
  runtimeInputs = [
    coreutils
    direnv
    git
    gnused
  ];
  text = ''
    ws="''${DEVBOX_WORKSPACE:-${workspaceDir}}"
    shells="base|node|python|rust|go|upstream|none"

    usage() {
      cat >&2 <<EOF
    usage: devbox-project init <git-url> [shell]   clone a repo
           devbox-project new <name> [shell]       start an empty repo
           devbox-project migrate <name>           move an old <name>/src checkout to <name>/<name>
    shell: $shells (default: base)
    EOF
      exit 2
    }
    die() { echo "devbox-project: $*" >&2; exit 1; }

    check_name() {
      case "$1" in
        "" | wt | .* | */*) die "invalid project name '$1'" ;;
      esac
    }

    envrc_for() { # <shell> <name>
      case "$1" in
        base|node|python|rust|go) echo "use flake devbox#$1" ;;
        upstream) echo "use flake ./$2" ;;
        none) echo "" ;;
        *) usage ;;
      esac
    }

    finish() { # <dir> <name> <shell>
      local dir="$1" name="$2" shell="$3" envrc
      envrc="$(envrc_for "$shell" "$name")"
      if [ "$shell" = upstream ] && [ ! -e "$dir/$name/flake.nix" ]; then
        echo "devbox-project: $name has no flake.nix; falling back to devbox#base" >&2
        envrc="use flake devbox#base"
      fi
      printf '%s\n' "$envrc" > "$dir/.envrc"
      direnv allow "$dir"
      echo "created $dir/$name  (env: ''${envrc:-none})"
      echo "open $dir/$name as the project; the first command in it builds the environment"
    }

    cmd="''${1-}"
    case "$cmd" in
      init)
        url="''${2-}"
        [ -n "$url" ] || usage
        shell="''${3-base}"
        envrc_for "$shell" x >/dev/null
        name="$(basename "''${url%/}" .git)"
        check_name "$name"
        dir="$ws/$name"
        [ -e "$dir" ] && die "$dir already exists"
        mkdir -p "$dir/wt"
        git clone "$url" "$dir/$name" || { rm -rf "$dir"; die "clone failed"; }
        finish "$dir" "$name" "$shell"
        ;;

      new)
        name="''${2-}"
        check_name "$name"
        shell="''${3-base}"
        [ "$shell" = upstream ] && die "a new repo has no upstream flake"
        envrc_for "$shell" x >/dev/null
        dir="$ws/$name"
        [ -e "$dir" ] && die "$dir already exists"
        mkdir -p "$dir/wt" "$dir/$name"
        git -C "$dir/$name" init -q
        finish "$dir" "$name" "$shell"
        ;;

      migrate)
        name="''${2-}"
        check_name "$name"
        dir="$ws/$name"
        [ -d "$dir/src" ] || die "$dir/src not found"
        [ -e "$dir/$name" ] && die "$dir/$name already exists"
        # Every linked worktree, wherever it is: each .git/worktrees/<id>/gitdir
        # holds the path of that worktree's .git file.
        worktrees=()
        for f in "$dir"/src/.git/worktrees/*/gitdir; do
          [ -f "$f" ] && worktrees+=("$(dirname "$(cat "$f")")")
        done
        mv "$dir/src" "$dir/$name"
        mkdir -p "$dir/wt"
        # Re-point the worktrees at the moved checkout, and it at them.
        git -C "$dir/$name" worktree repair "''${worktrees[@]}"
        if [ -f "$dir/.envrc" ]; then
          sed -i "s#use flake \./src\b#use flake ./$name#" "$dir/.envrc"
          direnv allow "$dir"
        fi
        echo "moved $dir/src -> $dir/$name (''${#worktrees[@]} worktree(s) repaired)"
        echo "open $dir/$name as the project; sessions opened in src/ keep their history but point to a missing folder"
        ;;

      *) usage ;;
    esac
  '';
}
