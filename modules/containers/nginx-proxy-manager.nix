{ config, lib, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/nginx-proxy-manager 0755 root root -"
    "d /var/lib/nginx-proxy-manager/letsencrypt 0755 root root -"
  ];

  virtualisation.oci-containers.containers.nginx-proxy-manager = {
    image = "jc21/nginx-proxy-manager:2.15.1";
    autoStart = true;
  
    ports = [
      "80:80"
      "443:443"
      "81:81"
    ];

    volumes = [
      "/var/lib/nginx-proxy-manager:/data"
      "/var/lib/nginx-proxy-manager/letsencrypt:/etc/letsencrypt"
    ];
  };
}