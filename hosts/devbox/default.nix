{ ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base.nix
    ../../modules/users.nix
    ../../modules/secrets.nix
    ../../modules/dev.nix
    ../../modules/mcp.nix
    ../../modules/opencode.nix
  ];

  networking.hostName = "devbox";
  system.stateVersion = "26.05";
}
