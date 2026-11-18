# Pull deployer: every 5 minutes applies the newest commit of main with health checks and rollback.
{ config, lib, pkgs, ... }:

let
  stateDir = "/var/lib/homelab-deploy";
  triggerDir = "/var/lib/homelab-deploy-trigger";

  # Units that must be active after a deploy, in addition to the built-in checks.
  healthUnits = lib.optional (config.containers ? hermes) "container@hermes.service";

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
      TRIGGER_DIR="${triggerDir}"
      HEALTH_TIMEOUT=120
      HEALTH_UNITS="${lib.concatStringsSep " " healthUnits}"
    '' + builtins.readFile ./homelab-deploy.sh;
  };
in
{
  imports = [ ./status.nix ];

  options.homelab.deploy.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = homelab-deploy;
    description = "The homelab-deploy command, for other modules that call it.";
  };

  config = {
    environment.systemPackages = [ homelab-deploy ];

    # Readable by everyone: status and revisions are not secret, and the hermes container reads them.
    systemd.tmpfiles.rules = [ "d ${stateDir} 0755 root root -" ];

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

    # Run a deploy as soon as a file appears in the trigger directory.
    systemd.paths.homelab-deploy-trigger = {
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathExistsGlob = "${triggerDir}/*";
        Unit = "homelab-deploy.service";
      };
    };

    systemd.timers.homelab-deploy = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitInactiveSec = "5min";
      };
    };
  };
}
