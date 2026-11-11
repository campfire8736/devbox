# Secrets are committed ENCRYPTED (sops + age) so this repo can stay public.
# The age private key lives only at /var/lib/sops-nix/key.txt on the box.
#
# Everything is conditional on the encrypted file existing so that a fresh
# clone of a public repo still evaluates; without it the box comes up with no
# provider credentials and the opencode unit cannot start.
{ config, lib, ... }:
let
  haveSecrets = builtins.pathExists ../secrets/secrets.yaml;
in
{
  sops = lib.mkIf haveSecrets {
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
    # the opencode unit as a systemd credential, so `dev` cannot read it.
    templates."devbox.env" = {
      owner = "root";
      mode = "0400";
      content = ''
        GITEA_HOST=${config.sops.placeholder.GITEA_HOST}
        GITEA_TOKEN=${config.sops.placeholder.GITEA_TOKEN}
        GITHUB_PERSONAL_ACCESS_TOKEN=${config.sops.placeholder.GITHUB_PERSONAL_ACCESS_TOKEN}
        OPENROUTER_API_KEY=${config.sops.placeholder.OPENROUTER_API_KEY}
        OPENCODE_SERVER_PASSWORD=${config.sops.placeholder.OPENCODE_SERVER_PASSWORD}
      '';
    };
  };

  users.users.dev = lib.mkIf haveSecrets {
    hashedPasswordFile = config.sops.secrets.dev_password_hash.path;
  };
}
