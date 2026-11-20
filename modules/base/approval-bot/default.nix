# Telegram bot that lets the owner approve protected deploys with a button, and reports the
# agent's skill changes with a rollback button. It runs on the host with its own token; the
# hermes container never sees that token, so the agent cannot approve its own changes.
{ config, inputs, lib, pkgs, ... }:

let
  stateDir = "/var/lib/homelab-approval-bot";

  approval-bot = pkgs.writeShellApplication {
    name = "homelab-approval-bot";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      diffutils
      findutils
      gawk
      gnugrep
      gnutar
      jq
      util-linux
      config.homelab.deploy.package
    ];
    text = ''
      STATE_DIR="${stateDir}"
      DEPLOY_STATE_DIR="/var/lib/homelab-deploy"
      # The agent's skills as seen from the host (the container's root is nixos-containers/hermes).
      SKILLS_DIR="/var/lib/nixos-containers/hermes/var/lib/hermes/.hermes/skills"
      BUNDLED_SKILLS="${inputs.hermes-agent}/skills"
      PROTECTED_SKILLS="${lib.concatStringsSep " " (lib.attrNames (builtins.readDir ../hermes-policy/skills))}"
      HERMES_UID=2000 # users.users.hermes.uid in ../hermes-container.nix
      # Topic (thread) of the owner's group the bot posts into (t.me/c/4369153107/90).
      APPROVAL_THREAD_ID=90
    '' + builtins.readFile ./skill-watch.sh + builtins.readFile ./approval-bot.sh;
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
