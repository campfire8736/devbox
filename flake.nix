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
  };

  outputs =
    { self, nixpkgs, nixpkgs-unstable, disko, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.devbox = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          unstable = nixpkgs-unstable;
          # registered as the `devbox` flake on the box, so a project's .envrc
          # can say `use flake devbox#node` without a clone of this repo
          devboxFlake = self;
        };
        modules = [
          disko.nixosModules.disko
          ./hosts/devbox
        ];
      };

      # Shared project environments: see shells.nix and docs/decisions.md.
      devShells.${system} = import ./shells.nix { inherit pkgs; };

      # `nix flake check` boots the box in a VM and runs devbox-doctor.
      checks.${system}.devbox = import ./tests/devbox.nix {
        inherit pkgs self;
      };
    };
}
