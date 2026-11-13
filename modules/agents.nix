# Terminal agents next to opencode: Claude Code (`claude`) and the Antigravity
# CLI (`agy`), used over SSH in tmux. Each gets the same three MCP servers
# (devbox.mcpServers), its own variant of the devbox instructions, and the
# project environment by the same rules as agent-shell.
{ config, lib, pkgs, ... }:
let
  cfg = config.devbox;
  user = cfg.user;
  home = "/home/${user}";
  claudeOn = cfg.claudeCode.enable;
  agyOn = cfg.antigravity.enable;

  instructions = tool: pkgs.writeText "${tool}.md" (import ./agents-md.nix { inherit cfg tool; });

  # Both tools keep MCP servers in files they also write themselves
  # (~/.claude.json holds account state; agy edits its own config), so the
  # servers are registered through each tool's own CLI rather than by owning
  # the file. Re-running is idempotent: a devbox server is replaced, anything
  # you added yourself is left alone.
  claude = lib.getExe pkgs.devbox.claude-code;
  agy = "${pkgs.devbox.antigravity-cli}/bin/agy"; # the real binary, not the env wrapper
  sync = pkgs.writeShellScript "devbox-agents-sync" (
    ''
      set -u
      status=0
    ''
    + lib.optionalString claudeOn (lib.concatStrings (lib.mapAttrsToList (name: s: ''
      ${claude} mcp remove --scope user ${name} >/dev/null 2>&1 || true
      ${claude} mcp add-json --scope user ${name} ${lib.escapeShellArg (builtins.toJSON {
        type = "stdio";
        inherit (s) command args;
      })} || status=1
    '') cfg.mcpServers))
    + lib.optionalString agyOn (lib.concatStrings (lib.mapAttrsToList (name: s: ''
      ${agy} mcp add ${name} -- ${lib.escapeShellArgs ([ s.command ] ++ s.args)} || status=1
    '') cfg.mcpServers))
    + ''
      exit "$status"
    ''
  );

  envHook = [ { hooks = [ { type = "command"; command = lib.getExe pkgs.devbox.claude-env-hook; } ]; } ];
in
lib.mkMerge [
  (lib.mkIf (claudeOn || agyOn) {
    systemd.services.devbox-agents-sync = {
      description = "Register the devbox MCP servers with Claude Code and agy";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      # re-run on `nixos-rebuild switch` whenever the server set changes
      restartTriggers = [ sync ];
      environment = {
        HOME = home;
        XDG_CONFIG_HOME = "${home}/.config";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        Group = "users";
        ExecStart = sync;
      };
    };
  })

  (lib.mkIf claudeOn {
    # nixpkgs' wrapper already sets DISABLE_AUTOUPDATER=1: the store is read-only.
    environment.systemPackages = [ pkgs.devbox.claude-code ];

    # Managed settings: read by every Claude Code session on the box, owned by
    # this repo, and merged with (not replacing) hooks you add yourself in
    # ~/.claude/settings.json. Only the environment hook lives here.
    environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
      hooks = {
        SessionStart = envHook;
        CwdChanged = envHook;
      };
    };

    environment.etc."devbox/agents/claude.md".source = instructions "claude";

    systemd.tmpfiles.rules = [
      "d ${home}/.claude 0700 ${user} users -"
      # Created once, then yours: Claude Code's /memory edits this file, so it
      # cannot be a read-only link. The import keeps the devbox part current.
      "f ${home}/.claude/CLAUDE.md 0644 ${user} users - @/etc/devbox/agents/claude.md"
    ];
  })

  (lib.mkIf agyOn {
    # `agy` here is the wrapper that starts the real binary in the launch
    # directory's environment.
    environment.systemPackages = [ pkgs.devbox.agy ];

    environment.etc."devbox/agents/agy.md".source = instructions "agy";

    systemd.tmpfiles.rules = [
      "d ${home}/.gemini 0755 ${user} users -"
      # ~/.gemini/AGENTS.md is a global rules file agy reads; GEMINI.md next to
      # it stays free for your own rules.
      "L+ ${home}/.gemini/AGENTS.md - - - - /etc/devbox/agents/agy.md"
    ];
  })
]
