{ pkgs, ... }:
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

  # A dev box fills /nix fast; 80G disk, keep 30 days of generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_US.UTF-8";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # 4096 = opencode server (API + web UI), reached through the umbrelOS forward.
  networking.firewall.allowedTCPPorts = [ 22 4096 ];

  services.qemuGuest.enable = true;

  boot.tmp.cleanOnBoot = true;
  environment.systemPackages = with pkgs; [ curl less file ];
}
