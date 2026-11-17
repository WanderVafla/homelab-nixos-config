# General system settings that are not critical for remote access.
{ ... }:

{
  imports = [
    ./boot.nix
    ./networking.nix
    ./memory.nix
    ./nix.nix
    ./power.nix
    ./packages.nix
    ./monitoring.nix
  ];
}
