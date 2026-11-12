# Personal preferences: editor, file manager, git TUI, shell ergonomics.
# Nothing in the rest of the repo depends on this file — delete it and its
# import in hosts/devbox/default.nix if you fork and don't want any of it.
{ pkgs, ... }:
{
  programs.vim = {
    enable = true;
    defaultEditor = true; # EDITOR=vim
    # `vi` comes from the vim package itself ($out/bin/vi -> vim), so no
    # separate symlink here: a second one would collide in the profile.
  };

  programs.lazygit.enable = true;

  environment.systemPackages = [ pkgs.nnn ];

  environment.shellAliases = {
    lg = "lazygit";
  };

  # nnn writes the last directory to $NNN_TMPFILE on quit; sourcing it after the
  # process exits is what lets the *shell* follow the file manager. That has to
  # be a function, not an alias — an alias cannot change the parent shell's cwd.
  # Adapted from upstream misc/quitcd/quitcd.bash_sh_zsh.
  environment.interactiveShellInit = ''
    n() {
      [ "''${NNNLVL:-0}" -eq 0 ] || { echo "nnn is already running"; return; }
      export NNN_TMPFILE="''${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"
      command nnn "$@"
      if [ -f "$NNN_TMPFILE" ]; then
        . "$NNN_TMPFILE"
        rm -f -- "$NNN_TMPFILE"
      fi
    }
  '';
}
