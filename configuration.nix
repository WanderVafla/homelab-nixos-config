{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/services.nix
    ./modules/memory.nix
    ./modules/storage.nix
    ./modules/system.nix
    ./modules/containers/default.nix
  ];

  system.stateVersion = "26.05";
}