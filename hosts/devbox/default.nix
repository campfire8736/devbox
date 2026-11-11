# ─────────────────────────────────────────────────────────────────────────────
#  THE ONLY FILE YOU NEED TO EDIT
#
#  Everything else is generic. Fork, change these values, install.
#  Leaving the defaults works: you get a key-only box on /dev/vda, no secrets,
#  and opencode asks you to log in to a provider in the browser.
# ─────────────────────────────────────────────────────────────────────────────
{ ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/options.nix
    ../../modules/base.nix
    ../../modules/users.nix
    ../../modules/secrets.nix
    ../../modules/dev.nix
    ../../modules/mcp.nix
    ../../modules/opencode.nix
  ];

  devbox = {
    hostname = "devbox";
    user = "dev";
    timeZone = "Europe/Paris";
    webPort = 4096;

    # PUBLIC keys only. Without at least one you cannot log in after install.
    sshKeys = [
      # "ssh-ed25519 AAAA... you@laptop"
    ];

    # none | file | sops  (see modules/options.nix for what each means)
    secrets = "sops";
  };

  system.stateVersion = "26.05";
}
