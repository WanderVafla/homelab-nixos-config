# Pull deployer: every 5 minutes applies the newest commit of main with health checks and rollback.
{ pkgs, ... }:

let
  stateDir = "/var/lib/homelab-deploy";

  homelab-deploy = pkgs.writeShellApplication {
    name = "homelab-deploy";
    runtimeInputs = with pkgs; [
      coreutils
      git
      gnugrep
      iproute2
      jq
      nix
      systemd
      tailscale
      util-linux
    ];
    text = ''
      REMOTE="https://github.com/WanderVafla/homelab-nixos-config.git"
      BRANCH="main"
      HOST="homelab-server"
      ADMIN_USER="WanderVafla"
      STATE_DIR="${stateDir}"
      HEALTH_TIMEOUT=120
    '' + builtins.readFile ./homelab-deploy.sh;
  };
in
{
  environment.systemPackages = [ homelab-deploy ];

  systemd.tmpfiles.rules = [ "d ${stateDir} 0750 root root -" ];

  systemd.services.homelab-deploy = {
    description = "Pull and apply homelab-nixos-config with rollback";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Never restart this unit during its own switch-to-configuration run.
    restartIfChanged = false;
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${homelab-deploy}/bin/homelab-deploy run";
    };
  };

  systemd.timers.homelab-deploy = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitInactiveSec = "5min";
    };
  };
}
