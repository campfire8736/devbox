# Every deployment-specific value is an option here. A host file sets only what
# it needs; nothing in `modules/` hardcodes a hostname, user, disk or port.
{ lib, ... }:
{
  options.devbox = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "devbox";
      description = "Network hostname.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = "Operator account, and the account the opencode service runs as.";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 4096;
      description = "Port for the opencode API + web UI.";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/work";
      description = "Directory the agent works in.";
    };

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "PUBLIC keys allowed to log in. Login is key-only unless a password is declared.";
    };

    secrets = lib.mkOption {
      type = lib.types.enum [
        "none"
        "file"
        "sops"
      ];
      default = "none";
      description = ''
        none: no credentials; opencode asks you to log in to a provider in the UI.
        file: an env file on the box at `secretsFile`, created out of band.
        sops: an encrypted file in the repo, decrypted with the host age key.
      '';
    };

    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/devbox/secrets.env";
      description = "Used by secrets = \"file\" (and as the fallback path).";
    };
  };
}
