# homelab-nixos-config

NixOS flake for `homelab-server`.

- `modules/base/` — lifeline layer (SSH, Tailscale, firewall, watchdog, admin user). Owner-reviewed only.
- `modules/system/` — general system settings.
- `secrets/` — agenix recipients and encrypted secrets.

Apply: `sudo nixos-rebuild switch --flake .#homelab-server`
