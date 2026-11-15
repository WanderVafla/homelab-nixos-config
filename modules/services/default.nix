# Services the owner uses (not needed to keep the server reachable).
{ ... }:

{
  imports = [
    ./anki-sync-server.nix
  ];
}
