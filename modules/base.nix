{ config, pkgs, ... }:
let
  cfg = config.devbox;
in
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    auto-optimise-store = true;
  };

  # A dev box fills /nix fast; keep 30 days of generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  networking.hostName = cfg.hostname;
  time.timeZone = cfg.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [
    22
    cfg.webPort
  ];

  services.qemuGuest.enable = true;

  boot.tmp.cleanOnBoot = true;
  environment.systemPackages = with pkgs; [ curl less file ];
}
