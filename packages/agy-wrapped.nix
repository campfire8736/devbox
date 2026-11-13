{ writeShellApplication, direnv, nix, agent-shell, antigravity-cli }:
# `agy` started inside the environment of the directory it is launched from.
#
# agy has no hook or shell-prefix setting, so its commands simply inherit the
# environment agy itself runs in. Resolving it here (same rules as agent-shell)
# gives a session started in /srv/work/foo/src the project's toolchain even
# when the interactive shell has no direnv hook loaded.
writeShellApplication {
  name = "agy";
  runtimeInputs = [
    direnv
    nix
    agent-shell
  ];
  text = ''
    real=${antigravity-cli}/bin/agy
    IFS=$'\t' read -r kind root < <(agent-shell --resolve "$PWD")
    case "$kind" in
      direnv) exec direnv exec "$root" "$real" "$@" ;;
      flake) exec nix develop "$root" --command "$real" "$@" ;;
      *) exec "$real" "$@" ;;
    esac
  '';
}
