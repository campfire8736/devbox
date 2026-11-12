{ config, pkgs, unstable, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      devbox = {
        # Upstream's release binary is linked against a generic glibc loader
        # (/lib64/ld-linux-x86-64.so.2) and cannot start on NixOS; the channel
        # builds it from source with bun instead.
        opencode = unstable.legacyPackages.${final.stdenv.hostPlatform.system}.opencode;
        # Static Go binary, no interpreter dependency.
        gitea-mcp = final.callPackage ../packages/gitea-mcp.nix { };
        serena = final.callPackage ../packages/serena.nix { };
        agent-shell = final.callPackage ../packages/agent-shell.nix { };
        devbox-project = final.callPackage ../packages/devbox-project.nix {
          inherit (config.devbox) workspaceDir;
        };
      };
    })
  ];

  environment.systemPackages = [
    pkgs.devbox.opencode
    pkgs.devbox.gitea-mcp
    pkgs.github-mcp-server
    pkgs.devbox.serena
    pkgs.devbox.agent-shell
    pkgs.devbox.devbox-project
  ];
}
