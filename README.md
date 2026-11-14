# homelab-nixos-config

NixOS flake for `homelab-server`.

- `modules/base/` — lifeline layer: SSH, Tailscale, firewall, watchdog, admin user, deployer, hermes container.
- `modules/system/` — general system settings.
- `modules/hermes/` — Hermes agent settings, evaluated inside the hermes container only.
- `secrets/` — agenix recipients and encrypted secrets.

## Deploying

`homelab-deploy` on the server applies the newest `main` every 5 minutes, or at once when a file
appears in `/var/lib/homelab-deploy-trigger/`. It checks invariants, activates with `test`, runs a
health check, then promotes the new generation or rolls back.

Any change outside `modules/hermes/` waits for the owner: `sudo homelab-deploy approve` on the server.
