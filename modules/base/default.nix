# Lifeline layer: everything needed to keep the server reachable and recoverable.
# Changes here must be reviewed by the owner; the agent may never modify these files.
{ ... }:

{
  imports = [
    ./admin-user.nix
    ./ssh.nix
    ./tailscale.nix
    ./firewall.nix
    ./watchdog.nix
  ];
}
