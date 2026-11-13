{ config, lib, pkgs, unstable, ... }:
let
  cfg = config.devbox;

  # The agent CLIs come from unstable: they move fast, and the 26.05 channel
  # lags (opencode 1.x, no antigravity-cli). The two proprietary ones are
  # allowed by name only, so nothing else unfree slips in.
  unfreeAllowed = [ "claude-code" "antigravity-cli" ];
  unstablePkgs = import unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeAllowed;
  };
in
{
  options.devbox.mcpServers = lib.mkOption {
    internal = true;
    readOnly = true;
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        command = lib.mkOption { type = lib.types.str; };
        args = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
      };
    });
    description = ''
      The MCP servers every agent on the box gets (opencode, Claude Code, agy),
      defined once. Tokens are read by the launchers, not passed by the agents.
    '';
  };

  config = {
    nixpkgs.overlays = [
      (final: prev: {
        devbox = rec {
          # Upstream's release binary is linked against a generic glibc loader
          # (/lib64/ld-linux-x86-64.so.2) and cannot start on NixOS; the channel
          # builds it from source with bun instead.
          opencode = unstablePkgs.opencode;
          claude-code = unstablePkgs.claude-code;
          antigravity-cli = unstablePkgs.antigravity-cli;
          # Static Go binary, no interpreter dependency.
          gitea-mcp = final.callPackage ../packages/gitea-mcp.nix { };
          serena = final.callPackage ../packages/serena.nix { };
          agent-shell = final.callPackage ../packages/agent-shell.nix { };
          devbox-project = final.callPackage ../packages/devbox-project.nix {
            inherit (cfg) workspaceDir;
          };
          mcp = final.callPackage ../packages/devbox-mcp.nix {
            inherit gitea-mcp;
            inherit (cfg) secretsFile;
          };
          claude-env-hook = final.callPackage ../packages/claude-env-hook.nix {
            inherit agent-shell;
          };
          agy = final.callPackage ../packages/agy-wrapped.nix {
            inherit agent-shell antigravity-cli;
          };
        };
      })
    ];

    devbox.mcpServers = {
      gitea.command = lib.getExe pkgs.devbox.mcp.gitea;
      github.command = lib.getExe pkgs.devbox.mcp.github;
      serena = {
        command = lib.getExe pkgs.devbox.serena;
        args = [ "start-mcp-server" "--context" "agent" "--project-from-cwd" ];
      };
    };

    # The launchers run as the operator (under opencode, or from an SSH shell
    # for claude/agy), so the secrets file is group-readable by `users` rather
    # than root-only. That costs nothing: the operator has passwordless sudo.
    # `z` only adjusts an existing file; the directory rule is limited to the
    # default location so a custom secretsFile never re-modes e.g. /etc.
    systemd.tmpfiles.rules =
      lib.optional (dirOf cfg.secretsFile == "/var/lib/devbox") "d /var/lib/devbox 0750 root users -"
      ++ [ "z ${cfg.secretsFile} 0640 root users -" ];

    environment.systemPackages = [
      pkgs.devbox.opencode
      pkgs.devbox.gitea-mcp
      pkgs.github-mcp-server
      pkgs.devbox.serena
      pkgs.devbox.mcp.gitea
      pkgs.devbox.mcp.github
      pkgs.devbox.agent-shell
      pkgs.devbox.devbox-project
    ];
  };
}
