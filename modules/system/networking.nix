# Host name and network management.
{ ... }:

{
  networking.hostName = "homelab-server";
  networking.networkmanager.enable = true;
}
