# Laptop-as-server power behaviour: never sleep, keep running with the lid closed.
{ ... }:

{
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
  };

  powerManagement.cpuFreqGovernor = "performance";
}
