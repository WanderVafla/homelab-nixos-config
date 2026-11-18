# secret-request: a Hermes plugin that lets the agent ask the owner for a secret in Telegram while
# the value never reaches the model. The owner's reply is taken out before the agent, encrypted
# with age to the host and owner keys (the same recipients as every agenix secret), and deleted
# from the chat; the agent gets only the .age file. See ./plugin/__init__.py for the flow.
{ pkgs, ... }:

let
  inbox = "/var/lib/hermes/secret-inbox";

  # Every secret uses the same two recipients (host and owner), so any entry gives the list.
  recipients = (import ../../../secrets/secrets.nix)."hermes-env.age".publicKeys;

  config = pkgs.writeText "secret-request-config.json" (builtins.toJSON {
    age = "${pkgs.age}/bin/age";
    inherit recipients inbox;
    # The owner's Telegram user id; only the owner's messages can answer a request.
    ownersEnv = "TELEGRAM_ALLOWED_USERS";
  });

  plugin = pkgs.runCommand "secret-request" { } ''
    mkdir -p $out
    cp ${./plugin}/*.py ${./plugin}/plugin.yaml $out/
    cp ${config} $out/config.json
  '';
in
{
  services.hermes-agent = {
    extraPlugins = [ plugin ];
    settings.plugins.enabled = [ "secret-request" ];
  };

  systemd.tmpfiles.rules = [ "d ${inbox} 0750 hermes hermes -" ];
}
