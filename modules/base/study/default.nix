# Study automation: secrets and services the hermes container gets for Moodle and Google Calendar.
#   - moodle-token: read only by the Moodle gateway user (uid 2001) inside the container;
#     the agent reaches Moodle only through the gateway's read-only allowlist.
#   - google-calendar-key: service account key, readable by the agent (uid 2000). The service
#     account sees only the calendar the owner shared with it.
{ config, ... }:

let
  hermesUid = "2000"; # users.users.hermes.uid in ../hermes-container.nix
  gatewayUid = "2001"; # users.users.moodle-gateway.uid in ./moodle-gateway.nix
in
{
  age.secrets.moodle-token = {
    file = ../../../secrets/moodle-token.age;
    owner = gatewayUid;
    group = gatewayUid;
    mode = "0400";
  };

  age.secrets.google-calendar-key = {
    file = ../../../secrets/google-calendar-key.age;
    owner = hermesUid;
    group = hermesUid;
    mode = "0400";
  };

  containers.hermes = {
    bindMounts = {
      "/run/secrets/moodle-token" = {
        hostPath = config.age.secrets.moodle-token.path;
        isReadOnly = true;
      };
      "/run/secrets/google-calendar-key" = {
        hostPath = config.age.secrets.google-calendar-key.path;
        isReadOnly = true;
      };
    };
    config.imports = [ ./moodle-gateway.nix ];
  };

  # Bind mounts pin the decrypted files at container start.
  systemd.services."container@hermes".restartTriggers = [
    config.age.secrets.moodle-token.file
    config.age.secrets.google-calendar-key.file
  ];
}
