{ config, lib, pkgs, ... }:
let
  haveSecrets = builtins.pathExists ../secrets/secrets.yaml;

  # With sops enabled the env file is rendered by sops-nix at activation; without
  # it, the fallback path is a file you create by hand (escape hatch).
  envFile =
    if haveSecrets then
      config.sops.templates."devbox.env".path
    else
      "/var/lib/devbox/secrets.env";

  cfgFile = pkgs.writeText "opencode.json" (builtins.readFile ./opencode.json);

  start = pkgs.writeShellScript "opencode-start" ''
    if [ -f "''${CREDENTIALS_DIRECTORY:-}/env" ]; then
      set -a
      . "$CREDENTIALS_DIRECTORY/env"
      set +a
    fi
    export OPENCODE_DISABLE_AUTOUPDATE=1
    exec ${pkgs.devbox.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /srv/work 0755 dev users -"
    "d /home/dev/.config 0755 dev users -"
    "d /home/dev/.config/opencode 0755 dev users -"
    "L+ /home/dev/.config/opencode/opencode.json - - - - ${cfgFile}"
  ];

  systemd.services.opencode = {
    description = "opencode server (API + web UI)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # MCP servers are spawned by opencode and inherit this PATH.
    path = [
      pkgs.devbox.opencode
      pkgs.devbox.gitea-mcp
      pkgs.github-mcp-server
      pkgs.devbox.serena
      pkgs.git
      pkgs.gh
      pkgs.ripgrep
      pkgs.fd
      pkgs.jq
      pkgs.bash
      pkgs.coreutils
      pkgs.nodejs_22
      pkgs.python3
      pkgs.uv
      pkgs.openssh
      pkgs.nix
    ];

    environment = {
      HOME = "/home/dev";
      XDG_CONFIG_HOME = "/home/dev/.config";
      XDG_DATA_HOME = "/home/dev/.local/share";
      XDG_CACHE_HOME = "/home/dev/.cache";
    };

    serviceConfig = {
      User = "dev";
      Group = "users";
      WorkingDirectory = "/srv/work";
      LoadCredential = [ "env:${envFile}" ];
      ExecStart = start;
      Restart = "always";
      RestartSec = 5;
    };
  };
}
