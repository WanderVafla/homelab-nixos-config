# Lifeline layer: everything needed to keep the server reachable and recoverable.
# Changes here must be reviewed by the owner (Telegram button or sudo homelab-deploy approve);
# the agent may never modify these files.
{ ... }:

{
  imports = [
    ./admin-user.nix
    ./ssh.nix
    ./tailscale.nix
    ./firewall.nix
    ./watchdog.nix
    ./deploy
    ./approval-bot
    ./hermes-container.nix
  ];
}
