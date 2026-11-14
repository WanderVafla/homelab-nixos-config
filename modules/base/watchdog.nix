# Hardware watchdog: reboot automatically if the kernel or systemd hangs.
{ ... }:

{
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "10min";
  };
}
