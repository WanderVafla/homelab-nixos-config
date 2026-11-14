# Isolated NixOS container for the Hermes agent.
# The host decides what the container can see; the agent's own settings live in modules/hermes.
{ inputs, ... }:

let
  hermesUid = 2000;
in
{
  containers.hermes = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.231.0.1";
    localAddress = "10.231.0.2";
    specialArgs = { inherit inputs; };

    bindMounts = {
      # Deployer state (status.json, revisions, public repo clone), read-only.
      "/var/lib/homelab-deploy" = {
        hostPath = "/var/lib/homelab-deploy";
        isReadOnly = true;
      };
      # Dropping any file here asks the host to run a deploy now.
      "/var/lib/homelab-deploy-trigger" = {
        hostPath = "/var/lib/homelab-deploy-trigger";
        isReadOnly = false;
      };
    };

    config = { lib, ... }: {
      imports = [ ../hermes ];

      system.stateVersion = "26.05";

      # Fixed ids so file ownership matches on host-side bind mounts.
      users.users.hermes.uid = hermesUid;
      users.groups.hermes.gid = hermesUid;

      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
    };
  };

  # Internet access for the container through the host, on Wi-Fi or Ethernet.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-hermes" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-deploy-trigger 0755 ${toString hermesUid} ${toString hermesUid} -"
  ];
}
