# Keep systemd-machined running when a new configuration is activated in place.
# A changed machined is stopped together with its socket; while the socket is down, stopping
# container@hermes runs `machinectl`, which starts machined over D-Bus, so the socket then
# refuses to start and switch-to-configuration test fails (seen on the systemd 261 -> 262
# update). The new machined starts on the next reboot.
{ ... }:

{
  systemd.services.systemd-machined.restartIfChanged = false;
}
