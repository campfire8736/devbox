# Credentials are pluggable so this repo stays usable without forking anything:
#
#   secrets = "none"  no credentials at all. opencode starts and asks you to log
#                     in to a model provider in the web UI; MCP servers report
#                     auth errors until you give them tokens.
#   secrets = "file"  one env file on the box ($devbox.secretsFile), created out
#                     of band. Nothing secret touches the repo.
#   secrets = "sops"  an encrypted file committed to the repo, decrypted at
#                     activation with the host's age identity.
#
# "sops" is bound to specific age recipients, so it is a per-deployment choice:
# reusing this repo on another machine means re-encrypting (scripts/secrets-sops-init.sh).
{ config, lib, ... }:
let
  cfg = config.devbox;
  sopsEnabled = cfg.secrets == "sops";
  haveSopsFile = builtins.pathExists ../secrets/secrets.yaml;
in
{
  sops = lib.mkIf (sopsEnabled && haveSopsFile) {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    validateSopsFiles = true;

    secrets = {
      dev_password_hash.neededForUsers = true;
      GITEA_HOST = { };
      GITEA_TOKEN = { };
      GITHUB_PERSONAL_ACCESS_TOKEN = { };
      OPENROUTER_API_KEY = { };
      OPENCODE_SERVER_PASSWORD = { };
    };

    # Rendered at activation into /run/secrets-rendered/devbox.env and handed to
    # the opencode unit as a systemd credential, so the operator cannot read it.
    templates."devbox.env" = {
      owner = "root";
      mode = "0400";
      # a changed secret restarts the consumer, so the new env is picked up
      restartUnits = [ "opencode.service" ];
      content = ''
        GITEA_HOST=${config.sops.placeholder.GITEA_HOST}
        GITEA_TOKEN=${config.sops.placeholder.GITEA_TOKEN}
        GITHUB_PERSONAL_ACCESS_TOKEN=${config.sops.placeholder.GITHUB_PERSONAL_ACCESS_TOKEN}
        OPENROUTER_API_KEY=${config.sops.placeholder.OPENROUTER_API_KEY}
        OPENCODE_SERVER_PASSWORD=${config.sops.placeholder.OPENCODE_SERVER_PASSWORD}
      '';
    };
  };
}
