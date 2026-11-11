{ pkgs, ... }:
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
    nodejs_22
    python3
    uv
    bubblewrap
    gnumake
    gcc
    sops
    age
    ssh-to-age
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
