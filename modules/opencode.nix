{ config, lib, pkgs, ... }:
let
  cfg = config.devbox;

  haveSopsEnv = cfg.secrets == "sops" && builtins.pathExists ../secrets/secrets.yaml;
  # sops selected without a committed secrets file behaves like "none" rather
  # than pointing LoadCredential at a path that does not exist.
  credentials = cfg.secrets == "file" || haveSopsEnv;

  # sops renders into /run/secrets-rendered at activation; "file" mode reads the
  # operator-provided path directly.
  envFile = if haveSopsEnv then config.sops.templates."devbox.env".path else cfg.secretsFile;

  cfgFile = pkgs.writeText "opencode.json" (builtins.readFile ./opencode.json);

  start = pkgs.writeShellScript "opencode-start" ''
    if [ -f "''${CREDENTIALS_DIRECTORY:-}/env" ]; then
      set -a
      . "$CREDENTIALS_DIRECTORY/env"
      set +a
    fi
    export OPENCODE_DISABLE_AUTOUPDATE=1
    exec ${pkgs.devbox.opencode}/bin/opencode serve --hostname 0.0.0.0 --port ${toString cfg.webPort}
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${cfg.workspaceDir} 0755 ${cfg.user} users -"
    "d /home/${cfg.user}/.config 0755 ${cfg.user} users -"
    "d /home/${cfg.user}/.config/opencode 0755 ${cfg.user} users -"
    "L+ /home/${cfg.user}/.config/opencode/opencode.json - - - - ${cfgFile}"
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
      HOME = "/home/${cfg.user}";
      XDG_CONFIG_HOME = "/home/${cfg.user}/.config";
      XDG_DATA_HOME = "/home/${cfg.user}/.local/share";
      XDG_CACHE_HOME = "/home/${cfg.user}/.cache";
    };

    serviceConfig = {
      User = cfg.user;
      Group = "users";
      WorkingDirectory = cfg.workspaceDir;
      LoadCredential = lib.optionals credentials [ "env:${envFile}" ];
      ExecStart = start;
      Restart = "always";
      RestartSec = 5;
    };
  };
}
