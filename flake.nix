{
  description = "Homelab NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    # Pinned to a release: upstream supports Nix on a best-effort basis and main may break.
    # No nixpkgs follows: the uv2nix Python set is tested against upstream's own nixpkgs pin.
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.1";
  };

  outputs = { self, nixpkgs, agenix, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.homelab-server = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
