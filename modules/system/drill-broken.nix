# Rollback drill: a service that always fails, to prove the deployer rolls back. Remove after the drill.
{ pkgs, ... }:

{
  systemd.services.drill-broken = {
    description = "Rollback drill: always fails";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/false";
    };
  };
}
