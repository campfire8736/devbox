# ─────────────────────────────────────────────────────────────────────────────
#  THE ONLY FILE YOU NEED TO EDIT
#
#  Everything else is generic. Fork, change these values, install.
#  As shipped you get a key-only box on /dev/vda with no credentials at all,
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

    # none | file | sops   (modules/options.nix explains each)
    #   none -> no credentials, provider login happens in the UI
    #   file -> env file on the box, created by scripts/secrets-file-init.sh
    #   sops -> encrypted secrets/secrets.yaml, created by
    #           scripts/secrets-sops-init.sh  (run it BEFORE installing)
    secrets = "none";
  };

  system.stateVersion = "26.05";
}
