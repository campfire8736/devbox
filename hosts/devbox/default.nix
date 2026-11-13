# ─────────────────────────────────────────────────────────────────────────────
#  THE ONLY FILE YOU NEED TO EDIT
#
#  Everything else is generic. Fork, change these values, install.
#  As shipped you get a key-only box on /dev/vda. Credentials are optional: put
#  them in /var/lib/devbox/secrets.env with scripts/secrets-file-init.sh, or
#  skip it and log in to a model provider in the browser.
# ─────────────────────────────────────────────────────────────────────────────
{ ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/options.nix
    ../../modules/base.nix
    ../../modules/users.nix
    ../../modules/dev.nix
    ../../modules/operator.nix
    ../../modules/docker.nix
    ../../modules/mcp.nix
    ../../modules/opencode.nix
    ../../modules/agents.nix
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

    # a project's test suite needs a system Docker daemon
    docker.enable = true;

    # terminal agents for SSH + tmux, next to opencode (both unfree)
    claudeCode.enable = true;
    antigravity.enable = true;
  };

  system.stateVersion = "26.05";
}
