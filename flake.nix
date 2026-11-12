{
  description = "devbox: declarative NixOS dev machine for opencode + MCP servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # opencode is a bun build that the 26.05 channel still ships as 1.x; take it
    # from unstable until the release branch catches up.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, nixpkgs-unstable, disko, sops-nix, ... }:
    {
      nixosConfigurations.devbox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { unstable = nixpkgs-unstable; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/devbox
        ];
      };
    };
}
