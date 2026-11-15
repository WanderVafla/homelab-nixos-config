# Anki sync server for the EPSIC flashcards. The owner's phone syncs over Tailscale; the hermes
# container syncs through its veth link to add new cards. The LAN firewall keeps the port closed.
{ config, ... }:

let
  port = 27701;
  hermesUid = "2000"; # users.users.hermes.uid in modules/base/hermes-container.nix
in
{
  # The bare password. The host service reads it as root; the agent reads it inside the container.
  age.secrets.anki-sync-password = {
    file = ../../secrets/anki-sync-password.age;
    owner = hermesUid;
    group = hermesUid;
    mode = "0400";
  };

  services.anki-sync-server = {
    enable = true;
    address = "0.0.0.0";
    inherit port;
    users = [
      {
        username = "vladyslav";
        passwordFile = config.age.secrets.anki-sync-password.path;
      }
    ];
  };

  # tailscale0 is already trusted; open the port to the hermes container as well.
  networking.firewall.interfaces."ve-hermes".allowedTCPPorts = [ port ];

  containers.hermes.bindMounts."/run/secrets/anki-sync-password" = {
    hostPath = config.age.secrets.anki-sync-password.path;
    isReadOnly = true;
  };
  systemd.services."container@hermes".restartTriggers = [ config.age.secrets.anki-sync-password.file ];
}
