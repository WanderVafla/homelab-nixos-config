{ config, lib, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/adguardhome 0755 root root -"
    "d /var/lib/adguardhome/work 0755 root root -"
    "d /var/lib/adguardhome/conf 0755 root root -"
  ];

  virtualisation.oci-containers.containers.adguardhome = {
    image = "adguard/adguardhome:latest";
    autoStart = true;
   
    ports = [
      "53:53/tcp"
      "53:53/udp"
      "3000:3000/tcp"
      "8085:8085/tcp"
    ];

    volumes = [
      "/var/lib/adguardhome/work:/opt/adguardhome/work"
      "/var/lib/adguardhome/conf:/opt/adguardhome/conf"
    ];
  };
}