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
    ../../modules/operator.nix
    ../../modules/mcp.nix
    ../../modules/opencode.nix
  ];

  devbox = {
    hostname = "devbox";
    user = "dev";
    timeZone = "Europe/Paris";
    webPort = 4096;

    # How you log in. Pick one:
    #   1. sshKeyFiles - paths to files with one key each. Not in git, but a
    #      rebuild is required after a key changes (the file is read at eval).
    #   2. sshKeys     - inline keys. Convenient, but they land in the repo.
    #   3. neither, and set manualSshKeys = true to manage ~/.ssh/authorized_keys.
    sshKeyFiles = [
      # /etc/devbox/authorized_keys
    ];
    sshKeys = [
      # "ssh-ed25519 AAAA... you@laptop"
    ];
    manualSshKeys = true;

    # none | file | sops   (modules/options.nix explains each)
    #   none -> no credentials, provider login happens in the UI
    #   file -> env file on the box, created by scripts/secrets-file-init.sh
    #   sops -> encrypted secrets/secrets.yaml, created by
    #           scripts/secrets-sops-init.sh  (run it BEFORE installing)
    secrets = "file";
  };

  system.stateVersion = "26.05";
}
