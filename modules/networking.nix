{ config, lib, pkgs, ... }:

{
  networking.hostName = "homelab-server";
  networking.networkmanager.enable = true;
  
  networking.firewall.allowedTCPPorts = [ 22 5984 80 443 81 53 3000 8085 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}