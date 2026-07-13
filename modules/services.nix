{ config, lib, pkgs, ... }:

{
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  services.tailscale.enable = true;
}