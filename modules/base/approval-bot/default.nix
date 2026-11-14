# Telegram bot that lets the owner approve protected deploys with a button.
# It runs on the host with its own token; the hermes container never sees that token,
# so the agent cannot approve its own changes.
{ config, pkgs, ... }:

let
  stateDir = "/var/lib/homelab-approval-bot";

  approval-bot = pkgs.writeShellApplication {
    name = "homelab-approval-bot";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      config.homelab.deploy.package
    ];
    text = ''
      STATE_DIR="${stateDir}"
      DEPLOY_STATE_DIR="/var/lib/homelab-deploy"
    '' + builtins.readFile ./approval-bot.sh;
  };
in
{
  age.secrets.approval-bot = {
    file = ../../../secrets/approval-bot.age;
    mode = "0400";
  };

  systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];

  systemd.services.homelab-approval-bot = {
    description = "Telegram approval buttons for homelab-deploy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    restartTriggers = [ config.age.secrets.approval-bot.file ];
    serviceConfig = {
      ExecStart = "${approval-bot}/bin/homelab-approval-bot";
      EnvironmentFile = config.age.secrets.approval-bot.path;
      Restart = "always";
      RestartSec = 10;
      PrivateTmp = true;
      ProtectHome = true;
    };
  };
}
