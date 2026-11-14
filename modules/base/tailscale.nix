# Tailscale VPN: the primary remote access path.
{ ... }:

{
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
