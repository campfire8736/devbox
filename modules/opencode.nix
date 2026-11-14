{ config, lib, pkgs, ... }:
let
  cfg = config.devbox;
  home = "/home/${cfg.user}";

  # Generated rather than a static JSON file: commands are store paths, so the
  # config cannot drift from what is installed and does not depend on PATH.
  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    shell = lib.getExe pkgs.devbox.agent-shell;
    # The documented `mcp.servers.<name>` shape yields "No MCP servers configured"
    # on 2.2.x; the flat `mcp.<name>` record is what the binary parses.
    # Servers come from devbox.mcpServers (modules/mcp.nix), shared with the
    # other agents; the launchers read their tokens themselves.
    mcp = lib.mapAttrs (_: s: {
      type = "local";
      command = [ s.command ] ++ s.args;
    }) cfg.mcpServers;
    # "New workspace" in the web UI is a git worktree. A relative directory is
    # resolved from the project's main checkout, so `src/` puts them in the
    # project's `wt/`, under the shared .envrc. The default
    # (~/.local/share/opencode/worktree/) has no .envrc above it, so commands
    # there would run without the project's toolchain.
    worktree.directory = "../wt";
  };

  cfgFile = pkgs.writeText "opencode.json" (builtins.toJSON opencodeConfig);

  # opencode reads ~/.config/opencode/AGENTS.md as global instructions.
  agentsFile = pkgs.writeText "AGENTS.md" (import ./agents-md.nix { inherit cfg; tool = "opencode"; });

  start = pkgs.writeShellScript "opencode-start" ''
    export OPENCODE_DISABLE_AUTOUPDATE=1
    exec ${lib.getExe pkgs.devbox.opencode} serve --hostname 0.0.0.0 --port ${toString cfg.webPort}
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${cfg.workspaceDir} 0755 ${cfg.user} users -"
    "d ${home}/.config 0755 ${cfg.user} users -"
    "d ${home}/.config/opencode 0755 ${cfg.user} users -"
    "L+ ${home}/.config/opencode/opencode.json - - - - ${cfgFile}"
    "L+ ${home}/.config/opencode/AGENTS.md - - - - ${agentsFile}"
  ];

  systemd.services.opencode = {
    description = "opencode server (API + web UI)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # The agent's shell commands inherit this PATH, so it is the operator's PATH:
    # the setuid wrappers (sudo) and the whole system profile. A hand-picked list
    # here silently hid gcc, make and docker from the agent.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];

    environment = {
      HOME = home;
      XDG_CONFIG_HOME = "${home}/.config";
      XDG_DATA_HOME = "${home}/.local/share";
      XDG_CACHE_HOME = "${home}/.cache";
      # Login shells get this from environment.variables; a service does not.
      # Without it direnv never loads nix-direnv, and `use flake` falls back to
      # direnv's uncached built-in that re-evaluates on every agent command.
      DIRENV_CONFIG = "/etc/direnv";
    };

    # A changed secrets file is picked up on restart; nothing to rebuild.
    restartTriggers = [ cfgFile agentsFile ];

    serviceConfig = {
      User = cfg.user;
      Group = "users";
      WorkingDirectory = cfg.workspaceDir;
      # `-`: a missing file is not an error, the box just has no credentials.
      # Not a systemd credential: the same account has passwordless sudo, so
      # hiding the file from it would protect nothing.
      EnvironmentFile = "-${cfg.secretsFile}";
      ExecStart = start;
      Restart = "always";
      RestartSec = 5;
    };
  };
}
