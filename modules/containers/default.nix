{ config, lib, pkgs, ... }:

{
  imports = [
    ./nginx-proxy-manager.nix
    ./adguardhome.nix
  ];

  virtualisation.docker.enable = true;
}