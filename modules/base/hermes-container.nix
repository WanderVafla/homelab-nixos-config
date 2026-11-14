# Isolated NixOS container for the Hermes agent.
# The host decides what the container can see; the agent's own settings live in modules/hermes.
{ config, inputs, ... }:

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
      # Agent environment (tokens, API keys). Decrypted by agenix on the host, root-only inside.
      "/run/secrets/hermes-env" = {
        hostPath = config.age.secrets.hermes-env.path;
        isReadOnly = true;
      };
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
      # No IPv6 route through the NAT, so resolve IPv4 addresses only.
      networking.enableIPv6 = false;
      networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
    };
  };

  age.secrets.hermes-env = {
    file = ../../secrets/hermes-env.age;
    mode = "0400";
  };

  # The bind mount pins the decrypted file at container start, so restart the container
  # whenever the secret changes.
  systemd.services."container@hermes".restartTriggers = [ config.age.secrets.hermes-env.file ];

  # Internet access for the container through the host, on Wi-Fi or Ethernet.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-hermes" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-deploy-trigger 0755 ${toString hermesUid} ${toString hermesUid} -"
  ];
}
