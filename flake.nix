{
  description = "Homelab NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, agenix }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.homelab-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          agenix.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}