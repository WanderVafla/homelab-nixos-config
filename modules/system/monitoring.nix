# Host monitoring: interactive process viewer, disk-usage explorer and
# a network traffic counter (vnstat keeps a small SQLite history).
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    btop
    ncdu
  ];

  services.vnstat.enable = true;
}
