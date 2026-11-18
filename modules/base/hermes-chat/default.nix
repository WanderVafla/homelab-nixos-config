# Desktop chat with Hermes over SSH. The API server runs inside the hermes container
# (modules/hermes/api-server.nix) and listens only on the container's veth address; the owner's
# laptop reaches it through `ssh homelab hermes-chat ...`, so SSH is the authorization and the
# API key stays on the server. No new port is opened on the LAN or the tailnet.
{ config, pkgs, ... }:

let
  secretInContainer = "/run/secrets/hermes-api-env";
  apiPort = 8642; # API_SERVER_PORT in modules/hermes/api-server.nix

  hermes-chat = pkgs.writeShellApplication {
    name = "hermes-chat";
    runtimeInputs = with pkgs; [ coreutils curl gawk gnused jq ];
    text = ''
      API_URL="http://${config.containers.hermes.localAddress}:${toString apiPort}"
      KEY_FILE="${config.age.secrets.hermes-api-env.path}"
      ${builtins.readFile ./hermes-chat.sh}
    '';
  };
in
{
  # API_SERVER_KEY=<key>. Owned by the owner's login, so hermes-chat over SSH can read it;
  # root inside the container reads the bind mount into the agent's .env.
  age.secrets.hermes-api-env = {
    file = ../../../secrets/hermes-api-env.age;
    owner = "WanderVafla";
    mode = "0400";
  };

  containers.hermes.bindMounts.${secretInContainer} = {
    hostPath = config.age.secrets.hermes-api-env.path;
    isReadOnly = true;
  };

  # The bind mount pins the decrypted file at container start.
  systemd.services."container@hermes".restartTriggers = [ config.age.secrets.hermes-api-env.file ];

  environment.systemPackages = [ hermes-chat ];
}
