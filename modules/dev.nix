{ config, pkgs, ... }:
let
  cfg = config.devbox;

  # The health check must not depend on a git clone being present: the install
  # runs from the installer's /tmp, which is gone after the first reboot.
  doctor = pkgs.writeShellScriptBin "devbox-doctor" ''
    export DEVBOX_USER=${cfg.user}
    export DEVBOX_PORT=${toString cfg.webPort}
    exec ${pkgs.bash}/bin/bash ${../scripts/doctor.sh} "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    git
    gh
    ripgrep
    fd
    jq
    yq-go
    tree
    tmux
    htop
    unzip
    nodejs
    python3
    uv
    bubblewrap
    gnumake
    gcc
    sops
    age
    ssh-to-age
    doctor
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    config.init.defaultBranch = "main";
  };
}
