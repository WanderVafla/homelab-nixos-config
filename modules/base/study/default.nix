# Study automation: services and secrets for Moodle and Google Calendar.
#   - moodle-token: stays on the host; the Moodle gateway (./moodle-gateway.nix) uses it and the
#     agent reaches Moodle only through the gateway's read-only allowlist.
#   - google-calendar-key: service account key, readable by the agent (uid 2000). The service
#     account sees only the calendar the owner shared with it.
{ config, ... }:

let
  hermesUid = "2000"; # users.users.hermes.uid in ../hermes-container.nix
in
{
  imports = [ ./moodle-gateway.nix ];

  age.secrets.google-calendar-key = {
    file = ../../../secrets/google-calendar-key.age;
    owner = hermesUid;
    group = hermesUid;
    mode = "0400";
  };

  containers.hermes.bindMounts."/run/secrets/google-calendar-key" = {
    hostPath = config.age.secrets.google-calendar-key.path;
    isReadOnly = true;
  };

  # The bind mount pins the decrypted file at container start.
  systemd.services."container@hermes".restartTriggers = [ config.age.secrets.google-calendar-key.file ];
}
