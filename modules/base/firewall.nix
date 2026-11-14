# Firewall: only SSH is reachable from the LAN; the tailnet is trusted.
{ ... }:

{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
    trustedInterfaces = [ "tailscale0" ];
  };
}
