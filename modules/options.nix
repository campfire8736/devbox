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
      description = "PUBLIC keys allowed to log in. These DO end up in git.";
    };

    sshKeyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Files each holding one public key, read at build time into
        /etc/ssh/authorized_keys.d/<user>. Keeps keys out of git at the cost of
        a rebuild when they change. The path must exist when the flake is
        evaluated, which is also what stops a typo from silently locking you out.
      '';
    };

    manualSshKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Assert that you manage ~/.ssh/authorized_keys yourself. NixOS only
        writes authorized_keys when sshKeys/sshKeyFiles are non-empty, so the
        user's own file is left alone — set this to silence the lockout check.
      '';
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

    docker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run a rootful Docker daemon and add the operator to the docker group.
          The group is root-equivalent; enable it when a project's tests need it.
        '';
      };
    };

    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/devbox/secrets.env";
      description = "Used by secrets = \"file\" (and as the fallback path).";
    };
  };
}
