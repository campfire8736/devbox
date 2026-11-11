{ pkgs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      devbox = {
        opencode = final.callPackage ../packages/opencode.nix { };
        gitea-mcp = final.callPackage ../packages/gitea-mcp.nix { };
        serena = final.callPackage ../packages/serena.nix { };
      };
    })
  ];

  environment.systemPackages = [
    pkgs.devbox.opencode
    pkgs.devbox.gitea-mcp
    pkgs.github-mcp-server
    pkgs.devbox.serena
  ];
}
